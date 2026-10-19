# libmpv Android (arm64)

The media_kit gallery player loads one of two libmpv builds from here. The app picks one per
process: Settings -> Video -> media_kit libmpv build (restart after changing it).
`third_party/media_kit_libs_android_video` copies both jars into the APK and checks their SHA-256.

## Classic: `default-arm64-v8a.jar`

[libmpv-android-video-build v1.1.11](https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.11)
**default** flavor: `libmpv.so` (mpv git `78d43740` of 2023-10-14, between 0.36 and 0.37;
FFmpeg 6.0; no libplacebo, no Vulkan) and `libmediakitandroidhelper.so` (the only helper in the APK,
used by both builds). SHA-256:

```
2A906875AF68BE8C98C4A83C236BC24053F46E0ACCF62B115993EF1D740E98CC
```

## Our own: `ls-arm64-v8a.jar` (token 153)

`lib/arm64-v8a/libmpvls.so` = **mpv v0.41.0-110-g32a164cc**, FFmpeg 7.1.3, libplacebo d4624cbf
(Vulkan + shaderc + lcms2), mpv built with Vulkan, NDK r27c, API 26, 16 KB pages. SHA-256:

```
1274F9F4CD9EA8F777D0E3FB761EB986A79648090715C1A25206E1B679339AA8
```

It is [Predidit/libmpv-android-video-build](https://github.com/Predidit/libmpv-android-video-build)
at `dd2bfba8` (= their v1.2.7, the build Kazumi ships) with our changes:

1. mpv's library is named `mpvls` (file and SONAME `libmpvls.so`), so it can sit next to the
   classic `libmpv.so` without the Android linker mixing them up.
2. arm64-v8a only; the helper is not rebuilt (the classic jar's is used).

Checked on 2026-10-12: same 15,525 exported symbols as Predidit's v1.2.7 `libmpv.so`; size
21,727,800 vs 21,727,928 bytes (the name).

The old "stay below mpv 0.37" rule is gone: media-kit#1091 (Android `vo=gpu` flicker on 0.37+) was
fixed in media_kit 1.2.1 by observing `video-params` (PR #1107), and we run 1.2.6. See
`docs/research/media-kit-engine.md`.

### Rebuild it

On this PC (WSL Ubuntu with Docker; nothing installed on Windows or in WSL itself):

```
wsl -d Ubuntu -- bash /mnt/c/<repo>/third_party/libmpv-android/build/build_ls_libmpv.sh
```

About 4 minutes with 12 CPUs after the first run (the NDK and sources are cached in `~/lsbuild`).
It writes `~/lsbuild/out/ls-arm64-v8a.jar` and prints its SHA-256. Copy it here and update the hash
in `third_party/media_kit_libs_android_video/android/build.gradle` and
`test/media_kit_engine_test.dart`. To change FFmpeg decoders, edit
`~/lsbuild/src/buildscripts/flavors/default.sh` via a sed in `build/inner.sh` (so the change is
recorded here), then rebuild.
