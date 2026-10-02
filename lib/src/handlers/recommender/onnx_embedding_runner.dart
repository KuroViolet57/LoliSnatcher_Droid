import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The real runner: one ONNX Runtime session over the downloaded model.
///
/// BERT-family exports take `input_ids` and `attention_mask` (int64,
/// `[batch, length]`), some `token_type_ids` too; the session's own input
/// names decide. The first output is the token embeddings
/// `[batch, length, dim]` (or an already pooled `[batch, dim]`, which the
/// handler recognises by its size).
class OnnxEmbeddingRunner implements EmbeddingRunner {
  OnnxEmbeddingRunner(this.modelPath, {required this.dim, required this.wantsTokenTypeIds, int? threads, ModelAccelerator? accelerator})
    : threads = threads ?? defaultThreads,
      accelerator = accelerator ?? savedAccelerator(ModelKind.text);

  /// r77: one thread (no count was set before, so ORT used every core - 8
  /// on an 8-core phone). With one thread ORT builds no pool and nothing spins.
  static const int defaultThreads = 1;

  final int threads;

  /// r86: what the model runs on (Settings → Models → Run on).
  final ModelAccelerator accelerator;

  OrtSessionOptions get options => onnxSessionOptions(threads: threads, accelerator: accelerator);

  ModelAccelerator _used = ModelAccelerator.cpu;
  String _provider = '';

  /// How the log names what it runs on ("CPU x2", "NNAPI x2").
  String get provider => _provider.isEmpty ? '${accelerator.label} x$threads' : _provider;

  final String modelPath;

  @override
  final int dim;

  @override
  final bool wantsTokenTypeIds;

  OrtSession? _session;
  Future<OrtSession>? _opening;

  /// A session that failed to open is tried again next time, not kept as a
  /// failed future forever.
  Future<OrtSession> _open() => _opening ??= _openNow();

  Future<OrtSession> _openNow() async {
    try {
      // A choice or a thread count the runtime refuses falls back (the CPU,
      // then its defaults), and says so - like the other two runners.
      final OpenedSession o = await openOnnxSession(modelPath, model: ModelKind.text, threads: threads, accelerator: accelerator, who: 'encoder');
      _used = o.used;
      _provider = o.provider;
      return _session = o.session;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<Float32List> run(List<List<int>> ids, List<List<int>> mask) async {
    final OrtSession session = await _open();
    final int batch = ids.length;
    final int length = ids.first.length;
    final Int64List flatIds = Int64List(batch * length);
    final Int64List flatMask = Int64List(batch * length);
    for (int b = 0; b < batch; b++) {
      for (int t = 0; t < length; t++) {
        flatIds[b * length + t] = ids[b][t];
        flatMask[b * length + t] = mask[b][t];
      }
    }
    final List<int> shape = [batch, length];
    final Map<String, OrtValue> inputs = {};
    try {
      for (final String name in session.inputNames) {
        switch (name) {
          case 'input_ids':
            inputs[name] = await OrtValue.fromList(flatIds, shape);
          case 'attention_mask':
            inputs[name] = await OrtValue.fromList(flatMask, shape);
          case 'token_type_ids':
            inputs[name] = await OrtValue.fromList(Int64List(batch * length), shape);
          default:
            Logger.Inst().log('encoder input "$name" is not one this app knows; left unset', 'OnnxEmbeddingRunner', 'run', LogTypes.booruHandlerInfo);
        }
      }
      final Stopwatch sw = Stopwatch()..start();
      final Map<String, OrtValue> outputs = await session.run(inputs);
      ModelTimings.instance.recordRun(ModelKind.text, _used, sw.elapsedMilliseconds, threads: threads);
      try {
        final OrtValue value = outputs['last_hidden_state'] ?? outputs['token_embeddings'] ?? outputs.values.first;
        final List<dynamic> raw = await value.asFlattenedList();
        // r77: the plugin hands float outputs over as a typed array already;
        // copying it value by value was work on the UI isolate for nothing.
        if (raw is Float32List) return raw;
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
      for (final OrtValue v in inputs.values) {
        await v.dispose();
      }
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
