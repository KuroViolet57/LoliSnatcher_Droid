/// Side and distance for a double-tap on the video controls.
///
/// [newPosition] is null when the tap is a play/pause (centre, or a clip
/// too short to skip) instead of a seek.
class DoubleTapSkip {
  const DoubleTapSkip({
    required this.side,
    required this.skipSeconds,
    required this.newPosition,
  });

  /// -1 left, 0 centre, 1 right.
  final int side;
  final int skipSeconds;
  final Duration? newPosition;
}

/// The skip rule [LoliControls] has always used.
///
/// A clip of 5 seconds or less does not skip. Up to 10 seconds skips 1
/// second, up to 60 seconds skips 5, and anything longer skips 10. The
/// right band starts strictly past the middle plus one sixth of the width.
DoubleTapSkip doubleTapSkip({
  required double screenWidth,
  required double tapX,
  required Duration duration,
  required Duration position,
}) {
  final double middle = screenWidth / 2;
  final double band = screenWidth / 6;
  final int side = tapX > middle + band
      ? 1
      : tapX < middle - band
      ? -1
      : 0;
  final int seconds = duration.inSeconds;
  final int skip = seconds <= 5
      ? 0
      : seconds <= 10
      ? 1
      : seconds <= 60
      ? 5
      : 10;
  if (side == 0 || skip == 0) {
    return DoubleTapSkip(side: side, skipSeconds: skip, newPosition: null);
  }
  final int nextMs = (position.inMilliseconds + skip * 1000 * side).clamp(0, duration.inMilliseconds).toInt();
  return DoubleTapSkip(
    side: side,
    skipSeconds: skip,
    newPosition: Duration(milliseconds: nextMs),
  );
}
