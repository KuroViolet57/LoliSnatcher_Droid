import 'dart:convert';
import 'dart:io';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r78: learning the app could not finish before it left the screen.
///
/// Until r78 a step still waiting when the app went away was run "lite":
/// learned without the encoder, the looks model and the picture tags. That
/// cannot be undone - the item is learned once, from a poorer picture of
/// itself - and it is exactly what a person who never pauses would get for
/// everything they did. Now the step is kept here instead and learned in
/// full the next time the app runs.
///
/// The file is written as soon as something is kept, because the app is
/// usually about to be ended.
class DeferredLearning {
  DeferredLearning._();

  static final DeferredLearning instance = DeferredLearning._();

  /// At most this many are kept; the oldest go first.
  static const int cap = 200;

  /// Where they are kept. Replaced in tests.
  String Function() fileFor = _defaultFile;

  static String _defaultFile() => '${SettingsHandler.instance.path}recommender${Platform.pathSeparator}deferred.json';

  final List<Map<String, dynamic>> _kept = <Map<String, dynamic>>[];
  bool _read = false;

  void resetForTests() {
    _kept.clear();
    _read = false;
    fileFor = _defaultFile;
  }

  /// How many are waiting for a next run (after [takeAll] has read the file).
  int get waiting => _kept.length;

  /// Keeps one event. Synchronous on purpose: the app may be ended next.
  void keep(Map<String, dynamic> event) {
    _readFile();
    _kept.add(event);
    while (_kept.length > cap) {
      _kept.removeAt(0);
    }
    _write();
  }

  /// Everything kept, oldest first. They are handed over once: the file is
  /// emptied, so a crash during the replay loses them rather than doubling
  /// them.
  Future<List<Map<String, dynamic>>> takeAll() async {
    _readFile();
    if (_kept.isEmpty) return const <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> out = List<Map<String, dynamic>>.of(_kept);
    _kept.clear();
    _write();
    return out;
  }

  void _readFile() {
    if (_read) return;
    _read = true;
    try {
      final File f = File(fileFor());
      if (!f.existsSync()) return;
      final Object? raw = jsonDecode(f.readAsStringSync());
      if (raw is! List) return;
      for (final Object? e in raw) {
        if (e is Map<String, dynamic>) _kept.add(e);
      }
    } catch (e) {
      // A half-written or hand-edited file is not worth a crash.
      Logger.Inst().log('recommender: could not read the kept learning: $e', 'DeferredLearning', 'read', LogTypes.booruHandlerInfo);
    }
  }

  void _write() {
    try {
      final File f = File(fileFor());
      if (_kept.isEmpty) {
        if (f.existsSync()) f.deleteSync();
        return;
      }
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(_kept));
    } catch (e) {
      Logger.Inst().log('recommender: could not keep the learning for later: $e', 'DeferredLearning', 'write', LogTypes.booruHandlerInfo);
    }
  }
}
