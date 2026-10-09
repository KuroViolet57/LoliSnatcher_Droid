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
