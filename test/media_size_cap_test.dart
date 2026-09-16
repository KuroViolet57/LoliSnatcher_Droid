import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/media_size_cap.dart';

/// r59: media_kit gives the Android video surface the video's native size, so
/// an 8K post (4320x7680) made Skia draws take 600-925 ms and the warm players
/// held ~2.1 GB of graphics memory. r57 tried to resize that surface from
/// outside and broke playback (§4.27); the cap now lives inside our own copy of
/// media_kit_video, which asks the app for the size before it sets it.
///
/// Pictures keep their own ceiling: the viewer limited only their width, so a
/// very tall picture could still decode into hundreds of MB.
void main() {
  // The user's S24 Ultra, in physical pixels.
  const Size screen = Size(1440, 3120);

  group('video surface', () {
    test('an 8K portrait video is cut down to the screen', () {
      expect(
        MediaSizeCap.videoSurface(source: const Size(4320, 7680), screen: screen),
        const Size(1440, 2560),
      );
    });

    test('a 4K landscape video fits the screen turned sideways', () {
      // 3840x2086 fits inside 3120x1440 -> scaled by 1440/2086.
      expect(
        MediaSizeCap.videoSurface(source: const Size(3840, 2086), screen: screen),
        const Size(2650, 1440),
      );
    });

    test('a square video fits the narrow side', () {
      expect(
        MediaSizeCap.videoSurface(source: const Size(4096, 4096), screen: screen),
        const Size(1440, 1440),
      );
    });

    test('videos the screen can already show are left alone, never upscaled', () {
      for (final Size source in [
        const Size(1920, 1080),
        const Size(1280, 720),
        const Size(1080, 1920),
        const Size(640, 360),
        const Size(1440, 3120),
      ]) {
        expect(MediaSizeCap.videoSurface(source: source, screen: screen), source, reason: '$source');
      }
    });

    test('an unknown or empty size changes nothing', () {
      expect(MediaSizeCap.videoSurface(source: Size.zero, screen: screen), Size.zero);
      expect(MediaSizeCap.videoSurface(source: const Size(4320, 0), screen: screen), const Size(4320, 0));
      expect(
        MediaSizeCap.videoSurface(source: const Size(4320, 7680), screen: Size.zero),
        const Size(4320, 7680),
        reason: 'no screen size yet: leave the video alone',
      );
    });

    test('the capped size is even on both sides and keeps the shape', () {
      final Size capped = MediaSizeCap.videoSurface(source: const Size(4321, 7681), screen: screen);
      expect(capped.width.round() % 2, 0);
      expect(capped.height.round() % 2, 0);
      expect(capped.width / capped.height, closeTo(4321 / 7681, 0.01));
      expect(capped.width, lessThanOrEqualTo(1440));
    });
  });

  group('picture decode', () {
    // What the viewer already asks for: about twice the screen width.
    const int widthLimit = 2900;

    test('a huge square picture is bound by the width limit, as before', () {
      expect(
        MediaSizeCap.imageDecodeSize(source: const Size(8000, 8000), widthLimit: widthLimit),
        const Size(2900, 2900),
      );
    });

    test('a very tall picture is bound by the 4K ceiling', () {
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

    test('the ceiling is 4K', () {
      expect(MediaSizeCap.imageLongEdge, 3840);
    });
  });
}
