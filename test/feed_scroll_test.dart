import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/preview/feed_scroll.dart';

/// r66: the feed loaded its next page whenever a scroll notification said
/// "near the end" - but a horizontal scroll INSIDE a card (the tag rows, the
/// title, the tab cards) bubbles up to the same listener, and one sitting at
/// its own end looks exactly like the feed being near its bottom. Only the
/// feed's own vertical scrolling may count.
void main() {
  ScrollMetrics metrics({required Axis axis, double pixels = 0}) => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 1000,
    pixels: pixels,
    viewportDimension: 500,
    axisDirection: axis == Axis.vertical ? AxisDirection.down : AxisDirection.right,
    devicePixelRatio: 1,
  );

  test("the feed's own vertical scrolling counts", () {
    expect(FeedScroll.accepts(depth: 0, metrics: metrics(axis: Axis.vertical, pixels: 900)), isTrue);
    expect(FeedScroll.accepts(depth: 0, metrics: metrics(axis: Axis.vertical, pixels: 0)), isTrue);
  });

  test('a horizontal scroll inside a card does not, whatever its position', () {
    expect(FeedScroll.accepts(depth: 1, metrics: metrics(axis: Axis.horizontal, pixels: 999)), isFalse);
    expect(FeedScroll.accepts(depth: 0, metrics: metrics(axis: Axis.horizontal, pixels: 999)), isFalse);
  });

  test('a nested vertical scroll (a sheet inside the feed) does not either', () {
    expect(FeedScroll.accepts(depth: 1, metrics: metrics(axis: Axis.vertical, pixels: 900)), isFalse);
    expect(FeedScroll.accepts(depth: 2, metrics: metrics(axis: Axis.vertical, pixels: 900)), isFalse);
  });

  testWidgets('a real notification from the feed itself is accepted', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final ScrollUpdateNotification n = ScrollUpdateNotification(
      metrics: metrics(axis: Axis.vertical, pixels: 900),
      context: tester.element(find.byType(SizedBox)),
      scrollDelta: 1,
    );
    expect(n.depth, 0, reason: 'fresh from the scrollable, before any viewport bumped it');
    expect(FeedScroll.isFeedScroll(n), isTrue);
  });
}
