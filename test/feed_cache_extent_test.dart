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
}
