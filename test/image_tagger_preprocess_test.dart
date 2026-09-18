import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';

/// r74: the picture as the WD taggers want it (the author's reference
/// code): transparency onto white, padded to a square with white, resized
/// to the model's size, float32 0-255, BGR, one image per batch.
void main() {
  Uint8List rgb(List<List<List<int>>> rows) {
    final img.Image image = img.Image(width: rows.first.length, height: rows.length);
    for (int y = 0; y < rows.length; y++) {
      for (int x = 0; x < rows[y].length; x++) {
        image.setPixelRgb(x, y, rows[y][x][0], rows[y][x][1], rows[y][x][2]);
      }
    }
    return img.encodePng(image);
  }

  List<double> at(Float32List t, int size, int x, int y) => [t[(y * size + x) * 3], t[(y * size + x) * 3 + 1], t[(y * size + x) * 3 + 2]];

  test('a square picture at the model size: no padding, no resize, BGR order, 0-255 floats', () {
    final Float32List t = ImageTaggerHandler.prepareTensor(
      rgb([
        [
          [255, 0, 0],
          [0, 255, 0],
        ],
        [
          [0, 0, 255],
          [255, 255, 255],
        ],
      ]),
      2,
    );
    expect(t, hasLength(2 * 2 * 3));
    expect(at(t, 2, 0, 0), [0, 0, 255], reason: 'red reads B=0, G=0, R=255');
    expect(at(t, 2, 1, 0), [0, 255, 0]);
    expect(at(t, 2, 0, 1), [255, 0, 0], reason: 'blue reads B=255');
    expect(at(t, 2, 1, 1), [255, 255, 255]);
  });

  test('a wide picture is padded below with white, a tall one to the right (the reference pads from the top-left half)', () {
    final Float32List wide = ImageTaggerHandler.prepareTensor(
      rgb([
        [
          [255, 0, 0],
          [0, 0, 255],
        ],
      ]),
      2,
    );
    expect(at(wide, 2, 0, 0), [0, 0, 255]);
    expect(at(wide, 2, 1, 0), [255, 0, 0]);
    expect(at(wide, 2, 0, 1), [255, 255, 255]);
    expect(at(wide, 2, 1, 1), [255, 255, 255]);
    final Float32List tall = ImageTaggerHandler.prepareTensor(
      rgb([
        [
          [255, 0, 0],
        ],
        [
          [0, 0, 255],
        ],
      ]),
      2,
    );
    expect(at(tall, 2, 0, 0), [0, 0, 255]);
    expect(at(tall, 2, 0, 1), [255, 0, 0]);
    expect(at(tall, 2, 1, 0), [255, 255, 255]);
    expect(at(tall, 2, 1, 1), [255, 255, 255]);
    // 3 wide, 1 high: pad_top = (3 - 1) ~/ 2 = 1, so the picture sits in the middle row.
    final Float32List three = ImageTaggerHandler.prepareTensor(
      rgb([
        [
          [255, 0, 0],
          [255, 0, 0],
          [255, 0, 0],
        ],
      ]),
      3,
    );
    expect(at(three, 3, 1, 0), [255, 255, 255]);
    expect(at(three, 3, 1, 1), [0, 0, 255]);
    expect(at(three, 3, 1, 2), [255, 255, 255]);
  });

  test('a picture larger than the model size is resized to it; every value stays within 0-255', () {
    final img.Image big = img.Image(width: 40, height: 30);
    img.fill(big, color: img.ColorRgb8(10, 20, 30));
    final Float32List t = ImageTaggerHandler.prepareTensor(img.encodePng(big), 8);
    expect(t, hasLength(8 * 8 * 3));
    for (final double v in t) {
      expect(v, inInclusiveRange(0, 255));
    }
    // The top-left is picture (a 40x30 picture padded to 40x40 sits in rows 5..34), read as BGR.
    expect(at(t, 8, 3, 3), [30, 20, 10]);
    // The bottom row is padding: white.
    expect(at(t, 8, 3, 7), [255, 255, 255]);
  });

  test('transparency is laid onto white before anything else; a broken picture is a FormatException', () {
    final img.Image image = img.Image(width: 2, height: 1, numChannels: 4);
    image.setPixelRgba(0, 0, 255, 0, 0, 0);
    image.setPixelRgba(1, 0, 255, 0, 0, 255);
    final Float32List t = ImageTaggerHandler.prepareTensor(img.encodePng(image), 2);
    expect(at(t, 2, 0, 0), [255, 255, 255], reason: 'fully transparent = white');
    expect(at(t, 2, 1, 0), [0, 0, 255]);
    expect(() => ImageTaggerHandler.prepareTensor(Uint8List.fromList([1, 2, 3, 4]), 2), throwsA(isA<FormatException>()));
  });
}
