import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Token 153: how long a viewed video took from its player being asked for to
/// its first position past zero (mpv presenting frames). One reading per
/// video; it is the "time to first frame" used to compare the libmpv builds.
class FirstFrameClock {
  bool _done = false;

  /// A video that was not on screen when its player was asked for (a
  /// neighbour warmed up early) is not timed: its wait was not the user's.
  void skip() => _done = true;

  Duration? _stale;

  /// A reused pool player was paused at [parked] and is sought to [target]
  /// (the start, or a saved position); until that seek lands it still reports
  /// [parked], which must not count as its first frame (review 2026-10-14,
  /// finding 4 and recheck issue A). When [parked] is the start or equals
  /// [target] there is nothing to tell apart and the clock runs as before.
  void afterRewind({required Duration parked, required Duration target}) {
    _stale = parked > Duration.zero && parked != target ? parked : null;
  }

  /// [elapsedMs] since the player was asked for. Returns it once, at the first
  /// position past zero; null before and after.
  int? onPosition(Duration position, int elapsedMs) {
    if (_done) return null;
    final Duration? stale = _stale;
    if (stale != null) {
      if (position == stale) return null;
      _stale = null;
    }
    if (position <= Duration.zero) return null;
    _done = true;
    return elapsedMs;
  }

  /// "video: playing after 410 ms (reused, mpv041)".
  static String line(int ms, String how, MpvBuild? build) =>
      'video: playing after $ms ms ($how, ${build?.setting ?? '?'})';
}
