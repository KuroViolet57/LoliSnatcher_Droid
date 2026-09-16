import 'dart:math';
import 'dart:ui' show Size;

/// The ceiling on what a picture decodes to (r57).
///
/// The viewer already limited a picture's width to about twice the screen's,
/// but nothing bounded its height, so one very tall picture could decode into
/// hundreds of MB.
///
/// r58 removed the video half of this: capping the video surface from outside
/// made media_kit treat every resize as a new surface and rebuild its video
/// output, so anything that needed scaling never played.
class MediaSizeCap {
  const MediaSizeCap._();

  /// A picture never decodes larger than this on its long edge.
  static const int imageLongEdge = 3840;

  /// What a picture decodes to, mirroring `ResizeImage` with
  /// `ResizeImagePolicy.fit` and no upscaling: it fits inside [widthLimit]
  /// (the viewer's existing limit, null when it has none) and inside the
  /// [imageLongEdge] ceiling, which is the part that bounds very tall
  /// pictures.
  static Size imageDecodeSize({
    required Size source,
    required int? widthLimit,
    int longEdge = imageLongEdge,
  }) {
    if (source.width <= 0 || source.height <= 0) return source;
    final double maxWidth = min(
      (widthLimit != null && widthLimit > 0) ? widthLimit.toDouble() : double.infinity,
      longEdge.toDouble(),
    );
    final double scale = min(maxWidth / source.width, longEdge / source.height);
    if (scale >= 1) return source;
    return Size((source.width * scale).roundToDouble(), (source.height * scale).roundToDouble());
  }
}
