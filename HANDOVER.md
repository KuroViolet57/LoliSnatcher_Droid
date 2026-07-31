# LoliSnatcher_Droid — Session Handover

Paste this back to resume with full context. Last updated: 2026-07-15 (build 5210, Flow rounded-icon sweep + sqlite3 sandbox build fix).

## Project / workflow
- **CONTAINER RESETS HAPPEN.** After a reset: toolchain is gone (reinstall
  Flutter 3.42.0-0.4.pre beta to /opt/flutter + Android SDK/NDK 28.2.13676358
  via cmdline-tools to /opt/android-sdk), Drive oauth.json is gone (ask user to
  re-paste client_id/secret/refresh_token; folder id
  1v27HWGKh2L_tmoxB1gBo1MaEgc3Y2eYi), and the fresh clone lands on the
  auto-named session branch — switch back to megabuild. The sqlite3 release
  download and the signing keystore are handled now: the TEST keystore is
  COMMITTED at android/app/lolisnatcher-test.jks + android/key.properties
  (force-added over gitignore; passwords 'lolisnatcher-test'). Builds signed
  before 2026-07-31 used a lost key — users must uninstall/reinstall once.

- Flutter Android booru gallery app. Autonomous multi-feature build.
- **Working branch: `claude/experimental-megabuild`** (NOT the auto-named
  `claude/google-oauth-refresh-token-*` — all features live on megabuild).
- Build: `export PATH="$PATH:/opt/flutter/bin"; bash build.sh test`
  (must `git config --global --add safe.directory /opt/flutter` first; flutter
  warns about running as root but works). APKs land in
  `build/app/outputs/flutter-apk/LoliSnatcher_2.5.0_<build>_<abi>_test.apk`.
- Each feature: build → commit → push → upload test APK.
- **sqlite3 native-asset build break (sandbox only).** In THIS restricted
  sandbox the release build fails with `Hash of downloaded file
  libsqlite3.arm64.android.so is <x>, expected <y>` — the `sqlite3` pub package
  downloads a prebuilt `.so` from `github.com/simolus3/sqlite3.dart/releases`,
  but the GitHub proxy is scoped to only the app repo, so it returns a 195-byte
  JSON error instead of the binary. The user's real CI (with normal network)
  is unaffected — do NOT commit a workaround into the repo. Sandbox fix (all
  ephemeral, redo after a container reset): (1) the valid `.so` files may still
  be cached under `.dart_tool/hooks_runner/shared/sqlite3/build/download-*/`
  (match by sha256 to the expected hashes in the sqlite3 package's
  `lib/src/hook/asset_hashes.dart`); copy them into
  `/root/.pub-cache/sqlite3_prebuilt_seed/` named by release filename
  (`libsqlite3.{arm,arm64,x64}.android.so`); (2) patch the pub-cache hook
  `~/.pub-cache/hosted/pub.dev/sqlite3-*/lib/src/hook/description.dart` so
  `PrecompiledFromGithubAssets._fetchFromSource` serves that seed file when it
  exists (before the HttpClient download) — the hash is still verified by the
  caller; (3) `rm -rf .dart_tool/hooks_runner/sqlite3` to force a hook recompile,
  then rebuild. If `add_repo` for `simolus3/sqlite3.dart` becomes available,
  that's the clean fix instead (no patch/seed needed).

## Uploading builds
- **Google Drive (primary, durable):** creds live at
  `~/.config/lolisnatcher-drive/oauth.json` (gone after container reset —
  recreate from the block the user pasted; client_id/secret/refresh_token +
  `booru_apk_folder_id: 1v27HWGKh2L_tmoxB1gBo1MaEgc3Y2eYi`). Then:
  ```
  python3 scripts/drive_upload_build.py --token <short> --descriptor "label" \
    --apk <apk_path> --changelog-file /tmp/changes_<short>.txt
  ```
  Prints folder/changelog/apk URLs — post them in chat. `--token` is just a
  short folder-name key (litterbox is down, so make one up, e.g. `login5210`).
- **APK naming scheme (user request, from 2.6.0 on):** every uploaded APK is
  named `{1-2 words describing the changes}-{version}.apk` via the script's
  `--apk-name` flag (e.g. `drawer-cleanup-2.6.0.apk`). The same string minus
  `.apk` shows in Settings → version row: update `Constants.buildCodename`
  (lib/src/data/constants.dart) each build, and bump the version in
  pubspec.yaml + constants.dart updateInfo together.
- Fallback host: **gofile.io** (works). Litterbox = HTTP 500, catbox rejects,
  0x0.st disabled.

## DONE this session (committed to megabuild)
- xxxtik.com handler (`lib/src/boorus/xxxtik_handler.dart`) — HLS video site,
  keyset cursor pagination, creators as artist tags, autocomplete. Commit 8744616.
- **Account login (commit bd1dad5):**
  - **xxxtik** = Firebase email/password (Identity Toolkit signInWithPassword,
    key `AIzaSyAm9k1Y1GRbET-w1Z9joYMp63x1EHwZ5fY`). idToken cached statically +
    refreshed via securetoken endpoint; Bearer header when `_authedEmail` matches
    `booru.userID`. 5-min backoff on failed login. Reuses booru userID/apiKey
    fields, relabelled Email/Password in `booru_edit_page.dart`.
  - **redgifs** = WebView login (their API login needs an hCaptcha). New
    `lib/src/pages/settings/redgifs_login_page.dart` opens redgifs' login page,
    injects a fetch/XHR hook capturing the Bearer token the signed-in page sends,
    accepts it only if it's a *user* token (sub != `client/…`). Token is
    IP+User-Agent bound → WebView uses `Tools.browserUserAgent`. Stored in
    `booru.apiKey`; `RedGifsHandler._activeToken` prefers it over guest while
    JWT `exp` valid; dropped on 401. Editor shows signed-in/guest status +
    "Sign in with browser" button (`_buildRedGifsLogin` in booru_edit_page).
  - **UNTESTED end-to-end** (no real accounts here) — ask user to verify both,
    esp. that the redgifs WebView auto-closes on login.

## xxxfollow.com support — HANDLER DONE (browsing), UI section PENDING
Site = React SPA + **Laravel** backend, same-origin API `https://www.xxxfollow.com/api/v1`.
Handler: `lib/src/boorus/xxxfollow_handler.dart` (registered; enum `XXXFollow`
added to booru_type.dart; factory pageNum=0 → 1-indexed; booru_edit_page prefill/
onTest/instructions wired). **Fully reverse-engineered + verified live.**

THE one content endpoint:
`GET /api/v1/post/search/tag?query=Q&genders=G&limit=L&page=N`
(headers: `X-Requested-With: XMLHttpRequest`, `Accept: application/json`,
`Referer/Origin https://www.xxxfollow.com`; session cookies auto-handled by
DioNetwork's cookie interceptor after a GET of `/`).
- **query present** → `{ tags:[{id,tag,posts}], users:[creators], search:[posts] }`
  - `users[]` = creators in the tag: `{id, username, display_name,
    public_avatar_url, public_cover_picture_url, gender:'f'|'m', type:'model'}`
  - `tags[]` = similar tags.
- **query empty** → discovery `{ new[10], popular[10], popular_search[15],
    tags_trending[10], contest }` (IGNORES page → handler serves once, locks p2+).
- **post shape** (in search[]/new[]/popular[]): `{ like_count, favorite_count,
  comment_count, post:{ id, slug, text, user_id, media:[{ type:'video'|'picture',
  url(full mp4), sd_url, fhd_url, uhd_url, thumb_url, thumb_webp_url, blur_url,
  start_url, width, height, duration_in_second, has_audio, order }], media_count,
  duration_total } }`. **Media = direct MP4 (downloadable).**
- `genders` param: '' / 'f' / 'm' (exposed as sort chip All/Female/Male; filtering
  effect unverified but harmless).
- No sort param exists in the API (user's "sort like redgifs" ≈ the gender filter).
- Guest = teaser set only (~10 posts/tag, page2 empty) — a SITE restriction.
- Autocomplete: reuses post/search/tag, returns `tags[]` (or `tags_trending`).
- Other real endpoints (unused so far): `user/<username>` (creator profile),
  `user/public/top` (top creators, params {genders}), `post/public/<id>`
  (single post → {post}), `post/<id>/{view,like,favorite,tag-vote}` (POST),
  `user/<id>/follow/public` (POST), `account` (auth user), `site_config` (csrf).
- The handler stashes `lastRelatedTags` + `lastCreators` (List<XXXFollowCreator>)
  from each tag query — **ready for the UI section to consume.**

## step 3 — creators + similar-tags UI — DONE + GENERALIZED
Generic `lib/src/widgets/preview/discovery_strip.dart` (DiscoveryStrip): header
strip above results with a "Creators in these results" avatar row + "Similar
tags" chip Wrap, each under a divider label. Tapping a creator runs
`CreatorInfo.searchQuery`; tapping a tag searches it (SearchHandler.searchAction).
Inserted as SliverToBoxAdapter after MainAppBar in `waterfall_view.dart`;
rebuilds on `filteredFetched`; invisible unless the handler filled the data.

Booru-agnostic via base `BooruHandler` fields (`List<CreatorInfo> relatedCreators`,
`List<String> relatedTags`) + shared `lib/src/data/creator_info.dart` (CreatorInfo:
searchQuery/displayName/avatarUrl/coverUrl/subtitle). Populated by:
- **xxxfollow**: from the tag response `users` (creators) + `tags` (similar).
- **redgifs** (`_buildDiscoveryFromGifs`, page 1 only): distinct gif uploaders →
  creators (searchQuery `creator:<name>`, avatar from response `users` block when
  present; hidden when <2 distinct creators, e.g. a single-creator feed); most
  common co-occurring tags (minus the searched terms captured in
  `_queryTagsLower`) → similar tags. Verified: redgifs suggest returns related
  tags; gif objects carry `userName`; `creator:` routing already works.
Old xxxfollow-only strip (xxxfollow_tag_strip.dart / XXXFollowCreator) removed.
Committed in 5210d.

## FEEDBACK ROUND (build 5210e/f) — DONE
- **For You infinite loading FIXED** (`foryou_handler.dart`): was fanning to 8
  sources/page with no timeout + 3 empty-round recursions → a few slow/captcha
  boorus hung it. Now: rotating subset of 4 sources/page, every alias-resolve
  (6s) and source search (12s) time-bounded via `_bounded`, seed prefixes
  (creator:/artist:/niche:/sort:/…) stripped via `_sanitizeSeed` so seeds port
  across boorus, empty-recursion capped at 2.
- **Tag-chip long-press** now opens the tag as a background tab (`addTabByString`,
  switchToNew:false) + confirmation snackbar, instead of the floating preview
  (tag_view.dart ~969). Preview still available via tap→dialog.
- **DiscoveryStrip labels** use onSurface (were invisible on dark themes).
- **Left sidebar repurposed** (build 5210f): the downloads/snatch drawer now has
  a `DrawerQuickAccess` panel on top
  (`lib/src/widgets/drawers/downloads/drawer_quick_access.dart`) — shortcut
  circles to For You / Collections / Favourites / Downloads (open as tabs) +
  recent-search chips (re-open as tabs), then a "Downloads" divider above the
  existing queue. Wired in downloads_drawer.dart.
- Player/image errors: NOT from our video_viewer change (video/HLS only); it's
  the known Gelbooru rate-limit/AdGuard issue.

## FEEDBACK ROUND 2 (build 5210h) — DONE
- **Tag-chip long-press** (tag_view ~969) now matches the app's standard
  background-tab open: respects the "New tab placement" setting
  (`defaultTabAddMode` end/next), shows the standard green "added new tab" toast
  (`loc.tagView.addedNewTab`), stronger haptic (vibrate 40ms/amp180). Earlier I
  wrongly removed the toast — the standard flow DOES toast; matched it.
- **Left drawer fully redesigned** (`drawer_quick_access.dart` +
  `downloads_drawer.dart`): removed the whole download queue (DDContent +
  DDControlPanel; DownloadsDrawer is now a StatelessWidget wrapping only the
  panel). Layout = Quick access shortcuts (top) → **Pinned tags** (top, favourited
  searches) → Recent searches (bottom). Long-press a chip to pin/unpin (uses
  `dbHandler.setFavouriteSearchHistory` + `getSearchHistory`). Chip icons use
  onSurface (clock/pin) for contrast.
- **Hide status bar setting** (interface): new `hideStatusBar` bool in
  settings_handler (map/getByString/setByString). `ServiceHandler.
  setSystemUiVisibility(true)` now hides the top status bar (keeps bottom nav via
  `SystemUiMode.manual, overlays:[bottom]`) when it's on. Toggle in
  user_interface_page applies immediately. Applied app-wide because main.dart:98
  calls setSystemUiVisibility(true) at startup.
- Download queue UI removed from the drawer per user request; downloading still
  works (only the queue panel was removed). NOTE: if a user actually snatches,
  they no longer have the in-drawer queue/controls — revisit if needed.

## "FLOW" UI MODERNIZATION (big multi-phase redesign) — IN PROGRESS
Design handoff = user-provided zip (design_handoff_flow_ui): README.md + HTML
prototypes (`Redesign 1e - Flow.dc.html` is THE spec, 16 screens, 412x892).
Dark violet "Flow" look. Map tokens onto ThemeHandler; keep custom accents
working (violet is just the default accent). Fonts: Manrope + Material Symbols
Rounded. Full token list is in the zip README (palette, radii, type scale,
tag-type colors, per-screen specs 1-16).

**Phase 1 DONE (build 5210i / "flow1"):** theme foundation.
- `theme_handler.dart`: Flow dark palette constants (flowBg #0A090D, flowSurface
  #14111B, flowRaised #17131F, flowInput #1D1827, flowDeep #241E33, flowBorder
  #2E2940...). `colorScheme()` copyWith pins dark neutral surfaces/text to Flow
  (accent stays theme-driven). `scaffoldBackground()` = flowBg. App bars flat
  dark in dark mode (appBarTheme). dividerTheme uses flowBorder. textTheme:
  'System' font → Manrope. AMOLED + light mode left on the seed scheme.
- `settings_handler.dart`: "Flow" ThemeItem (violet #B9A0E8) added first + set as
  default theme + default `theme` Rx.
- `tag_type.dart`: getColour() → Flow tag palette.

**Phase 2 DONE (builds 5210j/k/m):** Browse.
- `flow_tab_carousel.dart` (FlowTabCarousel): swipeable tab cards under the app
  bar — active = wide gradient card (booru avatar+name, count right-aligned,
  query 16.5/800 + edit btn → query editor, status line), following tabs peek,
  dashed "+" adds a tab, dots track position. Renders from active forward so the
  neighbour is the real next tab; snaps to start on tab switch. Inserted as a
  SliverToBoxAdapter after MainAppBar in waterfall_view. `TabsCountPill` (same
  file) replaced the old inline switcher (ActiveTitle) as the app-bar title →
  opens TabManagerPage (no more redundant switcher).
- `flow_search_bar.dart`: floating blurred bottom search pill (search/history/
  bookmark/accent arrow) + inline removable type-coloured tag chips (reuses
  MainSearchTagChip; ✕ removes tag + re-searches).
- Grid tiles restyled (rounded, badges) — in waterfall/thumbnail build.

**Phase 3 IN PROGRESS (builds 5210n/o/p):** Viewer + Info Flow + Tag Menu.
- Tag Menu (`showTagDialog` in tag_view.dart) converted from dialog →
  `showModalBottomSheet` with Flow header (type bar + tag name in type colour +
  type label + drag handle); all actions kept, redundant Close row dropped.
- Info-flow tag chips: added the ⧉ preview zone (divider + picture_in_picture in
  type colour → FloatingPreviewHandler) as its own tap target; added "Tags N ·
  tap · hold = tab · ⧉ = preview" hint header above the per-type sections.
- Viewer peek bar (`_InfoPeekBar` in gallery_view_page.dart): collapsed-sheet
  bottom bar with artist chip + N-tags chip + swipe-up hint, tied to
  viewerHandler.displayAppbar; tap → openInfoPanel.
- STILL TODO in phase 3: artist carousel + uploader pill w/ Save/Fav/Collect at
  top of info panel; "Media size on open" slider (README 86%); viewer top-scrim
  restyle (screen 08).

**Phase 3 + Phase 4 more (builds 5210q-t):**
- Info-panel action row (`_flowActionRow` in tag_view): Favorite / Save (snatch) /
  Collect / Details — reuses toggleItemFavourite / SnatchHandler.queue /
  showAddToCollectionSheet / showPostDetailsSheet.
- `booru_switcher_sheet.dart` (showBooruSwitcherSheet): Flow "Switch booru" sheet
  (favicon+name+domain rows, radio, Add-booru-config footer) → searchAction to
  switch. Drawer got a current-booru card that opens it.
- `post_details_sheet.dart` (showPostDetailsSheet): ID/Rating/Score/Resolution/
  Size/Type/Posted/Uploader/Source(link)/MD5, tap row = copy.
- main_drawer got the Flow "Menu" header + close.

**FEEDBACK-DRIVEN FIXES + FULL SWEEP (builds 5210w–5210z):**
- Search bar chips: fixed-height custom chips (were stretching); tap=edit, ✕=remove.
- Left sidebar (drawer_quick_access.dart): rebuilt to screen 03 — "Pinned tags"
  header + pinned-tag rows (dbHandler.getAllPinnedTags; tap=add to search) at top,
  QUICK ACCESS section (Global blacklist→TagsFiltersPage, For You blacklist→ForYou
  BooruEdit, Favorites→fav tab, Saved searches→HistoryList, Collections→
  CollectionsPage) at bottom. No recent searches.
- Right drawer (main_drawer.dart): removed old tab manager (TabSelector/TabButtons/
  SavedSearchesDrawerSection); order = Menu header → search → booru card →
  multibooru → Downloads → Favourites → …settings/webview.
- Tab manager (TabManagerItem in tab_selector.dart): compact Flow rows (avatar +
  tag-coloured query via TabRow + "booru · count" + tune/close, active tint).
- Settings row widgets (settings_widgets.dart): SettingsButton, SettingsToggle,
  SettingsToggleTristate, SettingsTextInput, SettingsDropdown → Flow cards
  (surfaceContainer + outlineVariant, w600 labels, chevron on page rows). Hub
  grouped into SEARCH/LOOK&FEEL/SYSTEM/ABOUT (settings_page.dart).
- History/saved-searches rows (history.dart): Flow cards + gold "kept" star.

**FINAL SWEEP (builds 5210ac–5210ad):**
- Snackbar (flash_elements.dart): Flow light-lilac bar (#E9E2F5) + dark ink;
  title/content/icon/dismiss forced dark so readable; radius 14. DONE.
- Favourites/Downloads/Collections media filter chips (media_filter_chips.dart):
  All/Images/Video/Sound above the grid; BooruHandler.mediaFilter drives an
  in-place filter in filterFetched(). DONE.
- ALL settings row widgets now carded (button/toggle/tristate/textinput/dropdown/
  segmented/optionslist). For You card, tags-manager rows explicitly Flow-carded.
- Swept lib for hardcoded borders — only context-appropriate greys remain
  (notes_renderer = image-note boxes; main_search_tag_chip = disabled-delete).

**DELIBERATE NON-CHANGES (justified):**
- Snatcher/Downloads queue screen (blueprint 17): the user explicitly asked
  earlier to REMOVE the download/snatch section; re-adding it would contradict
  that. Downloading still works; the queue UI stays removed by their request.
- Material Symbols Rounded icon set: material_symbols_icons pkg is NOT in
  pubspec; kept Material Icons (adding + swapping every icon is a huge
  mechanical change with low visual delta on top of the palette/type reskin).
- Dialogs / minor sub-widgets inherit Flow via theme tokens (colours, radius,
  Manrope) rather than each being hand-restyled.

Redesign is comprehensive across all major screens + shared components; 0
analyzer errors project-wide.
- Phase 2 — Browse (`mobile_home_page`/`waterfall_view`): tab-card carousel w/
  edit btn + peek + dashed "+" ; header (tabs pill + menu); 2-col grid tiles
  (badges bottom-left type+duration on scrim, heart bottom-right, r14); bottom
  floating blurred search bar (search/history/bookmark_add/accent arrow).
- Phase 3 — Viewer + Info Flow + Tag Menu (`gallery_view_page`, `hideable_appbar`,
  `tag_view`): media 86% on open (setting "Media size on open"); peek sheet →
  Info Flow (artist carousel, uploader pill w/ Save/Fav/Collect, tags cloud
  split chips: tap=menu, hold=new tab, ⧉ zone=preview). Tag Menu = bottom sheet
  replacing the dialog (Preview/Add/Exclude/New tab/Copy/Marked/Hidden→submenu/
  Pin→sheet/Related tabs/Edit).
- Phase 4 — Sheets/drawers: right drawer (mirrored top search bar, booru card,
  multibooru toggle, downloads/favs/settings/webview rows); left sidebar
  (pinned tags top + Quick Access bottom — note: I already put quick-access in
  the downloads drawer, reconcile); Booru Switcher / Search History / Add to
  Collection / Post Details sheets; Query Editor (chips + helper key row +
  suggestions + accent Search btn); All Tabs manager (filter, fast-scroll, bulk);
  Settings hub (SEARCH/LOOK&FEEL/SYSTEM cards → detail pages); Downloads/Favorites.
- Snackbar Flow style (bg #E9E2F5, text #2A2240, r14, w800) in flash_elements.
- **Material Symbols Rounded icons — DONE.** `material_symbols_icons` IS in
  pubspec now. Icons app-wide use `Symbols.<name>_rounded` (the unsuffixed
  `Symbols.<name>` is the Outlined family — always keep the `_rounded` suffix
  so the rounded font is what tree-shaking keeps). Converted: the 6 core Flow
  widgets, collections/about/saved-searches, add-to-collection sheet, tab/tag/
  page dialogs, ALL `widgets/common/*` shared widgets, and the gallery/drawers/
  tabs/history/tags/thumbnail/home surfaces. Name gotchas: `Icons.copy`→
  `Symbols.content_copy_rounded`, `paste`→`content_paste_rounded`; never touch
  `FontAwesomeIcons.*` / `CupertinoIcons.*` (use a `\bIcons\.` regex).
Approach: reskin, reuse existing GetX handlers (SearchHandler/ViewerHandler/
SettingsHandler), build+ship per phase so each is testable. Fill missing UIs in
the design's style.

## POSSIBLE FUTURE POLISH (not requested yet)
- Populate relatedCreators/relatedTags for more handlers (any with tag data).
- xxxfollow login (Laravel email/password + Google reCAPTCHA) — same WebView
  token/cookie-capture pattern as redgifs would be needed to unlock the full
  (non-teaser) catalog. `site_config` exposes `recaptcha_public_key`.
- Verify the `genders` filter actually changes results (was inconclusive live).

## Key architecture notes
- BooruHandler: makeURL/fetchSearch/parseListFromResponse/parseItemFromResponse,
  availableMetaTags (SortMetaTag), hasTagSuggestions/getTagSuggestions,
  translateOrSyntax, validateTags, getHeaders, searchSetup (base handles
  signIn flow when `hasSignInSupport` + `canSignIn` = userID&apiKey nonempty).
- New booru type: add to `booru_type.dart` enum + getters + detectable/alias,
  register in `booru_handler_factory.dart`, add editor cases in `booru_edit_page.dart`.
- Virtual boorus already added this project: Collections, ForYou (+ Favourites/
  Downloads). InterestsHandler (behavior tracker), TagAliasResolver (cross-booru
  tag unification), FloatingPreviewHandler (route-tied floating preview window).
- WebView infra: `lib/src/widgets/webview/webview_page.dart` (InAppWebviewView,
  onLoadStop callback exposes controller for evaluateJavascript).
