import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// A picture decoded to straight RGBA bytes, and the size of the file's.
class RawPicture {
  const RawPicture(this.rgba, this.width, this.height, {required this.sourceWidth, required this.sourceHeight});

  final Uint8List rgba;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;

  img.Image toImage() => rawToImage(rgba, width, height);
}

/// RGBA bytes as an `image` picture (alpha kept, for the white backgrounds).
img.Image rawToImage(Uint8List rgba, int width, int height) =>
    img.Image.fromBytes(width: width, height: height, bytes: rgba.buffer, bytesOffset: rgba.offsetInBytes, numChannels: 4, order: img.ChannelOrder.rgba);

Float32List _taggerRaw((Uint8List, int, int, int) a) => ImageTaggerHandler.tensorFromImage(rawToImage(a.$1, a.$2, a.$3), a.$4);

Float32List _taggerBytes((Uint8List, int) a) => ImageTaggerHandler.prepareTensor(a.$1, a.$2);

Float32List _looksRaw((Uint8List, int, int, int, List<double>?, List<double>?) a) =>
    LookModelHandler.imageFromPicture(rawToImage(a.$1, a.$2, a.$3), a.$4, mean: a.$5, std: a.$6);

Float32List _looksBytes((Uint8List, int, List<double>?, List<double>?) a) => LookModelHandler.prepareImage(a.$1, a.$2, mean: a.$3, std: a.$4);

Uint8List _jpegRaw((Uint8List, int, int) a) => img.encodeJpg(rawToImage(a.$1, a.$2, a.$3).convert(numChannels: 3), quality: 88);

/// r86: the pictures the models read. With [PictureDecoder.phone] (the
/// default) Flutter's engine decodes them - Android's own decoders, which
/// shrink a picture while decoding it - to twice what the model needs, and
/// the same preparation as before (padding, crop, the model's resize) runs
/// on that small picture in a background isolate. Before r86 the pure-Dart
/// `image` package decoded the whole file at full size first: 979 ms for a
/// 4 MB picture in the tagger (log 2026-10-02). That decoder is the
/// [PictureDecoder.dart] choice and the fallback for a file the phone
/// cannot read.
///
/// The engine decodes on the UI isolate's engine threads, so the decoding
/// is asked for there; only the preparation goes to an isolate.
class ModelPictures {
  const ModelPictures._();

  static PictureDecoder get chosen => SettingsHandler.instance.pictureDecoder;

  /// [bytes] decoded by the phone, its long side at most [longSide] (or its
  /// short side at most [shortSide]), never scaled up; null when the phone
  /// cannot read it.
  static Future<RawPicture?> decodeOnPhone(Uint8List bytes, {int? longSide, int? shortSide}) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int w = descriptor.width, h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      double scale = 1;
      if (longSide != null) scale = math.min(scale, longSide / math.max(w, h));
      if (shortSide != null) scale = math.min(scale, shortSide / math.min(w, h));
      final int tw = math.max(1, (w * scale).round()), th = math.max(1, (h * scale).round());
      codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
      image = (await codec.getNextFrame()).image;
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      return RawPicture(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), image.width, image.height, sourceWidth: w, sourceHeight: h);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// The tagger's input (ImageTaggerHandler.prepareTensor's), and which
  /// decoder read it. Throws a FormatException for a file neither reads.
  static Future<({Float32List tensor, PictureDecoder used})> forTagger(Uint8List bytes, int size) async {
    final Stopwatch sw = Stopwatch()..start();
    final RawPicture? raw = chosen == PictureDecoder.phone ? await decodeOnPhone(bytes, longSide: 2 * size) : null;
    final Float32List tensor = raw != null
        ? await compute(_taggerRaw, (raw.rgba, raw.width, raw.height, size))
        : await compute(_taggerBytes, (bytes, size));
    final PictureDecoder used = raw != null ? PictureDecoder.phone : PictureDecoder.dart;
    ModelTimings.instance.recordDecode(used, sw.elapsedMilliseconds);
    return (tensor: tensor, used: used);
  }

  /// The looks model's input (LookModelHandler.prepareImage's), and which
  /// decoder read it. Throws a FormatException for a file neither reads.
  static Future<({Float32List tensor, PictureDecoder used})> forLooks(
    Uint8List bytes,
    int size, {
    List<double>? mean,
    List<double>? std,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final RawPicture? raw = chosen == PictureDecoder.phone ? await decodeOnPhone(bytes, shortSide: 2 * size) : null;
    final Float32List tensor = raw != null
        ? await compute(_looksRaw, (raw.rgba, raw.width, raw.height, size, mean, std))
        : await compute(_looksBytes, (bytes, size, mean, std));
    final PictureDecoder used = raw != null ? PictureDecoder.phone : PictureDecoder.dart;
    ModelTimings.instance.recordDecode(used, sw.elapsedMilliseconds);
    return (tensor: tensor, used: used);
  }

  /// A video frame (a JPEG) with its long side at most [limit]; a small one
  /// comes back as it is; null when it is not a picture
  /// (VideoFrames.shrinkJpeg's, by the chosen decoder).
  static Future<Uint8List?> shrinkFrame(Uint8List jpeg, int limit, {Uint8List? Function((Uint8List, int))? dartShrink}) async {
    if (chosen == PictureDecoder.phone) {
      final RawPicture? raw = await decodeOnPhone(jpeg, longSide: limit);
      if (raw != null) {
        if (math.max(raw.sourceWidth, raw.sourceHeight) <= limit) return jpeg;
        return compute(_jpegRaw, (raw.rgba, raw.width, raw.height));
      }
    }
    if (dartShrink == null) return null;
    return compute(dartShrink, (jpeg, limit));
  }
}
