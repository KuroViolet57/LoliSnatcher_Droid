import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// The clearance token niyaniya/Schale requires before it will serve readable
/// pages.
///
/// Grid thumbnails are anonymous, and so is everything about browsing. Only
/// reading is gated: the page list and the page images both hang off a `crt`
/// query parameter. The site obtains that token by solving a Cloudflare
/// Turnstile challenge and POSTing it to `auth.schale.network/clearance`, then
/// keeps the result in `localStorage["clearance"]` and reuses it until it is
/// rejected.
///
/// Rather than reimplement the challenge, this opens the site in the app's own
/// webview, lets the person solve it exactly as they would in a browser, and
/// then reads the token the site stored. That is deliberately manual: solving
/// Turnstile automatically is neither reliable nor something to build.
///
/// Two things make that work, both learned the hard way from a device log:
///
///  * The site's bundle runs `navigator.userAgent.includes("wv")` and, when it
///    matches, renders NO Turnstile and skips the reader's init entirely. Every
///    Android WebView UA contains `wv`, so the challenge simply never appeared
///    and the reader sat on a spinner. The webview is therefore given a UA with
///    the WebView markers stripped.
///  * The mirrors serve full-page interstitial ads. One of them replaced the
///    challenge page outright. The webview refuses pop-ups and any navigation
///    away from the site and Cloudflare.
class SchaleClearanceHandler {
  SchaleClearanceHandler._();

  static final SchaleClearanceHandler instance = SchaleClearanceHandler._();

  static const String fileName = 'schale_clearance.json';

  /// Where the site keeps it, and therefore where it is read from.
  static const String localStorageKey = 'clearance';

  String? _token;
  bool _loaded = false;

  /// Rises whenever the token changes, so a reader waiting on one can retry.
  final ValueNotifier<int> revision = ValueNotifier(0);

  File? get _file {
    try {
      return File('${SettingsHandler.instance.path}$fileName');
    } catch (_) {
      return null;
    }
  }

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final File? file = _file;
      if (file == null || !file.existsSync()) return;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map && decoded['token'] is String) {
        final String stored = decoded['token'] as String;
        if (stored.isNotEmpty) _token = stored;
      }
    } catch (_) {}
  }

  String? get token {
    ensureLoaded();
    return _token;
  }

  bool get hasToken => token?.isNotEmpty ?? false;

  void store(String value) {
    ensureLoaded();
    if (value.isEmpty) return;
    // Whatever is being stored has just been produced or re-validated by the
    // site, so nothing is "rejected" any more — including the same string.
    _rejectedToken = null;
    _token = value;
    _persist();
    revision.value++;
  }

  /// The token the API most recently rejected.
  ///
  /// The site keeps its clearance in the page's own localStorage, and
  /// [invalidate] only ever dropped OUR copy. The webview then reopened,
  /// read the SAME dead token straight back out of localStorage, adopted it and
  /// closed itself — so the challenge never ran, the reader never worked, and
  /// restarting the app changed nothing because the value was still sitting in
  /// the webview's storage. Remembering it is what lets the challenge actually
  /// be re-run.
  String? _rejectedToken;

  @visibleForTesting
  String? get rejectedToken => _rejectedToken;

  /// Whether [candidate] is a token worth adopting.
  ///
  /// [afterClear] is whether the challenge webview has been observed with NO
  /// clearance in its storage during this attempt. Before that point, a value
  /// equal to the refused one is the stale copy the page still held and must
  /// be ignored. After it, any value present was written by the site DURING
  /// this challenge — and is accepted even if it is the same string, because
  /// the site has just validated it.
  ///
  /// The previous rule refused the rejected value unconditionally. The API
  /// hands the same token back after a fresh challenge, so the Turnstile
  /// passed, the page unblurred, and the app sat there refusing the token the
  /// site had just re-issued. A single 403 had become permanent.
  @visibleForTesting
  bool isUsableToken(String? candidate, {required bool afterClear}) {
    if (candidate == null || candidate.isEmpty) return false;
    if (afterClear) return true;
    return candidate != _rejectedToken;
  }

  /// Called when the API rejects the token, so the next read asks for a new one
  /// rather than repeating a request that cannot succeed.
  void invalidate() {
    ensureLoaded();
    if (_token == null) return;
    _rejectedToken = _token;
    _token = null;
    _persist();
    revision.value++;
  }

  /// Injected before the site's own code runs, to delete a clearance the API
  /// has already refused. Without this the page sees a stored clearance, skips
  /// the Turnstile entirely, and there is nothing for anyone to solve.
  ///
  /// Deliberately removes ONLY the rejected value: a clearance earned moments
  /// ago during this same challenge must survive a redirect.
  @visibleForTesting
  static String clearRejectedScript(String? rejected) {
    if (rejected == null || rejected.isEmpty) return '';
    final String encoded = jsonEncode(rejected);
    return '''
(() => {
  try {
    const dead = $encoded;
    const held = window.localStorage.getItem('$localStorageKey');
    if (held && (held === dead || held === JSON.stringify(dead))) {
      window.localStorage.removeItem('$localStorageKey');
    }
  } catch (e) {}
})();
''';
  }

  void _persist() {
    try {
      final File? file = _file;
      if (file == null) return;
      if (_token == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(jsonEncode({'token': _token}));
    } catch (e, s) {
      Logger.Inst().log(
        'failed to persist schale clearance: $e',
        'SchaleClearanceHandler',
        '_persist',
        LogTypes.exception,
        s: s,
      );
    }
  }

  @visibleForTesting
  void resetForTests() {
    _token = null;
    _rejectedToken = null;
    _loaded = true;
  }

  /// Reads the token the site stored after a challenge was solved.
  ///
  /// Separated from the webview so it can be tested against the shape the page
  /// actually returns: `evaluateJavascript` hands back the raw value, which is
  /// a bare string, a quoted string, or null depending on platform.
  @visibleForTesting
  static String? tokenFromLocalStorage(dynamic raw) {
    if (raw == null) return null;
    String value = raw.toString().trim();
    if (value.isEmpty || value == 'null' || value == 'undefined') return null;
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }

  /// The site itself, its API, and its auth host — the challenge POSTs the
  /// Turnstile token to auth.schale.network, so blocking that would break it.
  static List<String> allowedChallengeHosts(String siteUrl) {
    final String host = Uri.tryParse(siteUrl)?.host ?? '';
    return [
      if (host.isNotEmpty) host,
      'schale.network',
      'niyaniya.moe',
      'shupogaki.moe',
    ];
  }

  /// The bridge name the challenge page reports through.
  static const String bridgeName = 'lsClearance';

  /// Injected at document start into the challenge webview. Reports, into the
  /// app log, the three things that decide whether a clearance is obtained:
  /// the Turnstile callback firing, the POST to auth.schale.network and what
  /// it answered, and the site writing `localStorage["clearance"]`.
  ///
  /// Three device logs in a row show the same thing: the Turnstile appears,
  /// then nothing, and no token is ever stored. From outside the webview that
  /// is all that can be seen. This puts eyes inside it. It changes nothing
  /// about the page's behaviour — every hook calls straight through.
  static const String diagnosticScript = r'''
(() => {
  if (window.__lsClearanceHook) return;
  window.__lsClearanceHook = true;
  const say = (event, detail) => {
    try { window.flutter_inappwebview.callHandler('lsClearance', { event, detail: String(detail || '').slice(0, 300) }); } catch (e) {}
  };
  say('page', location.href + ' | stored=' + (localStorage.getItem('clearance') || 'null'));

  // The site writes the clearance here on success.
  const origSet = Storage.prototype.setItem;
  Storage.prototype.setItem = function (k, v) {
    if (k === 'clearance') say('setItem', 'clearance=' + String(v).slice(0, 12) + '…');
    return origSet.apply(this, arguments);
  };
  const origRemove = Storage.prototype.removeItem;
  Storage.prototype.removeItem = function (k) {
    if (k === 'clearance') say('removeItem', 'clearance');
    return origRemove.apply(this, arguments);
  };

  // The site's XHR to auth.schale.network/clearance carries the Turnstile
  // token and answers with the clearance. Its status is the whole story.
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) { this.__lsUrl = String(u); return origOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function () {
    const u = this.__lsUrl || '';
    if (/schale\.network/.test(u)) {
      this.addEventListener('loadend', () => say('xhr', this.status + ' ' + u.replace(/crt=[^&]+/, 'crt=…') + ' | ' + String(this.responseText || '').slice(0, 120)));
    }
    return origSend.apply(this, arguments);
  };
  const origFetch = window.fetch;
  window.fetch = async function (...args) {
    const u = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '';
    const res = await origFetch.apply(this, args);
    if (/schale\.network/.test(u)) {
      try { res.clone().text().then((t) => say('fetch', res.status + ' ' + u.replace(/crt=[^&]+/, 'crt=…') + ' | ' + t.slice(0, 120))); } catch (e) {}
    }
    return res;
  };

  // Turnstile: wrap render so the callback and any error are visible.
  const wrapTurnstile = () => {
    const t = window.turnstile;
    if (!t || t.__lsWrapped) return false;
    t.__lsWrapped = true;
    const origRender = t.render;
    t.render = function (el, opts) {
      say('turnstile.render', 'sitekey=' + (opts && opts.sitekey) + ' keys=' + Object.keys(opts || {}).join(','));
      const o = Object.assign({}, opts);
      const cb = o.callback;
      o.callback = function (token) { say('turnstile.callback', 'token len=' + String(token || '').length); return cb && cb.apply(this, arguments); };
      const ecb = o['error-callback'];
      o['error-callback'] = function (code) { say('turnstile.error', code); return ecb && ecb.apply(this, arguments); };
      const xcb = o['expired-callback'];
      o['expired-callback'] = function () { say('turnstile.expired', ''); return xcb && xcb.apply(this, arguments); };
      return origRender.call(this, el, o);
    };
    return true;
  };
  if (!wrapTurnstile()) {
    let tries = 0;
    const iv = setInterval(() => { if (wrapTurnstile() || ++tries > 200) clearInterval(iv); }, 100);
  }
  window.addEventListener('error', (e) => say('js.error', (e.message || '') + ' @' + (e.filename || '') + ':' + e.lineno));
})();
''';

  void _logFromPage(dynamic call) {
    if (call is! Map) return;
    Logger.Inst().log(
      'challenge page: ${call['event']} — ${call['detail']}',
      'SchaleClearanceHandler',
      'challenge',
      LogTypes.booruHandlerInfo,
    );
  }

  bool _challengeOpen = false;

  /// Opens the site so the challenge can be solved by hand, then takes whatever
  /// clearance the site stored. Returns true when a token was obtained.
  ///
  /// [siteUrl] follows the configured mirror rather than being hardcoded, so a
  /// switch to shupogaki.moe challenges on the mirror actually in use.
  Future<bool> requestClearance(String siteUrl) async {
    if (_challengeOpen) return hasToken;

    _challengeOpen = true;
    Timer? poll;
    try {
      // Resolved inside the try on purpose. There is no navigator before the
      // first route is mounted, or while the app is being torn down, and this
      // throws rather than returning null in that case. Outside the try it
      // took the reader down with it instead of letting loadItem report that
      // the check could not be shown.
      final BuildContext context = NavigationHandler.instance.navContext;
      final String? rejected = _rejectedToken;

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => InAppWebviewView(
            initialUrl: siteUrl,
            title: 'Reader access',
            subtitle: 'Complete the check, then come back — pages need it, browsing does not',
            // Without this the site detects a WebView and never shows the
            // challenge at all. This is the whole reason the flow works.
            userAgent: Tools.nonWebViewUserAgent,
            // The mirrors serve interstitials that hijack the page; a hijacked
            // page can never complete the challenge.
            blockPopupsAndAds: true,
            allowedHosts: allowedChallengeHosts(siteUrl),
            // Delete the clearance the API already refused, before the site's
            // code reads it. Otherwise the site sees a stored clearance and
            // never runs the Turnstile at all.
            initialUserScripts: [
              if (clearRejectedScript(rejected).isNotEmpty)
                UserScript(
                  source: clearRejectedScript(rejected),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              UserScript(
                source: diagnosticScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ],
            onWebViewReady: (controller) {
              controller.addJavaScriptHandler(
                handlerName: bridgeName,
                callback: (args) {
                  _logFromPage(args.isNotEmpty ? args.first : null);
                  return null;
                },
              );
              Logger.Inst().log(
                'challenge opened on $siteUrl (rejected=${rejected == null ? 'none' : '${rejected.substring(0, 8)}…'})',
                'SchaleClearanceHandler',
                'challenge',
                LogTypes.booruHandlerInfo,
              );
              // The token appears when the Turnstile callback finishes, which
              // is well after the page has loaded — so this watches for it
              // rather than looking once on load.
              //
              // Seeing the storage EMPTY once is the proof that the injected
              // script has run and the site is being challenged afresh. From
              // then on whatever appears was written by the site in response
              // to that challenge, same string or not.
              bool sawEmpty = rejected == null;
              int ticks = 0;
              poll = Timer.periodic(const Duration(milliseconds: 700), (timer) async {
                final String? found = await _readToken(controller);
                // Every ~5s, say what the poll sees — the one fact none of the
                // logs so far contain.
                if (ticks++ % 7 == 0) {
                  Logger.Inst().log(
                    'challenge poll: ${found == null ? 'no clearance in storage' : 'clearance ${found.substring(0, found.length < 8 ? found.length : 8)}…'} (sawEmpty=$sawEmpty)',
                    'SchaleClearanceHandler',
                    'challenge',
                    LogTypes.booruHandlerInfo,
                  );
                }
                if (found == null) {
                  sawEmpty = true;
                  return;
                }
                if (!isUsableToken(found, afterClear: sawEmpty)) return;
                timer.cancel();
                store(found);
                if (context.mounted) unawaited(Navigator.of(context).maybePop());
              });
            },
          ),
        ),
      );
    } catch (e, s) {
      Logger.Inst().log(
        'clearance challenge failed: $e',
        'SchaleClearanceHandler',
        'requestClearance',
        LogTypes.exception,
        s: s,
      );
    } finally {
      poll?.cancel();
      _challengeOpen = false;
      Logger.Inst().log(
        'challenge closed: ${hasToken ? 'token obtained' : 'NO token'}',
        'SchaleClearanceHandler',
        'challenge',
        LogTypes.booruHandlerInfo,
      );
    }
    return hasToken;
  }

  Future<String?> _readToken(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: "window.localStorage.getItem('$localStorageKey')",
      );
      return tokenFromLocalStorage(raw);
    } catch (_) {
      return null;
    }
  }
}
