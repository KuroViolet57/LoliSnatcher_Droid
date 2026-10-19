# Our own media_kit engine (libmpv 0.41) — design

Date 2026-10-12. Research: `docs/research/media-kit-engine.md`. Token 153 (side-by-side APK).

## Why, and principles

The pooled media_kit player ("Use media_kit engine", N warm players) runs libmpv v1.1.11
(mpv git of 2023-10, FFmpeg 6.0, no libplacebo, no Vulkan). The reason we stayed there,
media-kit#1091, was fixed upstream in media_kit 1.2.1 (`video-params`), which we already run.
Kazumi runs mpv 0.41 on Android through the same media_kit code with a few option changes.

Principles: one engine change at a time; the old engine stays in the APK and selectable;
defaults keep today's behaviour; every new option has an info button; our changes to
third-party code are small, marked `LoliSnatcher patch` and listed in a LOLISNATCHER_PATCH.md.

## What the user sees

Settings → Video → (Use media_kit engine on) → **"media_kit libmpv build"** dropdown, right
under the pool size, with an (i) button:

- **Classic (mpv 2023, FFmpeg 6.0)** — default, what every build up to 151 used.
- **New (mpv 0.41, FFmpeg 7.1, libplacebo)** — our own build. Enables `vo=gpu-next` (Vulkan with
  OpenGL fallback). Same pool, same controls.

Subtitle: "Restart the app after changing it. Loaded now: <build>." The (i) window explains both
builds, what gpu-next needs, that HWDEC "vulkan" decodes in software on phones whose GPU has no
Vulkan video decoding (the Thor's Adreno 740 has none, measured), and the measured times once known.

Log lines (Settings → Debug log, and the trace):
- once per start: `media_kit engine: mpv041 (libmpvls.so) · mpv v0.41.0-… · FFmpeg …`
- per video when it is left: `video: decoder <hwdec-current> · output <current-vo> · gpu <current-gpu-context>`
  (gpu context only on the new build; classic has no such property → "?")
- per viewed video: `video: first frame after N ms (new player|reused|re-pointed)` and trace event
  `video.firstframe`.

## Platform limits (sources in the research file)

- Two libmpv builds in one APK need different file names; the new one is built as
  `libmpvls.so` (SONAME too) so the Android linker never confuses them.
- One build per process: media_kit resolves the library once; switching needs a restart.
- media_kit's `AndroidHelper` opens `libmpv.so` by name for `mpv_lavc_set_java_vm` → patched to
  open the chosen library, or the new build would get no JavaVM and no MediaCodec.
- `--cache-dir` was removed in mpv 0.39; `--demuxer-cache-dir` exists in both builds.
- Thor: no `VK_KHR_video_*` → `hwdec=vulkan` is software decoding with either build.

## Data

New setting `mediaKitLibmpv` (`stringFromList`, options `classic`/`mpv041`, default `classic`) in
`schema.dart`, field + storage get/set like `videoEngineChoice`. It lives in settings.json, so the
settings backup already carries it; unknown values read as `classic`. Not device-specific (same
as `videoEngineChoice`).

## Logic and app

- `lib/models/settings/mpv_build.dart`: `MpvBuild { classic, mpv041 }` with setting string,
  library file name, label, `fromSetting()`.
- `lib/features/video/logic/media_kit_engine.dart`: `MediaKitEngine.ensureInitialized(setting)`
  — the only caller of `MediaKit.ensureInitialized`; first call locks the build for the process;
  if the new library cannot be opened it logs and falls back to classic; later calls never
  re-resolve. `loaded`, `restartNeeded(setting)`.
- Pool (`player_pool.dart`) and `MediaKitVideoPlayer.registerWith` call it.
- `MediaKitEngineOptions.nativeProperties`: `demuxer-cache-dir`.
- third_party/media_kit (new, 1.2.6 copy): AndroidHelper patch; upstream #1446 leak fixes in
  `real.dart` (`_getPropertyString`/`_setProperty`/`_command` free their memory on every path).
- third_party/media_kit_video: `androidGpuOptions(vo)` — `gpu-next` → `gpu-api=vulkan,opengl`
  (no forced GL context, Predidit e3732e30); anything else keeps `opengl-es=yes`,
  `gpu-context=android` exactly as today. Surface cap unchanged.
- third_party/media_kit_libs_android_video: copies both jars, each with its SHA-256 check.
- third_party/libmpv-android: `default-arm64-v8a.jar` (classic, unchanged),
  `ls-arm64-v8a.jar` (new), `build/` recipe (Docker in WSL, Predidit dd2bfba + our rename).

## What is not changed

Pool size, planner, rebind/reuse, start delay, surface cap, controls, frame grabs, Chewie /
better_player / Media3 / mpvlib paths, the helper library (classic jar's), the user's vo/hwdec.

## Tests

PC: MpvBuild parsing; MediaKitEngine lock-once + fallback (injected opener); options use
`demuxer-cache-dir`; AndroidHelper library name; androidGpuOptions; gradle copies both jars with
hashes; schema key/default; first-frame clock. Device (Thor, 153 side-by-side): classic and new,
mp4 + webm in the pool, a gif post (picture viewer, regression), seek/loop/mute, vo gpu and
gpu-next; time to first frame, dropped frames, memory (Record a trace + dumpsys meminfo).

## Assumption register

| ID | Assumption | Verify | Status |
|---|---|---|---|
| A1 | #1107 (in 1.2.6) stops the ≥0.37 flicker with our vendored video controller | Thor, vo=gpu, watch + screenshots | guessed → device |
| A2 | AndroidHelper patch gives the new build MediaCodec | log `hwdec-current` = mediacodec with auto-safe | guessed → device |
| A3 | Classic still works with the patched media_kit | Thor, classic, same videos | guessed → device |
| A4 | gpu-next renders into the Flutter surface via Vulkan | log `current-gpu-context` | guessed → device |
| A5 | Our build equals Predidit's v1.2.7 except the name | size 21,727,800 vs 21,727,928; 15,525 identical exports | verified (PC) |
| A6 | The old helper .so works with the new libmpv | Thor playback with new build | guessed → device |
| A7 | APK grows ~9 MB | aapt/size of the 153 APK | to measure |

## Coverage of the brief

Research (done) · spec/plan (this) · own libmpv (built) · own media_kit fork (this round) ·
surface cap carried · pool unchanged · old engine selectable · info button · settings backup ·
one APK with changes.txt. Deferred: Vulkan *decoding* (no device support), FFmpeg 9 / mpv git
master (one change at a time), the 3 extra features (user picks).
