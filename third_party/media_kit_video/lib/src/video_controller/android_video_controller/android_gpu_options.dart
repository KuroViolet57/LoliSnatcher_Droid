/// LoliSnatcher patch (token 153): the GPU options mpv gets on Android.
///
/// `vo=gpu` (and anything else) keeps what media_kit_video 2.0.1 always set:
/// OpenGL ES through the Android context. `vo=gpu-next` needs libplacebo,
/// which only our mpv 0.41 build (libmpvls.so) has; it is left free to pick
/// Vulkan and falls back to OpenGL on devices without a usable Vulkan, as
/// Kazumi's fork does (Predidit/media-kit e3732e30).
Map<String, String> androidGpuOptions(String? vo) {
  if (vo == 'gpu-next') {
    return const {'gpu-api': 'vulkan,opengl'};
  }
  return const {'opengl-es': 'yes', 'gpu-context': 'android'};
}
