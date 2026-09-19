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
