import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The saved boards (r73) and the SauceNAO key, in `boards.json` beside the
/// settings; reference images are copied under `boards/`.
class BoardsHandler {
  BoardsHandler._();

  static final BoardsHandler instance = BoardsHandler._();

  static const String fileName = 'boards.json';
  static const String imagesDirName = 'boards';

  /// Ticks on every change; the Boards page listens.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final List<Board> _boards = [];
  String sauceNaoApiKey = '';
  bool _loaded = false;
  int _lastId = 0;

  @visibleForTesting
  String? directoryOverride;

  String get _dir => directoryOverride ?? SettingsHandler.instance.path;
  File get file => File('$_dir$fileName');
  Directory get imagesDir => Directory('$_dir$imagesDirName');

  bool get isLoaded => _loaded;
  List<Board> get boards => List<Board>.unmodifiable(_boards);

  Board? byId(String id) => _boards.where((b) => b.id == id).firstOrNull;

  /// Unique even when asked twice in the same microsecond.
  String newId() {
    _lastId = max(_lastId + 1, DateTime.now().microsecondsSinceEpoch);
    return _lastId.toRadixString(36);
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _boards.clear();
    sauceNaoApiKey = '';
    try {
      if (!file.existsSync()) return;
      final dynamic decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return;
      sauceNaoApiKey = decoded['sauceNaoApiKey']?.toString() ?? '';
      for (final dynamic b in (decoded['boards'] as List?) ?? const []) {
        if (b is Map) _boards.add(Board.fromJson(Map<String, dynamic>.from(b)));
      }
    } catch (e, s) {
      Logger.Inst().log('boards.json could not be read: $e', 'BoardsHandler', 'load', LogTypes.exception, s: s);
      _boards.clear();
    }
  }

  /// After a restore from backup: read the file again.
  Future<void> reloadFromDisk() async {
    _loaded = false;
    await load();
    revision.value++;
  }

  Future<Board> save(Board board) async {
    await load();
    final Board stored = board.copyWith(updatedAt: DateTime.now());
    final int i = _boards.indexWhere((b) => b.id == board.id);
    if (i >= 0) {
      _boards[i] = stored;
    } else {
      _boards.add(stored);
    }
    await _write();
    return stored;
  }

  Future<void> delete(String id) async {
    await load();
    final Board? b = byId(id);
    if (b == null) return;
    _boards.removeWhere((x) => x.id == id);
    if (b.imagePath.isNotEmpty && b.imagePath.startsWith(imagesDir.path)) {
      try {
        File(b.imagePath).deleteSync();
      } catch (_) {}
    }
    await _write();
  }

  Future<void> setSauceNaoApiKey(String key) async {
    await load();
    sauceNaoApiKey = key.trim();
    await _write();
  }

  /// Copies a reference image under `boards/<board id>.<ext>`.
  Future<String> importImageBytes(List<int> bytes, String boardId, {String ext = 'jpg'}) async {
    imagesDir.createSync(recursive: true);
    final File f = File('${imagesDir.path}${Platform.pathSeparator}$boardId.$ext');
    f.writeAsBytesSync(bytes, flush: true);
    return f.path;
  }

  Future<String> importImageFile(String path, String boardId) async {
    final String tail = path.split('.').last.toLowerCase();
    final String ext = tail.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(tail) ? tail : 'jpg';
    return importImageBytes(File(path).readAsBytesSync(), boardId, ext: ext);
  }

  Future<void> _write() async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'sauceNaoApiKey': sauceNaoApiKey,
        'boards': [for (final Board b in _boards) b.toJson()],
      }),
      flush: true,
    );
    revision.value++;
  }

  @visibleForTesting
  Future<void> resetForTests() async {
    _boards.clear();
    sauceNaoApiKey = '';
    _loaded = false;
    directoryOverride = null;
    revision.value = 0;
  }
}
