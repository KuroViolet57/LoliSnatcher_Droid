/// How far past the screen the feed grid keeps thumbnails built.
///
/// Resting is the value the grid already used. A fling or a scroll-button
/// jump opens a wider window for [hold], and another event resets that hold.
/// Low performance mode never opens it and never uses the wide value.
class FeedCacheWindow {
  FeedCacheWindow({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _until;

  static const Duration hold = Duration(seconds: 3);
  static const int restingPixels = 300;
  static const int prefetchPixels = 900;

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
    return !wasOpen;
  }

  Duration remainingAt(DateTime now) {
    final DateTime? until = _until;
    if (until == null || !now.isBefore(until)) return Duration.zero;
    return until.difference(now);
  }

  double extent({required double devicePixelRatio, bool shitDevice = false}) {
    final int pixels = (!shitDevice && isOpen) ? prefetchPixels : restingPixels;
    return pixels * devicePixelRatio;
  }
}
