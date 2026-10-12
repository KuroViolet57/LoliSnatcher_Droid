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
3. Classic behaviour drift: same options for vo=gpu (`android_gpu_options_test`), same library name.
4. JavaVM handed to the chosen library (`android_helper_library_test`).
5. Settings: unknown stored value → classic; key in schema (test).
6. Gradle copies both jars, both hash-checked (text test).
7. `cache-dir` gone in 0.41 → `demuxer-cache-dir` (options test).

## Tasks

- [ ] T1 tests red: `test/media_kit_engine_test.dart` (MpvBuild, MediaKitEngine, options,
  helper name, gpu options, gradle, schema, first-frame clock).
- [ ] T2 third_party/media_kit: vendor 1.2.6, AndroidHelper patch, #1446 leak hunks, LOLISNATCHER_PATCH.md;
  pubspec override.
- [ ] T3 media_kit_video: `androidGpuOptions`, patch notes.
- [ ] T4 libs package: second jar + hash; libmpv-android README + build recipe.
- [ ] T5 app: MpvBuild, setting plumbing, MediaKitEngine, call sites, options rename, logs,
  first-frame clock, Settings → Video dropdown + ExplainButton.
- [ ] T6 analyzer, focused tests green; build 153 `--side-by-side` (deliver_build.py); full suite.
- [ ] T7 Thor: classic vs mpv041 runs, traces, screenshots; mark tested.

## Execution notes
