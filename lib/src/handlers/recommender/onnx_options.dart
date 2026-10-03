import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_availability.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r87: Qualcomm's QNN on the HTP (the NPU), float models at 16-bit.
const Map<String, String> qnnHtpOptions = {
  'backend_path': 'libQnnHtp.so',
  'enable_htp_fp16_precision': '1',
  'htp_performance_mode': 'high_performance',
};

/// r86: the options a model's ONNX Runtime session opens with. The CPU is
/// exactly the options before r86 (no providers: ONNX Runtime's default);
/// the others ask for their provider first and the CPU for what it does not
/// take. r87 (our plugin copy passes provider options): XNNPACK gets the
/// thread count for its own pool, the session one thread and no spinning, as
/// ONNX Runtime recommends; NNAPI keeps its default flags; the NPU is QNN on
/// the HTP ([qnnHtpOptions]) - opened through [npuAttempts].
OrtSessionOptions onnxSessionOptions({required int threads, required ModelAccelerator accelerator}) => switch (accelerator) {
  ModelAccelerator.cpu => OrtSessionOptions(intraOpNumThreads: threads),
  ModelAccelerator.xnnpack => OrtSessionOptions(
    intraOpNumThreads: 1,
    providers: const [OrtProvider.XNNPACK, OrtProvider.CPU],
    providerOptions: {
      'XNNPACK': {'intra_op_num_threads': '$threads'},
    },
    sessionConfig: const {'session.intra_op.allow_spinning': '0'},
  ),
  ModelAccelerator.nnapi => OrtSessionOptions(intraOpNumThreads: threads, providers: const [OrtProvider.NNAPI, OrtProvider.CPU]),
  ModelAccelerator.npu => _npuOptions(threads),
};

OrtSessionOptions _npuOptions(int threads, {String? compileTo, bool cpuFallback = true}) => OrtSessionOptions(
  intraOpNumThreads: threads,
  // r88: the whole-model try names only the NPU - the CPU listed next to a
  // forbidden CPU fallback is a conflict ONNX Runtime refuses (log 2026-10-02).
  providers: cpuFallback ? const [OrtProvider.QNN, OrtProvider.CPU] : const [OrtProvider.QNN],
  providerOptions: const {'QNN': qnnHtpOptions},
  sessionConfig: {
    if (!cpuFallback) 'session.disable_cpu_ep_fallback': '1',
    if (compileTo != null) ...{
      'ep.context_enable': '1',
      'ep.context_file_path': compileTo,
      'ep.context_embed_mode': '1',
    },
  },
  // The NPU needs fixed sizes: every free input dimension (the batch) is 1.
  symbolicDims: compileTo != null ? const {'*': 1} : null,
);

/// r87: one way to open a model on the NPU.
class NpuAttempt {
  const NpuAttempt(this.path, this.options, {required this.whole, this.compileTo});

  /// The file opened: the model, or a compiled copy of it.
  final String path;
  final OrtSessionOptions options;

  /// The whole model runs on the NPU (else some parts stay on the CPU).
  final bool whole;

  /// Where this opening writes its compiled copy (null: it opens one).
  final String? compileTo;
}

/// r87: the NPU compiles a model the first time it opens it - seconds to a
/// minute - so the compiled copy is kept next to the model
/// (`<model>.npu2-<bytes>-whole.onnx`, or `-mixed` when some parts stay on the
/// CPU; a new download of another size compiles again). Without a copy the
/// whole model is tried first (the CPU forbidden, so it fails fast when the
/// NPU cannot take everything), then a mix.
///
/// r89: `npu2`. Build 117's copies (`npu-…`) are all the mixed kind - its
/// whole-model try failed on a settings conflict every time - and the looks
/// model's mixed copy failed on its first run twice (QNN 6033, logs
/// 2026-10-02 and -03), so every model compiles once more, whole first. A
/// whole copy that fails while running leaves [npuWholeFailedMarker], and the
/// next compile is the mixed kind.
List<NpuAttempt> npuAttempts(String modelPath, {required int modelBytes, required int threads, required bool Function(String path) exists}) {
  final String whole = _npuCopyPath(modelPath, modelBytes, whole: true);
  final String mixed = _npuCopyPath(modelPath, modelBytes, whole: false);
  if (exists(whole)) return [NpuAttempt(whole, _npuOptions(threads), whole: true)];
  if (exists(mixed)) return [NpuAttempt(mixed, _npuOptions(threads), whole: false)];
  return [
    if (!exists(npuWholeFailedMarker(modelPath, modelBytes)))
      NpuAttempt(modelPath, _npuOptions(threads, compileTo: whole, cpuFallback: false), whole: true, compileTo: whole),
    NpuAttempt(modelPath, _npuOptions(threads, compileTo: mixed), whole: false, compileTo: mixed),
  ];
}

String _npuCopyPath(String modelPath, int bytes, {required bool whole}) => '$modelPath.npu2-$bytes-${whole ? 'whole' : 'mixed'}.onnx';

/// r89: left next to the model when its whole-model copy failed while
/// running; the model's next compile is the mixed kind.
String npuWholeFailedMarker(String modelPath, int bytes) => '$modelPath.npu2-$bytes-whole.failed';

/// r89: the NPU files beside [modelPath] that no longer belong to it: build
/// 117's copies (`npu-…`, which are never opened again) and copies or marks
/// for another size of the model (another download).
List<String> staleNpuFiles(String modelPath, int bytes, Iterable<String> siblings) {
  final String legacy = '$modelPath.npu-';
  final String any = '$modelPath.npu2-';
  final String mine = '$modelPath.npu2-$bytes-';
  return [
    for (final String s in siblings)
      if (s.startsWith(legacy) || (s.startsWith(any) && !s.startsWith(mine))) s,
  ];
}

/// r89: the NPU copy beside [modelPath], for the Speed part: the whole model
/// or the mixed kind (null: not compiled yet), when it was compiled, and
/// whether the whole model failed here.
({bool? whole, DateTime? compiled, bool wholeFailed}) npuCopyState(String modelPath) {
  final int bytes;
  try {
    bytes = File(modelPath).lengthSync();
  } catch (_) {
    return (whole: null, compiled: null, wholeFailed: false);
  }
  final bool failed = File(npuWholeFailedMarker(modelPath, bytes)).existsSync();
  for (final bool whole in [true, false]) {
    final File copy = File(_npuCopyPath(modelPath, bytes, whole: whole));
    try {
      if (copy.existsSync()) return (whole: whole, compiled: copy.lastModifiedSync(), wholeFailed: failed);
    } catch (_) {}
  }
  return (whole: null, compiled: null, wholeFailed: failed);
}

/// r89: QNN's own codes that say something in plain words (QnnGraph.h,
/// QnnCommon.h of the QNN SDK).
const Map<int, String> _qnnErrors = {
  1002: 'out of memory',
  6031: 'aborted',
  6033: 'the NPU timed out',
};

/// r89: an NPU failure in a few words for the model's page; the whole text
/// stays in the log. The phone's looks model: "QNN error 6033 (the NPU timed
/// out) in part 107 of the model".
String npuErrorWords(String reason) {
  final String? code = RegExp(r'Error code: (\d+)').firstMatch(reason)?.group(1);
  if (code == null) {
    final String first = reason.split('\n').first.trim();
    return first.length > 120 ? '${first.substring(0, 120)}…' : first;
  }
  final String? part = RegExp(r'QNN_\d+_(\d+) node').firstMatch(reason)?.group(1);
  final String? meaning = _qnnErrors[int.parse(code)];
  return 'QNN error $code${meaning != null ? ' ($meaning)' : ''}${part != null ? ' in part $part of the model' : ''}';
}

/// What [model] opens on: the saved Run on choice, unless this build lacks
/// it (r88) or the NPU failed twice while running it since it was picked
/// (r88); the CPU when the settings cannot be read (a runner made before
/// they load, or in a test).
ModelAccelerator savedAccelerator(ModelKind model) {
  try {
    final ModelAccelerator a = ModelTasks.runOn(model);
    if (!OnnxAvailability.has(a)) return ModelAccelerator.cpu;
    if (a == ModelAccelerator.npu && (ModelTimings.instance.npuFailures(model)?.count ?? 0) >= 2) return ModelAccelerator.cpu;
    return a;
  } catch (_) {
    return ModelAccelerator.cpu;
  }
}

/// r88: what [model] really runs on: [savedAccelerator], unless its last
/// opening asked for that and got the CPU (`refused` says why). On the
/// emulator the card said "runs on NPU" while the CPU did the work.
({ModelAccelerator used, String? refused}) actualAccelerator(ModelKind model) {
  final ModelAccelerator want = savedAccelerator(model);
  final ({ModelAccelerator tried, ModelAccelerator used, String? refused})? last = ModelTimings.instance.lastOpened(model);
  if (last != null && last.tried == want && last.used != want) return (used: last.used, refused: last.refused);
  return (used: want, refused: null);
}

/// r88: one model run. When it fails on the NPU (the looks model timed out
/// there - QNN error 6033, log 2026-10-02), the failure is counted for the
/// model and the same input runs on the CPU ([onCpu]); a failure anywhere
/// else is a real one and is thrown.
///
/// r89: [copy] is the compiled copy the session runs (OpenedSession.npuCopy).
/// A whole-model copy that fails is deleted and marked, so the model's next
/// opening compiles the mixed kind; a mixed copy is kept - compiling again
/// would build the same one.
Future<T> runGuarded<T>({
  required ModelKind model,
  required ModelAccelerator used,
  required String who,
  required Future<T> Function() run,
  required Future<T> Function() onCpu,
  String? copy,
}) async {
  try {
    return await run();
  } catch (e) {
    if (used != ModelAccelerator.npu) rethrow;
    ModelTimings.instance.recordNpuFailure(model, '$e');
    _log('$who: the NPU failed while running ($e); this one on the CPU');
    if (copy != null && copy.endsWith('-whole.onnx')) {
      _delete(copy);
      try {
        File('${copy.substring(0, copy.length - '.onnx'.length)}.failed').writeAsBytesSync(const []);
      } catch (_) {}
      _log('$who: the whole-model copy failed while running; deleted - the next opening compiles one with some parts on the CPU');
    }
    return onCpu();
  }
}

/// A session as it was opened: what it really runs on, and how the log
/// names it ("NNAPI x2", "NPU", "NPU + CPU", or "CPU x2 (NNAPI refused)").
/// r89: `npuCopy` is the compiled copy behind an NPU session (for
/// [runGuarded]); null otherwise.
typedef OpenedSession = ({OrtSession session, ModelAccelerator used, String provider, String? npuCopy});

void _log(String line) => Logger.Inst().log(line, 'OnnxSession', 'open', LogTypes.booruHandlerInfo);

Future<OrtSession> _createOrtSession(String path, OrtSessionOptions? options) => OnnxRuntime().createSession(path, options: options);
Future<void> _closeOrtSession(OrtSession s) => s.close();

/// Opens and closes ONNX Runtime sessions (tests stand in for the plugin).
@visibleForTesting
Future<OrtSession> Function(String path, OrtSessionOptions? options) createOrtSession = _createOrtSession;
@visibleForTesting
Future<void> Function(OrtSession s) closeOrtSession = _closeOrtSession;

@visibleForTesting
void resetOnnxSeamsForTests() {
  createOrtSession = _createOrtSession;
  closeOrtSession = _closeOrtSession;
}

void _delete(String path) {
  try {
    final File f = File(path);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

/// r87: the NPU's openings, in order; a compiled copy that fails is deleted
/// and the model compiled again. Null when the NPU refused every one.
Future<OpenedSession?> _openOnNpu(String path, {required ModelKind model, required int threads, required String who}) async {
  int bytes;
  try {
    bytes = File(path).lengthSync();
  } catch (_) {
    bytes = 0;
  }
  // r89: build 117's copies and other sizes' copies go (a mixed S2 copy is
  // tens of MB).
  try {
    for (final String stale in staleNpuFiles(path, bytes, File(path).parent.listSync().map((e) => e.path))) {
      _delete(stale);
      _log('$who: removed an old NPU copy (${stale.split(Platform.pathSeparator).last})');
    }
  } catch (_) {}
  bool recompiled = false;
  List<NpuAttempt> attempts = npuAttempts(path, modelBytes: bytes, threads: threads, exists: (p) => File(p).existsSync());
  for (int i = 0; i < attempts.length; i++) {
    final NpuAttempt a = attempts[i];
    final Stopwatch sw = Stopwatch()..start();
    try {
      OrtSession s = await createOrtSession(a.path, a.options);
      final String? copy = a.compileTo;
      // r88: a compiling opening that leaves no compiled copy is one the NPU
      // took no part of - QNN could not start ("QNN SetupBackend failed" on
      // the emulator, 2026-10-03), ONNX Runtime gave every part to the CPU,
      // and the timings said NPU. The NPU compiles whatever it takes.
      if (copy != null && !File(copy).existsSync()) {
        try {
          await closeOrtSession(s);
        } catch (_) {}
        _log('$who: the NPU took no part of the model${a.whole ? '' : ' (every part went to the CPU)'}');
        continue;
      }
      ModelTimings.instance.recordOpen(model, ModelAccelerator.npu, sw.elapsedMilliseconds);
      _log(
        '$who: opened on the NPU${a.whole ? '' : ' (some parts on the CPU)'} in ${sw.elapsedMilliseconds} ms'
        '${a.compileTo != null ? ', compiled and kept' : ', from the compiled copy'}',
      );
      // r89: a new copy gets a fresh chance - the failures counted were the
      // old copy's.
      if (copy != null) ModelTimings.instance.clearNpuFailures(model);
      // r88: right after compiling, the compiled copy is opened instead -
      // the first run of the compiling session took 42 s on the phone, the
      // first one from a copy under a second (log 2026-10-02).
      if (copy != null) {
        try {
          final OrtSession fromCopy = await createOrtSession(copy, _npuOptions(threads));
          await closeOrtSession(s);
          s = fromCopy;
          _log('$who: switched to the compiled copy');
        } catch (e) {
          _log('$who: the fresh compiled copy did not open ($e); keeping the compiling session');
        }
      }
      return (session: s, used: ModelAccelerator.npu, provider: a.whole ? 'NPU' : 'NPU + CPU', npuCopy: copy ?? a.path);
    } catch (e) {
      if (a.compileTo != null) {
        _delete(a.compileTo!);
        _log('$who: the NPU ${a.whole ? 'cannot run the whole model' : 'refused the model'} ($e)');
      } else {
        // A compiled copy that does not open (cut short, another runtime):
        // gone, and the model compiled again.
        _delete(a.path);
        _log('$who: the compiled copy did not open ($e); compiling again');
        if (!recompiled) {
          recompiled = true;
          attempts = npuAttempts(path, modelBytes: bytes, threads: threads, exists: (_) => false);
          i = -1;
        }
      }
    }
  }
  return null;
}

/// r86: opens [path] on [accelerator] with [threads]; when that is refused,
/// the CPU with [threads], then ONNX Runtime's defaults (as before r86). The
/// time the opening took is kept per model and choice (ModelTimings).
Future<OpenedSession> openOnnxSession(
  String path, {
  required ModelKind model,
  required int threads,
  required ModelAccelerator accelerator,
  required String who,
}) async {
  Object? refused;
  if (accelerator == ModelAccelerator.npu) {
    final OpenedSession? npu = await _openOnNpu(path, model: model, threads: threads, who: who);
    if (npu != null) {
      ModelTimings.instance.recordOpened(model, tried: accelerator, used: npu.used);
      return npu;
    }
    refused = 'the NPU took no part of it';
  } else {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final OrtSession s = await createOrtSession(path, onnxSessionOptions(threads: threads, accelerator: accelerator));
      ModelTimings.instance.recordOpen(model, accelerator, sw.elapsedMilliseconds);
      if (accelerator != ModelAccelerator.cpu) _log('$who: opened on ${accelerator.label} in ${sw.elapsedMilliseconds} ms');
      ModelTimings.instance.recordOpened(model, tried: accelerator, used: accelerator);
      return (session: s, used: accelerator, provider: '${accelerator.label} x$threads', npuCopy: null);
    } catch (e) {
      refused = e;
    }
  }
  if (accelerator != ModelAccelerator.cpu) {
    _log('$who: ${accelerator.label} refused the model ($refused); the CPU instead');
    try {
      final Stopwatch cpu = Stopwatch()..start();
      final OrtSession s = await createOrtSession(path, onnxSessionOptions(threads: threads, accelerator: ModelAccelerator.cpu));
      ModelTimings.instance.recordOpen(model, ModelAccelerator.cpu, cpu.elapsedMilliseconds);
      ModelTimings.instance.recordOpened(model, tried: accelerator, used: ModelAccelerator.cpu, refused: '$refused');
      return (session: s, used: ModelAccelerator.cpu, provider: 'CPU x$threads (${accelerator.label} refused)', npuCopy: null);
    } catch (e) {
      refused = e;
    }
  }
  _log('$who: could not open the model with $threads thread(s) ($refused); default options');
  final OrtSession s = await createOrtSession(path, null);
  ModelTimings.instance.recordOpened(model, tried: accelerator, used: ModelAccelerator.cpu, refused: accelerator == ModelAccelerator.cpu ? null : '$refused');
  return (session: s, used: ModelAccelerator.cpu, provider: 'CPU', npuCopy: null);
}
