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
  void resetForTests({String? dir, bool? loaded}) {
    _stats.clear();
    _npuFailures.clear();
    _lastOpened.clear();
    _dir = dir;
    _loaded = loaded ?? dir != null;
    _loading = null;
    _saving = null;
    _dirty = false;
  }

  static String _runKey(ModelKind m, ModelAccelerator a, [int? threads]) => 'run.${m.name}.${a.name}${threads == null ? '' : '.x$threads'}';
  static String _openKey(ModelKind m, ModelAccelerator a) => 'open.${m.name}.${a.name}';
  static String _decodeKey(PictureDecoder d) => 'decode.${d.name}';

  /// The runs on [a]; with [threads], only those on that many threads (r88).
  TimingStat? run(ModelKind m, ModelAccelerator a, {int? threads}) => _stats[_runKey(m, a, threads)];

  /// r88: the thread counts [a] has been measured with, smallest first.
  List<int> threadsMeasured(ModelKind m, ModelAccelerator a) {
    final String prefix = '${_runKey(m, a)}.x';
    return [
      for (final String k in _stats.keys)
        if (k.startsWith(prefix)) ?int.tryParse(k.substring(prefix.length)),
    ]..sort();
  }

  /// r88: the fastest way [m] has run on this phone: the choice (and thread
  /// count, when known) with the lowest average; null before any run.
  ({ModelAccelerator accelerator, int? threads, int averageMs})? fastest(ModelKind m) {
    ({ModelAccelerator accelerator, int? threads, int averageMs})? best;
    for (final ModelAccelerator a in ModelAccelerator.values) {
      final List<int> counts = threadsMeasured(m, a);
      final List<(int?, TimingStat?)> rows = counts.isEmpty ? [(null, run(m, a))] : [for (final int c in counts) (c, run(m, a, threads: c))];
      for (final (int? threads, TimingStat? s) in rows) {
        if (s == null || s.runs == 0) continue;
        if (best == null || s.averageMs < best.averageMs) best = (accelerator: a, threads: threads, averageMs: s.averageMs);
      }
    }
    return best;
  }
  TimingStat? open(ModelKind m, ModelAccelerator a) => _stats[_openKey(m, a)];
  TimingStat? decode(PictureDecoder d) => _stats[_decodeKey(d)];

  void recordRun(ModelKind m, ModelAccelerator a, int ms, {int? threads}) {
    _record(_runKey(m, a), ms);
    if (threads != null) _record(_runKey(m, a, threads), ms);
  }

  // ── r88: NPU failures while running ──

  final Map<ModelKind, ({int count, String reason})> _npuFailures = {};

  /// How often the NPU failed while running [m] since it was last picked.
  ({int count, String reason})? npuFailures(ModelKind m) => _npuFailures[m];

  void recordNpuFailure(ModelKind m, String reason) {
    final int count = (_npuFailures[m]?.count ?? 0) + 1;
    _npuFailures[m] = (count: count, reason: reason.length > 300 ? '${reason.substring(0, 300)}…' : reason);
    _dirty = true;
    if (_loaded) unawaited(_save());
  }

  void clearNpuFailures(ModelKind m) {
    if (_npuFailures.remove(m) == null) return;
    _dirty = true;
    if (_loaded) unawaited(_save());
  }
  // ── r88: the last opening, this run of the app ──

  final Map<ModelKind, ({ModelAccelerator tried, ModelAccelerator used, String? refused})> _lastOpened = {};

  /// What [m]'s last opening asked for, what it got, and why not.
  ({ModelAccelerator tried, ModelAccelerator used, String? refused})? lastOpened(ModelKind m) => _lastOpened[m];

  void recordOpened(ModelKind m, {required ModelAccelerator tried, required ModelAccelerator used, String? refused}) =>
      _lastOpened[m] = (tried: tried, used: used, refused: refused);

  /// A new pick is a new try.
  void forgetOpened(ModelKind m) => _lastOpened.remove(m);

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
            if (key is String && key.startsWith('npuFailed.') && value is Map) {
              final ModelKind? m = ModelKind.values.where((k) => 'npuFailed.${k.name}' == key).firstOrNull;
              final dynamic count = value['count'], reason = value['reason'];
              if (m != null && count is int && reason is String && !_npuFailures.containsKey(m)) _npuFailures[m] = (count: count, reason: reason);
              return;
            }
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

  /// r89 (recheck): one load, however many ask at once (startup, a model
  /// opening, a page) - a second load added the saved runs again.
  Future<void>? _loading;

  Future<void> ensureLoaded() async {
    if (!_loaded) await (_loading ??= load());
  }

  /// One write at a time; a change during a write is written after it.
  Future<void> _save() async {
    if (_saving != null) return;
    _saving = () async {
      while (_dirty) {
        _dirty = false;
        try {
          final File f = File('${await _folder()}$fileName');
          await f.writeAsString(
            jsonEncode({
              for (final e in _stats.entries) e.key: e.value.toJson(),
              for (final e in _npuFailures.entries) 'npuFailed.${e.key.name}': {'count': e.value.count, 'reason': e.value.reason},
            }),
            flush: true,
          );
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
