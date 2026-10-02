# libmpv Android (arm64)

The experimental media_kit gallery player loads native `libmpv.so` from this
jar. **mpv must stay on the 0.36-class ABI.** media-kit issue #1091: Android
`vo=gpu` flickers on mpv 0.37 and newer.

`default-arm64-v8a.jar` is [libmpv-android-video-build v1.1.11](https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.11)
**default** flavor (not encoders-gpl). SHA-256:

```
2A906875AF68BE8C98C4A83C236BC24053F46E0ACCF62B115993EF1D740E98CC
```

`third_party/media_kit_libs_android_video` copies that jar into the plugin
instead of downloading v1.1.7 (all ABIs) from the published package.

To use a **self-built** jar (extra FFmpeg demuxers/decoders, still mpv &lt; 0.37):

1. Fork `media-kit/libmpv-android-video-build`, keep the mpv pin, change
   FFmpeg `configure`, run the Android job.
2. Replace `default-arm64-v8a.jar` here. Update the SHA-256 in
   `third_party/media_kit_libs_android_video/android/build.gradle`.
3. Do not bump mpv to 0.37+ until `media_kit_video`'s Android `vo=gpu` is
   rewritten.
