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
