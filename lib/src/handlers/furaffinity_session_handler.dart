import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart' show webViewEnvironment;

/// The FurAffinity account (r40). The site's login sits behind a Cloudflare
/// Turnstile check, so the person logs in inside a WebView; the site then
/// sets its two session cookies, `a` and `b`. They are copied here, into the
/// app's own file, and removed from the shared jar — the app's HTTP client
/// adds jar cookies to every request, and the site's images come from other
/// hosts that have no business seeing an account. The handler sends them to
/// www.furaffinity.net only ([sendsTo]).
class FurAffinitySessionHandler {
  FurAffinitySessionHandler._();

  static final FurAffinitySessionHandler instance = FurAffinitySessionHandler._();

  static const String fileName = 'furaffinity_session.json';
  static const List<String> jarOrigins = ['https://www.furaffinity.net/', 'https://furaffinity.net/'];

  /// Bumped on every change so settings rows can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? _a;
  String? _b;
  bool _loaded = false;

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
      final dynamic decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        final String a = decoded['a']?.toString() ?? '';
        final String b = decoded['b']?.toString() ?? '';
        if (a.isNotEmpty && b.isNotEmpty) {
          _a = a;
          _b = b;
        }
      }
    } catch (e) {
      Logger.Inst().log('could not read $fileName: $e', 'FurAffinitySessionHandler', 'ensureLoaded', LogTypes.exception);
    }
  }

  bool get isLoggedIn {
    ensureLoaded();
    return (_a ?? '').isNotEmpty && (_b ?? '').isNotEmpty;
  }

  /// The `Cookie` value for a request to the site itself.
  String cookieHeader() {
    ensureLoaded();
    return isLoggedIn ? 'a=$_a; b=$_b' : '';
  }

  /// Only the site's own pages get the session.
  static bool sendsTo(Uri uri) => uri.host == 'www.furaffinity.net' || uri.host == 'furaffinity.net';

  void store({required String a, required String b}) {
    ensureLoaded();
    if (a.isEmpty || b.isEmpty) return;
    _a = a;
    _b = b;
    _persist();
    revision.value++;
  }

  void logout() {
    ensureLoaded();
    _a = null;
    _b = null;
    try {
      final File? file = _file;
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
    revision.value++;
  }

  void _persist() {
    try {
      final File? file = _file;
      if (file == null) return;
      file.writeAsStringSync(jsonEncode({'a': _a, 'b': _b, 'at': DateTime.now().millisecondsSinceEpoch}));
    } catch (e) {
      Logger.Inst().log('could not write $fileName: $e', 'FurAffinitySessionHandler', '_persist', LogTypes.exception);
    }
  }

  /// The session's two cookies out of a cookie set (name -> value), or nulls.
  static ({String? a, String? b}) fromCookiePairs(Map<String, String> pairs) {
    String? clean(String? v) => (v == null || v.isEmpty || v == 'deleted') ? null : v;
    return (a: clean(pairs['a']), b: clean(pairs['b']));
  }

  /// The site's cookies in the shared jar (the login WebView writes them there).
  Future<Map<String, String>> readJar() async {
    if (Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return const {};
    final Map<String, String> pairs = {};
    try {
      final CookieManager manager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
      for (final String origin in jarOrigins) {
        try {
          for (final Cookie c in await manager.getCookies(url: WebUri(origin))) {
            pairs[c.name] = c.value.toString();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return pairs;
  }

  /// Puts the session into the jar for as long as an in-app browser tab is
  /// open on the site (the account's settings page). [scrubJar] undoes it.
  Future<void> seedJar() async {
    if (!isLoggedIn || Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return;
    await Tools.saveCookies(FurAffinityQueryHost.site, [
      // No spaces: saveCookies splits on ';' and '=' without trimming.
      'a=$_a;domain=.furaffinity.net;path=/;secure',
      'b=$_b;domain=.furaffinity.net;path=/;secure',
    ]);
  }

  /// Empties the jar for the site's origins.
  Future<void> scrubJar() async {
    if (Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return;
    try {
      final CookieManager manager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
      for (final String origin in jarOrigins) {
        try {
          await manager.deleteCookies(url: WebUri(origin));
          await manager.deleteCookies(url: WebUri(origin), domain: '.furaffinity.net');
        } catch (_) {}
      }
    } catch (_) {}
  }

  @visibleForTesting
  void reloadForTests() {
    _loaded = false;
    _a = null;
    _b = null;
    ensureLoaded();
  }

  @visibleForTesting
  void resetForTests() {
    _loaded = true;
    _a = null;
    _b = null;
  }
}

/// The site's address without importing the query library here.
class FurAffinityQueryHost {
  const FurAffinityQueryHost._();
  static const String site = 'https://www.furaffinity.net';
}
