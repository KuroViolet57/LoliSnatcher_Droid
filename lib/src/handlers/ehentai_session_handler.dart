import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// The e-hentai forum session, kept in `ehentai_session.json` beside the
/// settings — and deliberately NOT in the shared WebView cookie jar.
///
/// The jar's cookies for a source's host ride on every media request the
/// app makes for that source (`Tools.getFileCustomHeaders`), and e-hentai's
/// images come from hath.network nodes run by volunteers: a session cookie
/// there is an account handed to a stranger. So the login page copies the
/// two cookies the forum sets (`ipb_member_id`, `ipb_pass_hash`) into this
/// file and deletes them from the jar; the handler adds them to its own
/// requests to the site hosts only, and the settings page puts them back
/// into the jar just for the time an in-app browser tab is open.
///
/// `igneous` is exhentai.org's own cookie, set on the first visit with the
/// two forum cookies; the value `mystery` means the account has no access.
class EHentaiSessionHandler {
  EHentaiSessionHandler._();

  static final EHentaiSessionHandler instance = EHentaiSessionHandler._();

  static const String fileName = 'ehentai_session.json';

  /// The origins the site's cookies are written to.
  static const List<String> jarOrigins = [
    'https://e-hentai.org/',
    'https://forums.e-hentai.org/',
    'https://exhentai.org/',
  ];

  /// Cookie names that make up a session, as the forum sets them.
  static const String memberIdCookie = 'ipb_member_id';
  static const String passHashCookie = 'ipb_pass_hash';
  static const String igneousCookie = 'igneous';

  /// Bumped on every change so settings rows can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? _memberId;
  String? _passHash;
  String? _igneous;
  int _savedAt = 0;
  bool _loaded = false;

  /// Test seam: answers the exhentai probe with its `set-cookie` headers.
  @visibleForTesting
  Future<List<String>> Function(Map<String, String> headers)? setCookieFetcher;

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
      if (decoded is Map) {
        _memberId = decoded['memberId']?.toString();
        _passHash = decoded['passHash']?.toString();
        _igneous = decoded['igneous']?.toString();
        _savedAt = int.tryParse(decoded['at']?.toString() ?? '') ?? 0;
        if ((_memberId ?? '').isEmpty || (_passHash ?? '').isEmpty) {
          _memberId = null;
          _passHash = null;
        }
        if ((_igneous ?? '').isEmpty) _igneous = null;
      }
    } catch (e) {
      Logger.Inst().log('could not read $fileName: $e', 'EHentaiSessionHandler', 'ensureLoaded', LogTypes.exception);
    }
  }

  String? get memberId {
    ensureLoaded();
    return _memberId;
  }

  String? get igneous {
    ensureLoaded();
    return _igneous;
  }

  int get savedAt {
    ensureLoaded();
    return _savedAt;
  }

  bool get isLoggedIn {
    ensureLoaded();
    return (_memberId ?? '').isNotEmpty && (_passHash ?? '').isNotEmpty;
  }

  /// A usable exhentai cookie: present and not the site's "no access" value.
  bool get hasExHentai => isLoggedIn && (igneous ?? '').isNotEmpty && igneous != 'mystery';

  /// The `Cookie` header for a request to the site itself. `nw=1` skips the
  /// content-warning interstitial some galleries show.
  String cookieHeader({required bool exhentai}) {
    ensureLoaded();
    final List<String> parts = ['nw=1'];
    if (isLoggedIn) {
      parts.add('$memberIdCookie=$_memberId');
      parts.add('$passHashCookie=$_passHash');
      if (exhentai && hasExHentai) parts.add('$igneousCookie=$_igneous');
    }
    return parts.join('; ');
  }

  /// The cookie pairs for a browser visit on [exhentai] or e-hentai.
  Map<String, String> cookiePairs({required bool exhentai}) {
    ensureLoaded();
    if (!isLoggedIn) return const {};
    return {
      memberIdCookie: _memberId!,
      passHashCookie: _passHash!,
      if (exhentai && hasExHentai) igneousCookie: _igneous!,
    };
  }

  void store({required String memberId, required String passHash, String? igneous}) {
    ensureLoaded();
    if (memberId.isEmpty || passHash.isEmpty) return;
    _memberId = memberId;
    _passHash = passHash;
    if (igneous != null && igneous.isNotEmpty) _igneous = igneous;
    _savedAt = DateTime.now().millisecondsSinceEpoch;
    _persist();
    revision.value++;
  }

  void setIgneous(String? value) {
    ensureLoaded();
    _igneous = (value ?? '').isEmpty ? null : value;
    _persist();
    revision.value++;
  }

  void logout() {
    ensureLoaded();
    _memberId = null;
    _passHash = null;
    _igneous = null;
    _savedAt = 0;
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
      if (!isLoggedIn) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(jsonEncode({'memberId': _memberId, 'passHash': _passHash, 'igneous': _igneous, 'at': _savedAt}));
    } catch (e) {
      Logger.Inst().log('could not write $fileName: $e', 'EHentaiSessionHandler', '_persist', LogTypes.exception);
    }
  }

  /// The session cookies the forum left in the shared jar.
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

  /// Puts the session into the jar for one host, for as long as an in-app
  /// browser tab is open on it. [scrubJar] undoes it.
  Future<void> seedJar(String host, Map<String, String> pairs) async {
    if (pairs.isEmpty || Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return;
    final String domain = '.${Uri.parse(host).host}';
    await Tools.saveCookies(host, [for (final e in pairs.entries) '${e.key}=${e.value}; domain=$domain; path=/; secure']);
  }

  /// Empties the jar for the site's origins. Everything, not a list of
  /// names: the site sets more cookies than the two (`sk`, `ipb_session_id`,
  /// `igneous`…) and any of them identifies the account.
  Future<void> scrubJar() async {
    if (Tools.isTestMode || !Tools.isOnPlatformWithWebviewSupport) return;
    try {
      final CookieManager manager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
      for (final String origin in jarOrigins) {
        try {
          await manager.deleteCookies(url: WebUri(origin));
          await manager.deleteCookies(url: WebUri(origin), domain: '.${Uri.parse(origin).host}');
        } catch (_) {}
      }
    } catch (_) {
      // No WebView on this platform (or none yet): nothing to scrub.
    }
  }

  /// Called once when the source is first used: a session left behind by a
  /// crash, an older build, or the app's generic in-app browser must not
  /// stay in the jar.
  static bool _scrubbedOnce = false;
  void scrubJarOnce() {
    if (_scrubbedOnce) return;
    _scrubbedOnce = true;
    unawaited(scrubJar());
  }

  /// The session's two cookies out of a cookie set (name -> value), or nulls.
  static ({String? memberId, String? passHash, String? igneous}) fromCookiePairs(Map<String, String> pairs) {
    String? clean(String? v) => (v == null || v.isEmpty || v == 'deleted' || v == '0') ? null : v;
    return (
      memberId: clean(pairs[memberIdCookie]),
      passHash: clean(pairs[passHashCookie]),
      igneous: clean(pairs[igneousCookie]),
    );
  }

  /// `igneous` out of a response's `set-cookie` headers.
  static String? igneousFromSetCookie(List<String> headers) {
    for (final String h in headers) {
      final String first = h.split(';').first.trim();
      final int eq = first.indexOf('=');
      if (eq > 0 && first.substring(0, eq).trim() == igneousCookie) {
        final String v = first.substring(eq + 1).trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  /// Visits exhentai.org once with the forum cookies so it hands out its
  /// `igneous`. Returns whether the account can read exhentai.
  Future<(bool ok, String message)> fetchIgneous() async {
    ensureLoaded();
    if (!isLoggedIn) return (false, 'Not logged in.');
    final Map<String, String> headers = {
      'User-Agent': Tools.browserUserAgent,
      'Accept': 'text/html',
      'Cookie': '$memberIdCookie=$_memberId; $passHashCookie=$_passHash',
    };
    List<String> setCookies;
    try {
      if (setCookieFetcher != null) {
        setCookies = await setCookieFetcher!(headers);
      } else {
        final Response response = await DioNetwork.get(
          'https://exhentai.org/',
          headers: headers,
          options: Options(followRedirects: false, validateStatus: (_) => true),
        );
        setCookies = response.headers['set-cookie'] ?? const [];
      }
    } catch (e) {
      return (false, 'exhentai.org did not answer: $e');
    }
    final String? value = igneousFromSetCookie(setCookies);
    if (value == null) {
      // A session that already had one keeps it; the site only sets the
      // cookie when it is missing.
      if (hasExHentai) return (true, 'exhentai access kept.');
      return (false, 'exhentai.org set no access cookie for this account.');
    }
    setIgneous(value);
    if (value == 'mystery') return (false, 'This account has no exhentai access yet (the site answered "mystery").');
    return (true, 'exhentai access confirmed.');
  }

  @visibleForTesting
  void reloadForTests() {
    _loaded = false;
    _memberId = null;
    _passHash = null;
    _igneous = null;
    _savedAt = 0;
    ensureLoaded();
  }

  @visibleForTesting
  void resetForTests() {
    _loaded = true;
    _memberId = null;
    _passHash = null;
    _igneous = null;
    _savedAt = 0;
    setCookieFetcher = null;
  }
}
