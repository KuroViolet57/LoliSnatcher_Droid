# LoliSnatcher_Droid — Session Handover

Paste this back to resume with full context. Last updated: 2026-07-13 (build 5210).

## Project / workflow
- Flutter Android booru gallery app. Autonomous multi-feature build.
- **Working branch: `claude/experimental-megabuild`** (NOT the auto-named
  `claude/google-oauth-refresh-token-*` — all features live on megabuild).
- Build: `export PATH="$PATH:/opt/flutter/bin"; bash build.sh test`
  (must `git config --global --add safe.directory /opt/flutter` first; flutter
  warns about running as root but works). APKs land in
  `build/app/outputs/flutter-apk/LoliSnatcher_2.5.0_<build>_<abi>_test.apk`.
- Each feature: build → commit → push → upload test APK.

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

**REMAINING PHASES (per zip spec screens; not yet done):**
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
- Material Symbols Rounded icons (material_symbols_icons pkg NOT in pubspec;
  either add it or keep Material Icons — currently kept Material Icons).
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
