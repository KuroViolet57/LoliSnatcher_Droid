import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The eahentai.com login (r69): the site's `POST /api/auth/login` answers a
/// bearer token, kept here in `eahentai_session.json` beside the settings so
/// it is asked for once, not on every search, and sent only to the site's
/// API - never to the image CDN, which takes no headers but a referer.
///
/// The credentials themselves stay in the booru's own fields (username or
/// email, password); this file holds what the site handed back.
class EaHentaiSessionHandler {
  EaHentaiSessionHandler._();

  static final EaHentaiSessionHandler instance = EaHentaiSessionHandler._();

  static const String fileName = 'eahentai_session.json';

  /// Bumped on every change so settings rows can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? _token;
  String? _username;
  String? _loginName;
  int _savedAt = 0;
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
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        _token = decoded['token']?.toString();
        _username = decoded['username']?.toString();
        _loginName = decoded['login']?.toString();
        if ((_loginName ?? '').isEmpty) _loginName = null;
        _savedAt = int.tryParse(decoded['at']?.toString() ?? '') ?? 0;
        if ((_token ?? '').isEmpty) _token = null;
        if ((_username ?? '').isEmpty) _username = null;
      }
    } catch (e) {
      Logger.Inst().log('could not read $fileName: $e', 'EaHentaiSessionHandler', 'ensureLoaded', LogTypes.exception);
    }
  }

  String? get token {
    ensureLoaded();
    return _token;
  }

  String? get username {
    ensureLoaded();
    return _username;
  }

  /// The username or email the token was obtained with, so a changed
  /// credential is noticed.
  String? get loginName {
    ensureLoaded();
    return _loginName;
  }

  int get savedAt {
    ensureLoaded();
    return _savedAt;
  }

  bool get isLoggedIn => (token ?? '').isNotEmpty;

  /// The header the site's account endpoints want; nothing when logged out.
  Map<String, String> get bearerHeaders => isLoggedIn ? {'Authorization': 'Bearer $_token'} : const {};

  void store({required String token, String? username, String? loginName}) {
    ensureLoaded();
    if (token.isEmpty) return;
    _token = token;
    if (username != null && username.isNotEmpty) _username = username;
    if (loginName != null && loginName.isNotEmpty) _loginName = loginName;
    _savedAt = DateTime.now().millisecondsSinceEpoch;
    _persist();
    revision.value++;
  }

  void setUsername(String? username) {
    ensureLoaded();
    _username = (username ?? '').isEmpty ? null : username;
    _persist();
    revision.value++;
  }

  void logout() {
    ensureLoaded();
    _token = null;
    _username = null;
    _loginName = null;
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
      file.writeAsStringSync(jsonEncode({'token': _token, 'username': _username, 'login': _loginName, 'at': _savedAt}));
    } catch (e) {
      Logger.Inst().log('could not write $fileName: $e', 'EaHentaiSessionHandler', '_persist', LogTypes.exception);
    }
  }

  @visibleForTesting
  void resetForTests() {
    _loaded = true;
    _token = null;
    _username = null;
    _loginName = null;
    _savedAt = 0;
  }
}
