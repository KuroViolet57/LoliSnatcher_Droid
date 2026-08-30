import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';

/// Round 3, item 7: the big-cover header used to run at the image's own
/// aspect ratio, so a portrait cover was nearly twice as tall as it was wide
/// and pushed the title, action row and tags off screen. It is now full width
/// with its height capped to half the viewport, cropping or letterboxing
/// beyond that instead of stretching.
void main() {
  // A typical phone in portrait, in logical pixels.
  const Size phone = Size(400, 860);

  test('a tall portrait cover is capped to half the viewport', () {
    final box = DoujinDetailPage.bigCoverBox(
      screen: phone,
      imageWidth: 800,
      imageHeight: 1200,
    );

    // Full width (minus the page's side padding).
    expect(box.width, phone.width - DoujinDetailPage.coverSidePadding * 2);
    // Capped, and the cap is the requested 45–55% band.
    expect(box.capped, isTrue);
    expect(box.height, phone.height * DoujinDetailPage.maxCoverViewportFraction);
    expect(box.height / phone.height, inInclusiveRange(0.45, 0.55));
  });

  test('an extreme cover is capped just the same', () {
    final box = DoujinDetailPage.bigCoverBox(
      screen: phone,
      imageWidth: 400,
      imageHeight: 2000,
    );
    expect(box.capped, isTrue);
    expect(box.height, phone.height * DoujinDetailPage.maxCoverViewportFraction);
  });

  test('a wide cover keeps its natural height and is NOT capped', () {
    final box = DoujinDetailPage.bigCoverBox(
      screen: phone,
      imageWidth: 1600,
      imageHeight: 1200,
    );
    // 372 wide at 4:3 is ~279 tall — well under the 430 cap.
    expect(box.capped, isFalse);
    expect(box.height, lessThan(phone.height * DoujinDetailPage.maxCoverViewportFraction));
    expect(box.height, closeTo(box.width / (1600 / 1200), 0.01));
  });

  test('unknown dimensions fall back to a doujin cover shape, still capped', () {
    final box = DoujinDetailPage.bigCoverBox(screen: phone);
    expect(box.height, lessThanOrEqualTo(phone.height * DoujinDetailPage.maxCoverViewportFraction));
  });

  test('the cap scales with the viewport, so landscape and tablets behave too', () {
    for (final screen in const [Size(400, 860), Size(860, 400), Size(1200, 1600)]) {
      final box = DoujinDetailPage.bigCoverBox(screen: screen, imageWidth: 800, imageHeight: 1200);
      expect(
        box.height,
        lessThanOrEqualTo(screen.height * DoujinDetailPage.maxCoverViewportFraction + 0.01),
        reason: 'cover must stay within the cap on $screen',
      );
      expect(box.width, screen.width - DoujinDetailPage.coverSidePadding * 2);
    }
  });
}
