/// How far past the screen the feed grid keeps thumbnails built.
///
/// Resting is the value the grid already used. A fling or a scroll-button
/// jump opens a wider window for [hold], and another event resets that hold.
/// Low performance mode never opens it and never uses the wide value.
///
/// Ramped (the doujin List view, 2026-10-10), the window opens in
/// [rampSteps] steps over [ramp] instead of at once: a list row is tall and
/// costly, and opening at once built 13 rows in one 28 ms frame on the Thor.
/// Each step is about one row a side.
class FeedCacheWindow {
  FeedCacheWindow({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _until;
  DateTime? _openedAt;

  static const Duration hold = Duration(seconds: 3);
  static const int restingPixels = 300;
  static const int prefetchPixels = 900;
  static const Duration ramp = Duration(milliseconds: 360);
  static const int rampSteps = 6;

  bool get isOpen => isOpenAt(_clock());

  bool isOpenAt(DateTime now) {
    final DateTime? until = _until;
    return until != null && now.isBefore(until);
  }

  /// True only when this event opens a window that was closed.
  bool noteActivity(DateTime now, {required bool shitDevice}) {
    if (shitDevice) return false;
    final bool wasOpen = isOpenAt(now);
    _until = now.add(hold);
    if (!wasOpen) _openedAt = now;
    return !wasOpen;
  }

  /// How many ramp steps are open at [now] (1 right after opening).
  int rampStepAt(DateTime now) {
    final DateTime? opened = _openedAt;
    if (opened == null) return rampSteps;
    final int ms = now.difference(opened).inMilliseconds;
    final int step = ms * rampSteps ~/ ramp.inMilliseconds + 1;
    return step > rampSteps ? rampSteps : step;
  }

  /// True once a ramped window is fully open (or nothing is ramping).
  bool rampDone(DateTime now) => rampStepAt(now) >= rampSteps;

  Duration remainingAt(DateTime now) {
    final DateTime? until = _until;
    if (until == null || !now.isBefore(until)) return Duration.zero;
    return until.difference(now);
  }

  double extent({required double devicePixelRatio, bool shitDevice = false, bool ramped = false}) {
    if (shitDevice || !isOpen) return restingPixels * devicePixelRatio;
    if (!ramped) return prefetchPixels * devicePixelRatio;
    final int step = rampStepAt(_clock());
    return (restingPixels + (prefetchPixels - restingPixels) * step / rampSteps) * devicePixelRatio;
  }
}
