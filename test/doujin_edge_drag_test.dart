import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';

/// Round 4, item 1: the mini tab manager's drag strip. Flutter's ~20px
/// default sits under Android's gesture handle and is unreachable one-handed,
/// and the earlier widening only applied to tab-hosted pages — the pushed
/// detail page (tapping a card, the common path) still had the default.
void main() {
  // Real phone widths in logical pixels, not the minimum that technically
  // works: a small phone, a common one, a large one, and a tablet.
  const List<Size> screens = [
    Size(360, 780), // compact Android
    Size(393, 852), // Pixel-class
    Size(430, 932), // large phone
    Size(800, 1280), // tablet
  ];

  test('the strip is a quarter to a third of the width on real phones', () {
    for (final screen in screens.take(3)) {
      final double width = DoujinDetailPage.edgeDragWidthFor(screen);
      final double fraction = width / screen.width;
      expect(
        fraction,
        inInclusiveRange(0.25, 0.34),
        reason: 'on $screen the strip is ${fraction.toStringAsFixed(2)} of the width',
      );
    }
  });

  test('it is far wider than the platform default it replaces', () {
    // Flutter's default edge drag is ~20 logical pixels.
    for (final screen in screens) {
      expect(DoujinDetailPage.edgeDragWidthFor(screen), greaterThan(20 * 4));
    }
  });

  test('a tablet is clamped so the strip cannot swallow half the page', () {
    const Size tablet = Size(1400, 1000);
    final double width = DoujinDetailPage.edgeDragWidthFor(tablet);
    expect(width, DoujinDetailPage.maxEdgeDragWidth);
    expect(width / tablet.width, lessThan(0.25));
  });

  test('a very narrow window still gets a usable strip', () {
    final double width = DoujinDetailPage.edgeDragWidthFor(const Size(240, 600));
    expect(width, DoujinDetailPage.minEdgeDragWidth);
    expect(width, greaterThanOrEqualTo(90));
  });

  test('the width does not depend on how the page was opened', () {
    // One function, no asTab parameter: a pushed detail page and a
    // tab-hosted one get exactly the same strip.
    const Size screen = Size(393, 852);
    expect(
      DoujinDetailPage.edgeDragWidthFor(screen),
      DoujinDetailPage.edgeDragWidthFor(screen),
    );
    expect(DoujinDetailPage.edgeDragWidthFor(screen), closeTo(393 * 0.3, 0.01));
  });
}
