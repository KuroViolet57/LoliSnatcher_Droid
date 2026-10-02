import 'dart:io';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
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
  providers: const [OrtProvider.QNN, OrtProvider.CPU],
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
/// (`<model>.npu-<bytes>-whole.onnx`, or `-mixed` when some parts stay on the
/// CPU; a new download of another size compiles again). Without a copy the
/// whole model is tried first (the CPU forbidden, so it fails fast when the
/// NPU cannot take everything), then a mix.
List<NpuAttempt> npuAttempts(String modelPath, {required int modelBytes, required int threads, required bool Function(String path) exists}) {
  final String whole = '$modelPath.npu-$modelBytes-whole.onnx';
  final String mixed = '$modelPath.npu-$modelBytes-mixed.onnx';
  if (exists(whole)) return [NpuAttempt(whole, _npuOptions(threads), whole: true)];
  if (exists(mixed)) return [NpuAttempt(mixed, _npuOptions(threads), whole: false)];
  return [
    NpuAttempt(modelPath, _npuOptions(threads, compileTo: whole, cpuFallback: false), whole: true, compileTo: whole),
    NpuAttempt(modelPath, _npuOptions(threads, compileTo: mixed), whole: false, compileTo: mixed),
  ];
}

/// r86: the saved Run on choice for [model]; the CPU when the settings
/// cannot be read (a runner made before they load, or in a test).
ModelAccelerator savedAccelerator(ModelKind model) {
  try {
    return ModelTasks.runOn(model);
  } catch (_) {
    return ModelAccelerator.cpu;
  }
}

/// A session as it was opened: what it really runs on, and how the log
/// names it ("NNAPI x2", "NPU", "NPU + CPU", or "CPU x2 (NNAPI refused)").
typedef OpenedSession = ({OrtSession session, ModelAccelerator used, String provider});

void _log(String line) => Logger.Inst().log(line, 'OnnxSession', 'open', LogTypes.booruHandlerInfo);

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
  bool recompiled = false;
  List<NpuAttempt> attempts = npuAttempts(path, modelBytes: bytes, threads: threads, exists: (p) => File(p).existsSync());
  for (int i = 0; i < attempts.length; i++) {
    final NpuAttempt a = attempts[i];
    final Stopwatch sw = Stopwatch()..start();
    try {
      final OrtSession s = await OnnxRuntime().createSession(a.path, options: a.options);
      ModelTimings.instance.recordOpen(model, ModelAccelerator.npu, sw.elapsedMilliseconds);
      _log(
        '$who: opened on the NPU${a.whole ? '' : ' (some parts on the CPU)'} in ${sw.elapsedMilliseconds} ms'
        '${a.compileTo != null ? ', compiled and kept' : ', from the compiled copy'}',
      );
      return (session: s, used: ModelAccelerator.npu, provider: a.whole ? 'NPU' : 'NPU + CPU');
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
    if (npu != null) return npu;
    refused = 'the NPU took no part of it';
  } else {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final OrtSession s = await OnnxRuntime().createSession(path, options: onnxSessionOptions(threads: threads, accelerator: accelerator));
      ModelTimings.instance.recordOpen(model, accelerator, sw.elapsedMilliseconds);
      if (accelerator != ModelAccelerator.cpu) _log('$who: opened on ${accelerator.label} in ${sw.elapsedMilliseconds} ms');
      return (session: s, used: accelerator, provider: '${accelerator.label} x$threads');
    } catch (e) {
      refused = e;
    }
  }
  if (accelerator != ModelAccelerator.cpu) {
    _log('$who: ${accelerator.label} refused the model ($refused); the CPU instead');
    try {
      final Stopwatch cpu = Stopwatch()..start();
      final OrtSession s = await OnnxRuntime().createSession(path, options: onnxSessionOptions(threads: threads, accelerator: ModelAccelerator.cpu));
      ModelTimings.instance.recordOpen(model, ModelAccelerator.cpu, cpu.elapsedMilliseconds);
      return (session: s, used: ModelAccelerator.cpu, provider: 'CPU x$threads (${accelerator.label} refused)');
    } catch (e) {
      refused = e;
    }
  }
  _log('$who: could not open the model with $threads thread(s) ($refused); default options');
  final OrtSession s = await OnnxRuntime().createSession(path);
  return (session: s, used: ModelAccelerator.cpu, provider: 'CPU');
}
