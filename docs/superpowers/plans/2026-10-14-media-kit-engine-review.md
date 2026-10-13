# Fresh review: media_kit engine (builds 153 + 154), 2026-10-14

Reviewer: one fresh agent (strongest model), report-only, worktree `review-mk-fe005af5` detached at
fe005af5. Scope `git diff a60fc3d3..fe005af5`. Focused tests it ran: 35/35 green
(`media_kit_engine_test`, `media_kit_engine_step2_test`, `media_kit_engine_options_test`).
Reviewer's verdict: ship; items 1 and 2 small follow-ups. Triage and fixes: see "Triage" below and
the plan section "Review (2026-10-14)" in `2026-10-12-media-kit-engine-step2.md`.

## Report (verbatim, line numbers as the reviewer gave them)

1. **ux/risk — Settings promises a restart that cannot switch after a fallback.**
   `lib/features/video/logic/media_kit_engine.dart:414-429`. Scenario: setting = mpv041, `libmpvls.so`
   fails to dlopen (missing/corrupt, or a non-arm64 build) -> fallback to Classic is logged,
   `_loaded = classic`; `restartNeeded('mpv041')` is then true forever, so the dropdown subtitle reads
   "Loaded now: Classic. Restart the app to switch." A restart repeats the fallback. Fix: keep a
   `static bool fellBack` and show "mpv 0.41 would not open; using Classic (see log)" instead of the
   restart line. CONFIRMED (code trace).
2. **risk — resize fix can run `widListener()` on a disposed player.**
   `third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart:142-144`.
   Scenario (SurfaceTexture on): a pool slot above capacity is disposed (`_disposeOverflow`) while its
   `videoParams` handler is awaiting `SetSurfaceSize`; `_dispose` cancels the subscription but the
   running closure continues, sets `rect.value` on a disposed notifier and calls `widListener()` ->
   `setProperty` throws `AssertionError('[Player] has been disposed')` as an unhandled async error (no
   crash in release, noisy log, debug assertion). The SurfaceProducer path has the same `rect.value`
   window upstream; our hunk adds the mpv calls. Fix: `if (player.platform?.disposed ?? true) return;`
   (or `_controllers.containsKey(handle)`) before the `unawaited(widListener())`. PLAUSIBLE.
3. **ux/nit — chain vs "Use hardware acceleration".** `media_kit_engine_options.dart:466` turns the
   chain off when `altVideoPlayerHwAccel` is false but then sends the dropdown's hardware decoder
   (e.g. `auto-safe`), because media_kit_video only uses `enableHardwareAcceleration` when `hwdec` is
   null (`android_video_controller/real.dart:173`). Pre-existing for the pool; the new test
   `media_kit_engine_step2_test.dart:55` is named "hardware acceleration off still means software
   decoding" while asserting `'auto-safe'`. The toggle subtitle "Overrides HWDEC while hardware decoding
   is on" is true to the code. Fix: rename the test; optionally say in the (i) that the toggle does not
   switch the pool to software. CONFIRMED.
4. **nit — "playing after N ms (reused)" is not a first-picture time.** `media_kit_player_view.dart:333-343`:
   a reused slot is paused at a position > 0, so the first position tick fires the clock at once; the
   number is time-to-resume. The (i) footer calls these "your own times". Fix: label reused as
   "resumed" or skip it. PLAUSIBLE.
5. **nit — (i) footer wording.** `video_page.dart:295`: "vulkan decodes in software with both builds on
   phones whose GPU has no Vulkan video decoding" — Classic was built without Vulkan at all (no
   `libvulkan` NEEDED, no gpu-next), so on Classic it is software on every phone. CONFIRMED (ELF NEEDED
   list).
6. **nit — doc claims not matching code (no behaviour effect).** Plan step 2 says "No codec whitelist",
   but media_kit_video 2.0.1 already sets `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`
   (`real.dart:229`), so the chain runs under it. Session log says "Both keys device-specific in
   settings.json (backup)": `deviceSpecificSettings` only strips keys from LoliSync payloads
   (`loli_sync_handler.dart:817`); the backup carries every key regardless. CONFIRMED.
7. **nit — debug-only hot-restart hazard.** `MediaKitEngine._loaded` resets on hot restart while the .so
   stays loaded; with the setting changed between restarts, `nativeEnsureInitialized` resolves the other
   library and `NativeReferenceHolder` (`media_kit real.dart:56`) sends `quit` to handles of the old one.
   `kDebugMode` only; release unaffected. PLAUSIBLE.

### Checked and found correct (reviewer)

- JavaVM handoff: `nativeEnsureInitialized` passes `libmpv` to `AndroidHelper` and `NativeLibrary`; with
  no name `libmpvName(null)` = `libmpv.so`, identical to 1.2.6. Isolate initializer opens
  `NativeLibrary.path`; NativeCallable uses the same bindings; the JavaVM is process-global per .so.
  Fallback re-runs `AndroidHelper` with `libmpv.so` because `MediaKit._initialized` stays false on throw.
  Vendored media_kit differs from the pub-cache 1.2.6 only in `native_library.dart`,
  `android_helper.dart`, `real.dart`.
- Classic invariant: `MediaKit.ensureInitialized(libmpv: 'libmpv.so')` yields the same
  `_resolved='libmpv.so'` as the old bare call; controller config byte-equal with both switches off;
  pool signature `gpu|vulkan|true` unchanged, `|chain`/`|texture` only appended when on; vo=gpu options
  same keys/values. Switching either toggle drops idle slots via `staleOptions`; in-use slots are
  dropped once idle on the next acquire.
- 99168f5b complete: the only bare `NativeLibrary.ensureInitialized()` is
  `media_kit_video/lib/src/utils/query_decoders.dart:25`, reachable only after a `Player` exists; no
  other caller; `MediaKit.ensureInitialized` only in `media_kit_engine.dart` (test enforces). Debug
  seams inert in release.
- Race/lock: both call sites synchronous; `_loaded` records the library actually opened; fallback logged.
- #1446 hunks: same semantics as upstream; no double free; Classic unaffected.
- Binaries: SONAME `libmpvls.so`; 16 KB PT_LOAD alignment; jar hashes match gradle/test; classic
  `libmpv.so` contains `demuxer-cache-dir` (and `cache-dir`) option strings (binary scan).
- Gradle: each jar hash-checked before its copy; mismatch throws `GradleException`. Both jars arm64-only
  (pre-existing since r60). Build script pins Predidit `dd2bfba8`, NDK r27c, fixed timestamps.
- SurfaceTexture Java: matches Predidit 87cdfef7; all paths behind the flag; platform thread; `wid` freed
  5 s later; cleanup once per handle.
- Resize fix: cannot fire on SurfaceProducer; first attach excluded; no double re-init; no loop.
- Settings: three keys in schema with defaults, in `toJson` (backup), old backups get defaults via
  `setMissingKeys`, unknown value -> classic.
- R8: no new reflection/JNI names.

## Triage (2026-10-14, checked in the code at fe005af5)

| # | Verdict in the code | Action |
|---|---|---|
| 1 | Real. `media_kit_engine.dart` `restartNeeded` compared only stored vs loaded; after a fallback it stayed true and Settings promised a restart that falls back again. | Fix: `fellBackFrom`, `restartNeeded` false for the build that failed, `statusText()` used by `video_page.dart` ("<build> would not open on this device; Classic plays the videos"). Tests: `media_kit_engine_review_test` group 1. |
| 2 | Real. `NativePlayer.dispose` sets `disposed = true` before the `release` callbacks, so the videoParams closure finishing its `SetSurfaceSize` await after a pool slot is dropped queued `widListener()` -> `setProperty` threw `AssertionError` as an unhandled async error. No native call: the disposed check precedes the FFI call and `mpv_terminate_destroy` runs 5 s later. | Fix: `surface_texture_resize.dart` `reapplySurfaceSizeAfterResize(disposed:)`, and `catchError` (only while disposed) for a dispose landing while the re-init waits for the lock. Tests: group 2; step2 text test updated. |
| 3 | Test name wrong; behaviour pre-existing (the pool sends the HWDEC dropdown even with "Use hardware acceleration" off, since before 153). Chain subtitle is true. | Test renamed. Behaviour left as is (Classic invariant); on the next list. |
| 4 | Plausible: the reused slot's `seek(0)` happens before the position subscription, so a stale pre-seek position could time a reused video at ~0 ms. | Fix: `FirstFrameClock.afterRewind()` ignores positions >= 1 s until one below arrives; armed for reused slots before listening. Tests: group 3. |
| 5 | Real. Classic has no Vulkan at all. | Both texts corrected (libmpv (i) footer and chain "Off" choice). Test: finding 5. |
| 6 | Real, docs only. media_kit_video 2.0.1 sends `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1` (`real.dart:239`); `deviceSpecificSettings` only keeps keys out of LoliSync, the settings backup carries every key. | Correction notes in the step 2 plan and the session log. No code. |
| 7 | Debug-only (hot restart keeps the .so loaded, `_loaded` resets). Release unaffected. | Accepted, registered: switch the build only with a full restart while debugging. |
