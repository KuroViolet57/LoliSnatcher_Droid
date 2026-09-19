import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart' show webViewEnvironment;

/// What to do with the shared cookie jar after a FurAffinity webview closed.
enum FurAffinityJarAction { none, reseed }

/// The FurAffinity account (r40). The site's login sits behind a Cloudflare
/// Turnstile check, so the person logs in inside a WebView; the site then
/// sets its two session cookies, `a` and `b`, which are kept in the app's own
/// file and sent on the handler's page requests.
///
/// r41: the session also stays in the shared cookie jar. r40 removed it from
/// there, so a FurAffinity page opened in a webview was a guest visit, and the
/// guest `b` the site handed that visit then won over the account's `b` when
/// the app merged the jar into its requests: the feed fell back to guest
/// content. Now a FurAffinity webview gets the session before it loads
/// ([prepareWebView]) and, when it closes, newer account cookies are taken
/// and a guest jar gets the account back ([syncAfterWebView]). The image
/// hosts still never see it: the handler does not send jar cookies to media.
///
/// r42: the account's name and blocklist, as the site's own pages show them
/// ([noteUsername], [noteBlocklist]).
class FurAffinitySessionHandler {
  FurAffinitySessionHandler._();

  static final FurAffinitySessionHandler instance = FurAffinitySessionHandler._();

  static const String fileName = 'furaffinity_session.json';
  static const String site = 'https://www.furaffinity.net';
  static const List<String> jarOrigins = ['https://www.furaffinity.net/', 'https://furaffinity.net/'];
  static const Duration jarTimeout = Duration(seconds: 3);

  /// Bumped on every change so settings rows and the sidebar can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? _a;
  String? _b;
  String? _username;
  FurAffinityBlocklist? _blocklist;
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
          final String user = decoded['user']?.toString() ?? '';
          _username = user.isEmpty ? null : user;
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

  /// The account's name, once a logged-in page showed it.
  String? get username {
    ensureLoaded();
    return isLoggedIn ? _username : null;
  }

  /// The account's blocklist as the last logged-in page carried it.
  FurAffinityBlocklist? get siteBlocklist => isLoggedIn ? _blocklist : null;

  /// The `Cookie` value for a request to the site itself.
  String cookieHeader() {
    ensureLoaded();
    return isLoggedIn ? 'a=$_a; b=$_b' : '';
  }

  /// Only the site's own pages get the session.
  static bool sendsTo(Uri uri) => uri.host == 'www.furaffinity.net' || uri.host == 'furaffinity.net';

  /// [url] is one of the site's own pages.
  static bool isSiteUrl(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    return uri != null && uri.hasScheme && sendsTo(uri);
  }

  void store({required String a, required String b}) {
    ensureLoaded();
    if (a.isEmpty || b.isEmpty) return;
    if (a == _a && b == _b) return;
    _a = a;
    _b = b;
    _persist();
    revision.value++;
  }

  void noteUsername(String name) {
    ensureLoaded();
    final String clean = name.trim().toLowerCase();
    if (!isLoggedIn || clean.isEmpty || clean == _username) return;
    _username = clean;
    _persist();
    revision.value++;
  }

  void noteBlocklist(FurAffinityBlocklist blocklist) {
    if (!isLoggedIn) return;
    final FurAffinityBlocklist? old = _blocklist;
    _blocklist = blocklist;
    final bool same = old != null && old.hideTagless == blocklist.hideTagless && setEquals(old.tags, blocklist.tags) && setEquals(old.users, blocklist.users);
    if (!same) revision.value++;
  }

  void logout() {
    ensureLoaded();
    _a = null;
    _b = null;
    _username = null;
    _blocklist = null;
    try {
      final File? file = _file;
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
    revision.value++;
    scrubJar().ignore();
  }

  void _persist() {
    try {
      final File? file = _file;
      if (file == null) return;
      file.writeAsStringSync(jsonEncode({'a': _a, 'b': _b, 'user': _username, 'at': DateTime.now().millisecondsSinceEpoch}));
    } catch (e) {
      Logger.Inst().log('could not write $fileName: $e', 'FurAffinitySessionHandler', '_persist', LogTypes.exception);
    }
  }

  /// The session's two cookies out of a cookie set (name -> value), or nulls.
  static ({String? a, String? b}) fromCookiePairs(Map<String, String> pairs) {
    String? clean(String? v) => (v == null || v.isEmpty || v == 'deleted') ? null : v;
    return (a: clean(pairs['a']), b: clean(pairs['b']));
  }

  /// A webview on [url] should carry the account.
  bool webViewNeedsSession(String url) => isLoggedIn && isSiteUrl(url);

  /// What the jar says after a webview closed: both account cookies there
  /// are the newest (the site rotated them, or the person logged in inside
  /// the webview) and are kept; a jar without them while logged in lost the
  /// account to a guest visit and gets it back.
  FurAffinityJarAction afterWebView(Map<String, String> jar) {
    final parsed = fromCookiePairs(jar);
    if (parsed.a != null && parsed.b != null) {
      store(a: parsed.a!, b: parsed.b!);
      return FurAffinityJarAction.none;
    }
    return isLoggedIn ? FurAffinityJarAction.reseed : FurAffinityJarAction.none;
  }

  /// Before a webview on [url] loads: the account goes into the jar.
  Future<void> prepareWebView(String url) async {
    if (!webViewNeedsSession(url)) return;
    try {
      await seedJar().timeout(jarTimeout);
    } catch (_) {}
  }

  /// After a FurAffinity webview closed.
  Future<void> syncAfterWebView() async {
    try {
      final Map<String, String> jar = await readJar().timeout(jarTimeout);
      if (afterWebView(jar) == FurAffinityJarAction.reseed) {
        await seedJar().timeout(jarTimeout);
      }
    } catch (_) {}
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

  /// Puts the account into the jar, replacing any `a`/`b` there (a guest
  /// `b` set on the host alone would otherwise be sent next to it).
  Future<void> seedJar() async {
    if (!isLoggedIn || Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return;
    final String a = _a!;
    final String b = _b!;
    try {
      final CookieManager manager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
      for (final String origin in jarOrigins) {
        for (final String name in const ['a', 'b']) {
          try {
            await manager.deleteCookie(url: WebUri(origin), name: name);
            await manager.deleteCookie(url: WebUri(origin), name: name, domain: '.furaffinity.net');
          } catch (_) {}
        }
      }
      final int expires = DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch;
      for (final (String name, String value) in [('a', a), ('b', b)]) {
        await manager.setCookie(
          url: WebUri(site),
          name: name,
          value: value,
          domain: '.furaffinity.net',
          expiresDate: expires,
          isSecure: true,
          isHttpOnly: true,
        );
      }
    } catch (e) {
      Logger.Inst().log('could not put the session into the jar: $e', 'FurAffinitySessionHandler', 'seedJar', LogTypes.exception);
    }
  }

  /// Empties the jar for the site's origins (on log out).
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
    _username = null;
    ensureLoaded();
  }

  @visibleForTesting
  void resetForTests() {
    _loaded = true;
    _a = null;
    _b = null;
    _username = null;
    _blocklist = null;
  }
}
