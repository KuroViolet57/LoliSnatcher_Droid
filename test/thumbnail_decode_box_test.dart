import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/settings/preview_display_mode.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_decode_box.dart';

/// r69: a thumbnail's decode size followed the app-wide preview SHAPE, not the
/// box it is drawn in. With the default square shape a 450x629 doujin cover in
/// a 116x176 list column (406x616 px on the S24 Ultra) decoded into a 406x406
/// box - 290x406 - and was then drawn 1.4x larger than that: blur the app
/// added itself. Covers now decode for the box they fill, with some slack.
void main() {
  const double dpr = 3.5;
  const BoxConstraints column = BoxConstraints.tightFor(width: 116, height: 176);

  test('a cover in a bounded box decodes for that box, times the slack, both ways', () {
    final box = ThumbnailDecodeBox.of(
      constraints: column,
      devicePixelRatio: dpr,
      mode: PreviewDisplayMode.square,
      isStandalone: true,
      isCover: true,
    );
    expect(box.width, closeTo(116 * dpr * ThumbnailDecodeBox.coverSlack, 0.01));
    expect(box.height, closeTo(176 * dpr * ThumbnailDecodeBox.coverSlack, 0.01));
    expect(ThumbnailDecodeBox.coverSlack, greaterThanOrEqualTo(1.4), reason: 'a 0.7 cover in a square cell needs 1.43');
  });

  test('a cover whose height is unbounded keeps the old shape rule', () {
    final box = ThumbnailDecodeBox.of(
      constraints: const BoxConstraints(maxWidth: 116),
      devicePixelRatio: dpr,
      mode: PreviewDisplayMode.square,
      isStandalone: true,
      isCover: true,
    );
    expect(box.width, closeTo(116 * dpr, 0.01));
    expect(box.height, closeTo(116 * dpr, 0.01));
  });

  test('an embedded thumbnail decodes to its width only, as before', () {
    final box = ThumbnailDecodeBox.of(
      constraints: column,
      devicePixelRatio: dpr,
      mode: PreviewDisplayMode.square,
      isStandalone: false,
      isCover: true,
    );
    expect(box.width, closeTo(116 * dpr, 0.01));
    expect(box.height, isNull);
  });

  group('everything that is not a doujin cover keeps the old rules', () {
    test('square', () {
      final box = ThumbnailDecodeBox.of(
        constraints: column,
        devicePixelRatio: dpr,
        mode: PreviewDisplayMode.square,
        isStandalone: true,
        isCover: false,
      );
      expect(box.width, closeTo(116 * dpr, 0.01));
      expect(box.height, closeTo(116 * dpr, 0.01));
    });

    test('rectangle', () {
      final box = ThumbnailDecodeBox.of(
        constraints: column,
        devicePixelRatio: dpr,
        mode: PreviewDisplayMode.rectangle,
        isStandalone: true,
        isCover: false,
      );
      expect(box.width, closeTo(116 * dpr, 0.01));
      expect(box.height, closeTo(116 * dpr * 16 / 9, 0.01));
    });

    test('staggered with a known portrait ratio: width only; unknown: the 16:9 fallback', () {
      final portrait = ThumbnailDecodeBox.of(
        constraints: column,
        devicePixelRatio: dpr,
        mode: PreviewDisplayMode.staggered,
        isStandalone: true,
        isCover: false,
        aspectRatio: 0.7,
      );
      expect(portrait.width, closeTo(116 * dpr, 0.01));
      expect(portrait.height, isNull);

      final unknown = ThumbnailDecodeBox.of(
        constraints: column,
        devicePixelRatio: dpr,
        mode: PreviewDisplayMode.staggered,
        isStandalone: true,
        isCover: false,
      );
      expect(unknown.width, closeTo(116 * dpr, 0.01));
      expect(unknown.height, closeTo(116 * dpr * 16 / 9, 0.01));
    });
  });
}
