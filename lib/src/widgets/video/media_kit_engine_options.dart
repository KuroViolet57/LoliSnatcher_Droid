import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// mpv / media_kit knobs shared by the experimental gallery pool.
///
/// Settings → Video hwdec/vo used to apply only to the Chewie `video_player`
/// plugin path. The pooled media_kit Player ignored them. Keep the property
/// names here so tests can pin the cache/loop contract without constructing
/// a native player.
class MediaKitEngineOptions {
  const MediaKitEngineOptions._();

  static VideoControllerConfiguration videoController(SettingsHandler settings) {
    return VideoControllerConfiguration(
      enableHardwareAcceleration: settings.altVideoPlayerHwAccel,
      vo: settings.altVideoPlayerVO.toJson(),
      hwdec: settings.altVideoPlayerHWDEC.toJson(),
      androidAttachSurfaceAfterVideoParameters: settings.altVideoPlayerVO.isGpu ? true : null,
    );
  }

  /// How long a video has to stay on screen before its player is built (r62).
  ///
  /// Swiping past videos used to build and tear down a player for nearly
  /// every post (42 created, 38 destroyed in 25 s of swiping), and the codec
  /// churn showed up as stutter. Zero keeps the old behaviour.
  static Duration startDelay(SettingsHandler settings) =>
      Duration(milliseconds: settings.videoStartDelayMs.clamp(0, 5000));

  /// libmpv properties applied after the player opens a URL.
  ///
  /// [cacheDir] turns on the on-disk demuxer cache (the in-memory pool is
  /// still the warm-player LRU). Null = RAM cache only.
  static Map<String, String> nativeProperties({String? cacheDir}) {
    final Map<String, String> out = {
      'cache': 'yes',
      'cache-secs': '30',
      'demuxer-readahead-secs': '20',
      'demuxer-max-bytes': '67108864',
      'demuxer-max-back-bytes': '33554432',
      'loop-file': 'inf',
    };
    if (cacheDir != null && cacheDir.isNotEmpty) {
      out['cache-on-disk'] = 'yes';
      out['cache-dir'] = cacheDir;
    }
    return out;
  }
}
