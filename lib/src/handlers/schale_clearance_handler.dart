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
/// Browsing is anonymous. Reading is gated: the page list, the page dataset
/// and Related all hang off a `crt` query parameter. The site obtains that
/// token by solving a Cloudflare Turnstile and POSTing the result to
/// `auth.schale.network/clearance`, then keeps the reply in
/// `localStorage["clearance"]` and reuses it until the API refuses it.
///
/// This is TWO windows, and it only works because there are two. The design
/// is the one Keiyoushi's Koharu extension uses, which reads this site every
/// day from an embedded WebView:
///
///  * The SOLVER — [solve] — is visible and full-size. The person completes
///    the Turnstile in it by hand. It presents Chrome's reduced user agent,
///    allows pop-ups, and filters navigation for the MAIN frame only, so
///    Cloudflare's `blob:` challenge frames and workers load. It solves; it
///    never reads.
///  * The HARVESTER — [harvest] — is headless. It loads the site, reads
///    `localStorage.getItem('clearance')` once the page has finished, and
///    destroys itself. No user agent override, no navigation filter, no
///    scripts, a ten-second latch. It reads; it never solves.
///
/// They share WebView storage. That sharing IS the mechanism: the site writes
/// the clearance in the solver, the harvester reads it back. Collapsing the
/// two into one window is what broke every previous version of this.
///
/// Nothing here solves a challenge automatically, and nothing should.
class SchaleClearanceHandler {
  SchaleClearanceHandler._();

  static final SchaleClearanceHandler instance = SchaleClearanceHandler._();

  static const String fileName = 'schale_clearance.json';

  /// Where the site keeps it, and therefore where it is read from.
  static const String localStorageKey = 'clearance';

  /// How long the harvester waits for the page to finish before giving up.
  static const Duration harvestTimeout = Duration(seconds: 10);

  /// The message a gated call surfaces when there is no usable token. The
  /// detail page turns it into a button that opens the solver.
  static const String needsSolveMessage =
      'niyaniya needs a one-time check before it will serve pages. Open the check to complete it.';

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
    // Whatever is being stored was just produced or re-validated by the
    // site, so nothing is "rejected" any more — including the same string.
    _rejectedToken = null;
    _token = value;
    _persist();
    revision.value++;
  }

  /// The token the API most recently refused.
  ///
  /// The site keeps its clearance in the page's own localStorage, and
  /// dropping OUR copy does nothing to that. The harvester would read the
  /// same dead token straight back out of storage, so it must know which
  /// value not to trust, and the solver must delete it before the site's own
  /// code can see it — otherwise the site sees a stored clearance and never
  /// renders a Turnstile at all.
  String? _rejectedToken;

  @visibleForTesting
  String? get rejectedToken => _rejectedToken;

  /// Called when the API answers 400 or 403 to a gated call. Drops the token;
  /// the caller surfaces "open the check" and does NOT retry silently.
  void invalidate() {
    ensureLoaded();
    if (_token == null) return;
    _rejectedToken = _token;
    _token = null;
    _persist();
    revision.value++;
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
  /// `evaluateJavascript` hands back the raw value, which is a bare string, a
  /// quoted string, or null depending on platform.
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

  /// Whether a value read from storage is worth adopting: present, and not
  /// the one the API just refused.
  @visibleForTesting
  bool isUsableToken(String? candidate) =>
      candidate != null && candidate.isNotEmpty && candidate != _rejectedToken;

  // ── the harvester ─────────────────────────────────────────────────────

  bool _harvesting = false;

  /// Reads the site's stored clearance from a headless webview.
  ///
  /// Exactly Koharu's `getClearance()`: JavaScript and DOM storage on,
  /// network images off, load the site, read `localStorage['clearance']` on
  /// page finished, destroy. No user agent override and no scripts — this
  /// window never has to pass anything, it only has to share storage with the
  /// window that did.
  ///
  /// Returns the token, or null when storage holds nothing usable within
  /// [harvestTimeout].
  Future<String?> harvest(String siteUrl) async {
    ensureLoaded();
    if (_token != null) return _token;
    if (_harvesting) return null;
    _harvesting = true;

    final Completer<String?> done = Completer<String?>();
    HeadlessInAppWebView? headless;
    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(siteUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          blockNetworkImage: true,
        ),
        onLoadStop: (controller, url) async {
          if (done.isCompleted) return;
          try {
            final raw = await controller.evaluateJavascript(
              source: "window.localStorage.getItem('$localStorageKey')",
            );
            final String? found = tokenFromLocalStorage(raw);
            _log('harvest: page finished at ${url?.host ?? '?'}, storage=${_describe(found)}');
            if (!done.isCompleted) done.complete(isUsableToken(found) ? found : null);
          } catch (e) {
            _log('harvest: read failed: $e');
            if (!done.isCompleted) done.complete(null);
          }
        },
      );
      await headless.run();
      final String? found = await done.future.timeout(
        harvestTimeout,
        onTimeout: () {
          _log('harvest: timed out after ${harvestTimeout.inSeconds}s');
          return null;
        },
      );
      if (found != null) store(found);
      return found;
    } catch (e, s) {
      Logger.Inst().log('harvest failed: $e', 'SchaleClearanceHandler', 'harvest', LogTypes.exception, s: s);
      return null;
    } finally {
      _harvesting = false;
      try {
        await headless?.dispose();
      } catch (_) {}
    }
  }

  // ── the solver ────────────────────────────────────────────────────────

  bool _solverOpen = false;

  /// Chrome's reduced user agent, the shape Mihon's WebView presents and the
  /// one Cloudflare is known to accept from an embedded window. The major
  /// version follows the device's own Chrome build; everything that could
  /// identify the device is gone.
  ///
  /// The site's bundle refuses to render a Turnstile for any agent containing
  /// `wv`, so the WebView's own string can never be used here.
  static String reducedChromeUserAgent(String deviceUserAgent) {
    final RegExp major = RegExp(r'Chrome/(\d+)');
    final String version = major.firstMatch(deviceUserAgent)?.group(1) ?? '149';
    return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/$version.0.0.0 Mobile Safari/537.36';
  }

  /// The site, its API and its auth host. Only MAIN-frame navigation is held
  /// to this list: an interstitial that replaces the page is refused, while
  /// Cloudflare's challenge frames — including its `blob:` frames and workers,
  /// which the site's own security policy grants — load untouched. Filtering
  /// sub-frames is what starved the Turnstile before.
  static List<String> allowedMainFrameHosts(String siteUrl) {
    final String host = Uri.tryParse(siteUrl)?.host ?? '';
    return [
      if (host.isNotEmpty) host,
      'schale.network',
      'niyaniya.moe',
      'shupogaki.moe',
    ];
  }

  /// Injected into the SOLVER before the site's own code runs, to delete a
  /// clearance the API has already refused. Otherwise the page sees a stored
  /// clearance and never renders the Turnstile. Removes only the refused
  /// value, so a clearance earned during this very visit survives a redirect.
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

  /// The bridge name the solver page reports through.
  static const String bridgeName = 'lsClearance';

  /// Injected into the SOLVER at document start. Reports the links that
  /// decide the outcome: the Turnstile rendering, its callback or error, the
  /// POST to auth.schale.network and what it answered, and the site writing
  /// `localStorage["clearance"]`. Every hook calls straight through.
  ///
  /// `window.turnstile` is captured with a property setter so the wrapper is
  /// in place the instant Cloudflare's script assigns it. The previous version
  /// polled for it and lost the race every time, which is why no
  /// `turnstile.render` line ever appeared in a log.
  static const String diagnosticScript = r'''
(() => {
  if (window.__lsClearanceHook) return;
  window.__lsClearanceHook = true;
  const say = (event, detail) => {
    try { window.flutter_inappwebview.callHandler('lsClearance', { event, detail: String(detail || '').slice(0, 300) }); } catch (e) {}
  };
  say('page', location.href + ' | stored=' + (localStorage.getItem('clearance') ? 'present' : 'null'));

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

  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) { this.__lsMethod = String(m); this.__lsUrl = String(u); return origOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function () {
    const u = this.__lsUrl || '';
    if (/schale\.network/.test(u)) {
      this.addEventListener('loadend', () => say('xhr', (this.__lsMethod || '?') + ' ' + this.status + ' ' + u.replace(/crt=[^&]+/, 'crt=…') + ' | ' + String(this.responseText || '').slice(0, 120)));
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

  const wrap = (t) => {
    if (!t || t.__lsWrapped || typeof t.render !== 'function') return t;
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
    return t;
  };
  let held = window.turnstile;
  try {
    Object.defineProperty(window, 'turnstile', {
      configurable: true,
      get() { return held; },
      set(v) { held = wrap(v); },
    });
  } catch (e) {}
  if (held) held = wrap(held);
  window.addEventListener('error', (e) => say('js.error', (e.message || '') + ' @' + (e.filename || '') + ':' + e.lineno));
})();
''';

  /// Opens the site full-size so the challenge can be solved by hand.
  ///
  /// Does not read anything. When the page reports that the site has written
  /// a clearance, the window closes itself; the caller then runs [harvest].
  /// Returns true when the site was seen to store a clearance.
  Future<bool> solve(String siteUrl) async {
    if (_solverOpen) return false;
    _solverOpen = true;
    bool stored = false;
    try {
      // Resolved inside the try: there is no navigator before the first route
      // mounts, and this throws rather than returning null in that case.
      final BuildContext context = NavigationHandler.instance.navContext;
      final String? rejected = _rejectedToken;
      _log('solver opened on $siteUrl (rejected=${_describe(rejected)})');

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => InAppWebviewView(
            initialUrl: siteUrl,
            title: 'Reader access',
            subtitle: 'Complete the check. This window closes by itself once the site accepts it.',
            userAgent: reducedChromeUserAgent(Tools.browserUserAgent),
            restrictMainFrameHosts: allowedMainFrameHosts(siteUrl),
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
                  final call = args.isNotEmpty ? args.first : null;
                  if (call is! Map) return null;
                  _log('solver page: ${call['event']} — ${call['detail']}');
                  // The site wrote a clearance. The solver's job is done; the
                  // harvester reads it.
                  if (call['event'] == 'setItem' && !stored) {
                    stored = true;
                    if (context.mounted) unawaited(Navigator.of(context).maybePop());
                  }
                  return null;
                },
              );
            },
          ),
        ),
      );
    } catch (e, s) {
      Logger.Inst().log('solver failed: $e', 'SchaleClearanceHandler', 'solve', LogTypes.exception, s: s);
    } finally {
      _solverOpen = false;
      _log('solver closed: ${stored ? 'site stored a clearance' : 'no clearance was stored'}');
    }
    return stored;
  }

  /// The full manual flow: harvest what the site already holds; if nothing,
  /// open the solver, then harvest again. Returns the token or null.
  Future<String?> obtain(String siteUrl) async {
    final String? existing = await harvest(siteUrl);
    if (existing != null) return existing;
    await solve(siteUrl);
    return harvest(siteUrl);
  }

  static String _describe(String? token) =>
      token == null ? 'none' : '${token.substring(0, token.length < 8 ? token.length : 8)}…';

  static void _log(String message) => Logger.Inst().log(
    message,
    'SchaleClearanceHandler',
    'clearance',
    LogTypes.booruHandlerInfo,
  );
}
