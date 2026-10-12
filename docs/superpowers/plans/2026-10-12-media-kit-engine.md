# Plan: our own media_kit engine, step 1 (token 153)

- **Goal:** ship our own libmpv (mpv 0.41, FFmpeg 7.1, libplacebo) next to the classic one, picked
  in Settings → Video, through our own media_kit fork; classic stays the default.
- **Architecture:** spec `docs/superpowers/specs/2026-10-12-media-kit-engine-design.md`.
- **Tech:** Flutter 3.42 beta via `tool/flutterw.sh`; Docker in WSL for libmpv; Thor for device runs.
- **Branch:** `claude/1.0-media-kit-engine` from a60fc3d3 (151).

## Global constraints

- Setting `mediaKitLibmpv`: `classic` (default) | `mpv041`. Library files `libmpv.so` / `libmpvls.so`.
- Classic jar SHA-256 `2A906875AF68BE8C98C4A83C236BC24053F46E0ACCF62B115993EF1D740E98CC` (unchanged).
- New jar SHA-256 `1274F9F4CD9EA8F777D0E3FB761EB986A79648090715C1A25206E1B679339AA8`.
- `MediaKit.ensureInitialized` is called ONLY from `MediaKitEngine`.
- vo=gpu options stay `opengl-es=yes`, `gpu-context=android`.
- Stay out of lib/ outside video/viewer except the setting plumbing; never commit signing material;
  never raise the Thor's volume.

## Review focus

1. Two call sites resolving different libraries in one process → `media_kit_engine_test` lock-once.
2. New library missing/unloadable → falls back to classic and logs (test with throwing opener).
3. Classic behaviour drift: same options for vo=gpu (`media_kit_engine_test`), same library name.
4. JavaVM handed to the chosen library (`media_kit_engine_test`).
5. Settings: unknown stored value → classic; key in schema (test).
6. Gradle copies both jars, both hash-checked (text test).
7. `cache-dir` gone in 0.41 → `demuxer-cache-dir` (options test).

## Tasks

- [x] T1 tests red: `test/media_kit_engine_test.dart` (MpvBuild, MediaKitEngine, options,
  helper name, gpu options, gradle, schema, first-frame clock).
- [x] T2 third_party/media_kit: vendor 1.2.6, AndroidHelper patch, #1446 leak hunks, LOLISNATCHER_PATCH.md;
  pubspec override.
- [x] T3 media_kit_video: `androidGpuOptions`, patch notes.
- [x] T4 libs package: second jar + hash; libmpv-android README + build recipe.
- [x] T5 app: MpvBuild, setting plumbing, MediaKitEngine, call sites, options rename, logs,
  first-frame clock, Settings → Video dropdown + ExplainButton.
- [x] T6 analyzer, focused tests green; build 153 `--side-by-side` (deliver_build.py); full suite.
- [x] T7 Thor: classic vs mpv041 runs, traces, screenshots; mark tested.

## Execution notes

- a6e30379 build(video): own libmpv (Docker in WSL, ~4 min; Predidit dd2bfba8 + rename to mpvls).
- 4718837b feat(video): MediaKitEngine, setting, media_kit copy, gpu-next options, two jars.
- 99168f5b fix(video): Thor crash with mpv041 = SIGSEGV in classic libmpv.so mpv_get_property.
  media_kit_video's queryDecoders calls NativeLibrary.ensureInitialized() bare, which re-resolved to
  libmpv.so. Patched in our media_kit (bare call keeps the resolved library); test uses a default
  name that really opens (kernel32.dll) so it was red before the fix.
- Tests: media_kit_engine_test + options + choice + cap + architecture green (29, then 20 focused).
- Thor (153 side-by-side, FC392CB1): classic vs mpv041 x (software | auto-safe) + mpv041 gpu-next,
  traces in the session scratchpad; numbers in K: changes.txt. A1-A4 and A6 verified on device:
  no flicker, MediaCodec (mediacodec-copy) on mpv041, gpu-next via androidvk, old helper works.
- APK 149.4 -> 157.9 MB (+8.5; libmpvls.so 20.7 MB, 8.6 MB compressed).
- Gotchas: adb push from Git Bash needs MSYS_NO_PATHCONV=1 AND a C:/ local path; never
  `su -c 'cat tmp > settings.json'` without `[ -s tmp ] &&` (an empty push wiped settings.json once;
  restored byte-identical from the copy pulled seconds before). Check the app is in front before
  scripted taps (a crash sent taps to the launcher).
- Not done: webm sample, scrub/loop/fullscreen on mpv041, measured times inside the (i) window,
  fresh reviewer (needs the user's yes).
