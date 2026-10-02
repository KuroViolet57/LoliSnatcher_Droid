import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The real runner: one ONNX Runtime session per half of the looks model.
///
/// The picture half takes `pixel_values` `[1, 3, size, size]` and answers
/// the projected image vector; the text half takes `input_ids` and
/// `attention_mask` (int64, `[1, length]`) and answers the projected text
/// vector. The sessions' own input names are used, so another CLIP export
/// works too; the first output is taken either way.
class OnnxLookRunner implements LookRunner {
  OnnxLookRunner(this.imagePath, this.textPath, {int? threads, ModelAccelerator? accelerator})
    : threads = threads ?? defaultThreads,
      accelerator = accelerator ?? savedAccelerator(ModelKind.look);

  /// r77: one thread for everyone (was half the cores): with one thread ORT
  /// builds no thread pool, so nothing spins next to the screen and the video.
  static const int defaultThreads = 1;

  final String imagePath;
  final String textPath;
  final int threads;

  /// r86: what the model runs on (Settings → Models → Run on).
  final ModelAccelerator accelerator;

  OrtSessionOptions get options => onnxSessionOptions(threads: threads, accelerator: accelerator);

  /// What the picture half really opened on (the CPU when the choice was refused).
  ModelAccelerator _used = ModelAccelerator.cpu;

  OrtSession? _image;
  OrtSession? _text;
  Future<OrtSession>? _openingImage;
  Future<OrtSession>? _openingText;
  String _provider = '';

  @override
  String get provider => _provider;

  Future<OrtSession> _open(String path, {required bool image}) async {
    final OpenedSession o = await openOnnxSession(
      path,
      model: ModelKind.look,
      threads: threads,
      accelerator: accelerator,
      who: image ? 'look (picture half)' : 'look (text half)',
    );
    if (image) _used = o.used;
    _provider = o.provider;
    return o.session;
  }

  Future<OrtSession> _imageSession() => _openingImage ??= _open(imagePath, image: true).then((s) => _image = s).catchError((Object e) {
    _openingImage = null;
    throw e;
  });

  Future<OrtSession> _textSession() => _openingText ??= _open(textPath, image: false).then((s) => _text = s).catchError((Object e) {
    _openingText = null;
    throw e;
  });

  static Future<Float32List> _first(Map<String, OrtValue> outputs) async {
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
  }

  @override
  Future<Float32List> image(Float32List nchw, int size) async {
    final OrtSession session = await _imageSession();
    final String name = session.inputNames.isNotEmpty ? session.inputNames.first : 'pixel_values';
    final OrtValue input = await OrtValue.fromList(nchw, [1, 3, size, size]);
    try {
      final Stopwatch sw = Stopwatch()..start();
      final Map<String, OrtValue> outputs = await session.run({name: input});
      ModelTimings.instance.recordRun(ModelKind.look, _used, sw.elapsedMilliseconds);
      return await _first(outputs);
    } finally {
      await input.dispose();
    }
  }

  @override
  Future<Float32List> text(List<int> ids, List<int> mask) async {
    final OrtSession session = await _textSession();
    final List<int> shape = [1, ids.length];
    final Map<String, OrtValue> inputs = {};
    try {
      for (final String name in session.inputNames.isNotEmpty ? session.inputNames : const ['input_ids', 'attention_mask']) {
        if (name == 'attention_mask') {
          inputs[name] = await OrtValue.fromList(Int64List.fromList(mask), shape);
        } else if (name == 'input_ids' || inputs.isEmpty) {
          inputs[name] = await OrtValue.fromList(Int64List.fromList(ids), shape);
        } else {
          Logger.Inst().log('look: text input "$name" is not one this app knows; left unset', 'OnnxLookRunner', 'text', LogTypes.booruHandlerInfo);
        }
      }
      return await _first(await session.run(inputs));
    } finally {
      for (final OrtValue v in inputs.values) {
        await v.dispose();
      }
    }
  }

  @override
  Future<void> close() async {
    final OrtSession? i = _image;
    final OrtSession? t = _text;
    _image = null;
    _text = null;
    _openingImage = null;
    _openingText = null;
    await i?.close();
    await t?.close();
  }
}
