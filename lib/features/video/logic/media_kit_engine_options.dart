import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';

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
      hwdec: hwdec(settings),
      androidAttachSurfaceAfterVideoParameters: settings.altVideoPlayerVO.isGpu ? true : null,
      enableAndroidSurfaceProducer: !settings.mediaKitSurfaceTexture,
    );
  }

  /// Token 154, "Decoder chain": the phone's decoder straight into the
  /// picture, and where that cannot start (output gpu-next on Vulkan: mpv's
  /// direct mediacodec needs OpenGL) the copying one, before software. mpv
  /// goes down a list until one decoder starts (options.rst, --hwdec).
  static const String hwdecChain = 'mediacodec,mediacodec-copy';

  /// What mpv is asked for: the chain while it is on and hardware decoding is
  /// allowed, else the Settings -> Video HWDEC choice, as before.
  static String hwdec(SettingsHandler settings) =>
      settings.mediaKitHwdecChain && settings.altVideoPlayerHwAccel ? hwdecChain : settings.altVideoPlayerHWDEC.toJson();

  /// Token 154: "texture" when media_kit_video draws into a SurfaceTexture,
  /// "producer" for Flutter's SurfaceProducer (the default).
  static String surfaceLabel(SettingsHandler settings) => settings.mediaKitSurfaceTexture ? 'texture' : 'producer';

  /// The surface a slot built with [signature] draws into (for its log line).
  static String surfaceOfSignature(String signature) => signature.endsWith('|texture') ? 'texture' : 'producer';

  /// vo | hwdec | hardware acceleration (+ the token 154 switches when on),
  /// as a pool slot was built with. With both switches off it is what 153
  /// used, so slots built before an update keep matching.
  static String signature(SettingsHandler settings) {
    final String base = '${settings.altVideoPlayerVO.toJson()}|${settings.altVideoPlayerHWDEC.toJson()}|${settings.altVideoPlayerHwAccel}';
    return '$base${settings.mediaKitHwdecChain ? '|chain' : ''}${settings.mediaKitSurfaceTexture ? '|texture' : ''}';
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
      // mpv 0.39 removed the old `cache-dir` alias; both builds know this one.
      out['demuxer-cache-dir'] = cacheDir;
    }
    return out;
  }
}
