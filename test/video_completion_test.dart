import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/video_completion_tracker.dart';

/// r34: watching a video through is a signal. The tracker says so exactly
/// once per item, whether the player reports the last tenth or loops past
/// the end without ever reporting it.
void main() {
  const Duration total = Duration(seconds: 20);

  test('fires once when nine tenths are reached, and never again for the same item', () {
    final VideoCompletionTracker t = VideoCompletionTracker();
    expect(t.update(key: 'a', position: const Duration(seconds: 5), duration: total), isFalse);
    expect(t.update(key: 'a', position: const Duration(seconds: 17), duration: total), isFalse);
    expect(t.update(key: 'a', position: const Duration(seconds: 18), duration: total), isTrue);
    expect(t.update(key: 'a', position: const Duration(seconds: 19), duration: total), isFalse);
    expect(t.update(key: 'a', position: const Duration(seconds: 1), duration: total), isFalse, reason: 'looped; already counted');
  });

  test('a loop that wraps past the end counts; a seek back from the middle, or a player restarted after a swipe away, does not (review)', () {
    final VideoCompletionTracker t = VideoCompletionTracker();
    expect(t.update(key: 'a', position: const Duration(seconds: 17), duration: total), isFalse);
    expect(t.update(key: 'a', position: const Duration(seconds: 1), duration: total), isTrue, reason: 'from the last fifth to the start: wrapped');
    final VideoCompletionTracker s = VideoCompletionTracker();
    expect(s.update(key: 'b', position: const Duration(seconds: 12), duration: total), isFalse);
    expect(s.update(key: 'b', position: const Duration(seconds: 1), duration: total), isFalse, reason: 'a seek back from 60 % is not a loop');
    expect(s.update(key: 'b', position: const Duration(seconds: 19), duration: total), isTrue);
    // Swiped away at 85 % and back: the player starts over from zero — that
    // is a restart, not a loop.
    final VideoCompletionTracker u = VideoCompletionTracker();
    expect(u.update(key: 'c', position: const Duration(seconds: 17), duration: total), isFalse);
    u.markResumed();
    expect(u.update(key: 'c', position: Duration.zero, duration: total), isFalse);
    expect(u.update(key: 'c', position: const Duration(seconds: 18), duration: total), isTrue, reason: 'still counts once it really gets there');
    u.markResumed();
    expect(u.update(key: 'c', position: const Duration(seconds: 19), duration: total), isFalse, reason: 'and never twice');
  });

  test('a new item starts fresh; an unknown duration teaches nothing', () {
    final VideoCompletionTracker t = VideoCompletionTracker();
    expect(t.update(key: 'a', position: const Duration(seconds: 19), duration: total), isTrue);
    expect(t.update(key: 'b', position: const Duration(seconds: 19), duration: total), isTrue);
    expect(t.update(key: 'c', position: const Duration(seconds: 19), duration: Duration.zero), isFalse);
    expect(t.update(key: 'a', position: const Duration(seconds: 19), duration: total), isTrue, reason: 'back to a: the tracker remembers one item at a time');
  });
}
