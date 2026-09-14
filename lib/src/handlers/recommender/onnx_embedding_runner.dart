import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The real runner: one ONNX Runtime session over the downloaded model.
///
/// BERT-family exports take `input_ids` and `attention_mask` (int64,
/// `[batch, length]`), some `token_type_ids` too; the session's own input
/// names decide. The first output is the token embeddings
/// `[batch, length, dim]` (or an already pooled `[batch, dim]`, which the
/// handler recognises by its size).
class OnnxEmbeddingRunner implements EmbeddingRunner {
  OnnxEmbeddingRunner(this.modelPath, {required this.dim, required this.wantsTokenTypeIds});

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
      return _session = await OnnxRuntime().createSession(modelPath);
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
      final Map<String, OrtValue> outputs = await session.run(inputs);
      try {
        final OrtValue value = outputs['last_hidden_state'] ?? outputs['token_embeddings'] ?? outputs.values.first;
        final List<dynamic> raw = await value.asFlattenedList();
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
