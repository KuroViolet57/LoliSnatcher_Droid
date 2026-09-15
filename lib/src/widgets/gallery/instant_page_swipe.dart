import 'package:flutter/foundation.dart';

/// Instant page changes for the viewer (r53): the page never follows the
/// finger. A swipe past [distance], or a flick past [flick], jumps one page at
/// once, during the drag; the rest of that gesture does nothing. The viewer
/// used to slide pages (the page shifted by half the drag, a spring settle,
/// 100 ms cross-fades), which the thumbnail cover of r52 made visible.
class InstantPageSwipe {
  InstantPageSwipe({required this.onStep, this.isBlocked});

  /// +1 for the next page, -1 for the previous one.
  final ValueChanged<int> onStep;

  /// True while something else owns the drag (a zoomed image pans).
  final bool Function()? isBlocked;

  /// How far a swipe travels before it is one (logical pixels).
  static const double distance = 48;

  /// How fast a short swipe must end to count (logical pixels a second).
  static const double flick = 700;

  double _offset = 0;
  bool _done = true;

  /// The page a drag of [offset] ending at [velocity] asks for: swiping left
  /// (or up) is the next page; a flick back the other way cancels.
  static int stepFor({required double offset, required double velocity}) {
    if (offset <= -distance) return 1;
    if (offset >= distance) return -1;
    if (velocity <= -flick && offset <= 0) return 1;
    if (velocity >= flick && offset >= 0) return -1;
    return 0;
  }

  bool get _blocked => isBlocked?.call() ?? false;

  void start() {
    _offset = 0;
    _done = _blocked;
  }

  void update(double delta) {
    if (_done) return;
    if (_blocked) {
      _done = true;
      return;
    }
    _offset += delta;
    final int step = stepFor(offset: _offset, velocity: 0);
    if (step != 0) {
      _done = true;
      onStep(step);
    }
  }

  void end(double velocity) {
    if (_done) return;
    _done = true;
    if (_blocked) return;
    final int step = stepFor(offset: _offset, velocity: velocity);
    if (step != 0) onStep(step);
  }
}
