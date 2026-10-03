import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';

/// The real runner: one ONNX Runtime session over the downloaded tagger.
///
/// The WD v3 exports take one float32 input `[batch, size, size, 3]` and
/// answer one row of probabilities per tag; the session's own input name
/// is used, so a custom repo with another name works. r86: it runs on what
/// Settings → Models → Run on says (the CPU by default); the plugin cannot
/// set XNNPACK's own thread count, so that choice runs its share on one.
class OnnxTagRunner implements TagRunner {
  OnnxTagRunner(this.modelPath, {int? threads, ModelAccelerator? accelerator})
    : threads = threads ?? defaultThreads,
      accelerator = accelerator ?? savedAccelerator(ModelKind.tagger);

  /// r77: two threads for everyone (was half the cores, 4 on an 8-core phone):
  /// a session's pool is fixed when it opens, and a reaction's tagging runs
  /// next to the screen and the video.
  static const int defaultThreads = 2;

  final String modelPath;
  final int threads;

  /// r86: what the model runs on (Settings → Models → Run on).
  final ModelAccelerator accelerator;

  OrtSessionOptions get options => onnxSessionOptions(threads: threads, accelerator: accelerator);

  ModelAccelerator _used = ModelAccelerator.cpu;

  /// r88: set when the NPU failed while running: this runner's next opening
  /// is on the CPU (the next runner tries the NPU again, up to twice).
  bool _cpuAfterFailure = false;

  /// r89: the compiled copy behind an NPU session (see runGuarded).
  String? _npuCopy;

  OrtSession? _session;
  Future<OrtSession>? _opening;
  String _provider = '';
  String? _inputName;

  @override
  String get provider => _provider;

  /// A session that failed to open is tried again next time, not kept as a
  /// failed future forever.
  Future<OrtSession> _open() => _opening ??= _openNow();

  Future<OrtSession> _openNow() async {
    try {
      final OpenedSession o = await openOnnxSession(
        modelPath,
        model: ModelKind.tagger,
        threads: threads,
        accelerator: _cpuAfterFailure ? ModelAccelerator.cpu : accelerator,
        who: 'tagger',
      );
      _session = o.session;
      _used = o.used;
      _provider = o.provider;
      _npuCopy = o.npuCopy;
      try {
        final List<Map<String, dynamic>> inputs = await _session!.getInputInfo();
        if (inputs.isNotEmpty) _inputName = inputs.first['name']?.toString();
      } catch (_) {}
      return _session!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<Float32List> run(Float32List nhwc, int size) async {
    final OrtSession session = await _open();
    // r88: a failure on the NPU runs the same picture on the CPU.
    return runGuarded(
      model: ModelKind.tagger,
      used: _used,
      copy: _npuCopy,
      who: 'tagger',
      run: () => _runOn(session, nhwc, size),
      onCpu: () async {
        _cpuAfterFailure = true;
        await close();
        final OrtSession cpu = await _open();
        _provider = '$_provider (NPU failed)';
        return _runOn(cpu, nhwc, size);
      },
    );
  }

  Future<Float32List> _runOn(OrtSession session, Float32List nhwc, int size) async {
    final String name = _inputName ?? (session.inputNames.isNotEmpty ? session.inputNames.first : 'input');
    final OrtValue input = await OrtValue.fromList(nhwc, [1, size, size, 3]);
    try {
      final Stopwatch sw = Stopwatch()..start();
      final Map<String, OrtValue> outputs = await session.run({name: input});
      ModelTimings.instance.recordRun(ModelKind.tagger, _used, sw.elapsedMilliseconds, threads: threads);
      try {
        final List<dynamic> raw = await outputs.values.first.asFlattenedList();
        final Float32List out = Float32List(raw.length);
        for (int i = 0; i < raw.length; i++) {
          out[i] = (raw[i] as num).toDouble();
        }
        return out;
      } finally {
        for (final OrtValue v in outputs.values) {
          await v.dispose();
        }
      }
    } finally {
      await input.dispose();
    }
  }

  @override
  Future<void> close() async {
    final OrtSession? s = _session;
    _session = null;
    _opening = null;
    await s?.close();
  }
}
