# Our copy of media_kit_video 2.0.1 (r59)

A verbatim copy of `media_kit_video` 2.0.1 from pub.dev, with one change of our
own. `pubspec.yaml` points at it:

```yaml
dependency_overrides:
  media_kit_video:
    path: third_party/media_kit_video
```

## The change

media_kit gives the Android video surface the video's **native** size, so an 8K
post (4320x7680) made Skia draws take 600-925 ms and the warm players held
about 2.1 GB of graphics memory (HANDOVER §4.23, §4.26). r57 tried to resize
that surface from app code afterwards and broke playback: the plugin handed out
a new surface and rebuilt its whole video output every time (§4.27).

So the size is capped **where the plugin already decides it**, once per video:

- `lib/src/video_controller/platform_video_controller.dart`
  adds `static Size Function(int width, int height)? androidSurfaceSizeCap`.
- `lib/src/video_controller/android_video_controller/real.dart`
  asks that hook for the size in its `videoParams` listener, before
  `VideoOutputManager.SetSurfaceSize` and before it publishes `rect`.

Both edits are marked with `LoliSnatcher patch` in the source. The app installs
the hook in `lib/src/widgets/video/video_surface_cap.dart` (behind the Modular
UI switch `viewer.videoCapToScreen`); with no hook installed, this copy behaves
exactly like the published package.

## Second change (token 153): GPU options for vo=gpu-next

The app can now load our own mpv 0.41 build (libmpvls.so, with libplacebo). Its `vo=gpu-next`
must not be forced onto the OpenGL context, so the two options media_kit_video set unconditionally
(`opengl-es=yes`, `gpu-context=android`) now come from
`lib/src/video_controller/android_video_controller/android_gpu_options.dart`:

- `vo=gpu` and anything else: exactly the old two options.
- `vo=gpu-next`: `gpu-api=vulkan,opengl` (Vulkan, OpenGL when Vulkan is not usable), as in
  Kazumi's fork (Predidit/media-kit e3732e30).

To undo: put the two options back in `real.dart` (search `LoliSnatcher patch (token 153)`) and
delete that file.

## Third change (token 154): SurfaceTexture fallback

Taken as is from Predidit/media-kit 87cdfef7 (the fork Kazumi ships; Kazumi has used it as its
default since 2026-06-18, with Impeller off as we do). On Android 10+ Flutter's
`createSurfaceProducer()` always hands out an ImageReader producer; with
`VideoControllerConfiguration.enableAndroidSurfaceProducer: false` the plugin instead creates a
classic `SurfaceTexture` (`createSurfaceTexture()`), sizes it with `setDefaultBufferSize` and
frees the old `wid` 5 s later, as the SurfaceProducer path does. The default (`true`) is the old
path, unchanged. The app sets it from Settings -> Video -> "Draw videos into a SurfaceTexture".

Files: `MediaKitVideoPlugin.java` (reads `enableSurfaceProducer`), `VideoOutputManager.java`,
`VideoOutput.java`, `android_video_controller/real.dart` (passes the flag),
`platform_video_controller.dart` (the field). Search `LoliSnatcher patch (token 154)`.
To undo: revert those five files to 2.0.1 (the field can stay; unknown arguments are ignored).

Our own fix on top (found on the Thor with the first 154 build): a SurfaceTexture keeps one
surface, so when a pooled player is re-pointed at a video of another size the plugin hands back
the same `wid`, `widListener` never runs, and mpv keeps the previous video's
`android-surface-size` (the next video was drawn squashed). `real.dart` now re-runs
`widListener()` after a resize of an already attached SurfaceTexture, the same vo re-init a new
`wid` triggers on the SurfaceProducer path. Predidit's fork does not have this (Kazumi opens one
video per player). Since the review of 2026-10-14 the condition lives in
`android_video_controller/surface_texture_resize.dart` and skips a player disposed while the resize
was in flight (a dropped pool slot); a dispose landing while the re-init waits for the lock is
swallowed instead of surfacing "[Player] has been disposed" as an unhandled error.

## To undo

1. Delete the four lines under `dependency_overrides` in `pubspec.yaml`.
2. Delete this folder.
3. `flutter pub get`.

The app keeps working: `VideoSurfaceCap.install()` then writes to a hook that no
longer exists, so delete the `PlatformVideoController.androidSurfaceSizeCap`
line in `video_surface_cap.dart` too (or the whole file and its use in
`media_kit_player_view.dart`).

## To move to a newer media_kit_video

Copy the new version over this folder and re-apply the two edits above (search
for `LoliSnatcher patch`), or drop the folder entirely if the package has gained
a real API for the surface size.
