import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Token 153: how long a viewed video took from its player being asked for to
/// its first position past zero (mpv presenting frames). One reading per
/// video; it is the "time to first frame" used to compare the libmpv builds.
class FirstFrameClock {
  bool _done = false;

  /// A video that was not on screen when its player was asked for (a
  /// neighbour warmed up early) is not timed: its wait was not the user's.
  void skip() => _done = true;

  bool _rewinding = false;

  /// A reused pool player was parked mid-video and is sought back to the
  /// start; position events from before that seek lands must not count as
  /// its first frame (review 2026-10-14, finding 4). Positions from
  /// [rewindWindow] on are ignored until one below it arrives.
  void afterRewind() => _rewinding = true;

  static const Duration rewindWindow = Duration(seconds: 1);

  /// [elapsedMs] since the player was asked for. Returns it once, at the first
  /// position past zero; null before and after.
  int? onPosition(Duration position, int elapsedMs) {
    if (_done) return null;
    if (_rewinding) {
      if (position >= rewindWindow) return null;
      _rewinding = false;
    }
    if (position <= Duration.zero) return null;
    _done = true;
    return elapsedMs;
  }

  /// "video: playing after 410 ms (reused, mpv041)".
  static String line(int ms, String how, MpvBuild? build) =>
      'video: playing after $ms ms ($how, ${build?.setting ?? '?'})';
}
