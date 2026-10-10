import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/feed/logic/feed_cache_extent.dart';

void main() {
  test('a fling widens the grid cache, and low performance mode does not', () {
    var now = DateTime(2026, 10, 7, 13);
    final FeedCacheWindow window = FeedCacheWindow(clock: () => now);

    expect(window.extent(devicePixelRatio: 2), 600, reason: 'resting cache stays 300 css pixels times the pixel ratio');
    expect(window.noteActivity(now, shitDevice: true), isFalse);
    expect(window.isOpen, isFalse);
    expect(window.extent(devicePixelRatio: 2, shitDevice: true), 600);

    expect(window.noteActivity(now, shitDevice: false), isTrue, reason: 'the first fling opens the window');
    expect(window.extent(devicePixelRatio: 2), 1800);
    expect(window.noteActivity(now, shitDevice: false), isFalse, reason: 'another fling while open does not reopen it');

    now = now.add(const Duration(seconds: 2));
    expect(window.noteActivity(now, shitDevice: false), isFalse);
    expect(window.isOpenAt(now.add(const Duration(seconds: 2, milliseconds: 999))), isTrue);
    expect(window.isOpenAt(now.add(const Duration(seconds: 3))), isFalse, reason: 'the hold is 3 seconds from the last fling');

    now = now.add(const Duration(seconds: 3));
    expect(window.extent(devicePixelRatio: 2), 600);
    expect(window.extent(devicePixelRatio: 2, shitDevice: true), 600);
  });

  /// 2026-10-10 (F42): in the doujin List view, opening the window at once
  /// built 13 rows in one 28 ms frame on the Thor. There it opens in steps of
  /// about one row a side, and still reaches the full width.
  test('ramped, the window opens in steps and ends as wide', () {
    var now = DateTime(2026, 10, 10, 6);
    final FeedCacheWindow window = FeedCacheWindow(clock: () => now);

    expect(window.extent(devicePixelRatio: 2, ramped: true), 600, reason: 'closed: resting');
    expect(window.noteActivity(now, shitDevice: false), isTrue);

    const double step = (1800 - 600) / FeedCacheWindow.rampSteps;
    expect(window.extent(devicePixelRatio: 2, ramped: true), 600 + step, reason: 'one step at first');
    expect(window.extent(devicePixelRatio: 2), 1800, reason: 'unramped (the grid) opens at once, as before');
    expect(window.rampDone(now), isFalse);

    final List<double> seen = [];
    for (int i = 1; i <= FeedCacheWindow.rampSteps + 2; i++) {
      now = now.add(FeedCacheWindow.ramp ~/ FeedCacheWindow.rampSteps);
      seen.add(window.extent(devicePixelRatio: 2, ramped: true));
    }
    for (int i = 1; i < seen.length; i++) {
      expect(seen[i] - seen[i - 1], lessThanOrEqualTo(step + 0.001), reason: 'never more than one step at a time');
    }
    expect(seen.last, 1800, reason: 'fully open after the ramp');
    expect(window.rampDone(now), isTrue);

    // Another fling while open does not start the ramp again.
    expect(window.noteActivity(now, shitDevice: false), isFalse);
    expect(window.extent(devicePixelRatio: 2, ramped: true), 1800);

    // Closed, then opened again: ramps again.
    now = now.add(const Duration(seconds: 4));
    expect(window.extent(devicePixelRatio: 2, ramped: true), 600);
    expect(window.noteActivity(now, shitDevice: false), isTrue);
    expect(window.extent(devicePixelRatio: 2, ramped: true), 600 + step);
  });
}
