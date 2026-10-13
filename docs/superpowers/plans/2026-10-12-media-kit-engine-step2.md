# Plan: media_kit engine, step 2 (token 154)

- **Goal:** finish 153: measured times in the (i) window, the not-done device checks on mpv 0.41
  (webm, scrub, loop, fullscreen, gif), and the extra features from
  `docs/research/media-kit-engine.md`, each behind its own switch (default = today), with an (i)
  and in the settings backup. Leave out what does not help on the Thor, with evidence.
- **Architecture:** spec `docs/superpowers/specs/2026-10-12-media-kit-engine-design.md` (step 1);
  this file is the step-2 design (bounded).
- **Tech:** Flutter 3.42 beta via `tool/flutterw.sh`; Thor (adb -s 63c3fa7f) for device runs.
- **Branch:** `claude/1-0-media-kit-engine-step2-45508a` (worktree) from a20abe26 (153).

## Ground truth (2026-10-12, this session)

- Thor probe on the installed 153, HWDEC `mediacodec` (no copy), output gpu, 4 rule34 mp4s:
  classic and mpv 0.41 both report `decoder mediacodec` (zero-copy through AImageReader);
  native memory after 4 videos 614 / 620 MB vs 713 / 740 MB with auto-safe (= mediacodec-copy)
  and 881 / 1028 MB with software (153's runs). Pictures right, frame grabs ran ("frame look").
  Traces: session scratchpad `runs/trace-probe-mc*.txt`.
- mpv 0.41 `--hwdec` docs (DOCS/man/options.rst v0.41.0): `mediacodec` is NOT in the `auto`
  whitelist (hence auto-safe = mediacodec-copy), needs `--vo=gpu --gpu-context=android`; "Most
  non-copy methods only work with the OpenGL GPU backend" -> with gpu-next on Vulkan a bare
  `mediacodec` cannot work; a list "will go down the list ... until one is successfully
  initialised", then software. Default `--hwdec-codecs` already covers h264, hevc, vp8, vp9, av1.
- SurfaceTexture fallback: Predidit/media-kit 87cdfef7 (Java VideoOutput + one config flag);
  Kazumi (35.7k stars) ships it ON by default since 060c6e67 (2026-06-18) with Impeller off, as
  we do (AndroidManifest EnableImpeller=false). Flutter 3.42 `createSurfaceProducer()` on API 29+
  is always the ImageReader producer (FlutterRenderer.java:202), so the fallback really changes
  the path on the Thor and the S24U. "Only effective with Skia" (Predidit's comment) - we are on Skia.
- Safe screenshot (Predidit a7d4a070) fixes media_kit's `screenshot()` (`_screenshot` allocates
  `args.join().length` bytes for a pointer array, real.dart:2765). Nothing in the app calls
  `screenshot()`: the frame reader sends `screenshot-to-file` through `command()` (real.dart
  `_command`: 128 zeroed pointer slots). -> **left out**: it cannot help a path we never take.
- Our media_kit_video Java is upstream 2.0.1 unchanged, so 87cdfef7's Java applies as is.

## Design

1. **(i) times.** `lib/features/video/logic/engine_measurements.dart`: plain const texts, one per
   build/option, "Measured on the AYN Thor (Snapdragon 8 Gen 2), 2026-10-12: …", from 153's
   changes.txt plus this session's runs. The libmpv (i) uses them as `ExplainChoice.timing`.
2. **Decoder chain** (switch `mediaKitHwdecChain`, bool, default false). On: the pooled engine
   asks mpv for `hwdec=mediacodec,mediacodec-copy` instead of the HWDEC dropdown: the phone's
   decoder straight into the picture, and where that cannot start (output gpu-next on Vulkan,
   a codec the direct path refuses) the copying decoder, before software. No codec whitelist:
   mpv's default already lists every booru codec (mpv-android's extra mpeg4/mpeg2video are not
   booru formats). Settings -> Video, under the libmpv build, with (i).
3. **SurfaceTexture** (switch `mediaKitSurfaceTexture`, bool, default false). On: our
   media_kit_video creates its Android surface with `createSurfaceTexture()` instead of
   `createSurfaceProducer()` (87cdfef7). `VideoControllerConfiguration.enableAndroidSurfaceProducer`
   (default true) is the flag. Surface cap unchanged (it sizes the buffer the same way).
4. Both keys: schema bool, field, storage get/set, `deviceSpecificSettings` (next to HWDEC),
   settings.json -> backup. The pool's options signature gets both, so idle players built with
   the old value are dropped. The per-video log line adds `surface texture|producer`.

## Global constraints

- Defaults: `mediaKitHwdecChain` false, `mediaKitSurfaceTexture` false -> byte-for-byte the
  options 153 sent (hwdec from the dropdown, SurfaceProducer).
- Chain string exactly `mediacodec,mediacodec-copy`.
- No engine/package upgrades; third-party edits marked `LoliSnatcher patch (token 154)` and
  listed in LOLISNATCHER_PATCH.md. Never raise the Thor's volume. Settings file edits only
  through the guarded script (backup sha256 227eae8e…).

## Review focus

1. Defaults drift: with both switches off the controller config equals 153's
   (`media_kit_engine_options_test`).
2. A slot built with the old surface/decoder lives on after a switch -> signature includes both
   (`media_kit_engine_options_test`).
3. SurfaceTexture surface released twice / wid freed while mpv still draws -> dispose order
   copied from 87cdfef7 (wid freed 5 s later); device: swipe through 8+ videos, leave and reopen.
4. Surface cap with SurfaceTexture: setSurfaceSize must resize the buffer and re-notify
   (`media_kit_video` text test + device: an oversized post).
5. Chain with output gpu-next: must end on mediacodec-copy, not software (device, log line).
6. Settings: keys in schema, default false, survive reload, device-specific (test).
7. The (i) texts name the device and match the measured numbers (test).

## Tasks

- [x] T1 tests red: `test/media_kit_engine_step2_test.dart` (options, signature, settings,
  media_kit_video flag + Java path, measurements text).
- [x] T2 media_kit_video: config flag, real.dart passes it, Java SurfaceTexture path, patch notes.
- [x] T3 app: settings plumbing, MediaKitEngineOptions (chain, surface, signature), pool uses
  the shared signature + log, Settings -> Video toggles with (i), measured times in the libmpv (i).
- [x] T4 analyzer, focused tests green; changelog; build 154 `--side-by-side`; full suite.
- [x] T5 Thor: both builds x mp4/webm/gif, scrub/loop/fullscreen on mpv 0.41; chain (gpu and
  gpu-next); SurfaceTexture A/B (first frame, drops, memory); trace. Decide keep/drop per
  feature; put the numbers in the (i); rebuild if anything changed; restore the user's settings.

## Execution notes

- f56be2be plan; a82fb796 SurfaceTexture path in media_kit_video (Predidit 87cdfef7 applied as is,
  marked); 3ab2f566 app (settings, options, signature, (i) windows, measured times); 8b9b9f83 fix;
  472df5b0 Thor numbers in the (i). Research note 1 commit.
- Found on the Thor (first 154 build): SurfaceTexture + a re-pointed pool player at a video of another
  size -> squashed picture. The SurfaceTexture keeps one surface, so the resize returns the same wid,
  widListener never runs, mpv keeps the old android-surface-size (mpv only reads it on vo init:
  context_android.c android_reconfig; the option has no runtime update flag). Fix: real.dart re-runs
  widListener() after a resize of an attached SurfaceTexture. Verified: post 13 at 16:9 after 12 swipes.
- Thor runs (traces in the session scratchpad runs/trace-*.txt): r1 chain+gpu = mediacodec, 609 MB;
  r2 chain+gpu-next = mediacodec-copy, 0 drops; r2b mediacodec alone on gpu-next = software (graphics
  461 MB); r3/r4 producer vs texture graphics 182 vs 131 MB; r5 classic texture 128 MB; r6 gpu-next +
  chain + texture 203 MB vs 327; r7-r9 e621 VP9 webms on both builds (slow starts = e621 CDN, classic
  slower); scrub/loop/double-tap/fullscreen on mpv 0.41 with a webm; e621 gif animates with mpv041.
- Left out: safe screenshot (Predidit a7d4a070) - repairs NativePlayer.screenshot(), never called here.
- Tests: focused 44 green before the build; full suite after the first build +2030 ~14 -11 (all 11 =
  live booru_test network cases).
- Gotchas: rule34xxx re-encodes uploads to MP4 (its "webm" tag shows MP4 files) - use e621 type:webm.
  Long-press the top "+" for the add-tab dialog with a source picker; the tab manager closes tabs.
  Heredocs with \n inside python strings break; write edit scripts to files.

## Review (2026-10-14)

Fresh reviewer over a60fc3d3..fe005af5 (153 + 154), report and triage in
`2026-10-14-media-kit-engine-review.md`. Verdict "ship", 7 findings. Fix branch
`claude/1-0-media-kit-review-fixes` from fe005af5. Classic with both switches off is unchanged
by every fix (no option, library or signature touched).

- [x] R1 (finding 1) fallback status: `MediaKitEngine.fellBackFrom`, `restartNeeded` false for the
  build that failed to open, `statusText()` in Settings -> Video. Test group 1.
- [x] R2 (finding 2) resize re-init skipped for a disposed player, late dispose swallowed:
  `third_party/media_kit_video/.../surface_texture_resize.dart` + `real.dart`. Test group 2.
- [x] R3 (finding 4) reused slots timed from the rewind: `FirstFrameClock.afterRewind()`. Test group 3.
- [x] R4 (finding 5) Vulkan texts: Classic is software always. Test "finding 5".
- [x] R5 (finding 3) test renamed; (finding 6) correction notes below; (finding 7) accepted.
- Correction (finding 6): "No codec whitelist" above is wrong - media_kit_video 2.0.1 already sends
  `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`, so the chain runs under it (every booru
  codec is in it). "Device-specific" keys are only kept out of LoliSync; the settings backup carries
  every key.
- Next list (not this round): "Use hardware acceleration" off does not switch the media_kit pool to
  software (it sends the HWDEC dropdown; pre-existing since before 153).
- Tests: red first (10 failed, 1 control passed); then the four engine test files 46/46.
