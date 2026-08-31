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
    _token = value;
    _persist();
    revision.value++;
  }

  /// Called when the API rejects the token, so the next read asks for a new one
  /// rather than repeating a request that cannot succeed.
  void invalidate() {
    ensureLoaded();
    if (_token == null) return;
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

  bool _challengeOpen = false;

  /// Opens the site so the challenge can be solved by hand, then takes whatever
  /// clearance the site stored. Returns true when a token was obtained.
  ///
  /// [siteUrl] follows the configured mirror rather than being hardcoded, so a
  /// switch to shupogaki.moe challenges on the mirror actually in use.
  Future<bool> requestClearance(String siteUrl) async {
    if (_challengeOpen) return hasToken;

    _challengeOpen = true;
    try {
      // Resolved inside the try on purpose. There is no navigator before the
      // first route is mounted, or while the app is being torn down, and this
      // throws rather than returning null in that case. Outside the try it
      // took the reader down with it instead of letting loadItem report that
      // the check could not be shown.
      final BuildContext context = NavigationHandler.instance.navContext;
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
            onLoadStop: (context, controller, url) async {
              final String? found = await _readToken(controller);
              if (found != null) {
                store(found);
                // Closing on the caller's behalf: once the site has stored a
                // clearance there is nothing left to do on this page.
                if (context.mounted) unawaited(Navigator.of(context).maybePop());
              }
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
      _challengeOpen = false;
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
