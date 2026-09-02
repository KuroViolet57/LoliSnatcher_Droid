import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// The two-window clearance flow, modelled on Keiyoushi's Koharu extension.
///
/// The SOLVER is visible: reduced Chrome agent, pop-ups allowed, navigation
/// judged for the main frame only so Cloudflare's `blob:` challenge frames
/// load. The HARVESTER is headless: no agent override, no filter, reads
/// `localStorage['clearance']` on page finished.
///
/// What each group guards, stated as the observation that would prove it
/// still broken:
///  - agent: a solver string the site's `includes("wv")` test matches, or one
///    carrying the device model.
///  - navigation: a `blob:` or `about:srcdoc` main-frame load refused, or a
///    sub-frame load of any kind refused.
///  - token: the harvester adopting the exact value the API just refused.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Verbatim from the device log.
  const String deviceWebViewUA =
      'Mozilla/5.0 (Linux; Android 16; SM-S928B Build/BP4A.251205.006; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/152.0.7977.64 Mobile Safari/537.36';

  group('the agent the solver presents', () {
    test("is Chrome's reduced string, with the device's Chrome major version", () {
      expect(
        SchaleClearanceHandler.reducedChromeUserAgent(deviceWebViewUA),
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36',
      );
    });

    test("passes the site's own webview test", () {
      final String ua = SchaleClearanceHandler.reducedChromeUserAgent(deviceWebViewUA);
      expect(RegExp('webview|wv', caseSensitive: false).hasMatch(ua), isFalse);
    });

    test('carries nothing that identifies the device', () {
      final String ua = SchaleClearanceHandler.reducedChromeUserAgent(deviceWebViewUA);
      expect(ua, isNot(contains('SM-S928B')));
      expect(ua, isNot(contains('Android 16')));
      expect(ua, isNot(contains('Build/')));
    });

    test('a device agent with no Chrome version gets a sane default', () {
      expect(SchaleClearanceHandler.reducedChromeUserAgent('LoliSnatcher/2.6'), contains('Chrome/149.0.0.0'));
    });

    test('the older stripped agent still exists for other callers, and still passes', () {
      // Not used by the solver any more, but other webviews depend on it.
      expect(Tools.stripWebViewMarkers(deviceWebViewUA), isNot(contains('wv')));
    });
  });

  group('the solver judges the main frame only', () {
    const String site = 'https://shupogaki.moe';
    final List<String> hosts = SchaleClearanceHandler.allowedMainFrameHosts(site);

    bool allows(String url) => isMainFrameNavigationAllowed(url, initialUrl: site, allowedHosts: hosts);

    test("Cloudflare's challenge frames are allowed: blob: and about:srcdoc", () {
      // The site's own security policy grants Turnstile `frame-src blob:` and
      // `worker-src blob:`. Refusing them is what starved the challenge.
      expect(allows('blob:https://shupogaki.moe/3f2a1c9e-0b1d-4b9e-8f1a-1e2d3c4b5a69'), isTrue);
      expect(allows('about:srcdoc'), isTrue);
      expect(allows('about:blank'), isTrue);
    });

    test('the site, its API, its auth host and Cloudflare are allowed', () {
      expect(allows('https://shupogaki.moe/g/1/k'), isTrue);
      expect(allows('https://api.schale.network/books/index'), isTrue);
      expect(allows('https://auth.schale.network/clearance'), isTrue);
      expect(allows('https://challenges.cloudflare.com/turnstile/v0/api.js'), isTrue);
      expect(allows('https://niyaniya.moe/'), isTrue);
    });

    test('a page takeover by an ad host is refused', () {
      expect(allows('https://www.livejasmin.com/'), isFalse);
      expect(allows('https://api.shinybirdwhispered.com/x'), isFalse);
    });

    test('an intent:// that would leave the app is refused', () {
      expect(allows('intent://scan/#Intent;scheme=zxing;end'), isFalse);
      expect(allows('market://details?id=x'), isFalse);
    });

    test('a lookalike host does not pass on a suffix', () {
      expect(allows('https://shupogaki.moe.evil.com/'), isFalse);
      expect(allows('https://notshupogaki.moe/'), isFalse);
    });
  });

  group('the harvester never re-adopts a refused token', () {
    late Directory tempDir;

    setUp(() {
      SettingsHandler.register();
      ViewerHandler.register();
      tempDir = Directory.systemTemp.createTempSync('schale_harvest');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      SchaleClearanceHandler.instance.resetForTests();
    });

    tearDown(() {
      SchaleClearanceHandler.instance.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    const String dead = '6946c74f-1b0e-47a8-a510-3873624ed15d';

    test('the exact value the API refused is not usable', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();
      expect(c.isUsableToken(dead), isFalse);
    });

    test('any other value is', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c.invalidate();
      expect(c.isUsableToken('fresh'), isTrue);
    });

    test('empty and null are never usable', () {
      final c = SchaleClearanceHandler.instance;
      expect(c.isUsableToken(null), isFalse);
      expect(c.isUsableToken(''), isFalse);
    });

    test('storing a token clears the refused marker', () {
      final c = SchaleClearanceHandler.instance..store(dead);
      c
        ..invalidate()
        ..store('fresh');
      expect(c.rejectedToken, isNull);
    });

    test('the solver deletes exactly the refused value before the site runs', () {
      final String js = SchaleClearanceHandler.clearRejectedScript(dead);
      expect(js, contains(dead));
      expect(js, contains("removeItem('clearance')"));
      expect(js, contains('held === dead'));
      expect(SchaleClearanceHandler.clearRejectedScript(null), isEmpty);
    });

    test('the harvest latch matches Koharu', () {
      expect(SchaleClearanceHandler.harvestTimeout, const Duration(seconds: 10));
    });
  });

  group('the solver page reports what it is doing', () {
    const String js = SchaleClearanceHandler.diagnosticScript;

    test('turnstile is captured on assignment, not by polling', () {
      // The previous poller lost the race to the site's render() every time;
      // no turnstile.render line ever appeared in a log.
      expect(js, contains("Object.defineProperty(window, 'turnstile'"));
      expect(js, isNot(contains('setInterval')));
    });

    test('it reports callback, error and expiry', () {
      expect(js, contains('turnstile.callback'));
      expect(js, contains("'error-callback'"));
      expect(js, contains("'expired-callback'"));
    });

    test('it reports the method and status of every auth call', () {
      expect(js, contains('__lsMethod'));
      expect(js, contains(r'schale\.network'));
    });

    test('every hook calls straight through', () {
      expect(js, contains('origSet.apply(this, arguments)'));
      expect(js, contains('origSend.apply(this, arguments)'));
      expect(js, contains('origRender.call(this, el, o)'));
      expect(js, contains('cb && cb.apply(this, arguments)'));
    });

    test('it never puts a whole token in the log', () {
      expect(js, contains('slice(0, 12)'));
      expect(js, contains("stored=' + (localStorage.getItem('clearance') ? 'present' : 'null')"));
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

    test('with no navigator mounted the solver reports failure instead of throwing', () async {
      expect(await SchaleClearanceHandler.instance.solve('https://niyaniya.moe'), isFalse);
    });

    test('a gated call with no token surfaces the message a person can act on', () {
      expect(SchaleClearanceHandler.needsSolveMessage, contains('Open the check'));
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
      final h = handler();
      expect(h.tagBackfillConcurrency, 1);
      expect(h.tagBackfillDelay, greaterThan(Duration.zero));
    });

    test('a 429 waits for the time the server named', () {
      final now = DateTime.utc(2026, 8, 31, 19, 31, 40);
      final reset = now.add(const Duration(seconds: 30)).millisecondsSinceEpoch ~/ 1000;
      expect(SchaleHandler.backoffFrom('$reset', now: now), closeToDuration(const Duration(seconds: 30)));
    });

    test('a missing or unusable reset header falls back to a fixed wait', () {
      final now = DateTime.utc(2026, 8, 31);
      expect(SchaleHandler.backoffFrom(null, now: now), SchaleHandler.rateLimitBackoff);
      expect(SchaleHandler.backoffFrom('nonsense', now: now), SchaleHandler.rateLimitBackoff);
      expect(SchaleHandler.backoffFrom('1', now: now), SchaleHandler.rateLimitBackoff);
    });
  });
}

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (d) => (d - expected).abs() < const Duration(seconds: 2),
  'within 2s of $expected',
);
