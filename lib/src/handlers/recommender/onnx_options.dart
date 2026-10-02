import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r86: the options a model's ONNX Runtime session opens with. The CPU is
/// exactly the options before r86 (no providers: ONNX Runtime's default);
/// the others ask for their provider first and the CPU for what it does not
/// take. The plugin passes no provider options, so XNNPACK runs its share on
/// one thread of its own and NNAPI with its default flags (full precision,
/// its own CPU fallback allowed).
OrtSessionOptions onnxSessionOptions({required int threads, required ModelAccelerator accelerator}) => OrtSessionOptions(
  intraOpNumThreads: threads,
  providers: switch (accelerator) {
    ModelAccelerator.cpu => null,
    ModelAccelerator.xnnpack => const [OrtProvider.XNNPACK, OrtProvider.CPU],
    ModelAccelerator.nnapi => const [OrtProvider.NNAPI, OrtProvider.CPU],
  },
);

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
/// names it ("NNAPI x2", or "CPU x2 (NNAPI refused)").
typedef OpenedSession = ({OrtSession session, ModelAccelerator used, String provider});

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
  void log(String line) => Logger.Inst().log(line, 'OnnxSession', 'open', LogTypes.booruHandlerInfo);
  final Stopwatch sw = Stopwatch()..start();
  try {
    final OrtSession s = await OnnxRuntime().createSession(path, options: onnxSessionOptions(threads: threads, accelerator: accelerator));
    ModelTimings.instance.recordOpen(model, accelerator, sw.elapsedMilliseconds);
    if (accelerator != ModelAccelerator.cpu) log('$who: opened on ${accelerator.label} in ${sw.elapsedMilliseconds} ms');
    return (session: s, used: accelerator, provider: '${accelerator.label} x$threads');
  } catch (e) {
    if (accelerator != ModelAccelerator.cpu) {
      log('$who: ${accelerator.label} refused the model ($e); the CPU instead');
      try {
        final Stopwatch cpu = Stopwatch()..start();
        final OrtSession s = await OnnxRuntime().createSession(
          path,
          options: onnxSessionOptions(threads: threads, accelerator: ModelAccelerator.cpu),
        );
        ModelTimings.instance.recordOpen(model, ModelAccelerator.cpu, cpu.elapsedMilliseconds);
        return (session: s, used: ModelAccelerator.cpu, provider: 'CPU x$threads (${accelerator.label} refused)');
      } catch (_) {}
    }
    log('$who: could not open the model with $threads thread(s) ($e); default options');
    final OrtSession s = await OnnxRuntime().createSession(path);
    return (session: s, used: ModelAccelerator.cpu, provider: 'CPU');
  }
}
