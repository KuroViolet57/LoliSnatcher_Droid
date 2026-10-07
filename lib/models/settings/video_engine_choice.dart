/// Which decoder the viewer uses on Android.
///
/// [off] keeps the older switches: media_kit, then better_player, then Chewie.
/// The other values draw the same buttons and only swap the decoder.
enum VideoEngineChoice {
  off,
  media3,
  mpvlibVulkan,
  mpvlibOpengl,
  ;

  bool get isMpvlib => this == VideoEngineChoice.mpvlibVulkan || this == VideoEngineChoice.mpvlibOpengl;

  bool get usesVulkan => this == VideoEngineChoice.mpvlibVulkan;
}

VideoEngineChoice videoEngineChoiceFromString(String? raw) {
  return switch (raw) {
    'media3' => VideoEngineChoice.media3,
    'mpvlibVulkan' => VideoEngineChoice.mpvlibVulkan,
    'mpvlibOpengl' => VideoEngineChoice.mpvlibOpengl,
    _ => VideoEngineChoice.off,
  };
}

/// Text written to the native variant file. Media3 does not load mpvlib.
String mpvlibVariantFileText(VideoEngineChoice choice) {
  return switch (choice) {
    VideoEngineChoice.mpvlibVulkan => 'vulkan',
    VideoEngineChoice.mpvlibOpengl => 'opengl',
    VideoEngineChoice.media3 || VideoEngineChoice.off => 'off',
  };
}

/// Widget family for one video page.
enum ViewerVideoEngine {
  chewie,
  mediaKit,
  betterPlayer,
  media3,
  mpvlib,
}

/// Android-only engines. Anywhere else stays on Chewie, which is the
/// desktop player. A Media3 or mpvlib choice wins over the older switches
/// so the A/B is the thing that actually opens.
ViewerVideoEngine viewerVideoEngine({
  required bool isAndroid,
  required VideoEngineChoice choice,
  required bool useMediaKitPlayer,
  required bool useBetterPlayer,
}) {
  if (!isAndroid) return ViewerVideoEngine.chewie;
  return switch (choice) {
    VideoEngineChoice.media3 => ViewerVideoEngine.media3,
    VideoEngineChoice.mpvlibVulkan || VideoEngineChoice.mpvlibOpengl => ViewerVideoEngine.mpvlib,
    VideoEngineChoice.off when useMediaKitPlayer => ViewerVideoEngine.mediaKit,
    VideoEngineChoice.off when useBetterPlayer => ViewerVideoEngine.betterPlayer,
    VideoEngineChoice.off => ViewerVideoEngine.chewie,
  };
}
