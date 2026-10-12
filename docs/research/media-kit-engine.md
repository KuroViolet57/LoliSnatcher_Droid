# media_kit / libmpv engine for the pooled video player (research, 2026-10-12)

Checked live on 2026-10-12 through the GitHub API, pub.dev's API, the repos' own files, and the
Thor (adb -s 63c3fa7f). Reuse this file before searching again.

## What we ship today (verified in this repo)

| Piece | What | Source |
|---|---|---|
| `media_kit` | 1.2.6 from pub.dev (latest published, 2025-12-13), not vendored | `pubspec.lock` |
| `third_party/media_kit_video` | 2.0.1 (latest published, 2025-12-02) + the r59 surface cap (`LoliSnatcher patch`) | `LOLISNATCHER_PATCH.md` |
| `third_party/media_kit_libs_android_video` | 1.3.8, copies our jar instead of downloading v1.1.7 | its `android/build.gradle` |
| `third_party/libmpv-android/default-arm64-v8a.jar` | libmpv-android-video-build **v1.1.11** default flavor: `libmpv.so` 12.4 MB + `libmediakitandroidhelper.so` | SHA-256 `2A906875…E98CC` |

v1.1.11's own `depinfo.sh` pins **mpv `78d43740`** (2023-10-14, 549 commits after v0.36.0, 334 before
v0.37.0), **FFmpeg 6.0**, NDK 25. `mpv.sh` builds with `-Dvulkan=disabled -Dlibplacebo=disabled`;
the default flavor configures FFmpeg with `--disable-vulkan`, MediaCodec + JNI on, and **no gif,
webp or png decoders** (so mpv cannot play a .gif at all; the app shows gifs with the picture viewer,
`MediaType.animation`). Upstream v1.1.7 → v1.1.11 (2025-10 → 2026-01) only changed build plumbing
(16 KB pages, encoders-gpl), never mpv.

## Is media-kit #1091 (Android `vo=gpu` flicker on mpv ≥ 0.37) still a blocker? No.

- [media-kit#1091](https://github.com/media-kit/media-kit/issues/1091) is **closed** (2025-10-04) by
  [PR #1107](https://github.com/media-kit/media-kit/pull/1107) (Predidit): media_kit observed
  `video-out-params`, whose values change while mpv ≥ 0.37 renders, and every change re-sized the
  Android surface → flicker. The fix observes `video-params` instead (2 lines in
  `media_kit/lib/src/player/native/player/real.dart`). It shipped in media_kit 1.2.1; **we run 1.2.6,
  so we already have it.** Our README's "stay below 0.37" note is stale.
- Proof it works in production: Kazumi ([Predidit/Kazumi](https://github.com/Predidit/Kazumi),
  35.7k stars, pushed 2026-10-12) plays video on Android through
  [Predidit/media-kit](https://github.com/Predidit/media-kit) with
  [Predidit/libmpv-android-video-build v1.2.7](https://github.com/Predidit/libmpv-android-video-build/releases/tag/v1.2.7)
  = **mpv `32a164cc`** (2026-01-23, v0.41.0 + 110), **FFmpeg 7.1.3**, **libplacebo** (Vulkan + shaderc +
  lcms2), mpv `-Dvulkan=enabled`, NDK r27c, API 26. arm64 jar: `libmpv.so` 21.7 MB +
  helper, SHA-256 `13e882d9…fa2d1` (matches Predidit's gradle). FFmpeg still `--disable-vulkan`.

## Upstream now

- pub.dev: media_kit 1.2.6, media_kit_video 2.0.1, media_kit_libs_android_video 1.3.8 are still the
  newest releases. Upstream `main` has unreleased fixes after them: memory leaks on error paths
  ([#1446](https://github.com/media-kit/media-kit/pull/1446), 2026-08-30), SIGABRT on hot restart from
  a wakeup callback left set ([c35be8bd](https://github.com/media-kit/media-kit/commit/c35be8bd)),
  `(un)observeEvent`, SPM and a workspace move. No Android video change after 2.0.1.
- mpv: v0.41.0 (2025-12-21). Interface changes 0.36 → 0.41 that touch us
  ([interface-changes.rst](https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/interface-changes.rst)):
  `--cache-dir` renamed `--demuxer-cache-dir` in 0.37 and the alias **removed in 0.39** (our pool sets
  `cache-dir`; the old pin already accepts `demuxer-cache-dir`, checked in its `demux/cache.c`);
  `--hwdec=auto` behaves like `auto-safe` since 0.40; `vd-lavc-software-fallback` →
  `hwdec-software-fallback` (0.40); `mediacodec_embed` no longer the Android default vo (0.41);
  `current-gpu-context` property (0.38) — useful for the log. `--opengl-es` and
  `--gpu-context=android` still exist in 0.41 (`DOCS/man/options.rst`).

## Prior art and forks

- **Predidit/media-kit** (Kazumi's fork): the Android video controller is 2.0.1 plus
  `enableAndroidSurfaceProducer` (SurfaceTexture fallback, [87cdfef7](https://github.com/Predidit/media-kit/commit/87cdfef7))
  and, for mpv 0.41 ([90ea5598](https://github.com/Predidit/media-kit/commit/90ea5598),
  [e3732e30](https://github.com/Predidit/media-kit/commit/e3732e30)): drops `opengl-es=yes` and
  `gpu-context=android`, sets `gpu-api` = `vulkan,opengl` for `vo=gpu-next` (Vulkan 1.1-only devices
  fall back to GL) and `auto` otherwise. Also `seek(position)` instead of `seek(0)` after a surface
  rebuild ([c2c13936](https://github.com/Predidit/media-kit/commit/c2c13936)). Since 2026-09-21 the
  fork moved to Dart native-asset build hooks (no more libs packages) — too big a jump for us.
- **mpv-android** ([MPVView.kt](https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/MPVView.kt),
  release 2026-09-17, NDK r30, mpv from git): `vo=gpu` (gpu-next is an opt-in setting),
  `gpu-context=android`, `opengl-es=yes`, `hwdec=mediacodec,mediacodec-copy`,
  `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`. No Vulkan rendering.
- **Boorusama** ([pubspec](https://github.com/khoadng/Boorusama/blob/master/pubspec.yaml)): stock
  media_kit 1.2.x / media_kit_video 2.0.1 / libs 1.0.7 (so stock libmpv v1.1.7) plus fvp and
  video_player. Nothing newer than ours.
- Forks of libmpv-android-video-build with mpv 0.41: ister-app v1.2.1 (FFmpeg 9.0.1),
  My-Responsitories 20260930 (FFmpeg 9.0.2), Monster-DP v1.2.0-mpv041 (FFmpeg 8.1.2) — none with
  Kazumi's user base; Predidit's is the one proven at scale.
- Grok's build 145 `mpvlib` engines use [Riteshp2001/mpvlibAndroid](https://github.com/Riteshp2001/mpvlibAndroid)
  1.1.1 prebuilt AARs, loaded by path from extracted assets (`tool/prepare_mpvlib.py`) because a
  second `libmpv.so` clashes with media_kit's. Useful prior art for **coexistence** (load by path,
  restart to switch), not for building mpv.

## The Thor's GPU (primary source: `adb shell cmd gpu vkjson`)

Adreno 740, Vulkan 1.3.128, 113 device extensions, **no `VK_KHR_video_*`** (has
`VK_ANDROID_external_memory_android_hardware_buffer`, `VK_KHR_sampler_ycbcr_conversion`).
So `hwdec=vulkan` (the user's setting) can never be hardware decoding on the Thor, whatever libmpv
we ship; FFmpeg's Vulkan decoder would not help. Vulkan is useful only for rendering (`vo=gpu-next`).
The S24 Ultra (Adreno 750) is unchecked.

## Coexistence of two libmpv builds in one APK

- Both jars hold a self-contained `libmpv.so` (SONAME `libmpv.so`; NEEDED only system libs; the new
  one adds `libmediandk.so`, `libvulkan.so`) and a `libmediakitandroidhelper.so` that does not link
  libmpv.
- media_kit picks the library with `MediaKit.ensureInitialized(libmpv: name)`, **but**
  `AndroidHelper.ensureInitialized()` always opens `'libmpv.so'` to call `mpv_lavc_set_java_vm`
  (media_kit 1.2.6 `lib/src/player/native/utils/android_helper.dart`). A second engine under another
  file name would never get the JavaVM → no MediaCodec. **Needs a media_kit patch** (our fork).
- `MediaKit.ensureInitialized()` re-resolves on every call; the app calls it from two places
  (pool, Chewie bridge). Both must go through one function that locks the choice per process.

## Building libmpv on this PC

- WSL Ubuntu 26.04 is running, 16 cores / 31 GB inside, but `sudo` needs a password and meson,
  cmake, autotools, make and gcc are missing. **Docker works inside WSL** (user in the `docker` group;
  the user's Immich containers run there — leave them alone).
- Cheapest reliable route: run Predidit's CI recipe locally in `docker.io/debian:bookworm-slim`
  (`--rm`, CPU-limited), NDK r27c, arm64 only (`build.sh --arch arm64`). No GitHub fork or Actions run
  needed (that would publish under the user's account). Reproducibility check: Predidit's bundle sets
  fixed timestamps and prints md5s, so an unmodified arm64 build can be compared with their v1.2.7 jar.

## Extra features those projects have that we lack (the user picks)

1. SurfaceTexture fallback for devices where Flutter's SurfaceProducer misbehaves — [Predidit 87cdfef7](https://github.com/Predidit/media-kit/commit/87cdfef7)
2. A hardware-decoder chain with a copy fallback and a codec whitelist (`mediacodec,mediacodec-copy` + `hwdec-codecs`) — [mpv-android MPVView.kt](https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/MPVView.kt)
3. "Safe screenshot" (frame grab that cannot crash the player) for our frame reader — [Predidit a7d4a070](https://github.com/Predidit/media-kit/commit/a7d4a070)
