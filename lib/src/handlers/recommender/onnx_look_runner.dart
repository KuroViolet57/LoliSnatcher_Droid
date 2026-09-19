import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The real runner: one ONNX Runtime session per half of the looks model.
///
/// The picture half takes `pixel_values` `[1, 3, size, size]` and answers
/// the projected image vector; the text half takes `input_ids` and
/// `attention_mask` (int64, `[1, length]`) and answers the projected text
/// vector. The sessions' own input names are used, so another CLIP export
/// works too; the first output is taken either way.
class OnnxLookRunner implements LookRunner {
  OnnxLookRunner(this.imagePath, this.textPath, {int? threads}) : threads = threads ?? defaultThreads;

  /// r77: one thread for everyone (was half the cores): with one thread ORT
  /// builds no thread pool, so nothing spins next to the screen and the video.
  static const int defaultThreads = 1;

  final String imagePath;
  final String textPath;
  final int threads;

  OrtSessionOptions get options => OrtSessionOptions(intraOpNumThreads: threads);

  OrtSession? _image;
  OrtSession? _text;
  Future<OrtSession>? _openingImage;
  Future<OrtSession>? _openingText;
  String _provider = '';

  @override
  String get provider => _provider;

  Future<OrtSession> _open(String path, {required bool image}) async {
    OrtSession s;
    try {
      s = await OnnxRuntime().createSession(path, options: options);
      _provider = 'CPU x$threads';
    } catch (e) {
      Logger.Inst().log('look: could not open ${image ? 'the picture' : 'the text'} half with $threads threads ($e); default options', 'OnnxLookRunner', '_open', LogTypes.booruHandlerInfo);
      s = await OnnxRuntime().createSession(path);
      _provider = 'CPU';
    }
    return s;
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
      return await _first(await session.run({name: input}));
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
