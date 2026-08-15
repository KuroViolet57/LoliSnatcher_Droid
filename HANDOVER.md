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

## ═══ OPTIMIZATION MARATHON (2026-08-07, branch claude/experimental-megabuild) ═══
Ongoing perf pass. Every major chunk = its own build/APK for fallback. Codenames
below are `Constants.buildCodename`; APKs uploaded to Drive per the usual scheme.

### Network — shared pooled HttpClient (codename `net-pool`)
- `DioNetwork.getClient()` used to build a fresh `Dio`+`HttpClient` per request
  and every caller did `client.close()` after — destroying TCP keep-alive AND
  the TLS session, so each request paid a full handshake (brutal on slow boorus
  like rule34hentai, verified ~2s/query server-side + handshake on top).
- Now a single app-lifetime `DioNetwork.sharedHttpClient` (idleTimeout 20s,
  maxConnectionsPerHost 8, badCertificateCallback reads the live
  allowSelfSignedCerts setting). Every Dio's IOHttpClientAdapter returns it via
  `createHttpClient: () => sharedHttpClient`. **CRITICAL INVARIANT: never call
  `.close()` on any Dio from getClient()** — the adapter's close() closes the
  shared client for everyone. Removed all client.close() in dio_network.dart
  (get/post/head/download/stream), custom_network_image.dart (:179), and
  dio_downloader.dart (dispose now cancels via cancelToken, 4 post-request
  closes removed). dio 5.9.2 has NO `closeOnDispose` param.

### DB indexes (same build)
- `createCriticalIndexes()` runs on every DB open (in initDB, NOT gated by the
  heavy-index toggle): BooruItem(postURL), Tag(name), PinnedTag(tagName),
  ViewedPost(viewedAt), SeenPost(viewedAt). These columns were linearly
  scanned on hot paths (dedup/favourite lookup per item, tag colour/type
  resolution, pin scoping, history ordering).

### rule34hentai server reality (investigated live w/ user's cookies)
- Origin genuinely slow: list/search pages ~1.8–2.5s TTFB sustained, no caching.
  500s are load-dependent origin timeouts. Media (thumbs/videos) served fast via
  CDN (~0.35s). Cloudflare challenges target mobile-carrier IP ranges; cf_clearance
  is IP-bound so carrier IP rotation = frequent re-challenge. Nothing app-side
  fixes the slowness; the auto-captcha/probe/soft-refresh machinery is the mitigation.

### Auto-captcha stuck-flag fix (earlier build `group-heal`)
- `Tools.checkForCaptcha` set `captchaScreenActive=true` before pushing the
  webview and only reset it AFTER a normal return. A challenge at app startup
  (navigator not ready) threw → flag stuck true → ALL auto-captcha disabled for
  the session. Now reset in a `finally`.

### Tab groups (recap of the group system for future work)
- `SearchTab.groupName` (persisted in TabBackup as `g`). `addTabByString` takes
  `group:` (String | SearchHandler.inheritGroup sentinel | null). Insertion uses
  `_snapInsertionIndex` so a tab never splits a foreign group's contiguous block.
  `compactGroupBlocks()` heals pre-existing splits (runs on restoreTabs + tab
  manager open). Tab manager: `displayTabs` getter hides collapsed-group members
  (reorder disabled while any group collapsed so display==real indices). Group
  picker = `pickTabGroupName(context, allowOutside:)` returning group name /
  kOpenOutsideGroupSentinel / null.

### TODO / next optimization targets (not yet done)
- Video player pools (media_kit `_MediaKitPlayerPool`, better_player
  `_BetterPlayerPool`): review eviction + preload counts.
- Thumbnail pipeline: ResizeImage cache dimensions, decode sizing.
- Grid: RepaintBoundary coverage, const-ness, ListView cacheExtent.
- Dead code sweep (commented-out proxy/http2 block in dio_network already
  removed; look for more).

### Investigated — already optimal (don't redo)
- Grid rendering (waterfall_view/grid_builder/staggered_builder): already
  addRepaintBoundaries:false + per-card RepaintBoundary, addAutomaticKeepAlives:
  false, cacheExtent set. Good.
- Thumbnail decode: ResizeImage to constraints×devicePixelRatio, allowUpscaling
  false, ResizeImagePolicy.fit. Decodes at display size. Good.
- TagHandler.getTag: O(1) map lookup. Fine.
- `flutter analyze` project-wide: essentially zero dead code (2 trivial style
  infos in xxxfollow_handler / foryou_page). Codebase is well-maintained.
- Removed the old commented-out proxy/http2 block from getClient during the
  shared-client rewrite.
Conclusion of this pass: the two high-value wins were the shared pooled
HttpClient (net) and the critical DB indexes. Further gains would be marginal
and риск-prone; left video pools / interests as future targets only if profiling
shows a real hotspot.

## Build `open-from` (2026-08-07)
- Group picker sheet (`pickTabGroupName`, tag_view.dart): "Outside group"
  quick action is now ALWAYS the first tile; new "Open from" tile below it
  (returns `kOpenFromSentinel`, a `'\0open-from'` string like the outside
  sentinel — note the NUL byte, it makes grep call the file binary).
  "Open from" creates/joins group `from__{tag}` (spaces→underscores) via the
  normal `addTabByString(group:)` path, so tab-placement settings are
  honored and the group lands next to the current tab like any new group.
- Tab manager collapsed-group swipe freeze FIXED (tab_selector.dart):
  `displayTabs` was a getter rebuilding the whole list per call, and
  `rowExtentForIndex`/`offsetForTabIndex` called it per index inside
  `itemExtentBuilder` layout → O(N²) per scroll frame whenever a group was
  collapsed (the `_collapsedGroups.isEmpty` fast path is why expanded state
  was fine). Now: `_ensureDisplayCache()` builds display list + per-row
  extents + prefix offsets in ONE O(n) pass; all queries are O(1) cache
  reads; cache invalidated at the top of the State's `build()` (every data
  change goes through setState/Obx, so layout never reads stale data).
  Helpers `_groupOfDisplayRow`/`_isDisplayRunStart` were folded into the
  cache pass and removed.

## Build `vid-boost` (2026-08-07) — media_kit player fixes + feature
- Fullscreen no longer allocates a NEW VideoController per entry (was a
  platform-texture leak living until the pooled player died). The pooled
  controller is passed through `_MediaKitControls.controller` into
  `_FullscreenMediaKit` (now Stateless). Sharing one controller between the
  page Video and the fullscreen Video is fine — same textureId.
- `isFullscreen` flag on `_MediaKitControls`: the instance inside the
  fullscreen route always POPS on the fullscreen button (its local
  `_fullscreen` starts false, so it previously stacked a second fullscreen
  route) and shows the exit icon.
- Unmute restores `_lastNonZeroVolume` (tracked from bind + volume stream)
  instead of forcing 100.
- Long-press 2× speed: hold anywhere → `setRate(2)` + medium haptic + top
  "2×" chip; release/cancel → rate 1. Rate is PLAYER state and pooled
  players stay warm, so 1× is restored on release, on player swap in
  didUpdateWidget, and in dispose. Only engages while `_playing`.

## Build `find-elsewhere` (2026-08-07) — cross-booru MD5 lookup
- New file lib/src/widgets/gallery/find_elsewhere_sheet.dart:
  `showFindElsewhereSheet(context, item, sourceBooru)` + `md5ForItem(item)`
  (validated md5String, else 32-hex regex from file/sample/thumb URL —
  most boorus name files by MD5).
- Entry point: "Find this post elsewhere" ListTile in TagView, right under
  the "From {booru}" source row; only shown when an MD5 is extractable.
- Queries ALL configured boorus with MD5 search support in parallel
  (throwaway SearchTab per booru, storeTagsGlobally=false, 15s timeout,
  reads raw `fetched` so the user's hide-filters can't mask a hit).
  Excluded: the source booru itself (host-matched vs baseURL/postURL so
  virtual feeds exclude the true origin, not the feed).
- Per-type metatag in `_md5QueryFor`: shimmie family (Shimmie, R34Hentai)
  uses `hash=<md5>`; danbooru/gelbooru/moebooru/e621/sankaku/etc use
  `md5:<md5>`; types with no MD5 lookup (philomena, szurubooru, hydrus,
  nozomi, redgifs, xxxtik/xxxfollow, civitai, inkbunny...) are skipped
  entirely rather than shown as misleading "not found".
- Row shows favicon + found/not-found/error(tap to retry), subtitle with
  "{W}×{H} · higher/lower res · N tags (+diff)" vs the viewed copy (5%
  pixel-count tolerance before claiming higher/lower).
- Tapping a hit: addTabByString('md5:...'/'hash=...', customBooru,
  switchToNew: true, group: inheritGroup) → lands in the current tab group,
  snackbar reminds the tab is behind the viewer.

## Build `iqdb` (2026-08-07) — similarity search in the find-elsewhere sheet
- "Similarity search (IQDB)" section at the bottom of the find-elsewhere
  sheet (find_elsewhere_sheet.dart). Tap-to-run (never automatic — IQDB is
  slow + rate-limited per IP, 1 concurrent query).
- Flow: download sample (video→thumbnail) with booru headers → multipart
  upload to https://iqdb.org/ (field `file`, MAX_FILE_SIZE) → parse HTML.
- IQDB STREAMS the response: under load it holds the connection open
  emitting queue()-keep-alive script chunks until the result arrives —
  timeout is 4 MINUTES on purpose. No receiveTimeout on the shared client,
  so only our .timeout() applies.
- Parser (validated against live captures + synthesized result page):
  tables under #pages + #more1 (collapsed "possible" matches); skip tables
  without "% similarity" (the "Your image" one); td.image a href
  (protocol-relative → https:), thumb src → https://iqdb.org prefix, dims
  regex, [Rating]. div.err (e.g. "Can't read query result! Please try
  again.", per-IP 1-query limit) → thrown as retryable ERROR, never a
  false "no matches".
- Match tap: if host matches a configured booru AND an id is extractable
  (`[?&]id=` / `/post(s)?(/show)?/<id>` — covers danbooru/gelbooru/
  moebooru/sankaku), open `id:<n>` tab in current group + switchToNew;
  else external browser via launchUrlString.
- NOTE from testing: this container's datacenter IP got "content not
  available in your country"/504 on the ?url= variant and repeated
  backend errs on upload — could NOT capture a live success page from
  here; phone IPs should behave better. If users report persistent
  errors, consider SauceNAO with API key as alternative.

## Build `true-match` (2026-08-07) — find-elsewhere honesty fixes
- USER REPORT: MD5 lookup "always returns nothing" (their library is
  heavily 3D/video from rule34hentai — cross-site copies are re-encoded,
  so byte-identical MD5 hits are genuinely rare for that content; feature
  works for danbooru↔gelbooru↔r34.xxx mirrored art). rule34.xyz always
  "matched" = FALSE POSITIVE: its POST search API ignores the unknown
  md5: token and returns the normal listing; first-result-exists was read
  as a hit.
- FIX: hit verification in _lookup — accept only if md5ForItem(hit) ==
  query md5, or (no hash exposed on the hit) fetched.length == 1. Kills
  the ignored-metatag false-positive class for ALL boorus.
- IQDB: matches < 80% similarity (IQDB's own relevance bar) now hidden
  behind a "Show N low-confidence matches" expander; headline tile says
  "No confident IQDB matches" when only noise came back.
- New "Reverse search in browser" chip row (Yandex / Google Lens /
  SauceNAO) opening the engine with the sample/thumb URL prefilled —
  Yandex especially has the broadest repost coverage for this content.
- Alternatives assessment for the user: no public reverse index covers
  western/3D/video booru content (IQDB/SauceNAO/ascii2d = anime art,
  fluffle = furry, trace.moe = anime screenshots). The practical
  alternative is metadata pivots: artist/character-tag searches + source
  URL matching across boorus — proposed, not yet built.

## Build `related-pivot` (2026-08-07) — metadata pivot + browser handoff fix
- "Related elsewhere — artist/character/tag: {pivot}" section in the
  find-elsewhere sheet, auto-runs on open. Pivot priority: artist >
  character > copyright (first non-empty tag of that type on the item);
  hidden when none. Candidates: ALL real boorus (not just md5-capable;
  virtual types + source booru excluded by host).
- Per booru: TagAliasResolver.resolveQuery translates the pivot's spelling
  (15s timeout, falls back to literal), throwaway SearchTab search (15s),
  then searchCount when the handler didn't set totalCount. Row subtitle:
  '154 posts', '20+ posts' (page full, no total), '· as "resolved_tag"'
  when the spelling differs. Tap -> addTabByString(resolved, customBooru,
  switchToNew, inheritGroup).
- Browser reverse-search fix (user: "Yandex/Lens open but no image
  passed"): externalApplication let native apps (Google app for
  lens.google.com) deep-link-capture the URL and drop ?url= params. Now
  _launchExternal tries LaunchMode.inAppBrowserView (Custom Tab, loads the
  literal URL) with externalApplication fallback; Google switched from
  lens.google.com/uploadbyurl to www.google.com/searchbyimage?image_url=
  (the endpoint reverse-search extensions use; redirects into Lens with
  the image attached).
- Sheet header zero-case retitled "No exact copies found" (related section
  may still have hits below).

## Build `pivot-fix` (2026-08-08) — MD5 removed, pivot picker added
- USER: related section invisible (recording: shimmie 3D post) + "remove
  the md5 check, I won't use it". Root cause of invisibility: shimmie-type
  boorus report NO tag types, so the artist>character>copyright auto-pivot
  found nothing and the section self-hid.
- find_elsewhere_sheet.dart REWRITTEN: all MD5 machinery deleted
  (md5ForItem, _md5QueryFor, _LookupResult rows, verification). Sheet is
  now: Related elsewhere + IQDB + browser chips. tag_view entry tile no
  longer gated on md5 presence (always shown).
- Untyped boorus: section shows "Pick a tag to search elsewhere" tile →
  AlertDialog listing ALL the post's tags (typed first: artist>character>
  copyright>species>general>meta, then alphabetical) → picking one runs
  the lookups. Section header row = pivot switcher (tap to re-pick, edit
  icon). _lookupRelated guards against stale runs (pivot changed while a
  15s lookup was in flight) via runPivot capture.
- Sheet header: 'Find elsewhere' (no pivot yet) / 'Searching…' / 'Related
  on N boorus' / 'Nothing related found'.

## Build `typed-pivot` (2026-08-08)
- USER (screenshot): the info sheet showed Artist: sfmpov etc. for the
  same shimmie post whose related-pivot claimed "no types" — the APP's
  global tag store (TagHandler) knows the types even when the booru sends
  none; TagView's grouping uses tagHandler.getTag(name).tagType.
- find_elsewhere_sheet: `_typeOf(tag)` = tag's own type, else
  TagHandler.instance.getTag(name).tagType. Used by auto-pivot, picker
  sort, picker subtitles, picked-type. Auto-pivot now fires on shimmie
  posts (e.g. artist sfmpov auto-selected); manual picker remains the
  fallback for truly unknown tags.

## Build `smart-seed` (2026-08-08) — rule34.xyz suggestion research applied
RESEARCH (live API probing, scratchpad r34xyz_*/sugg*.json):
- rule34.xyz post-page suggestions = GET /api/v2/post/suggestion/{id}
  (anonymous OK, returns 30 posts w/ full tags incl. per-tag counts).
- ALGORITHM (verified on 2 posts, 30/30 both): candidate pool = SAME
  UPLOADER as the source post; ranked ~by shared-tag count with the
  source (mild shuffle/diversity, not strictly monotonic, not IDF-exact).
  Feels "perfect" because xyz uploaders are creators/single-artist
  reposters → same-creator + same-theme. Degrades to "imported around
  the same time" for the bulk-import account (uploader 2).
- Other endpoints found in the new UI bundle: tag/related/{tag},
  post/search/hot/, post/search/tag-subscriptions/, playlist APIs.
APPLIED to the app ("Recommend more like this" seed, _buildRelatedQuery
in tag_view.dart):
- Tag types now resolve through TagHandler store (same bug as the pivot:
  raw t.tagType is none on shimmie → char/artist/copyright picks always
  failed → fell back to '3d, blender'-style junk seeds. This was the
  user-visible "Recommend more like this: 3d, blender" screenshot).
- 'tagme' skipped everywhere.
- Untyped fallback picks the most DISTINCTIVE general tags: megaTags
  stoplist (3d/blender/animated/sound/video/1girls/...), then sort by
  Tag.count ascending when the handler reports counts (worldxyz does),
  else specificity heuristic (parenthesized/underscored/longer names).
- The "same creator" pool already exists in-app: inline 'More from
  artist' grids (store-typed) + uploader grid when handler exposes
  UserMetaTag + name. NOT re-implemented.
- NOT done (possible future): re-rank related-strip items by tag overlap
  with the source post (xyz's ordering); For You creator-clustered seeds.

## Build `rank-like` (2026-08-08) — similarity re-ranking of related strips
- NEW lib/src/utils/post_similarity.dart:
  `postSimilarityScore(candidate, source)` = sum over SHARED tags of
  typeWeight * rarityWeight. typeWeight artist 6 / character 5 /
  copyright 3 / species 2 / general 1 / meta 0.3; rarityWeight =
  log10(2e6/count) clamped [0.2,4] when the handler reports Tag.count,
  else 1; untyped tags in `kGenericMediumTags` capped at 0.15.
  `rankBySimilarity(items, source, {from})` = stable (decorate-sort with
  index tiebreak) reorder + drops the source post itself. `from` pins
  already-visible items so pagination never reshuffles under the thumb.
  `normalizeTagName` handles space-vs-underscore spelling across boorus.
- TagContentPreview gained `rankAgainst` (BooruItem?): after each
  search() the newly fetched slice is ranked and `filteredFetched.value`
  is REASSIGNED (never .refresh() — protected member; and in-place
  mutation doesn't notify). `_rankedUpTo` watermark resets on refresh.
- Wired: "Related" strip, "More from artist" and "More from uploader"
  grids all pass `rankAgainst: item`.
- InterestsHandler.seedTagsFromItem got the same store-type fix as
  _buildRelatedQuery (this was the actual source of the user's
  "Recommend more like this: 3d, blender" screenshot) + rarest-first
  distinctive fallback via kGenericMediumTags.
- VALIDATION: replayed the scorer over the captured xyz suggestion data
  (scratchpad sugg.json/src_post.json): Spearman 0.47 vs xyz's own order,
  with character/copyright-sharing posts promoted to the top — i.e.
  aligned with xyz but sharper (xyz ranks on raw shared-tag count).

## Build `blend` (2026-08-08) — recommendation system REBUILT (facet blend)
USER VERDICT on the previous approach: scrap it. "More from artist,
reordered" is pointless; picking artist+character just reproduces Tag Hub;
they want VARIED suggestions (different character same franchise, other
artists, similar style, act tags), nothing dominating.

RESEARCH REDONE PROPERLY (24 posts, 12 modern; scratchpad dataset.json).
The earlier "all suggestions share the uploader" claim was an artifact of
sampling two 2016 bulk-import posts (uploader 2). Real numbers for modern
posts, per 30-suggestion set:
  ~17 distinct artists, ~26 distinct characters, median max 7 posts from
  any one artist. Facet split: 34% share the artist, 44% share a character
  (different artist), 6% only the franchise, 16% share NONE of those
  (matched on body/act/style tags). Artist-overlap median across all
  sampled posts: 3%.
=> Suggestions are SEVERAL DIFFERENT QUERIES blended, not one ranked list.

NEW lib/src/handlers/suggestion_engine.dart:
- `facetsForItem(item, seed:)` → facets: character (quota 6, +4 for a 2nd
  character), franchise (5, excludeCharacters=true → different character,
  same franchise), artist (4 — deliberately small), act ×2 (4 each, from
  rarest distinctive general tags), style (4, `<medium> <actTag>` e.g.
  "3d mating_press" → same style, other artists). `seed` rotates which
  character/act is used per page so scrolling brings new material.
- `blend(byFacet, source:, exclude:, limit:)` → round-robin one item per
  facet, enforcing facet quotas + maxPerArtist 4 + maxPerCharacter 6,
  dedupe, drops the source post. Franchise facet filters source
  characters CLIENT-SIDE (not `-tag`, which not all boorus support).
NEW lib/src/boorus/suggestion_handler.dart: BooruHandler subclass running
all facets in parallel per page (12s search / 6s resolve budgets), blending
into afterParseResponse. `targetBoorus` >1 = cross-booru mode with
TagAliasResolver per-site spelling translation.
SearchTab gained `customHandler:` so a strip can host a virtual handler.

WIRING:
- tag_view: "Related" → "Suggested" strip (TagContentPreview.suggestFor).
  _buildRelatedQuery + _relatedQueryCache DELETED.
- "More from artist"/"More from uploader": rankAgainst REMOVED — back to
  plain chronological, as requested.
- find_elsewhere_sheet: pivot-tag list replaced by a cross-booru blended
  strip (suggestFor + suggestBoorus = all other real boorus). IQDB +
  browser chips kept below.
- foryou_handler: profile mode now `_searchBlended` — 3 recently viewed
  posts (dbHandler.getViewedPosts) × 3 facets each, fanned across source
  boorus, blended. Explicit seed mode (seed:/plain tags) keeps the old
  path untouched.
- post_similarity.dart trimmed to shared vocabulary (kGenericMediumTags,
  normalizeTagName, tagRelevanceWeight); rankBySimilarity/
  postSimilarityScore deleted with the approach that used them.

KNOWN LIMITATION (verified live): rule34.xyz's search API returns items
WITHOUT tags, so on that booru the per-artist/per-character caps have
nothing to read and can't fire — variety there comes from the facet
quotas alone. Gelbooru/danbooru-style APIs do return tags, so caps work.

## Build `bakemono` (2026-08-10) — URL parsing fix (bakemono.app support)
USER: bakemono.app couldn't be added; autodetect picked Nozomi, manual
Gelbooru options also returned nothing. Site docs (bakemono.app/booru)
say: type "Gelbooru (0.2 / gelbooru-compatible)", URL https://bakemono.app,
no API key. Endpoints: index.php?page=dapi&s=post&q=index (XML, &json=1
for JSON), tag dapi, autocomplete.php?q=. Tags are creator names.
ROOT CAUSE (found in talker log, verified live): NOT a site problem — the
dapi endpoint returns valid XML. `Tools.getFileExt` searched the WHOLE url
for the last '.', but bakemono file URLs are
`/data/xx/yy/<sha256>.jpeg?f=cover.jpeg` — the last dot sits INSIDE the
query, so substring(start=110, end=101) threw
`RangeError (end): Invalid value: Not in inclusive range 110..114: 101`
(reproduced exactly). BooruItem's constructor calls getFileExt, so EVERY
post threw; booru_handler.dart:344 catches per-item and logs, so all posts
were silently dropped -> 0 results -> autodetect scored the site as a
failure and fell through to Nozomi.
FIX:
- Tools.getFileExt / getFileName now operate on the PATH only (new
  `_pathPart` strips ?query and #fragment). getFileExt also returns ''
  when the last dot precedes the last slash (no real extension) instead
  of returning host/path garbage. Regression-checked against gelbooru /
  danbooru / rule34.xxx (?4567 suffix) / rule34hentai / e621 URL shapes —
  all unchanged.
- BooruItem: aspect ratios only computed when BOTH dimensions are > 0.
  bakemono reports width="0" height="0", and 0/0 = NaN was flowing into
  thumbnail layout (thumbnail.dart:206) as a NaN aspect ratio.

## Build `bakemono2` (2026-08-10) — autodetect no longer falls back to Nozomi
FOLLOW-UP log (58e50bf6) after the `bakemono` build: the URL-parsing fix
WORKED — the booru test now logs "Found Results as BooruType.Gelbooru"
for bakemono.app. But the user's SAVED booru entry was still typed Nozomi
from the earlier bad autodetect, so the tab kept loading nozomi.la:
every "Added N tags to queue from bakemono" was paired with fetches to
j./w./qtn.gold-usergeneratedcontent.net (NozomiHandler's HARDCODED hosts,
lines 17-21) and zero requests ever went to bakemono.app/data.
ROOT CAUSE of the mis-detection: NozomiHandler (and RedGifsHandler)
ignore booru.baseURL entirely and always hit their own fixed hosts, so
they "succeed" against ANY entered URL. They were still in
BooruType.detectable, making Nozomi a silent catch-all: any site that
failed the other probes got detected as Nozomi and then served nozomi.la
content under the user's site name.
FIX: removed BooruType.Nozomi and BooruType.RedGifs from `detectable`
(same treatment already applied to XXXTik / XXXFollow / Civitai, which
are also fixed-host). Both remain manually selectable (`saveable`).
USER ACTION still required for an already-saved wrong entry: edit the
booru, set type to Gelbooru, save (the stored type doesn't change by
itself).

## Build `booru-swap` (2026-08-10) — editing a booru now affects OPEN tabs
USER: "I already swapped bakemono from Nozomi to Gelbooru and it didn't
change anything."
ROOT CAUSE (real bug, independent of bakemono): `SearchTab.booruHandler`
was `late final`, built ONCE in the constructor from the booru's type,
and the tab also holds a reference to the Booru OBJECT that was in
booruList at creation time. Editing a booru replaces the list entry with
a NEW Booru object and rewrites its json — but NOTHING re-pointed open
tabs. So a type swap left every open tab on the old handler indefinitely;
for a fixed-host handler like Nozomi that means the tab silently keeps
loading nozomi.la under the user's own site name (log evidence: every
bakemono.app request in log 58e50bf6 is a booru-TEST probe with limit=5,
while the tab traffic goes to j./w./qtn.gold-usergeneratedcontent.net,
including nozomi/doe.nozomi + nozomi/jane.nozomi index fetches).
FIX:
- `booruHandler` is no longer final; new `SearchTab.rebuildHandler(booru)`
  rebuilds it via BooruHandlerFactory, re-applies merge tagOverrides and
  clears the selection.
- New `SearchHandler.applyBooruEdit(updated)`: matches open tabs by booru
  NAME (the identity used by configs + tab backups); rebuilds the handler
  only when type or baseURL changed (so favicon/API-key edits keep loaded
  results), otherwise just adopts the new object; logs the type
  transition and re-runs the current search.
- booru_edit_page calls it right after settingsHandler.saveBooru.
- TagHandler.queue log now prints `name [type]` — a booru's NAME never
  revealed which API a tab was really using, which is what made this
  invisible in logs.
NOTE: previously the only way to apply a type change was an app restart
(tabs are restored by name via parseTabFromBackup -> booruList.firstWhere).

## Build `site-profile` (2026-08-10) — per-site capability layer + bakemono
NEW EXTENSION POINT (the architectural ask): `lib/src/data/site_profile.dart`
`SiteProfile` — per-SITE deviations from a FAMILY handler, resolved per Booru
by HOST (`SiteProfile.forBooru`, cached). Every hook defaults to null/false =
"family behaviour unchanged", so shared handlers (gelbooru.com, rule34.xxx,
safebooru...) are untouched. Hooks: tagSuggestionsUrl, tagSuggestionCount,
metaTags, animatedFilters, listingUrl/parseListing/listingPageSize,
hasMultipleFilesPerPost/postFilesUrl/parsePostFiles + `PostFile` model.
`BooruHandler.siteProfile` (late final) exposes it to every family.
`lib/src/data/site_profiles/bakemono_profile.dart` — all verified live:
- autocomplete: /autocomplete.php?q= (gelbooru's index.php?page=autocomplete2
  is unimplemented there; bakemono ignores page= and returns the POST INDEX,
  which is why suggestions were silently empty). Count parsed out of
  `label` ("anna_anon (29603)") since there's no count field.
- metatags: Sort = Created/Views x asc/desc + a new SourceMetaTag
  (fanbox/fansly/onlyfans/patreon). Gelbooru's id/rating/user/height/width/
  updated/random are dropped for this site — none exist.
- HYBRID FETCH: dapi stays the default (returns ~90 items at limit=100);
  `listingUrl` takes over ONLY when sort:/source: is present, scraping
  /posts (hard-capped at 24/page — limit, per_page, count, n all ignored).
  Sort is deliberately NOT sent alongside a search term (verified: /posts?q=x
  and /posts?q=x&sort=views return identical order).
  GelbooruHandler.parseResponse: if the scrape yields nothing it LOGS,
  sets _listingDisabled permanently and re-fetches the same page via dapi —
  never an empty grid.
- animatedFilters() == const [] => the "videos/GIFs only" button is now
  HIDDEN on this site (both tag_view and floating_tag_preview_window guard
  on isNotEmpty). Justification: bakemono tags are only creator/platform/
  title words, and listing cards carry no video marker (a video post's card
  thumb is a plain .gif/.jpg). File kinds exist ONLY on each post page, so
  grid-level filtering would cost one request per post.
- multi-file: postFilesUrl builds /p/{platform}/{creatorId}/{postId} from the
  dapi `source` link (verified: dapi id 12402839 + creator 98535935 ->
  /p/fanbox/98535935/12402839 -> 26 files) and parsePostFiles reads the
  `viewer-data` JSON (explicit kind image/video; video entries have
  thumb/preview = null so slides must fall back to the post cover).
  MODEL + FETCH ONLY IN THIS BUILD — no UI yet (badge//overlay pending).
ALSO: BooruItem.fileCountHint (transient) for the pending grid badge.
VALIDATION: ran the real parsers over saved live markup (dart run inside the
project): 24 cards -> correct postURL/file/thumb/creator/views/count/id;
viewer-data 4 and 26 files; label counts 29603 / 1,234 / null.
PENDING (next build): multi-file UI — grid badge, viewer action in
hideable_appbar getActions(), nested carousel overlay reusing the existing
viewer stack via ViewerHandler.addViewer. NOTE maxActiveViewers is 1 and
gallery_view_page.dart:658 computes isViewerTooDeep from it; the overlay
needs it at 2 (the tag-preview + waterfall paths read the same constant),
and mediaKitMaxPlayers defaults to 4 so the overlay must cap its own
preload rather than raising the setting.

## Build `multifile` (2026-08-10) — bakemono part 2: gallery posts in the viewer
- NEW lib/src/handlers/post_files_handler.dart: lazy, deduped, session-cached
  per-post file lists via SiteProfile.postFilesUrl/parsePostFiles. Fetch is
  triggered ONLY from gallery_view_page (_loadPostFiles on open + on page
  change) — never during grid load. Failures are remembered so they don't
  retry in a loop. Sets item.fileCountHint on success.
  `itemsFor(post, files)` builds one BooruItem per file (thumb falls back to
  the post cover, since video entries have thumb/preview = null).
- NEW lib/src/pages/post_files_page.dart: the carousel overlay +
  `openPostFilesOverlay`. Registers its key with ViewerHandler.addViewer
  (same pattern as floating_tag_preview_window / waterfall_view) so zoom,
  mute, appbar visibility and player position/pause behaviour are inherited.
  `_PostFileSlide` mirrors gallery_view_page's widget selection exactly
  (media_kit -> better_player -> chewie -> ImageViewer), so video slides run
  through the SAME MediaKitPlayerView — no second player implementation.
  ONLY the visible slide has isViewed=true: no preload, so the overlay holds
  at most 1 player and the pool (mediaKitMaxPlayers default 4, parent viewer
  holding 1) is never thrashed. Setting NOT raised.
- ViewerHandler.maxActiveViewers 1 -> 2. At 1 the parent viewer unmounted the
  instant the overlay opened (gallery_view_page.dart isViewerTooDeep), which
  is the same path that tears down players. Side effect: tag-preview and
  waterfall nested viewers now also keep their parent alive one level.
- hideable_appbar getActions(): Obx-wrapped ToolbarAction (burst_mode icon,
  "N files in this post"), rendered ONLY when PostFilesHandler.hasMultiple —
  so it self-reveals once the lazy fetch lands and never shows otherwise.
- thumbnail_card_build.dart: top-left badge with the file count when
  fileCountHint > 1. DECISION: no per-item probe on the dapi path (that would
  be ~90 HTML requests per page); the count is learned when a post is opened,
  so the badge shows from the second visit on.
DESIGN ANSWERS (asked for): snatch = ALL files into a per-post subfolder
(cover-only silently loses 25 of 26 in the verified fanbox example);
favourites/history key on the POST (postURL) — files have no stable identity
across re-scrapes and the grid is one-item-per-post. NEITHER IS IMPLEMENTED
YET — snatching still takes the cover only; that is the next task.

## Build `badge-ahead` (2026-08-10) — file-count badges BEFORE opening a post
USER: overlay works, but the badge only appeared after opening+closing a
post, so the grid gave no at-a-glance signal.
INVESTIGATED FIRST (per the standing rule — don't accept an API gap):
dapi carries NO multi-file signal at all. Verified on the known 26-file
post 12402839: sample="0", has_children="false", parent_id="0". So there
is nothing free to read.
SOLUTION — background backfill from the site's own listing, matched BY ID:
- SiteProfile.enrichmentUrl(booru, tags, listingPage) (bakemono: /posts
  ?page=N, +q= when searching; returns null when sort/source is active
  since those already come from the listing WITH counts).
- PostFilesHandler.enrichCounts(items, booru, tags): for items lacking a
  count, sweeps up to 4 listing pages, reuses parseListing, and matches
  scraped serverId -> item, stopping early once every item is covered.
  Sweeps are deduped per (booru,url) for the session; failures log and
  abort quietly. Items not covered stay unbadged until opened.
- MEASURED on live data: one dapi page = 83 items; 4 listing pages
  returned 200 ids covering 72/83 = 86%, of which 58 were multi-file.
  Cost ~4 requests per ~90 items instead of 90.
- Triggered from GelbooruHandler.parseResponse (API branch only),
  unawaited so the page never blocks on it. `_lastApiTags` carries the
  query into the sweep.
- BooruItem.fileCountHint is now `Rxn<int>` and the badge is wrapped in
  Obx: counts land AFTER the cell is built, so a plain field never
  repainted. thumbnail_card_build updated accordingly.
CAVEAT (kept honest): the listing's count includes non-media attachments
(a card reading "7 files" had 4 entries in viewer-data), so the badge is an
upper bound until the post is opened, at which point ensureLoaded
overwrites it with the exact media count.

## Build `pause-fix2` (2026-08-10) — REVERT maxActiveViewers to 1 (regression)
USER: after `multifile`, opening a post from a preview window left the video
underneath still playing.
CAUSE: mine. `multifile` raised ViewerHandler.maxActiveViewers 1 -> 2.
There is NO explicit pause-on-cover anywhere in the app — covering a viewer
stopped playback purely as a side effect of gallery_view_page's
`isViewerTooDeep` swapping the item widget for a black container, which
DISPOSED the player (that is exactly why the saved-position hand-off in
ViewerHandler exists). At 2, the covered GalleryViewPage stayed mounted and
kept playing, audio included, under whatever was opened on top. This hit
every nested-viewer path (tag preview, floating window, waterfall), not
just the new carousel.
FIX: reverted to 1, with a comment at the constant explaining that it
doubles as the pause mechanism so nobody raises it again.
WHY THE RAISE WASN'T NEEDED: isViewerTooDeep is internal to
GalleryViewPage. The post-file carousel is its OWN route with its own
player widgets and never consults it, so it works identically at 1 — and
the covered parent now correctly tears down and restores its position via
the existing hand-off on the way back.
IF an explicit pause-on-cover is ever wanted (so a covered viewer can stay
mounted): the players already pause when isViewed goes false, but the
`isViewed` flags in gallery_view_page are computed inside
ValueListenableBuilders bound to `page` only — they would have to listen to
viewerHandler.activeViewers too, and MediaKitPlayerView.didUpdateWidget
seeks to zero when isViewed goes true again, so it would also need a
"covered" concept distinct from "not the current page". Not worth it while
unmount+hand-off already gives the right behaviour.

## Build `pools` (2026-08-13) — pool browsing (survey + feature)
SURVEY (all probed live with the user's own credentials):
- WORKS NOW: e621, e6ai (/pools.json, ordered post_ids), rule34.xxx,
  gelbooru.com, realbooru, xbooru (HTML `index.php?page=pool&s=list&pid=N`,
  25/page), derpibooru (Philomena "galleries",
  /api/v1/json/search/galleries).
- API KEY DOES NOT UNLOCK GELBOORU POOLS: `page=dapi&s=pool&q=index` returns
  an EMPTY body on rule34.xxx and gelbooru.com even with valid
  api_key+user_id (note: rule34.xxx 301s to api.rule34.xxx — follow it).
  HTML scrape is the only route. `&search=`/`&q=` on the list are ignored.
- NO POOLS (entry hidden, verified): tbib.org (pool page, zero pools),
  blacked/drunkenpumken booru.org, rule34.paheal (all pool routes 404),
  rule34.us, plus nozomi/civitai/redgifs/xxxtik/sankaku/rule34.dev.
- UNVERIFIED from this container: danbooru + AiBooru (Cloudflare 403 "Just
  a moment" on a datacenter IP), AllTheFallen (/pools.json returned HTML),
  rule34.xyz (playlists exist in their JS bundle; proxy blocked), and
  rule34hentai.net (site was down/502). Danbooru+Philomena sources are
  implemented anyway and will light up if the site answers on the phone.
KEY ORDERING FINDING: e621's `pool:<id>` tag returns DATE order, not pool
order (verified) — comics would be scrambled. Pool order therefore comes
from `post_ids` and the fetched members are reordered to match.
IMPLEMENTATION:
- lib/src/data/booru_pool.dart — BooruPool model.
- lib/src/handlers/pool_source.dart — `PoolSource.forBooru(booru)` resolves
  per Booru (type + host denylist) and returns null for sites without
  pools, which is exactly what the drawer entry keys off. Four sources:
  E621 (json, reorder), Danbooru (`ordpool:` = server-side pool order),
  Philomena (`gallery_id:`), GelbooruHtml (scrape list + scrape ordered ids
  from `<span class="thumb" id="pNNN">` on the pool page).
- lib/src/boorus/pool_posts_handler.dart — virtual BooruHandler serving one
  pool as a normal post feed (so viewer/snatcher/favourites/blacklist all
  behave normally). Three strategies: delegate straight through when the
  site's query already preserves order; fetch-all + reorder for e621;
  per-id fetch (`tags=id:<n>`, verified supported; OR of ids is NOT) in
  bounded parallel batches for the gelbooru family.
- SearchTab gained poolId/poolName (+ `isPool`), persisted in TabBackup as
  'p'/'pn' and passed to the CONSTRUCTOR on restore so the pool handler is
  rebuilt — a restored pool tab keeps working instead of degrading into a
  broken text search. addTabByString gained poolId/poolName.
- TabRow: red "pool" chip (theme error role, not a hex) inline before the
  MarqueeText; compact and non-flexing so the marquee keeps its width.
  One change covers both the tab strip and the tab manager.
- lib/src/pages/pools_page.dart — list with loading/error/empty states,
  infinite scroll; tap opens the pool, long-press / trailing button opens
  it as a background tab in the current group.
- main_drawer: "Pools" SettingsButton wrapped in Obx, hidden entirely when
  PoolSource.supports(currentBooru) is false.
NOT DONE: pool thumbnails on list rows (rule34's table has none and it
would cost a request per row — skipped per the brief). No runtime device
testing of the UI from here.

## Build `fav-keep` (2026-08-13)
1. POOLS NARROWED (user tested): PoolSource._poolHosts is now an ALLOWLIST —
   rule34.xxx, realbooru.com, xbooru.com, booru.allthefallen.moe. Everything
   else gets no drawer entry. The e621/Philomena sources stay in the file
   (working code) but are unreachable until a host is added.
2. NEW-TAB LONG-PRESS FIXED: tab_buttons.dart had
   GestureDetector(onLongPress) wrapping an IconButton; IconButton builds its
   own InkResponse whose tap recognizer is the innermost arena entry, so the
   ancestor's long-press lost under real touch. NOTE the same pattern is in
   ToolbarAction (and 2.5.0 hotfix 1 was literally "Fixed long tap actions on
   viewer toolbar buttons"), so this is a recurring trap. Fixed by putting BOTH
   gestures on one InkResponse (onTap + onLongPress + ripple), no nesting.
   NOT device-tested from here.
4. FAVOURITES/SNATCHED FILTER NO LONGER LIVE: BooruHandler gained
   `liveFilterExemptions` (+ exemptFromLiveFilter / exemptionKey). The
   favourites AND snatched branches of filterFetched now skip exempt items;
   every other filter (blacklist etc.) still applies live, and filterFetched
   itself is still called. Exemptions are added when favouriting (single +
   bulk in search_handler) and when queueing a snatch (snatch_handler), and
   cleared in booru_handler.search() where `fetched.value = []` on a new
   query. So a post you like mid-video stays put until an actual reload.
TAG-INDEX SURVEY (for the pending tag-browser feature):
  - rule34.xxx: index.php?page=dapi&s=tag&q=index (XML) works with key;
    fields type/count/name/ambiguous/id.
  - xbooru: same XML endpoint works, but count is 0 on everything.
  - realbooru: tag index returns EMPTY (and orderby -> "Search error").
  - allthefallen: /tags.json returns HTML, like its /pools.json (unverified
    from this IP).
  - CRITICAL: `orderby=count` is IGNORED everywhere tested — rule34.xxx
    returned counts 2,1,1 and xbooru all zeros. Tag indexes come out in id
    order, so "most popular tags first" is NOT free; it needs either local
    accumulation or a different source.

## Build `tag-atlas` (2026-08-14)

Per-booru tag knowledge: a local snapshot of each site's own tag database,
your corrections on top, and a browser that shows both.

### The bug this uncovered first
`GelbooruHandler.genTagObjects` was **dead code on every Gelbooru-0.2 site**.
It requested `…&s=tag&q=index&names=a b c&limit=100&json=1` and read
`response.data['tag']`. Verified live against rule34.xxx and xbooru with the
user's own key:
  - `names=` is IGNORED. The site answers with the first page of its whole
    tag index, so the tags asked about were never in the reply.
  - `json=1` is IGNORED on rule34.xxx — it always returns XML. So
    `data['tag']` threw on a String and the catch swallowed it.
Net effect: no tag on rule34.xxx/xbooru ever received a type from this path.
`&name=<tag>` (singular) IS honoured and returns exactly one authoritative
row (`vocaloid` -> type 3, count 47430), so genTagObjects now resolves one
tag per request with concurrency 3, capped at 45 per call (the TagHandler
queue re-feeds the rest), skipping anything the snapshot already answers.

### Storage (both tables in store.db, so DB backup/restore covers them)
- `BooruTag(booruKey, name, tagType, count, source, updatedAt)` PK
  (booruKey, name) — the snapshot. `source` = 'api' | 'import'. Disposable.
- `BooruTagOverride(booruKey, name, tagType, source, updatedAt)` PK
  (booruKey, name) — your corrections, `source='manual'`. Existing in this
  table IS the permanent exclusion: `BooruTagStore.record()` refuses to write
  a snapshot row for a pair you have corrected, so nothing ever re-types it.
- Index `BooruTag_browse_index (booruKey, tagType, count DESC)`.
- `booruKey` is the HOST (`rule34.xxx`), not the booru NAME — renaming a
  booru config must not orphan corrections. (TagAliasCache uses type/name;
  it was NOT touched, per the brief.)
- The global `Tag` table is untouched. Per-booru truth is layered on at read
  time by `TagHandler.getTagFor(tag, booru)`; writing it into the shared map
  is exactly what would recolour the tag on every other site.

### Resolution order
manual override -> this booru's snapshot row -> the app's global tag map
(i.e. some other site's opinion, marked `inferred`) -> untyped. A snapshot
row typed `none` still falls through to the global map on purpose: that is
the "this site files an artist under general" case, and surfacing it as
`inferred` with a dashed border is how you find tags worth correcting.

### lib/src/handlers/tag_index_source.dart
Per-family tag-database access, three operations: `pageAt` (walk the index),
`search` (substring), `exact` (one authoritative row). Verified live:
- Gelbooru 0.2: `name=` exact YES, `name_pattern=%x%` YES, `names=` NO,
  `orderby=count` NO. **The API index is worthless for snapshots** — six
  samples spread across rule34.xxx's index all had median post count 1. But
  the site's own HTML tag list DOES sort: `page=tags&s=list&sort=desc&
  order_by=index_count` starts at `female` (10.3M) and descends, 20 rows a
  page, `pid` counting ROWS. So `pageAt` scrapes that (types come from the
  `tag-type-<name>` span class) and only falls back to the API walk if a fork
  doesn't render the page. 250 pages deep reaches ~18k posts/tag.
- Danbooru + e621 `/tags.json`: `search[order]=count` DOES work, so those
  arrive most-used-first. e621 wants basic auth; danbooru unverified from
  this container (Cloudflare 403).
- Philomena `/api/v1/json/search/tags`, category strings not numbers.

### UI — lib/src/pages/tag_browser_page.dart (drawer: "Tag browser")
One page, both modes. Booru dropdown, live search (falls through to the
site's own tag search when the snapshot has no match, and stores what comes
back), type filter chips, and a "Yours" chip that turns the same list into
the corrections manager. Row borders carry the meaning: solid = the site
reported it, DASHED (`_DashedBorderPainter`) = inferred from elsewhere,
thick accent + lock = yours and permanent. Tap opens the tag, long-press
sets its type, trailing button opens a background tab. Menu: pull index,
import snapshot from the backup folder / from a URL, export snapshot, clear
snapshot, remove corrections.

### Snapshot portability (hosted snapshots)
`BooruTagStore.exportJson/importJson/importFromUrl`; format is
`{format, version, booru, createdAt, tags:[{n,t,c}]}`. Export/import via the
backup folder reuses `settingsHandler.backupPath` (ServiceHandler.writeImage
/ getFileFromSAFDirectory), so pointing that at a synced folder gets you
off-device backup for free. A file whose `booru` key doesn't match is still
importable but lands as `inferred`, never as reported.

### Where per-booru types are now read
tag_view (chip colour, type grouping, the type sections, the tag dialog, and
the double-tap editor — which now writes a per-booru correction instead of
overwriting the global type), tab_row (per TAB's booru), the main search bar
chips and flow search bar (current booru). Everything else still reads the
global map, which is unchanged behaviour.

NOT DONE: no device testing from here. Danbooru-family index/exact unverified
(Cloudflare blocks this container). realbooru's tag API is switched off by the
operator ("API offline because apparently it is broken") so that site can only
ever collect tags opportunistically. No snapshot files have been published
anywhere — the import-from-URL mechanism exists and works, but there is no
hosted snapshot to point it at yet.

### Rate limiting (found the hard way)
Scraping rule34.xxx's tag list back to back at ~7 req/s started returning
HTTP 429 at around page 190 (~3.5k tags). The in-app pull therefore waits
350ms between pages, keeps everything it managed to store when a page fails
(reported as "Stopped after N tags", orange, not a red failure), and
remembers the page it reached per booru so running it again continues rather
than restarting at `female`.

## Build `tik-porn` (2026-08-14)

New source: **tik.porn** (`BooruType.TikPorn`,
`lib/src/boorus/tikporn_handler.dart`). Short-form vertical video, video-only,
no account needed. Not related to the existing `XXXTik` type despite the
similar shape — different company, different backend.

### How it was found
Next.js frontend; `__NEXT_DATA__` on any page carries the server props, and
the client bundle names the real API (`https://apiv2.tik.porn`) plus a full
endpoint map. No auth on any content endpoint.

### Endpoints used
- `GET /search?search_term=Q&index=search&search_type=video&limit&offset`
- `GET /gettagvideos?tagid=ID&limit&offset&sort`
- `GET /getactionvideos?actionid=ID&…`, `GET /getuservideos?userid=ID&…`
- `GET /gettaglist` (84 tags), `GET /getactionlist` (131 acts) — the whole
  vocabulary in two requests, cached statically per app run
- `GET /getuserbyslug?slug=S` — creator slug -> numeric id (400s on a miss)
- `GET /getvideocomments?videoid&limit&offset`
- suggestions: the site's own Elasticsearch term index, with the read
  credentials its own bundle ships to every browser

Every listing row already carries signed, ready-to-play `mp4_url` / `hls_url`
/ `download_url` plus poster and list thumbnails, so no per-item request is
needed. Signed URLs expire — fine, feeds are refetched.

### Query grammar
Empty -> whole catalogue. Free text -> search. A single bare word that names
a real tag or act routes to that feed instead (exhaustive + sortable). Also
`tag:`, `action:`, `creator:`/`artist:`/`user:`, and `sort:recent|popular`.

### Two bugs caught by walking the features end to end
1. **Underscores zero out free-text search.** The index is natural language,
   not booru tags: `teen_anal` -> 0 results, `teen anal` -> 26722;
   `hatsune_miku` -> 0, `hatsune miku` -> 4. Every cross-booru feature (Tag
   Hub, Artist Hub, suggestions) passes underscored tags, so the site would
   have looked empty for nearly all of them. `_searchTerm` now converts
   `_` and `-` to spaces.
2. **A named-but-unresolved facet fell through to the whole catalogue.**
   `creator:typo` -> lookup 400s -> `search_term=*` -> 100k confident-looking
   but completely unrelated results. Now the unresolved name is searched as
   text instead, and `*` is reserved for "nothing was asked for".

### API quirks worth remembering
- `sort` only exists on the id-based feeds, and only `recent` (default) and
  `popular` differ. `views`, `likes`, `trending`, `random`, `best`, `oldest`
  all silently return `recent` ordering. `/search` ignores `sort` entirely —
  so the sort chip offers exactly two values, not a longer list that lies.
- `/getrecentvideos` ignores page AND limit AND offset — a fixed ten-item
  strip, not a feed. Unused.
- `/videos/popular` honours `offset` but pins page size to 10. Unused.
- `search_term=*` returns the whole catalogue (~102k) and pages correctly.
- `names=`-style batching does not exist here; ids are single-valued.

### Walked end to end against production
Feeds + 2-page pagination with zero overlap (catalogue 102065, free text
48340, tag 4583/13905, action 468, creator 229); sort:popular changes the
result set on tag and action feeds; every first item's mp4 and thumbnail
return 206 with the right content type; autocomplete returns vocabulary +
keyword hits for redh/anal/small/teen/cosplay; comments parse; underscore,
hyphen and uppercase spellings all resolve to the same feed.

NOT DONE: no device testing from here. Not autodetectable on purpose (fixed
API host, like xxxtik/RedGifs/Civitai) — pick "Tik.Porn" in the type list.

## Build `thumb-fix` (2026-08-14)

Three user-reported bugs, all found and fixed at the source.

### 1. Every video sharing one thumbnail (tik.porn AND xxxtik)
`ImageWriter.parseThumbUrlToName` named disk-cache files by the URL's **last
path segment only**. That is fine for boorus that put a hash or post id in
the filename, but some sites carry the identity in the DIRECTORY:

    tik.porn  …/video/1753/1753144/list-sm.jpg?ver=3  -> "list-sm.jpg"
    xxxtik    …/{uid}/thumbnail.webp                  -> "thumbnail.webp"

So every post on those sites read and wrote ONE cache entry, and the grid
rendered whichever thumbnail was fetched first. (The pre-existing `thumb.`
/ Paheal special-case in that function is the same bug, patched one site at
a time.) Now a generic basename gets a 10-char md5 of its directory
prefixed. "Generic" = the stem contains no alphanumeric run of 8+ characters
that includes a digit, so hash/id filenames are left exactly as they were and
no existing cache entry is invalidated for any other booru. Verified against
real URLs from tik.porn, xxxtik, rule34.xxx, r34us, gelbooru, e621, danbooru
and bakemono. **Both copies** of the function must stay in sync —
`image_writer.dart` and `image_writer_isolate.dart`.

### 2. New-tab long press still dead
I fixed the wrong button last time. The Flow UI's app-bar add button is
`NewTabButton` in `flow_tab_carousel.dart`, not the sidebar's `TabButtons` —
and it had the identical `GestureDetector(onLongPress:)` wrapped around an
`IconButton`. The IconButton builds its own InkResponse whose tap recognizer
is innermost in the gesture arena, so the ancestor's long press never wins.

This bug class has now shipped three times (2.5.0 hotfix 1 for the viewer
toolbar, the sidebar add button, this one), so the whole tree was swept:
`main_appbar.dart` menu button, `settings_widgets.dart` iconOnly
SettingsButton, and `webview_navigation_controls.dart` back button were all
the same pattern and are all converted. A grep for
`GestureDetector(onLongPress) -> IconButton` now returns zero hits.
**RULE: never wrap an IconButton in a GestureDetector. Put every gesture on
one InkResponse.**

### 3. rule34.us finding no posts for any tag
rule34.us serves **two completely different layouts by User-Agent**, and the
handler is written against the desktop one. `Tools.browserUserAgent` prefers
the device WebView's UA on Android, i.e. a mobile UA, so the app got the
mobile layout where:
  - grid thumbnails are lazy-loaded: `<img class="lazyload" data-src="…">`
    with **no `src` attribute at all** -> every item parsed to null -> "no
    posts found", and no error anywhere;
  - the post page has neither `.content_push` nor `.tag-list-left` (media is
    injected by script into `#ci`), so `loadItem` would have failed too.
Fixed by sending `Constants.defaultDesktopBrowserUserAgent` from
`R34USHandler.getHeaders()` (a user-set custom UA still wins), and by making
the grid parser accept `data-src` and use `querySelector` instead of
`children[0]`/`firstChild` node-walking. Verified: 42/42 items parse on the
desktop layout, 21/21 on the mobile one.

## Build `tag-flow` (2026-08-14)

### 1. Favourites filter never applied on load (real cause found)
`BooruHandler.afterParseResponse` called `filterFetched()` and only THEN
fired `setMultipleTrackedValues()` unawaited. `isFavourite` / `isSnatched`
come from the local DB via that call, so at filter time every freshly parsed
item still had both flags false and the favourites/snatched filters removed
nothing. They only ever appeared to work because favouriting a post later
re-ran the filter and yanked it out mid-view — the exact behaviour removed in
`fav-keep`, which is why the filter then looked completely dead. Now the
tracked values are awaited and `filterFetched()` runs a second time, so those
two settings apply where they are documented to: on load.

### 2. Re-typing a tag didn't move it between groups
`groupTagsList` and the section builder both gated the type lookup on
`tagHandler.hasTag(...)`, so a per-booru correction was ignored for any tag
the GLOBAL store had never seen — the chip recoloured but the tag stayed in
General. Replaced both with one `typeOfTag(tag)` helper: manual override ->
global store -> the item's own Tag. The chip colour now uses the same helper,
so colour and grouping can no longer disagree.

### 3. Cross-booru tag translation dying permanently
`getTagSuggestions` returns `Either`, and BOTH resolvers did
`res.fold((_) {}, (list) => candidates = list)` — silently discarding the
error branch. A 403, a CAPTCHA page or a rate-limit therefore looked exactly
like "this booru has no such tag":
  - `utils/tag_alias_resolver.dart` wrote that miss to the `TagAliasCache`
    table, honoured for SEVEN DAYS and surviving restarts;
  - `handlers/tag_alias_resolver.dart` cached it in memory for the session.
rule34.xxx now answers `page=autocomplete2` and `autocomplete.php` on its
www host with a CAPTCHA / 403, so a poisoning event is routine. Both
resolvers now track whether a lookup actually answered and never store a
negative they did not observe. Existing poisoned rows are cleared by
`DBHandler.purgeTagAliasMisses()` on every DB open, and the miss TTL dropped
from 7 days to 1.

NOTE: the resolver ALGORITHM was verified working against live gelbooru-alike
autocomplete — `robin` -> `robin_(honkai:_star_rail)`, `tifa` ->
`tifa_lockhart`, `2b` -> `2b_(nier:automata)`, `power` ->
`power_(chainsaw_man)`. The user's specific failure was NOT reproduced from
here; the caching bug above is the best-supported explanation, not a
confirmed one.

Endpoint notes found while investigating (not acted on):
  - `page=autocomplete2` returns the site homepage as HTML on xbooru,
    realbooru, safebooru, tbib and api.rule34.xxx — only gelbooru.com
    implements it. It is only used by `GelbooruHandler` (gelbooru.com), so
    nothing is broken today, but it is a trap for any future 0.2-family work.
  - `GelbooruAlikesHandler.makeTagURL` uses dapi `name_pattern=<input>%`,
    which is PREFIX-only. Tags whose target spelling reorders the words
    (`hatsune_miku` vs `miku_hatsune`) can never be found by it.
