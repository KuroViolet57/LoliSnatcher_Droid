import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The kemono account session: the `session` cookie the site sets after
/// `POST /api/v1/authentication/login`, kept per username beside the settings
/// (`kemono_session.json`), attached by the API helper to every call as
/// `Cookie: session=…`. The password itself is never written here; it stays
/// in the booru config like every other source's key. One login attempt per
/// username per minute at most, so a wrong password cannot become a storm.
class KemonoSessionHandler {
  KemonoSessionHandler._();

  static final KemonoSessionHandler instance = KemonoSessionHandler._();

  static const String fileName = 'kemono_session.json';
  static const String site = 'https://kemono.cr';
  static const String api = '$site/api/v1';
  static const Duration reloginInterval = Duration(seconds: 60);

  /// Rises whenever a session appears or goes, so sidebars can re-read.
  final ValueNotifier<int> revision = ValueNotifier(0);

  final Map<String, ({String cookie, int at})> _sessions = {};
  final Map<String, int> _lastAttempt = {};
  bool _loaded = false;

  File? get _file {
    try {
      return File('${SettingsHandler.instance.path}$fileName');
    } catch (_) {
      return null;
    }
  }

  static String keyFor(Booru booru) => (booru.userID ?? '').trim().toLowerCase();

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final File? file = _file;
      if (file == null || !file.existsSync()) return;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map && value['cookie'] is String && (value['cookie'] as String).isNotEmpty) {
          _sessions[entry.key.toString()] = (
            cookie: value['cookie'] as String,
            at: int.tryParse(value['at']?.toString() ?? '') ?? 0,
          );
        }
      }
    } catch (_) {}
  }

  void _persist() {
    try {
      final File? file = _file;
      if (file == null) return;
      if (_sessions.isEmpty) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(
        jsonEncode({for (final e in _sessions.entries) e.key: {'cookie': e.value.cookie, 'at': e.value.at}}),
      );
    } catch (e, s) {
      Logger.Inst().log('failed to persist kemono session: $e', 'KemonoSessionHandler', '_persist', LogTypes.exception, s: s);
    }
  }

  /// `session=…` for this booru's username, or null when signed out.
  String? cookieFor(Booru? booru) {
    if (booru == null) return null;
    ensureLoaded();
    final String key = keyFor(booru);
    if (key.isEmpty) return null;
    return _sessions[key]?.cookie;
  }

  bool hasSession(Booru? booru) => cookieFor(booru) != null;

  /// Whether the booru carries both a username and a password.
  static bool hasCredentials(Booru? booru) =>
      (booru?.userID?.trim().isNotEmpty ?? false) && (booru?.apiKey?.trim().isNotEmpty ?? false);

  /// `session=abc` out of a Set-Cookie list, or null when the site set none.
  @visibleForTesting
  static String? sessionCookieFrom(List<String> setCookie) {
    for (final String raw in setCookie) {
      final String pair = raw.split(';').first.trim();
      if (pair.toLowerCase().startsWith('session=') && pair.length > 'session='.length) return pair;
    }
    return null;
  }

  static Map<String, String> _headers() => {
    'Accept': 'text/css',
    'Content-Type': 'application/json',
    'User-Agent': Tools.browserUserAgent,
    'Referer': '$site/',
    'Origin': site,
  };

  /// Signs in with the booru's username and password. The message is meant
  /// for the person.
  Future<(bool ok, String message)> login(Booru booru) async {
    ensureLoaded();
    final String key = keyFor(booru);
    if (!hasCredentials(booru)) return (false, 'Enter a username and password in the booru settings first');
    _lastAttempt[key] = DateTime.now().millisecondsSinceEpoch;
    try {
      final Response response = await DioNetwork.post(
        '$api/authentication/login',
        data: jsonEncode({'username': booru.userID!.trim(), 'password': booru.apiKey}),
        headers: _headers(),
        options: Options(validateStatus: (_) => true, responseType: ResponseType.plain),
      );
      final int status = response.statusCode ?? -1;
      if (status == 200 || status == 201) {
        final String? cookie = sessionCookieFrom(response.headers.map['set-cookie'] ?? const []);
        if (cookie == null) {
          _log('login answered $status without a session cookie');
          return (false, 'kemono signed in but sent no session cookie');
        }
        _sessions[key] = (cookie: cookie, at: DateTime.now().millisecondsSinceEpoch);
        _persist();
        revision.value++;
        _log('signed in as ${booru.userID}');
        return (true, 'Signed in to kemono');
      }
      if (status == 409) {
        // Already logged in on the site's side (a session the shared cookie
        // jar still holds). Adopt it if it works, otherwise sign out and try
        // once more.
        final String? jar = await _sessionFromJar();
        if (jar != null) {
          _sessions[key] = (cookie: jar, at: DateTime.now().millisecondsSinceEpoch);
          _persist();
          revision.value++;
          _log('adopted the existing session for ${booru.userID}');
          return (true, 'Signed in to kemono');
        }
        await _remoteLogout(null);
        _lastAttempt.remove(key);
        return login(booru);
      }
      if (status == 400 || status == 401) return (false, 'kemono rejected the username or password');
      if (status == 429) return (false, 'kemono is rate-limiting sign-ins; wait a minute');
      return (false, 'kemono answered $status to the sign-in');
    } catch (e) {
      _log('login failed: $e');
      return (false, 'Sign-in failed: $e');
    }
  }

  Future<String?> _sessionFromJar() async {
    try {
      final String jar = await Tools.getCookies(site);
      for (final String pair in jar.split(';')) {
        final String p = pair.trim();
        if (p.toLowerCase().startsWith('session=') && p.length > 'session='.length) return p;
      }
    } catch (_) {}
    return null;
  }

  /// One automatic attempt after the API answered 401, at most once a minute
  /// per username. False when throttled or when the login fails.
  Future<bool> relogin(Booru booru) async {
    ensureLoaded();
    final String key = keyFor(booru);
    if (!hasCredentials(booru)) return false;
    final int last = _lastAttempt[key] ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < reloginInterval.inMilliseconds) {
      _log('relogin for ${booru.userID} throttled');
      return false;
    }
    _sessions.remove(key);
    final (bool ok, String message) = await login(booru);
    if (!ok) _log('relogin failed: $message');
    return ok;
  }

  Future<void> _remoteLogout(String? cookie) async {
    try {
      await DioNetwork.post(
        '$api/authentication/logout',
        headers: {..._headers(), 'Cookie': ?cookie},
        options: Options(validateStatus: (_) => true, responseType: ResponseType.plain),
      );
    } catch (_) {}
  }

  /// Forgets the session; [remote] also tells the site.
  Future<void> logout(Booru booru, {bool remote = true}) async {
    ensureLoaded();
    final String key = keyFor(booru);
    final String? cookie = _sessions.remove(key)?.cookie;
    if (cookie == null) return;
    _persist();
    revision.value++;
    if (remote) await _remoteLogout(cookie);
    _log('signed out ${booru.userID}');
  }

  void resetForTests() {
    _sessions.clear();
    _lastAttempt.clear();
    _loaded = true;
  }

  static void _log(String message) =>
      Logger.Inst().log(message, 'KemonoSessionHandler', 'session', LogTypes.booruHandlerInfo);
}
