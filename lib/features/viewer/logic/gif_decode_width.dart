/// Decode width for the fast GIF viewer, in physical pixels.
///
/// Null means the full file. That stays behind Don't scale images and a
/// post marked no-scale. A zoom uses twice the screen, the same cap a still
/// image uses, and never the full file while scaling is still on.
int? gifDecodeWidth({
  required bool disableImageScaling,
  required bool noScale,
  required bool zoomed,
  required double screenWidthCss,
  required double devicePixelRatio,
  double? fileWidth,
}) {
  if (disableImageScaling || noScale) return null;
  final double physical = screenWidthCss * devicePixelRatio;
  final double scaled = zoomed ? physical * 2 : physical;
  int target = scaled.round();
  if (fileWidth != null && fileWidth > 0 && fileWidth < target) {
    target = fileWidth.round();
  }
  return target < 64 ? 64 : target;
}
