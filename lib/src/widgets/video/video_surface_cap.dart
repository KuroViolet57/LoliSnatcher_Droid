import 'dart:ui';

import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/utils/media_size_cap.dart';

/// Tells our copy of media_kit_video how big a video's Android surface should
/// be (r59).
///
/// The published package always uses the video's own size, which costs
/// hundreds of MB of buffers and 600-925 ms draws for an 8K post. Our copy
/// (`third_party/media_kit_video`, see its LOLISNATCHER_PATCH.md) asks this
/// hook first, in the one place it sets the size — r57's attempt to resize the
/// surface afterwards made the plugin rebuild its whole video output and broke
/// playback (HANDOVER §4.27).
class VideoSurfaceCap {
  const VideoSurfaceCap._();

  /// The screen in physical pixels. There is no BuildContext where players are
  /// created, and an unknown size (zero) means "leave the video alone".
  static Size screenSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return Size.zero;
    return views.first.physicalSize;
  }

  /// Installs the hook. Called once, before the first player is built; the
  /// Modular UI switch is read per video, so turning it off takes effect on
  /// the next video without a restart.
  static void install({Size? screen}) {
    PlatformVideoController.androidSurfaceSizeCap = (int width, int height) {
      final Size source = Size(width.toDouble(), height.toDouble());
      if (!ModularUi.isOn(ModularUi.videoCapToScreen)) return source;
      return MediaSizeCap.videoSurface(source: source, screen: screen ?? screenSize());
    };
  }
}
