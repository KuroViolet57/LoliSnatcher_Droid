import 'dart:math';
import 'dart:ui' show Size;

/// Ceilings for what the app actually renders and decodes.
///
/// media_kit gives the Android video surface the video's native size, so an 8K
/// post (4320x7680) made Skia draws take 600-925 ms and the warm players held
/// about 2.1 GB of graphics memory. Our own copy of media_kit_video asks the
/// app for the size before it sets it (r59, `third_party/media_kit_video`);
/// the earlier attempt to resize it afterwards broke playback (HANDOVER §4.27).
///
/// Pictures have their own ceiling: the viewer limited only their width, so a
/// very tall picture could still decode into hundreds of MB.
class MediaSizeCap {
  const MediaSizeCap._();

  /// A picture never decodes larger than this on its long edge.
  static const int imageLongEdge = 3840;

  /// The size to give a video's surface for a screen of [screen].
  ///
  /// The screen is taken in its best orientation for the video (a landscape
  /// video may be watched fullscreen sideways), so a 1080p video is left
  /// alone while an 8K one is cut down. Keeps the shape, rounds to even
  /// pixels, never upscales, and returns [source] unchanged when it already
  /// fits or when either size is not known yet.
  static Size videoSurface({required Size source, required Size screen}) {
    if (source.width <= 0 || source.height <= 0 || screen.width <= 0 || screen.height <= 0) {
      return source;
    }
    final double screenLong = max(screen.width, screen.height);
    final double screenShort = min(screen.width, screen.height);
    // A taller-than-wide video is shown upright, a wider one can be turned.
    final bool upright = source.height >= source.width;
    final double maxWidth = upright ? screenShort : screenLong;
    final double maxHeight = upright ? screenLong : screenShort;

    final double scale = min(maxWidth / source.width, maxHeight / source.height);
    if (scale >= 1) return source;

    return Size(_even(source.width * scale), _even(source.height * scale));
  }

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

  /// Even pixels: video surfaces and their buffers prefer them.
  static double _even(double value) {
    final int rounded = value.round();
    return (rounded.isEven ? rounded : rounded - 1).toDouble();
  }
}
