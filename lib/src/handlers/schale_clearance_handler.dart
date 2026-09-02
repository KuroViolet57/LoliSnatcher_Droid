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
    // The page client reloads on its next call, so it runs with this token.
    unawaited(_disposePageClient());
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

  // ── the page client ───────────────────────────────────────────────────
  //
  // Observed 2026-09-02 (log 12:31–12:33): five fresh clearances in a row;
  // for each, the site's OWN page spent the token with a 200 while the app's
  // Dio request with the same token, same agent, same Referer/Origin got a
  // 403 within the same second — no rate-limit headers, an empty body. The
  // first token had worked for three galleries. Whatever the server keys on
  // (TLS fingerprint, client hints, cookies the page does not send), the
  // page's request is the one that is accepted, so the two gated calls are
  // made FROM the page: a headless WebView kept on the site's origin runs a
  // plain fetch, exactly the XMLHttpRequest the site itself uses (no
  // credentials, no custom headers). Dio remains the fallback when the page
  // cannot be started. This is a third role beside the solver and the
  // harvester, and touches neither.

  HeadlessInAppWebView? _pageClient;
  InAppWebViewController? _pageController;
  Future<bool>? _pageStarting;
  String _pageSite = '';

  static const Duration pageClientTimeout = Duration(seconds: 12);

  /// The page client loads a document on the site's ORIGIN that runs none of
  /// the site's code: robots.txt. Loading the real page ran the site's
  /// invisible Turnstile a second time per solve and redeemed extra
  /// clearances (log 2026-09-02 12:58, after which every redemption was 403).
  /// A fetch from this document carries the origin, which is all the gated
  /// calls need.
  static String pageClientUrl(String siteUrl) {
    final String base = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    return '$base/robots.txt';
  }

  /// True when the last solver session saw the site's auth endpoint refuse
  /// the redemption (`POST …/clearance → 403`): the check itself passed and
  /// the token was rejected by the server. Nothing in the app changes that.
  bool lastSolveAuthRefused = false;

  static const String authRefusedMessage =
      'The check passed but niyaniya refused to issue a clearance (auth 403). '
      'That is a server-side refusal of this address or session, not the widget. '
      'Wait a while before trying again; if the site also fails in Chrome on this phone, it is the address.';

  /// The JS run inside the page for one gated call. Same shape as the site's
  /// XHR: no credentials, no body, no custom headers. Returns status + text.
  static const String pageRequestScript = '''
try {
  const r = await fetch(url, { method: method, credentials: 'omit' });
  const t = await r.text();
  return { status: r.status, body: t };
} catch (e) {
  return { status: -1, body: String(e) };
}
''';

  Future<bool> _startPageClient(String siteUrl) {
    // Only where a WebView exists; anywhere else (unit tests, desktop) the
    // caller falls back to Dio at once instead of waiting on a dead channel.
    if (!(Platform.isAndroid || Platform.isIOS)) return Future.value(false);
    if (_pageController != null && _pageSite == siteUrl) return Future.value(true);
    final Future<bool>? starting = _pageStarting;
    if (starting != null) return starting;
    final Completer<bool> done = Completer<bool>();
    _pageStarting = done.future;
    () async {
      await _disposePageClient();
      _pageSite = siteUrl;
      try {
        final HeadlessInAppWebView client = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(pageClientUrl(siteUrl))),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            blockNetworkImage: true,
            // The agent the solver presented when the page's own request was
            // seen to succeed.
            userAgent: reducedChromeUserAgent(Tools.browserUserAgent),
          ),
          onLoadStop: (controller, url) {
            _pageController = controller;
            _log('page client: ready at ${url?.host ?? '?'}');
            if (!done.isCompleted) done.complete(true);
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) {
              _log('page client: load error ${error.description}');
              if (!done.isCompleted) done.complete(false);
            }
          },
        );
        _pageClient = client;
        await client.run().timeout(pageClientTimeout);
        final bool ok = await done.future.timeout(pageClientTimeout, onTimeout: () {
          _log('page client: timed out after ${pageClientTimeout.inSeconds}s');
          return false;
        });
        if (!ok) await _disposePageClient();
      } catch (e, s) {
        Logger.Inst().log('page client failed: $e', 'SchaleClearanceHandler', '_startPageClient', LogTypes.exception, s: s);
        await _disposePageClient();
        if (!done.isCompleted) done.complete(false);
      } finally {
        _pageStarting = null;
      }
    }();
    return done.future;
  }

  Future<void> _disposePageClient() async {
    final HeadlessInAppWebView? client = _pageClient;
    _pageClient = null;
    _pageController = null;
    _pageSite = '';
    try {
      await client?.dispose();
    } catch (_) {}
  }

  /// Runs one gated request from inside the site's page. Null when the page
  /// client cannot be started (the caller then falls back to Dio).
  Future<({int status, String body})?> pageRequest(String siteUrl, {required String url, required String method}) async {
    if (!await _startPageClient(siteUrl)) return null;
    final InAppWebViewController? controller = _pageController;
    if (controller == null) return null;
    try {
      final CallAsyncJavaScriptResult? result = await controller
          .callAsyncJavaScript(functionBody: pageRequestScript, arguments: {'url': url, 'method': method})
          .timeout(pageClientTimeout);
      final value = result?.value;
      if (result?.error != null || value is! Map) {
        _log('page client: call failed: ${result?.error ?? value}');
        return null;
      }
      final int status = (value['status'] as num?)?.toInt() ?? -1;
      final String body = value['body']?.toString() ?? '';
      _log('page client: $method ${url.replaceAll(RegExp('crt=[^&]+'), 'crt=…')} → $status');
      if (status < 0) return null;
      return (status: status, body: body);
    } catch (e) {
      _log('page client: $e');
      await _disposePageClient();
      return null;
    }
  }

  /// Called when the API answers 400 or 403 to a gated call. Drops the token;
  /// the caller surfaces "open the check" and does NOT retry silently.
  void invalidate() {
    ensureLoaded();
    if (_token == null) return;
    _rejectedToken = _token;
    _token = null;
    _persist();
    revision.value++;
    unawaited(_disposePageClient());
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
  /// `window.turnstile` is NOT hooked (api.js refuses to install over an existing
  /// property); the challenge is observed through the DOM and its own requests, so the wrapper is
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

  // The four values the site's own gates read before it will draw a
  // Turnstile. Logged raw, BEFORE anything below touches them:
  //   /webview|wv/i.test(navigator.userAgent) || navigator.webdriver  → no widget
  //   await (window.outerWidth && window.outerHeight)                 → waits forever
  const env = () => 'ua=' + navigator.userAgent + ' | webdriver=' + navigator.webdriver +
    ' | outer=' + window.outerWidth + 'x' + window.outerHeight + ' | inner=' + window.innerWidth + 'x' + window.innerHeight +
    ' | ready=' + document.readyState;
  say('env', env());
  setTimeout(() => say('env+2s', env()), 2000);

  // Android's WebView is known to report 0 for outerWidth/outerHeight. The
  // site polls requestAnimationFrame until both are truthy, so a 0 here means
  // the widget is never rendered no matter what the agent says. Applied ONLY
  // when they really are 0 — the log line above shows what they were.
  try {
    if (!window.outerWidth || !window.outerHeight) {
      Object.defineProperty(window, 'outerWidth', { configurable: true, get: () => window.innerWidth || screen.width || 1 });
      Object.defineProperty(window, 'outerHeight', { configurable: true, get: () => window.innerHeight || screen.height || 1 });
      say('shim', 'outerWidth/outerHeight were 0 → now report inner size ' + window.outerWidth + 'x' + window.outerHeight);
    }
  } catch (e) { say('shim.error', e); }

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

  // Turnstile is observed, never touched. Cloudflare's api.js opens with
  // `"turnstile" in window` and treats an existing property as "imported
  // multiple times" — the previous defineProperty hook made that true before
  // api.js ran, and the widget was never installed. Now: the script's own
  // load event, the challenge iframe appearing, and the API object's shape.
  const cfIframe = (n) => n && n.tagName === 'IFRAME' && /challenges\.cloudflare\.com/.test(n.src || '');
  const cfScript = (n) => n && n.tagName === 'SCRIPT' && /challenges\.cloudflare\.com/.test(n.src || '');
  try {
    new MutationObserver((muts) => {
      for (const m of muts) {
        for (const n of m.addedNodes) {
          if (cfScript(n)) {
            say('turnstile.script', n.src);
            n.addEventListener('load', () => say('turnstile.loaded', 'typeof window.turnstile=' + typeof window.turnstile +
              ' render=' + typeof (window.turnstile && window.turnstile.render)));
            n.addEventListener('error', () => say('turnstile.script.error', n.src));
          }
          if (cfIframe(n)) say('turnstile.iframe', (n.src || '').slice(0, 80));
          if (n.querySelectorAll) {
            for (const f of n.querySelectorAll('iframe')) if (cfIframe(f)) say('turnstile.iframe', (f.src || '').slice(0, 80));
          }
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) { say('observer.error', e); }
  setTimeout(() => say('turnstile+5s', 'typeof window.turnstile=' + typeof window.turnstile +
    ' iframes=' + Array.from(document.querySelectorAll('iframe')).filter(cfIframe).length), 5000);
  window.addEventListener('error', (e) => say('js.error', (e.message || '') + ' @' + (e.filename || '') + ':' + e.lineno));
})();
''';

  /// Opens the site full-size so the challenge can be solved by hand.
  ///
  /// Does not read anything. When the page reports that the site has written
  /// a clearance, the window closes itself; the caller then runs [harvest].
  /// Returns true when the site was seen to store a clearance.
  ///
  /// [startUrl] is the page whose read was refused (the gallery), so the
  /// window opens where the site demanded the clearance rather than on the
  /// home feed; it falls back to [siteUrl].
  Future<bool> solve(String siteUrl, {String? startUrl}) async {
    if (_solverOpen) return false;
    _solverOpen = true;
    bool stored = false;
    try {
      // Resolved inside the try: there is no navigator before the first route
      // mounts, and this throws rather than returning null in that case.
      final BuildContext context = NavigationHandler.instance.navContext;
      final String? rejected = _rejectedToken;
      lastSolveAuthRefused = false;
      final String openAt = (startUrl != null && startUrl.isNotEmpty) ? startUrl : siteUrl;
      _log('solver opened on $openAt (site=$siteUrl, rejected=${_describe(rejected)})');

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => InAppWebviewView(
            initialUrl: openAt,
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
                  final String detail = call['detail']?.toString() ?? '';
                  if (call['event'] == 'xhr' && detail.startsWith('POST 403 https://auth.schale.network/clearance')) {
                    lastSolveAuthRefused = true;
                  }
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
