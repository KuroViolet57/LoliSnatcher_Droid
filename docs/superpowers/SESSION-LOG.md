# Session log

## 2026-10-09 Claude: info sheet one-tap open + per-frame rebuilds fixed, token 147 delivered (96c49777)
- Branch: claude/post-details-sheet-lag-1a23ce (worktree), on top of Grok's a3498f44 (token 146).
- Files: lib/features/viewer/logic/info_sheet_body.dart (InfoSheetContentGate, peek zone),
  lib/features/viewer/ui/info/item_info_bottom_sheet.dart (InfoSheetFrame, openInfoSheet),
  lib/features/viewer/ui/gallery_view_page.dart, gallery_view_page/swipe_up_listener.dart,
  lib/features/viewer/logic/viewer_handler.dart (RxBool infoSheetInPeekZone), test/info_sheet_body_test.dart,
  docs/FEATURES.md row 26, plan 2026-10-04-1.0-rebuild.md "Fix plan (2026-10-09)".
- Changed: one tap on the info button opened the sheet a little (the placeholder-to-TagView swap
  detached the sheet's scroll position; the SDK disposes sheet animations on detach). TagView is now
  built first and the animation starts after that frame. The sheet body, the video controls' lift and
  PopScope no longer rebuild on every frame of the sheet's motion.
- Tests: test/info_sheet_body_test.dart 8 passed (one tap reached 0.10-0.48 of 0.67 before the fix);
  viewer_peek_bar_artist, viewer_tutorial, video_engine_choice, desktop_image_listener passed.
  architecture_test FAILS on two imports that predate this work (6a3bbfd8: viewer_handler.dart ->
  media_kit_player_view.dart and gif_viewer.dart).
- Delivered: K:\My Drive\booruApk\147.apk (1.0 info sheet one tap and smooth swipe - tested), side-by-side APK.
- Not done: no device or emulator run (user: no device connected this session). The viewer still
  relayouts every frame while the sheet moves (split view); not measured on a phone.
- Next step: user tests 147 with the checklist in changes.txt. If the swipe still stutters, get a
  Settings -> Debug -> Record a trace report while swiping the sheet, and look at the viewer relayout
  (gallery_view_page.dart, the SizedBox(height: viewerH) builder) next.

## 2026-10-09 Claude: architecture test green again (zoom hooks moved to a logic interface), no build
- Branch: claude/optimistic-kalam-384c29 (worktree), fast-forwarded onto claude/post-details-sheet-lag-1a23ce (4ebea8a6).
- Files: new lib/features/viewer/logic/viewer_zoom_target.dart (ViewerZoomTarget: isZoomed, viewController,
  isZoomTargetLoaded, doubleTapZoom, resetZoom); lib/features/viewer/logic/viewer_handler.dart;
  lib/features/viewer/ui/media/gif_viewer.dart; lib/features/video/ui/media_kit_player_view.dart;
  new test/viewer_zoom_target_test.dart; test/viewer_zoom_targets_test.dart.
- Changed: 6a3bbfd8 had viewer_handler.dart (logic) import gif_viewer.dart and media_kit_player_view.dart (ui).
  GifViewerState and MediaKitPlayerViewState now implement ViewerZoomTarget and the handler reaches them with
  `case _ when state is ViewerZoomTarget`. Same behaviour: GIF reports loaded, media_kit reports loaded once it
  has a player. No allowlist line added.
- Tests: red first (architecture_test, the new zoom test and import check failed: 3), then architecture,
  viewer_zoom_target (2), viewer_zoom_targets, info_sheet_body, viewer_tutorial, viewer_peek_bar_artist: 20 passed.
  Analyzer: no issues in lib/features/viewer, lib/features/video/ui and the two tests.
  Note: a bare tester.pump() did not run setNewState's post-frame callback; the test schedules a frame first.
- Delivered: nothing (no APK asked for). Next token stays 148.
- Not done: not tried on a phone (no code path for the user changed, only how the handler finds the page).
- Next step: user tests 147 per its changes.txt; the next delivery (148) carries this refactor along with
  whatever change comes next.

## 2026-10-09 Claude: token 148 delivered (81ee01ef)
- Branch claude/post-details-sheet-lag-1a23ce fast-forwarded to 81ee01ef (the zoom-target refactor).
- Tests: architecture, viewer_zoom_target, viewer_zoom_targets, info_sheet_body, viewer_peek_bar_artist,
  viewer_tutorial, video_engine_choice, desktop_image_listener: 24 passed, 0 failed.
- Delivered: K:\My Drive\booruApk\148.apk (1.0 info sheet and zoom tidy - tested), side-by-side APK = 147 + zoom refactor.
- Not done: no phone or emulator run (no device connected).
- Next step: user tests 148 with its changes.txt checklist (sheet one-tap, swipe, GIF/video zoom). Next token 149.

## 2026-10-09 Claude: next architecture step chosen (no code)
- Next step (two steps): step 1, fast-forward grok/1.0-continue to this tip if its worktree is clean; step 2, the M3 leftovers:
  1) shrink test/architecture_allowlist.txt (79 entries; start with the 18 that import UI or app from a lower layer);
  2) remove the verified dead code from docs/superpowers/specs/1.0-map/*.json deadCode entries; 3) build token 149.

## 2026-10-09 Claude: token 149 delivered (doujin list lighter, grid titles), M3 not started (36a01753)
- Branch claude/suspicious-visvesvaraya-aacef1 (worktree), fast-forwarded to 19b7158c first.
- Step 1 of the plan done: grok/1.0-continue fast-forwarded to 19b7158c (its worktree was clean).
- The user then asked, mid-session, for two doujin fixes ASAP; they took this session and token 149
  (the planned "1.0 layer cleanup" moves to 150):
  1) 872730a2 feat(feed): titles on doujin grid cards. sourceSettings.gridTitle (default on), Source
     settings -> GRID -> Titles on grid cards with an ExplainButton; title (2 lines) between cover and
     tags; staggered cell +36 px; language badge stays tied to the tag strip. Also shows in the floating
     tag-preview grid (same card).
  2) 36a01753 perf(feed): lighter doujin list rows. DoujinListCard's tag block builds only the chips that
     fit the screen width (letter width 2.5 px, under any real glyph) until the first pointer-down on it;
     list feed uses SliverFixedExtentList at DoujinListCard.rowExtent(height) = height + 6.
- Tests: red first (120 chips built; missing gridTitle/rowExtent). Then doujin card/list/adapt/settings
  and architecture tests: 81 passed. Full suite: +1986 ~14 -11 = the 10 known live booru_test failures
  plus video_frames_test "r77: no grab until mpv..." (passes alone 20/20; timing-sensitive under the
  full parallel run, untouched here).
- Thor (149, E-Hentai tab in List): in-app trace, 8,395 frames over 161 s, app work median 0.2 ms / worst
  38 ms, drawing median 3 / worst 41, none over 100 ms. E-Hentai listings carry 1-6 tags per gallery, so the
  chip saving is small there. A SurfaceFlinger --latency A/B against 148 was void: the gaps between scripted
  adb swipes showed up as 135-170 ms "frames". Grid titles were not looked at on the device.
- Device state: the 1.0 side-by-side app on the Thor has 149 installed plus one extra E-Hentai tab (5064
  tabs) I added; after a burn-in refresh the screen stopped updating (app drawn in the top part).
- Delivered: K:\My Drive\booruApk\149.apk (1.0 doujin list lighter and grid titles - tested), side-by-side.
- Next step: user tests 149 with its changes.txt checklist. Then M3 leftovers as planned, as token 150:
  2a) shrink test/architecture_allowlist.txt (79 entries), starting with the 18 lower-layer -> UI/app imports
  (core->features/ui 5, sources->features/ui 5, features/logic->features/ui 7, core->app 1), pattern of
  lib/features/viewer/logic/viewer_zoom_target.dart (81ee01ef); 2b) dead code from
  docs/superpowers/specs/1.0-map/*.json deadCode, grepped first. Build 150 "1.0 layer cleanup" --side-by-side.

## 2026-10-10 Claude: token 150 delivered (doujin list rows same size + list rebuild storm), M3 moves to 151 (d59b9453)
- Branch claude/cool-wilson-ea4d28 (worktree), on 3eba19bd (token 149). Session "Fix doujin list rows (F42), test on the Thor".
- User (F42 "Doesn't work", 2026-10-10): List rows looked different sizes in Adapt; scrolling no smoother in any mode.
- Found on the Thor (screenshots measured): 148 and 149 both draw every row at the set height (184 dp); in Adapt the
  cover COLUMN took each cover's shape (48-140 dp), unchanged since r69. Trace: every list rebuild rebuilt every row.
- Commits: 558d10e8 fix(feed) every doujin list row the same size in Adapt (fixed column; Thumbnail.coverBackdrop =
  blurred dimmed copy of the same image behind the whole cover; help texts); 5085a469 feat(debug) trace section
  "SLOW FRAMES, WHAT WAS BUILT" (persistent frame callback, vsync -> end of paint via Timeline.now) + feed.cache /
  feed.list timeline events; b290f2d7 perf(feed) DoujinListSliver keeps row widgets while item + look unchanged
  (didUpdateWidget compares by identity: GetX RxList == never matched); d59b9453 perf(feed) List-view fling cache window
  opens in 6 steps over 360 ms (FeedCacheWindow.extent(ramped:)).
- Tests: red first (doujin_list_rows_equal_test: 1:2 cover got a 92 dp column; perf_trace_test; doujin_list_sliver_test;
  feed_cache_extent_test). Full suite on b290f2d7: +1994 ~14 -11, the 11 = live booru_test network cases (same as on 149);
  final run on d59b9453: +1995 ~14 -11, the same 11.
- Thor (side-by-side APK, in-app trace, 15+15 adb flings, screenshots checked): E-Hentai and hitomi rows equal in
  Adapt/Crop/Fit (184 dp / 176 dp, cover columns identical). App frames over 16.7 ms: E-Hentai 149 Adapt 33, Crop 38;
  hitomi before the list work Adapt 41 -> final Adapt 28, Crop 33, Fit 32; E-Hentai final Adapt 25. Rows built per
  run ~1,100-1,800 -> ~460. Left: a page landing at the bottom builds 10-11 rows in one frame (~25 ms).
- Tooling gotchas (Thor): uiautomator dump fails while a trace records (app draws every frame) and breaks the side
  drawer if taken while it is open; coming back from Settings leaves the drawer open (close with its X at 1015,75);
  pushing sourceSettings.json with cp loses its SELinux categories (write with `cat > file`). Scripts in this
  session's scratchpad (trace_run2.sh, ui.py, rows2.py).
- Thor state: 150 side-by-side installed; sourceSettings restored (e-hentai Adapt/List 184/140, hitomi as before);
  current tab back on E-Hentai.
- Not done: nhentai not tried; per-row build cost (~2.4 ms a row) and page-landing batches not reduced.
- Delivered: K:\My Drive\booruApk\150.apk (1.0 doujin list rows same size - tested), side-by-side.
- Next step: user tests 150 with its changes.txt checklist. Then the M3 layer cleanup as token 151:
  1) shrink test/architecture_allowlist.txt, starting with the 18 lower-layer -> UI/app imports (pattern of
  lib/features/viewer/logic/viewer_zoom_target.dart, 81ee01ef); 2) remove the verified dead code listed in
  docs/superpowers/specs/1.0-map/*.json deadCode (grep each first); build 151 "1.0 layer cleanup" --side-by-side.

## 2026-10-11 Claude: token 151 delivered (1.0 layer cleanup, M3), tested on the Thor (0f6a8584)
- Branch claude/1-0-m3-layer-cleanup-151-a2ff5d (worktree) from e98e54b0 (token 150). Session "1.0 build 151: M3 layer cleanup".
- Before starting: grok/1.0-continue had no new work since 19b7158c (only our 149 commits, worktree clean), fast-forwarded to
  e98e54b0. Stray C:\Program Files\Git\tmp_sliver_backup.dart (a copy of doujin_list_sliver.dart) deleted.
- Commits: f62def4a plan section; 1284f231 refactor(arch) the 18 lower-layer -> UI/app imports gone (allowlist 79 -> 61):
  moves (AppLocaleExt, webViewEnvironment, TabBooruSelectorItem, sync modes), interfaces (BottomBarVisibility,
  ViewerMediaPage/ViewerVideoPage), TagCatalogNamespace.pickerId, VideoFramePlayers (set by the media_kit pool),
  hooks bound in lib/app/layer_bindings.dart bindLayers() at the top of main(); 0f6a8584 dead code (~3,400 lines,
  16 files, allowlist 61 -> 60), ledger in docs/superpowers/specs/1.0-map/dead-code-151.md.
- Tests: red first; full suite after the build +2003 ~14 -11 (all live booru_test). Analyzer 0 errors/0 warnings.
- Thor (151 side-by-side): install/start, E-Hentai List + Grid, rule34 feed, viewer (video, image double-tap zoom,
  zoom button), Record a trace. Device state restored: zoomButtonPosition Disabled, e-hentai List, current tab E-Hentai.
- Order slip: the first full suite ran before the build; the build was parked before the deciding run.
- Not done: TabSelector/TabRow unused parameters, tagFetchActive/queue path, the 60 remaining allowlist lines
  (models -> core 16, models -> features/logic 4, core -> features/logic 20, core -> sources 9, sources -> features/logic 11).
- Delivered: K:\My Drive\booruApk\151.apk (1.0 layer cleanup - tested), side-by-side.
- Next step: user tests 151 with its changes.txt checklist (nothing should look different). Then the next M3 slice as
  token 152: the models -> core imports in test/architecture_allowlist.txt (models/booru_item.dart, models/settings/*,
  models/tag_type.dart ...), same pattern (move down or pass in), build 152 --side-by-side.

## 2026-10-12 Claude: token 153 delivered (own media_kit engine, mpv 0.41), tested on the Thor (99168f5b)
- Branch claude/1.0-media-kit-engine (worktree serene-sanderson-f1fe7c) from a60fc3d3 (151). Session "Custom media_kit engine: research and update".
- Research docs/research/media-kit-engine.md: media-kit#1091 (flicker on mpv >= 0.37) is fixed in media_kit 1.2.1
  (video-params, PR #1107; we run 1.2.6). Kazumi ships mpv 0.41 via Predidit's forks. Thor's Adreno 740 has no
  VK_KHR_video_* -> hwdec "vulkan" is software with any build. Spec docs/superpowers/specs/2026-10-12-media-kit-engine-design.md,
  plan docs/superpowers/plans/2026-10-12-media-kit-engine.md.
- Our libmpv: third_party/libmpv-android/ls-arm64-v8a.jar = libmpvls.so (mpv v0.41.0-110, FFmpeg 7.1.3, libplacebo),
  built in Docker inside WSL by third_party/libmpv-android/build/build_ls_libmpv.sh (Predidit dd2bfba8 + rename), ~4 min.
- Our media_kit: third_party/media_kit (1.2.6 + JavaVM to the chosen library + #1446 leak fixes + bare
  NativeLibrary call keeps the chosen library). media_kit_video: gpu-next gets gpu-api=vulkan,opengl.
- App: Settings -> Video -> media_kit libmpv build (Classic default | mpv 0.41) with (i); MediaKitEngine locks per process;
  log/trace lines video.engine, video.decoder, video.firstframe; demuxer-cache-dir.
- Thor A/B (4 mp4, 8 s each): output gpu both builds about equal; auto-safe = mediacodec-copy on both; mpv041 + gpu-next
  (androidvk) fastest first frames and 0 drops, +150 MB graphics memory. Numbers in K: changes.txt.
- Found on device: first build crashed with mpv041 (SIGSEGV in classic libmpv.so via media_kit_video queryDecoders) -> fixed.
- Slip: a failed adb push + unguarded `cat > settings.json` emptied the Thor's settings.json once; restored byte-identical
  within a minute (tabs/DB untouched). Thor state now: user's settings (vo gpu, hwdec vulkan, pool 8), Classic, 153 installed.
- Tests: full suite +2018 ~14 -10, the 10 = live booru_test network cases (151 had 11).
- Not done: webm sample, scrub/loop/fullscreen on mpv041, measured times in the (i) window, fresh reviewer (needs yes).
- Delivered: K:\My Drive\booruApk\153.apk (1.0 media_kit engine mpv 0.41 - tested), side-by-side, APK +8.5 MB.
- Next step: user tests 153 (changes.txt checklist, especially webm and scrubbing on mpv 0.41, and gpu-next on the S24U).
  Then engine step 2 as its own token: put the measured times into the (i) window and, if the user picks them, the
  extra features from docs/research/media-kit-engine.md (SurfaceTexture fallback, hwdec chain, safe screenshot).
- Report page: features/V75, reports/20261012-1905-media-kit-engine-153 and meta/project (v4) were sent from a scratch copy (the worktree guard blocks writing C:\bodu-apk\docs\reports); that main local copy does not have them yet - pull them before the next report there.

## 2026-10-12 Claude: token 154 delivered (media_kit engine step 2), tested on the Thor (472df5b0)
- Branch claude/1-0-media-kit-engine-step2-45508a (worktree) from a20abe26 (153). Session "Engine step 2: (i) times, webm check, 3 extras".
- Plan docs/superpowers/plans/2026-10-12-media-kit-engine-step2.md (ground truth, design, review focus, execution notes);
  research docs/research/media-kit-engine.md "Step 2 findings".
- (i) times: Settings -> Video -> media_kit libmpv build (i) lists the Thor's first-picture times, drops and memory per
  build/output/decoder (lib/features/video/logic/engine_measurements.dart).
- Decoder chain (mediaKitHwdecChain, off): hwdec "mediacodec,mediacodec-copy" instead of the HWDEC dropdown. Thor: gpu ->
  mediacodec (609 MB vs 881-1028 software); gpu-next -> mediacodec-copy (plain "mediacodec" there = software). Kept.
- SurfaceTexture (mediaKitSurfaceTexture, off): Predidit 87cdfef7 in third_party/media_kit_video + our fix (re-run
  widListener after a resize of an attached SurfaceTexture; without it a re-pointed pool player drew the next video
  squashed). Thor: graphics 131 vs 182 MB (gpu), 203 vs 327 MB (gpu-next). Kept.
- Safe screenshot (Predidit a7d4a070): left out - it repairs NativePlayer.screenshot(), which the app never calls.
- 153's open checks on mpv 0.41: webm (e621 VP9) plays on both builds, scrub, loop, double-tap skip, fullscreen, gif OK.
- Both keys device-specific in settings.json (backup); pool slot signature unchanged while both are off.
- Tests: focused 44 green; full suite after the first build +2030 ~14 -11, on the final tree +2032 ~14 -11 (all 11 = live booru_test).
- Thor state: 154 installed; settings.json restored byte-identical (sha256 227eae8e, 12,266 bytes; Classic, gpu, vulkan,
  pool 8); 2 test tabs closed (5,064 tabs, toned_body current). History/seen marks from the e621/rule34 runs remain.
- Not done: S24 Ultra; fresh reviewer (needs the user's yes).
- Delivered: K:\My Drive\booruApk\154.apk (1.0 media_kit engine step 2 - tested), side-by-side.
- Next step: user tests 154 with its changes.txt checklist (the two switches, especially SurfaceTexture and the chain
  with gpu-next on the S24 Ultra). Engine work has no further planned step; if the user wants one, the candidate is a
  fresh reviewer pass over 153+154's third_party changes (needs the user's yes).
- Report page: features/V75 (v2), V76, V77, reports/20261012-2130-media-kit-engine-step2-154 and meta/project (v5) were sent from a scratch copy (the worktree guard blocks C:\bodu-apk\docs\reports); pull them into the main checkout before the next report there.

## 2026-10-14 Claude: fresh review of the media_kit engine (153+154), fixes, token 155 delivered, tested on the Thor (859883c9)
- Branch claude/1-0-media-kit-review-fixes (worktree blissful-blackwell-a4b7f0) from fe005af5 (154). Session "Fresh review of the media_kit engine (153+154)".
- Review: one fresh reviewer (strongest model, report-only) in a detached worktree at fe005af5 over a60fc3d3..fe005af5. Report + triage +
  both rechecks: docs/superpowers/plans/2026-10-14-media-kit-engine-review.md; plan section "Review (2026-10-14)" in the step 2 plan.
  7 findings, verdict ship; no crash path, Classic invariant confirmed (library, options, pool signature byte-identical with both switches off).
- Commits: bce26eae docs; 48f1f7a2 fixes 1-5 (fallback status line: MediaKitEngine.fellBackFrom/statusText; SurfaceTexture resize re-init
  skipped for a disposed player + late dispose swallowed: third_party/media_kit_video .../surface_texture_resize.dart; reused-slot first-frame
  timing; Classic-has-no-Vulkan texts; test rename); f21d708e recheck issue A (clock ignores the parked position, not a 1 s window);
  859883c9 plan note. Recheck 2 clean; two plausible timing nits accepted (start delay 0 + instant swipe back; seek landing on the parked frame).
- Correction to the 154 entry above (review finding 6): "device-specific" only keeps mediaKitHwdecChain/mediaKitSurfaceTexture out of
  LoliSync; the settings backup carries every key. And the chain runs under media_kit_video's own hwdec-codecs list (h264..av1).
- Tests: red first (10, then 4); engine files 49/49; full suite after the build +2046 ~14 -11 (all 11 = live booru_test). Analyzer clean on changed files.
- Thor (155 side-by-side, user's settings): Classic plays, status line "Loaded now: Classic (...)", corrected (i) text; Logger "playing after
  564-2366 ms (new player)" and "34 ms (reused)"; SurfaceTexture on: 10 swipes forward + 3 back, shapes right, "surface texture" decoder
  lines, no new Logger error, no crash. settings.json backed up first (also /data/local/tmp/settings-155-backup.json on the Thor) and
  restored byte-identical after (sha256 227eae8e, 12,266 bytes). App left force-stopped. Viewer history/seen marks from the runs remain.
- Delivered: K:\My Drive\booruApk\155.apk (1.0 media_kit engine review fixes - tested), side-by-side.
- Not done: S24 Ultra; "Use hardware acceleration" off still does not make the media_kit pool decode in software (pre-existing, next list).
- Next step: user tests 155 with its changes.txt checklist (status line, the (i) text, SurfaceTexture swipe run, reused timings). Then the
  next M3 slice as token 152 (models -> core imports in test/architecture_allowlist.txt) as planned on 2026-10-11; next new token after that 156.

## 2026-10-14 Claude: models checked with 155 on the Thor (no code change)
- Asked by the user: do the three models (text, looks, tagger) and their options still work with the new player setup?
- Native libs: 155's APK = 151's plus libmpvls.so only; libonnxruntime*, libQnn*, libc++_shared identical in size. No model code changed in 153-155.
- Only code link between models and the player: frame grabs (video_frames.dart, screenshot-to-file on the pooled player).
  155 with mpv 0.41 + decoder chain + SurfaceTexture all on: decoder "mediacodec" (direct) on output gpu, 8 frames grabbed
  ("look: frame 1/5 ... in 304 ms (43 KB from mpv)"), the looks model read them (model_timings run.look.cpu.x2 133 -> 141), then
  "look: sessions closed (idle)". Text model (XNNPACK) and looks model (CPU) ran on 155 too.
- Tagger "Try it on a picture": works on the CPU (24 and 18 correct tags, 3.6 s), but the NPU refuses on EVERY build:
  155, 151 (pre-engine) and the regular app 2.6.0 (installed 2026-10-04) all log
  "QNN SetupBackend failed Failed to create device. Error: QNN_DEVICE_ERROR_INVALID_CONFIG", with SELinux denials for the app on
  /dev/adsprpc-smd-secure and /vendor/dsp/cdsp. Not caused by the player work; no record that the in-app NPU ever ran on the Thor
  (r87-r89 were tested on the suite/emulator). Proposed as its own session.
- Thor state: 155 installed again (151 and back for the A/B); settings.json restored byte-identical (227eae8e); a stray empty
  rule34xxx tab created by a mis-tap on 151 was closed (5,064 tabs, toned_body current). Music stream muted throughout.
- Next step: unchanged (user tests 155; then 152). NPU investigation only if the user starts that session.
