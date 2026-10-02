import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_pictures.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r86: pictures for the models are decoded by the phone (Flutter's engine,
/// Android's own decoders), shrunk while decoding to twice what the model
/// needs - instead of the pure-Dart decoder reading the whole file at full
/// size first (979 ms for one 4 MB picture in the tagger, log 2026-10-02).
/// What the model sees stays close to before; the old decoder is kept as a
/// choice and as the fallback for files the phone cannot read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  /// Smooth gradients: resize filters differ least on them, as on photos.
  img.Image gradient(int w, int h) {
    final img.Image image = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        image.setPixelRgb(x, y, (255 * x / w).round(), (255 * y / h).round(), (128 + 100 * (x - y) / (w + h)).round());
      }
    }
    return image;
  }

  Uint8List png(int w, int h) => img.encodePng(gradient(w, h));

  double meanAbsDiff(Float32List a, Float32List b) {
    expect(a.length, b.length);
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += (a[i] - b[i]).abs();
    }
    return s / a.length;
  }

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('model_pictures_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.pictureDecoder = PictureDecoder.phone;
  });

  tearDown(() {
    SettingsHandler.instance.pictureDecoder = PictureDecoder.phone;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('the phone decodes a big picture at the size asked for, keeping its shape', (tester) async {
    final RawPicture? long = await tester.runAsync<RawPicture?>(() => ModelPictures.decodeOnPhone(png(1600, 1000), longSide: 896));
    expect(long, isNotNull);
    expect((long!.width, long.height), (896, 560));
    expect((long.sourceWidth, long.sourceHeight), (1600, 1000));
    expect(long.rgba.length, 896 * 560 * 4);

    final RawPicture? short = await tester.runAsync<RawPicture?>(() => ModelPictures.decodeOnPhone(png(1600, 1000), shortSide: 512));
    expect((short!.width, short.height), (819, 512));
  });

  testWidgets('a picture smaller than that is never scaled up', (tester) async {
    final RawPicture? p = await tester.runAsync<RawPicture?>(() => ModelPictures.decodeOnPhone(png(300, 200), longSide: 896));
    expect((p!.width, p.height), (300, 200));
  });

  testWidgets("the tagger's input from the phone matches the one from before", (tester) async {
    final Uint8List bytes = png(1600, 1000);
    final Float32List before = ImageTaggerHandler.prepareTensor(bytes, 448);
    final r = await tester.runAsync(() => ModelPictures.forTagger(bytes, 448));
    expect(r!.used, PictureDecoder.phone);
    expect(meanAbsDiff(before, r.tensor), lessThan(4.0), reason: 'on the 0-255 scale');
    // The white band the square padding adds below a wide picture.
    const int lastRow = 447 * 448 * 3;
    expect(r.tensor.sublist(lastRow, lastRow + 6), everyElement(closeTo(255, 0.5)));
  });

  testWidgets("the looks model's input from the phone matches the one from before", (tester) async {
    final Uint8List bytes = png(1600, 1000);
    final Float32List before = LookModelHandler.prepareImage(bytes, 256);
    final r = await tester.runAsync(() => ModelPictures.forLooks(bytes, 256));
    expect(r!.used, PictureDecoder.phone);
    expect(meanAbsDiff(before, r.tensor), lessThan(0.02), reason: 'on the 0-1 scale');
  });

  testWidgets('transparency still reads as white for the tagger', (tester) async {
    final img.Image clear = img.Image(width: 64, height: 64, numChannels: 4);
    final Uint8List bytes = img.encodePng(clear);
    final r = await tester.runAsync(() => ModelPictures.forTagger(bytes, 32));
    expect(r!.tensor, everyElement(closeTo(255, 1)));
  });

  testWidgets('"As before" uses the old decoder; a file the phone cannot read falls back to it', (tester) async {
    SettingsHandler.instance.pictureDecoder = PictureDecoder.dart;
    final Uint8List bytes = png(400, 300);
    final r = await tester.runAsync(() => ModelPictures.forTagger(bytes, 64));
    expect(r!.used, PictureDecoder.dart);
    expect(r.tensor, ImageTaggerHandler.prepareTensor(bytes, 64));

    SettingsHandler.instance.pictureDecoder = PictureDecoder.phone;
    final Uint8List tga = img.encodeTga(gradient(40, 30));
    final f = await tester.runAsync(() => ModelPictures.forLooks(tga, 16));
    expect(f!.used, PictureDecoder.dart, reason: 'the phone reads no TGA; the old decoder does');

    Object? error;
    await tester.runAsync(() async {
      try {
        await ModelPictures.forTagger(Uint8List.fromList([1, 2, 3, 4]), 16);
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<FormatException>());
  });

  testWidgets('a video frame is shrunk to 512 px on its long side; a small one comes back as it was', (tester) async {
    final Uint8List big = img.encodeJpg(gradient(1280, 720), quality: 90);
    final Uint8List? small = await tester.runAsync<Uint8List?>(() => ModelPictures.shrinkFrame(big, 512));
    final img.Image out = img.decodeJpg(small!)!;
    expect((out.width, out.height), (512, 288));

    final Uint8List little = img.encodeJpg(gradient(400, 300), quality: 90);
    expect(await tester.runAsync<Uint8List?>(() => ModelPictures.shrinkFrame(little, 512)), same(little));
  });

  test('the choice is stored with the settings; the phone is the default', () {
    final settings = SettingsHandler.instance;
    expect(settings.map['pictureDecoder']!['default'], 'phone');
    settings.setByString('pictureDecoder', 'dart');
    expect(settings.pictureDecoder, PictureDecoder.dart);
    expect(settings.getByString('pictureDecoder'), 'dart');
    expect(PictureDecoder.parse('nonsense'), PictureDecoder.phone);
  });
}
