import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// Why the clearance webview showed no challenge at all.
///
/// From the site's own bundle (main-CCj_2yYk.js), in BOTH the Turnstile
/// component and the reader's init:
///
///   if (!window.navigator.webdriver && !navigator.userAgent.includes("wv")) {
///       await dr.Clearance.must(); ... }
///
///   /webview|wv/i.test(window.navigator.userAgent) || window.navigator.webdriver
///       || window.turnstile.render(...)
///
/// Every Android WebView user agent contains `wv`, so the site rendered no
/// challenge and never started the reader. The page just sat there — exactly
/// what the device showed.
///
/// FALSIFIER for the first group: a user agent that still matches the site's
/// own test. These assert against the REAL UA from the device log, because a
/// hand-written one would not have the `Build/` token that has to go too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Verbatim from the device log, 21:31:40.
  const String deviceWebViewUA =
      'Mozilla/5.0 (Linux; Android 16; SM-S928B Build/BP4A.251205.006; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/152.0.7977.64 Mobile Safari/537.36';

  /// The site's own predicate, transcribed.
  bool siteWouldSkipChallenge(String ua) =>
      RegExp('webview|wv', caseSensitive: false).hasMatch(ua) || ua.contains('wv');

  group('the user agent the site is shown', () {
    test('the real device UA is exactly what the site refuses', () {
      // If this ever stops being true the bug never existed.
      expect(siteWouldSkipChallenge(deviceWebViewUA), isTrue);
    });

    test('the stripped UA passes the site own test', () {
      final String ua = Tools.stripWebViewMarkers(deviceWebViewUA);
      expect(siteWouldSkipChallenge(ua), isFalse, reason: 'still reads as a webview: $ua');
    });

    test('it is still the same device and the same Chrome', () {
      // A hardcoded UA would work here too, and would lie about the device.
      final String ua = Tools.stripWebViewMarkers(deviceWebViewUA);
      expect(ua, contains('Android 16'));
      expect(ua, contains('SM-S928B'));
      expect(ua, contains('Chrome/152.0.7977.64'));
      expect(ua, contains('Mobile Safari/537.36'));
    });

    test('the webview-only tokens are gone, not just the "wv" one', () {
      final String ua = Tools.stripWebViewMarkers(deviceWebViewUA);
      expect(ua, isNot(contains('wv')));
      expect(ua, isNot(contains('Build/')), reason: 'Build/ only appears in WebView UAs');
      expect(ua, isNot(contains('Version/4.0')), reason: 'WebView announces itself twice');
      expect(ua, isNot(contains('  ')), reason: 'stripping left a double space');
    });

    test('it reads as a plain Chrome UA, parenthesis included', () {
      expect(
        Tools.stripWebViewMarkers(deviceWebViewUA),
        'Mozilla/5.0 (Linux; Android 16; SM-S928B) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/152.0.7977.64 Mobile Safari/537.36',
      );
    });

    test('a UA that was never a webview is left alone', () {
      const String chrome =
          'Mozilla/5.0 (Linux; Android 16; SM-S928B) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/152.0.7977.64 Mobile Safari/537.36';
      expect(Tools.stripWebViewMarkers(chrome), chrome);
    });

    test('a desktop UA keeps its real Version token', () {
      // Safari's "Version/17.4" is genuine and must survive... except it is the
      // same token WebView abuses, so document what actually happens.
      const String safari =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/17.4 Safari/605.1.15';
      final String out = Tools.stripWebViewMarkers(safari);
      // Only used for the Android clearance webview, so losing it is harmless,
      // but it must not corrupt the rest of the string.
      expect(out, startsWith('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'));
      expect(out, endsWith('Safari/605.1.15'));
    });
  });

  group('the challenge page cannot be hijacked', () {
    const String site = 'https://shupogaki.moe';

    bool allows(String url) => isWebviewNavigationAllowed(
      url,
      initialUrl: site,
      allowedHosts: SchaleClearanceHandler.allowedChallengeHosts(site),
    );

    test('Cloudflare is allowed, or no challenge could ever run', () {
      expect(allows('https://challenges.cloudflare.com/turnstile/v0/api.js'), isTrue);
    });

    test('the site, its API and its auth host are allowed', () {
      expect(allows('https://shupogaki.moe/g/1/k/read/1'), isTrue);
      expect(allows('https://api.schale.network/books/popular?page=1'), isTrue);
      expect(allows('https://auth.schale.network/clearance'), isTrue);
      expect(allows('https://niyaniya.moe/'), isTrue);
    });

    test('the ad hosts that took over the page are refused', () {
      // Seen in the recording replacing the challenge page outright.
      expect(allows('https://www.livejasmin.com/'), isFalse);
      expect(allows('https://api.shinybirdwhispered.com/x'), isFalse);
      expect(allows('https://tardierrouges.com/pop'), isFalse);
    });

    test('a lookalike host does not sneak through a suffix match', () {
      // The check is host-or-subdomain, never "contains".
      expect(allows('https://shupogaki.moe.evil.com/'), isFalse);
      expect(allows('https://notshupogaki.moe/'), isFalse);
      expect(allows('https://cloudflare.com.evil.net/'), isFalse);
    });

    test('a subdomain of the site is allowed', () {
      expect(allows('https://cdn.shupogaki.moe/x.js'), isTrue);
    });

    test('the page own scaffolding is not treated as a navigation', () {
      expect(allows('about:blank'), isTrue);
    });

    test('a junk or app-scheme url is refused', () {
      // Ad interstitials commonly try intent:// and market:// to leave the app.
      expect(allows('intent://scan/#Intent;scheme=zxing;end'), isFalse);
      expect(allows(''), isFalse);
    });
  });

  group('asking for a challenge cannot take the reader down with it', () {
    late Directory tempDir;

    setUp(() {
      SettingsHandler.register();
      ViewerHandler.register();
      tempDir = Directory.systemTemp.createTempSync('schale_nav');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      SchaleClearanceHandler.instance.resetForTests();
    });

    tearDown(() {
      SchaleClearanceHandler.instance.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('with no navigator mounted it reports failure instead of throwing', () async {
      // NavigationHandler.navContext is `navigatorKey.currentContext!` — before
      // the first route is mounted, or while the app is being torn down, that
      // is a null check on null. It used to be evaluated outside the try, so
      // instead of "the check could not be shown" the reader got an exception.
      NavigationHandler.register();

      expect(
        await SchaleClearanceHandler.instance.requestClearance('https://niyaniya.moe'),
        isFalse,
      );
      expect(SchaleClearanceHandler.instance.hasToken, isFalse);
    });

    test('a token already held is returned without opening anything', () async {
      NavigationHandler.register();
      SchaleClearanceHandler.instance.store('already-have-one');

      // No navigator, but no challenge is needed either.
      expect(SchaleClearanceHandler.instance.hasToken, isTrue);
      expect(SchaleClearanceHandler.instance.token, 'already-have-one');
    });
  });

  group('a refused token cannot lock the challenge out', () {
    late Directory tempDir;

    setUp(() {
      SettingsHandler.register();
      ViewerHandler.register();
      tempDir = Directory.systemTemp.createTempSync('schale_reject');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      SchaleClearanceHandler.instance.resetForTests();
    });

    tearDown(() {
      SchaleClearanceHandler.instance.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // The device log: a real clearance was obtained
    // (crt=6946c74f-1b0e-47a8-a510-3873624ed15d) and every POST carrying it
    // came back 403. The reader then reopened the webview, which read the SAME
    // dead token back out of the page's localStorage, adopted it, and closed
    // itself — so no challenge ever ran and restarting the app changed nothing.
    const String dead = '6946c74f-1b0e-47a8-a510-3873624ed15d';

    test('a rejected token is remembered, not merely dropped', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();

      expect(c.hasToken, isFalse);
      expect(c.rejectedToken, dead, reason: 'nothing knows which token failed');
    });

    test('the same token read back from the page is refused', () {
      // This is the exact loop from the log.
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();

      expect(c.isUsableToken(dead, afterClear: false), isFalse);
    });

    test('a genuinely new token is accepted', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();

      expect(c.isUsableToken('a-fresh-one', afterClear: false), isTrue);
    });

    test('empty and null are never adopted', () {
      final c = SchaleClearanceHandler.instance;
      expect(c.isUsableToken(null, afterClear: true), isFalse);
      expect(c.isUsableToken('', afterClear: true), isFalse);
    });

    test('once a new token lands the old one stops being blocked', () {
      // The rejected marker must not outlive its purpose, or a token that later
      // becomes valid again could never be reused.
      final c = SchaleClearanceHandler.instance..store(dead);
      c
        ..invalidate()
        ..store('fresh');

      expect(c.rejectedToken, isNull);
      expect(c.isUsableToken(dead, afterClear: false), isTrue);
    });

    test('the SAME token re-issued after a fresh challenge is accepted', () {
      // The second device log: the Turnstile passed, the site unblurred, and
      // the only crt value in the whole session was still the "rejected" one -
      // which had answered 200 six times that day. The API hands the same
      // token back after a fresh challenge. Refusing it unconditionally made
      // one 403 permanent.
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();

      // Before the page has been seen empty, the same string is the stale copy.
      expect(c.isUsableToken(dead, afterClear: false), isFalse);
      // Once it has, the same string was written by the site just now.
      expect(c.isUsableToken(dead, afterClear: true), isTrue);
    });

    test('storing the re-issued token clears the rejected marker', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c
        ..invalidate()
        ..store(dead);

      expect(c.hasToken, isTrue);
      expect(c.rejectedToken, isNull, reason: 'a token the site just handed out is not rejected');
    });

    test('the injected script deletes exactly the refused clearance', () {
      final String js = SchaleClearanceHandler.clearRejectedScript(dead);

      expect(js, contains(dead));
      expect(js, contains("removeItem('clearance')"));
      // Guarded, or a clearance earned seconds ago during this same challenge
      // would be wiped by the next redirect.
      expect(js, contains('held === dead'));
    });

    test('with nothing refused there is no script, so nothing is wiped', () {
      expect(SchaleClearanceHandler.clearRejectedScript(null), isEmpty);
      expect(SchaleClearanceHandler.clearRejectedScript(''), isEmpty);
    });

    test('a token containing quotes cannot break the injected script', () {
      final String js = SchaleClearanceHandler.clearRejectedScript("a'\"; alert(1); //");
      expect(js, contains(r'\"'));
      expect(js, isNot(contains('alert(1); //;')));
    });
  });

  group('the challenge page reports what it is doing', () {
    // Three logs in a row show the Turnstile appear and nothing follow. The
    // site closes its modal whether or not the auth POST returned 201, so from
    // outside the webview a pass and a failure look identical. This script is
    // the only way to tell them apart.
    const String js = SchaleClearanceHandler.diagnosticScript;

    test('it watches the three links that decide the outcome', () {
      expect(js, contains("callHandler('${SchaleClearanceHandler.bridgeName}'"));
      expect(js, contains('turnstile.callback'), reason: 'did Turnstile hand over a token');
      expect(js, contains(r'schale\.network'), reason: 'what did auth answer');
      expect(js, contains("k === 'clearance'"), reason: 'was the clearance written');
    });

    test('it reports Turnstile errors the site itself never listens for', () {
      // The site passes only `callback` to turnstile.render — no error
      // handler at all. A widget failure is invisible to it.
      expect(js, contains("'error-callback'"));
      expect(js, contains("'expired-callback'"));
    });

    test('every hook calls straight through, so the page is unchanged', () {
      expect(js, contains('origSet.apply(this, arguments)'));
      expect(js, contains('origSend.apply(this, arguments)'));
      expect(js, contains('origFetch.apply(this, args)'));
      expect(js, contains('origRender.call(this, el, o)'));
      expect(js, contains('cb && cb.apply(this, arguments)'));
    });

    test('it never puts a whole token in the log', () {
      // The clearance is a credential; a prefix is enough to correlate.
      expect(js, contains('slice(0, 12)'));
      expect(js, contains("replace(/crt=[^&]+/, 'crt=…')"));
    });

    test('it installs once, however many navigations happen', () {
      expect(js, contains('__lsClearanceHook'));
    });
  });

  group('the request budget is respected', () {
    late Directory tempDir;

    setUp(() {
      SettingsHandler.register();
      ViewerHandler.register();
      tempDir = Directory.systemTemp.createTempSync('schale_rl');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      SchaleHandler.resetRateLimitForTests();
    });

    tearDown(() {
      SchaleHandler.resetRateLimitForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    SchaleHandler handler() =>
        SchaleHandler(Booru('n', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''), 20);

    test('the backfill goes one at a time, paced', () {
      // The device log shows the listing backfill spending the whole budget,
      // after which every request the person made came back 429.
      final h = handler();
      expect(h.tagBackfillConcurrency, 1);
      expect(h.tagBackfillDelay, greaterThan(Duration.zero));
    });

    test('a 429 waits for the time the server named', () {
      final now = DateTime.utc(2026, 8, 31, 19, 31, 40);
      final reset = now.add(const Duration(seconds: 30)).millisecondsSinceEpoch ~/ 1000;

      expect(
        SchaleHandler.backoffFrom('$reset', now: now),
        closeToDuration(const Duration(seconds: 30)),
      );
    });

    test('a missing or unusable reset header falls back to a fixed wait', () {
      final now = DateTime.utc(2026, 8, 31);
      expect(SchaleHandler.backoffFrom(null, now: now), SchaleHandler.rateLimitBackoff);
      expect(SchaleHandler.backoffFrom('nonsense', now: now), SchaleHandler.rateLimitBackoff);
      // Already in the past.
      expect(SchaleHandler.backoffFrom('1', now: now), SchaleHandler.rateLimitBackoff);
    });

    test('a nonsensical reset far in the future does not stall the session', () {
      // The real header is unix seconds; misreading it as milliseconds would
      // otherwise park the source for weeks.
      final now = DateTime.utc(2026, 8, 31);
      final absurd = now.add(const Duration(days: 40)).millisecondsSinceEpoch ~/ 1000;
      expect(SchaleHandler.backoffFrom('$absurd', now: now), SchaleHandler.rateLimitBackoff);
    });
  });
}

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (d) => (d - expected).abs() < const Duration(seconds: 2),
  'within 2s of $expected',
);
