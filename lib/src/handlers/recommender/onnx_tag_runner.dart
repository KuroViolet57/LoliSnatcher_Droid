import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The real runner: one ONNX Runtime session over the downloaded tagger.
///
/// The WD v3 exports take one float32 input `[batch, size, size, 3]` and
/// answer one row of probabilities per tag; the session's own input name
/// is used, so a custom repo with another name works. Plain CPU with a few
/// threads: the plugin cannot set XNNPACK's own thread count, which would
/// leave that path single-threaded.
class OnnxTagRunner implements TagRunner {
  OnnxTagRunner(this.modelPath, {int? threads}) : threads = threads ?? math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

  final String modelPath;
  final int threads;

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
      try {
        _session = await OnnxRuntime().createSession(modelPath, options: OrtSessionOptions(intraOpNumThreads: threads));
        _provider = 'CPU x$threads';
      } catch (e) {
        Logger.Inst().log('tagger: could not open the model with $threads threads ($e); default options', 'OnnxTagRunner', '_openNow', LogTypes.booruHandlerInfo);
        _session = await OnnxRuntime().createSession(modelPath);
        _provider = 'CPU';
      }
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
    final String name = _inputName ?? (session.inputNames.isNotEmpty ? session.inputNames.first : 'input');
    final OrtValue input = await OrtValue.fromList(nhwc, [1, size, size, 3]);
    try {
      final Map<String, OrtValue> outputs = await session.run({name: input});
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
