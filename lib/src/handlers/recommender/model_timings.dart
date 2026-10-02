import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';

/// Runs of one kind: how many, their total and the last one, in ms.
class TimingStat {
  TimingStat({this.runs = 0, this.totalMs = 0, this.lastMs = 0});

  int runs;
  int totalMs;
  int lastMs;

  int get averageMs => runs == 0 ? 0 : (totalMs / runs).round();

  void add(int ms) {
    runs++;
    totalMs += ms;
    lastMs = ms;
  }

  Map<String, int> toJson() => {'runs': runs, 'totalMs': totalMs, 'lastMs': lastMs};

  static TimingStat? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final dynamic runs = raw['runs'], total = raw['totalMs'], last = raw['lastMs'];
    if (runs is! int || total is! int || last is! int || runs < 1) return null;
    return TimingStat(runs: runs, totalMs: total, lastMs: last);
  }
}

/// r86: what this phone measured, for the explain windows of Settings →
/// Models: each model's runs and openings per [ModelAccelerator], and the
/// picture preparation per [PictureDecoder]. Kept in `model_timings.json` in
/// the app's config folder (not in the settings: it is this phone's).
class ModelTimings {
  ModelTimings._();

  static final ModelTimings instance = ModelTimings._();

  final Map<String, TimingStat> _stats = {};
  String? _dir;
  bool _loaded = false;
  Future<void>? _saving;
  bool _dirty = false;

  static const String fileName = 'model_timings.json';

  @visibleForTesting
  void resetForTests({String? dir}) {
    _stats.clear();
    _dir = dir;
    _loaded = dir != null;
    _saving = null;
    _dirty = false;
  }

  static String _runKey(ModelKind m, ModelAccelerator a) => 'run.${m.name}.${a.name}';
  static String _openKey(ModelKind m, ModelAccelerator a) => 'open.${m.name}.${a.name}';
  static String _decodeKey(PictureDecoder d) => 'decode.${d.name}';

  TimingStat? run(ModelKind m, ModelAccelerator a) => _stats[_runKey(m, a)];
  TimingStat? open(ModelKind m, ModelAccelerator a) => _stats[_openKey(m, a)];
  TimingStat? decode(PictureDecoder d) => _stats[_decodeKey(d)];

  void recordRun(ModelKind m, ModelAccelerator a, int ms) => _record(_runKey(m, a), ms);
  void recordOpen(ModelKind m, ModelAccelerator a, int ms) => _record(_openKey(m, a), ms);
  void recordDecode(PictureDecoder d, int ms) => _record(_decodeKey(d), ms);

  void _record(String key, int ms) {
    (_stats[key] ??= TimingStat()).add(ms);
    _dirty = true;
    if (_loaded) unawaited(_save());
  }

  /// "On this phone: 200 ms per run on average over 2 runs, the last 300 ms."
  static String words(TimingStat? s, {required String unit}) {
    if (s == null || s.runs == 0) return 'Not tried yet on this phone.';
    return 'On this phone: ${s.averageMs} ms per $unit on average over ${s.runs} ${s.runs == 1 ? unit : '${unit}s'}, the last ${s.lastMs} ms.';
  }

  Future<String> _folder() async => _dir ??= await ServiceHandler.getConfigDir();

  /// Reads the saved timings once; what was measured before that is kept
  /// on top of them.
  Future<void> load() async {
    try {
      final File f = File('${await _folder()}$fileName');
      if (await f.exists()) {
        final dynamic raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          raw.forEach((key, value) {
            final TimingStat? s = TimingStat.fromJson(value);
            if (key is! String || s == null) return;
            final TimingStat? now = _stats[key];
            _stats[key] = now == null
                ? s
                : TimingStat(runs: s.runs + now.runs, totalMs: s.totalMs + now.totalMs, lastMs: now.lastMs);
          });
        }
      }
    } catch (_) {}
    _loaded = true;
    if (_dirty) unawaited(_save());
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// One write at a time; a change during a write is written after it.
  Future<void> _save() async {
    if (_saving != null) return;
    _saving = () async {
      while (_dirty) {
        _dirty = false;
        try {
          final File f = File('${await _folder()}$fileName');
          await f.writeAsString(jsonEncode({for (final e in _stats.entries) e.key: e.value.toJson()}), flush: true);
        } catch (_) {}
      }
    }();
    await _saving;
    _saving = null;
  }

  @visibleForTesting
  Future<void> saveNow() async {
    _dirty = true;
    await _save();
    await _saving;
  }
}
