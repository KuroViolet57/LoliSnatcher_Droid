/// Says, once per item, that a video was watched through (r35).
///
/// Players report progress in their own ways: some reach the last tenth,
/// some loop past the end before ever reporting it. Both count: nine tenths
/// reached, or a wrap from the last fifth back to the start. A player that
/// starts over because the page was swiped away and back is told so
/// ([markResumed]) and does not count as a loop.
class VideoCompletionTracker {
  VideoCompletionTracker({this.threshold = 0.9, this.wrapFrom = 0.8});

  final double threshold;

  /// A jump from at least this far back to the start reads as a loop.
  final double wrapFrom;

  String? _key;
  bool _fired = false;
  double _last = 0;

  /// The player starts this item over from the beginning (a swipe back, a
  /// re-created controller): the next low position is not a loop.
  void markResumed() => _last = 0;

  /// True exactly once per [key] when the video was watched through.
  bool update({required String key, required Duration position, required Duration duration}) {
    if (key != _key) {
      _key = key;
      _fired = false;
      _last = 0;
    }
    if (duration.inMilliseconds <= 0) return false;
    final double fraction = (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1).toDouble();
    if (_fired) {
      _last = fraction;
      return false;
    }
    final bool reached = fraction >= threshold;
    final bool wrapped = _last >= wrapFrom && fraction < 0.1;
    _last = fraction;
    if (reached || wrapped) {
      _fired = true;
      return true;
    }
    return false;
  }
}
