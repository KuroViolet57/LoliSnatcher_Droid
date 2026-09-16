import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/media_size_cap.dart';

/// r57: the viewer limited a picture's width to about twice the screen's, but
/// nothing bounded its height, so one very tall picture could decode into
/// hundreds of MB. (The video half of this cap was removed again in r58: see
/// [MediaSizeCap].)
void main() {
  // What the viewer already asks for: about twice the screen width.
  const int widthLimit = 2900;

  test('a huge square picture is bound by the width limit, as before', () {
    expect(
      MediaSizeCap.imageDecodeSize(source: const Size(8000, 8000), widthLimit: widthLimit),
      const Size(2900, 2900),
    );
  });

  test('a very tall picture is bound by the 4K ceiling, which is the new part', () {
    expect(
      MediaSizeCap.imageDecodeSize(source: const Size(2000, 20000), widthLimit: widthLimit),
      const Size(384, 3840),
    );
  });

  test('with no width limit the 4K ceiling still holds', () {
    expect(
      MediaSizeCap.imageDecodeSize(source: const Size(8000, 8000), widthLimit: null),
      const Size(3840, 3840),
    );
  });

  test('pictures that already fit are untouched and never upscaled', () {
    for (final Size source in [
      const Size(1920, 1080),
      const Size(2000, 2000),
      const Size(800, 3000),
    ]) {
      expect(MediaSizeCap.imageDecodeSize(source: source, widthLimit: widthLimit), source, reason: '$source');
    }
  });

  test('an unknown size changes nothing', () {
    expect(MediaSizeCap.imageDecodeSize(source: Size.zero, widthLimit: widthLimit), Size.zero);
  });

  test('the ceiling is 4K', () {
    expect(MediaSizeCap.imageLongEdge, 3840);
  });
}
