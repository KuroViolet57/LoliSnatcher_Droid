import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/utils/media_size_cap.dart';

/// Keeps a media_kit video's Android surface down to screen size (r57).
///
/// media_kit_video has no API for this on Android: `AndroidVideoController.
/// setSize` throws, and the width/height in its configuration are only read by
/// the desktop controller. Its Android controller sets the surface to the
/// video's native size on every `videoParams` event, through its own platform
/// channel. So the app makes the same call right after, with a capped size,
/// and tells mpv to render at that size (the plugin only refreshes mpv's
/// `android-surface-size` when the surface itself is recreated).
class VideoSurfaceCap {
  const VideoSurfaceCap._();

  /// media_kit_video's own channel — the same one its controller talks to.
  static const MethodChannel channel = MethodChannel('com.alexmercerind/media_kit_video');

  /// The screen in physical pixels. The player pool has no BuildContext, and
  /// an unknown size (zero) means "leave the video alone".
  static Size screenSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return Size.zero;
    return views.first.physicalSize;
  }

  /// Caps the surface of the player owning [handle] for a video of [source].
  ///
  /// Returns the size applied, or null when nothing was done (switched off,
  /// size unknown, or the screen can show the video as it is).
  static Future<Size?> applyTo({
    required int handle,
    required Size source,
    required Size screen,
    required bool enabled,
    Future<void> Function(String key, String value)? setProperty,
  }) async {
    if (!enabled) return null;
    final Size capped = MediaSizeCap.videoSurface(source: source, screen: screen);
    if (capped == source || capped.width <= 0 || capped.height <= 0) return null;

    final int width = capped.width.round();
    final int height = capped.height.round();
    await channel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
      'handle': handle.toString(),
      'width': width.toString(),
      'height': height.toString(),
    });
    // ORDER MATTERS: the surface first, then mpv's idea of its size.
    await setProperty?.call('android-surface-size', '${width}x$height');
    return capped;
  }
}
