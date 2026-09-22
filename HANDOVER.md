# LoliSnatcher_Droid — Handover

Written 2026-09-06 at build **r26-handover** (branch `claude/experimental-doujin`,
HEAD `e15d17e` + this document; §1, §2, §4.3, §10 and §12 updated for r27 the
same day, when the project moved to the user's Windows PC; §0, §2, §5, §10 and
§12 updated for r28, rule34video; r29 on 2026-09-08; r30 on 2026-09-09, e-hentai and
hdoujin; r31 the same day, the tag-builder sweep; r32 on 2026-09-13, the e-hentai
page previews; r33 on 2026-09-14, the recommender; r34 on 2026-09-14, stuck
doujin-tab retry, by Grok; r35 on 2026-09-14, the encoder; r36 the same evening, the exhentai
re-check; r37 the same night, doujin browse filters; r38 on 2026-09-15, the tab
cards and the tab pill; r39 the same day, the request storm and the
slowness). This file is the complete brief for a fresh
session: read Part A top to bottom before touching code. Part B is the
older chronological build log, kept verbatim as history.

---

# PART A — the current state of the project

## 0. Read this first

- **What this is.** A Flutter Android gallery app for boorus (Gelbooru,
  Danbooru, e621, …) that this branch extended with: video/tube sources,
  a full **doujin** (comic/book) reading system with its own data space,
  a **kemono-style** creator-archive source family (kemono.cr, pawchive.pw),
  a per-booru tag database and tag builder, pools, recommendations,
  Google Drive backups, and a source-capture tool for sites this machine
  cannot reach.
- **Branch:** `claude/experimental-doujin`. Everything lives there. Older
  history is on `claude/experimental-megabuild` (merged into this branch).
  Never push elsewhere; force-push is blocked.
- **Version:** `2.6.0+5211` in `pubspec.yaml`, mirrored in
  `lib/src/data/constants.dart` (`updateInfo`). Builds are told apart by
  `Constants.buildCodename` (`'r81-vectors-frames'` now), shown in About. Bump the
  codename every build: `rNN-<two words>`.
- **Build counter:** rounds are numbered r21, r22, … r80. Each build gets a
  numbered folder on the K: drive (§2): r80 used **109** and **110**, r81
  used **111**; the next build uses **112**. **103** is Grok's ("exp flutter 347") - never
  reuse a number.
- **The user** talks in voice notes and logs; expects one build per request
  round, checked on a Samsung phone. They cannot see tool output — only the
  final message.
- **Tests first, then an adversarial review (user rule, 2026-09-08).** Write
  the failing tests before the code; after the code is green, review the
  diff yourself. **Since 2026-09-21 an Agent (the adversarial review
  included) runs only after the user says yes, and a multi-agent Workflow
  only after an explicit yes to a cost estimate** - they burn the user's
  usage. The user noticed tests written after the code pass trivially. r29
  was the first round under it: the r28 review found five real bugs (§12).

### The user's standing rules (verbatim intent, all still in force)

1. **Never say "fixed".** Report per item: what *changed*, what was
   *observed* (in a test, a log, a live probe), what is *not verified*.
   Give numbered device-check steps. Always include the Drive folder link.
2. **Check prior art before saying something is impossible.** (Keiyoushi /
   Tachiyomi extensions, the site's own frontend, other apps.)
3. **Do the failure analysis before the build, not after.** Read the
   user's log first; find the request that is missing or the exception;
   only then change code.
4. **niyaniya (Schale) clearance:** manual solving only, two windows
   (visible solver + headless harvester), never a silent retry, keep the
   diagnostic lines in the log.
5. **Doujin and booru personal spaces stay separate** — favourites,
   history, blacklist, pins, saved searches, collections. A leak either
   way is a bug. `test/doujin_separation_test.dart` is the guard.
6. **nhentai is the tag API source** for the doujin tag builder's canonical
   list; other doujin sources bring their own catalogs.
7. **Update the parity artifact every build** (see §2.6).
8. Sub-agents are allowed, but the account's rate limit has killed every
   spawned agent lately (resets 06:00 UTC). Prefer doing the work inline.
9. **Credentials:** never in commits, changelogs, logs or uploads. The
   user's booru API keys leaked in an early log export and they were told
   to rotate them; `LogRedaction` now scrubs logs and captures.

## 1. Environment and toolchain

- **The project lives on the user's Windows PC** since r27 (2026-09-06); the
  Linux container of r1–r26 is gone. Working checkout: `C:\bodu-apk` (branch
  `claude/experimental-doujin`). The Claude session's persistent memory keeps
  these facts too.
- **Flutter:** the pubspec pins beta `3.42.0-0.4.pre` exactly, so the stable
  install on the machine (3.41.9 at `C:\Users\alexb\Documents\flutter\flutter`)
  cannot run it. A git worktree of that checkout at the tag lives at
  `C:\Users\alexb\Documents\flutter\flutter-3.42-beta`; prefix every flutter
  command with
  `export PATH="/c/Users/alexb/Documents/flutter/flutter-3.42-beta/bin:$PATH"`
  (Git Bash). Never switch the main install's channel: a newer beta breaks
  the exact pin.
- **Android SDK** at `C:\Users\alexb\AppData\Local\Android\Sdk` (platform 36,
  NDK present); flutter uses Android Studio's JDK 21. `adb` is at
  `C:\Users\alexb\Desktop\platform-tools` (no device attached by default).
- **Analyzer:** use `flutter analyze --no-pub`. `dart analyze` completes but
  its analysis server crashes on shutdown on this machine (perf_witness
  cannot delete its socket files under `%LOCALAPPDATA%\Dart\perf`) and prints
  nothing.
- **Network:** a normal residential connection — probe sites with `curl`
  directly. Cloudflare still challenges danbooru/aibooru/konachan for curl
  and the sandboxed browsers refuse those hosts; the phone gets through with
  the app's own cookie jar.
- **Signing:** a TEST keystore is committed on purpose:
  `android/app/lolisnatcher-test.jks` + `android/key.properties`
  (passwords `lolisnatcher-test`). Builds signed before 2026-07-31 used a
  lost key — a user on one of those must uninstall once.
- The sqlite3 native-asset workaround and the Drive OAuth file of the
  container days are no longer needed: normal network, and delivery is a
  file copy (§2).
- **Scratchpad** for temp files: the session's scratchpad directory
  (`C:\Users\alexb\AppData\Local\Temp\claude\C--bodu-apk\<session>\scratchpad`)
  — build logs, changelogs and the parity HTML go there.
- **Git:** `core.autocrlf=true` (working files CRLF, index LF); the repo-local
  identity is `Claude <noreply@anthropic.com>`.

## 2. The per-build workflow (every build, in this order)

1. Failure analysis from the user's log/recording; write the plan.
2. Write the tests red first, then implement (§0); run an adversarial
   review Agent over the diff and fix its findings before going on.
3. `flutter analyze --no-pub` → **0 errors**; the baseline is **60 issues**
   (r32: 54 infos + 6 warnings, lint style noise in old files). New code
   should add none.
4. `flutter test $(ls test/*_test.dart | grep -v booru_test)` → all green.
   Baseline **833** (r39). `booru_test.dart` is excluded because its cases
   hit live sites; `tag_index_live_test.dart`, `rule34video_live_test.dart`
   and the doujin parity walk are tagged `live` and skipped unless run with
   `--run-skipped --tags live`.
5. Bump `Constants.buildCodename`; write the changelog to the scratchpad
   (`changelog_rNN.md`) with **changed / observed / not verified** per item;
   `grep -iE 'password=|token|secret|cookie=' changelog_rNN.md` must be empty.
6. Commit with a descriptive body and BOTH trailers:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_<id>
   ```
   No model identifiers anywhere else. `git push -u origin claude/experimental-doujin`
   (retry with backoff on network errors).
7. Build in place (the tree is clean after the commit), **arm64 only** — the
   user asked for no universal APK:
   ```
   flutter build apk --release --split-per-abi --target-platform android-arm64 > <scratch>/buildNN.log 2>&1
   ```
   Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
8. Deliver by copying into the Google Drive folder synced on the PC:
   `K:\My Drive\booruApk\<token>.apk (<descriptor>)\` — e.g.
   `58.apk (r39 speed fixes - tested)` — holding `changes.txt` (the
   changelog) and the APK renamed `<codename>-2.6.0.apk`. Tokens are
   integers: r39 used 58, the next build uses 59.
   **The order since 2026-09-14 evening (user rule): build FIRST, test
   second.** Write the changelog, then run
   `python tool/deliver_build.py <token> "<descriptor>" <changelog.md>` —
   it builds the arm64 APK, waits, and copies APK + `changes.txt` into the
   folder labelled `- not tested`. Only then run the tests (the touched
   files, then the full suite once); when they pass,
   `python tool/deliver_build.py <token> "<descriptor>" --mark-tested`
   renames the folder to `- tested`. The user has run out of usage between
   a green suite and a delivered build more than once; this way the APK is
   there either way and its label says what it is. No agents without asking
   (the adversarial reviewer included), since the same evening. The report gives that folder path (a file copy has no)
   web link). `scripts/drive_upload_build.py` is retired.
9. Republish the **parity artifact** (§2.6) with a footer "build rNN".
10. Report: per item changed/observed/not verified, numbered device steps,
    the K: folder, what to send back (a log with the app's logger enabled,
    Settings → Debug → Logger; the source-capture file when a site fails).

### 2.6 The parity artifact
A single HTML page (`<scratch>/doujin_source_parity.html`, published at
`https://claude.ai/code/artifact/3283b8b2-e5b8-42c3-b8aa-63390a4eaf97`) with a
row per source and a column per capability (listing, search, detail, reader,
tags, favourites, login, downloads, related, recommended, tag catalog, media
headers, …) marked verified / unverified / n.a., plus per-build notes. Read it
with the Artifact tool (`action: read`) before republishing; scratch files do
not survive a container reset, so rebuild it from the read if missing.

## 3. Layout of the app

```
lib/main.dart                     runApp → MainApp → (init) InitHomePage → MobileHomePage / DesktopHomePage
lib/src/boorus/                   one handler per source family (50 files) + boorus/doujin/ (13)
lib/src/data/                     models: Booru, BooruItem, Tag/TagType, MetaTag, KemonoPost, SiteProfile, constants
lib/src/data/site_profiles/       per-host deviations (bakemono, kemono)
lib/src/handlers/                 singletons and services (43): settings, search, DB, doujin store, reader, tag store, …
lib/src/pages/                    full screens (26) + pages/settings/ (24)
lib/src/widgets/                  preview/ (feed), gallery/ (viewer chrome), drawers/, tabs/, image/, video/, webview/, root/, common/
lib/src/services/                 image_writer (downloads), dio_downloader, drive_backup, saf_file_cache
lib/src/utils/                    dio_network, logger + log_redaction, tools (UA, sanitize), html_parse, extensions
test/                             50 offline test files + test/fixtures/ (43 captured bodies)
scripts/drive_upload_build.py     Drive uploader (see §2)
```

### 3.1 Screens and navigation
- `MobileHomePage` hosts a vendored **`InnerDrawer`**: left = main drawer
  (booru/tab selector, settings entry), right = `DownloadsDrawer` whose top is
  `drawer_quick_access.dart` (favourites, history, pins, collections, doujin
  library entries when on a doujin tab, the "Use the <site> sidebar" swap row
  on kemono-style tabs). `pinnedSide()` swaps the right side for
  `KemonoSidebar` when the current tab is kemono-style and
  `settingsHandler.kemonoSidebar` is true.
- The feed is `waterfall_view.dart` (grid/staggered via `grid_builder` /
  `staggered_builder`, thumbnails in `widgets/thumbnail/`), the search bar is
  `main_search_bar.dart` + the query editor pages, the tab strip is
  `flow_tab_carousel.dart`, filter chips `media_filter_chips.dart`.
  Doujin tabs render `doujin_tab_view.dart` instead of the waterfall
  (grid of book cards; a detail tab shows the book's page).
- The viewer is `gallery_view_page.dart` → `image_viewer.dart` /
  `video_viewer.dart` (media_kit and the older players), chrome in
  `hideable_appbar.dart` (toolbar actions: files overlay, kemono post page,
  find elsewhere, …), the info panel `tag_view.dart` (tags, metatags card
  with the tag builder chips, related/recommended strips, comments, notes,
  kemono post button), `post_files_page.dart` for carousel posts,
  `doujin_detail_page.dart` + `doujin_reader_page.dart` for books.
- Settings: `settings_page.dart` hub → `pages/settings/*` (boorus,
  `booru_edit_page.dart` with per-type defaults and instructions, doujin
  settings, source settings, tags & filters, gallery, video, network, theme,
  backup/restore, database, debug with logger and source capture, …).
- Routing helpers: `widgets/root/routing.dart`, `NavigationHandler`
  (`navContext`), predictive back.

### 3.2 State conventions
- **GetX** singletons: `SettingsHandler.instance`, `SearchHandler.instance`,
  `DoujinDataHandler.instance`, etc. Reactive fields are `Rx*`; widgets
  rebuild with `Obx`. Settings are `RxBool`/`RxString` fields in
  `settings_handler.dart`, persisted to `settings.json` by
  `saveSettings(restate:)`; add a field there + its json key + a settings row.
- **Networking:** `DioNetwork` (`utils/dio_network.dart`) hands out Dio
  instances sharing one pooled `HttpClient`. **Never call `.close()` on a Dio
  from `getClient()`** — it kills the shared pool.
- **One User-Agent invariant:** every request, WebView and media fetch uses
  `Tools.browserUserAgent` (`utils/tools.dart`). Cloudflare ties cookies to
  the UA; mismatches were the cause of several "works in browser, 403 in app"
  rounds. Do not introduce another UA string.
- **Headers:** `BooruHandler.getHeaders()` for API calls,
  `getMediaHeaders()` for image/video fetches (viewer, thumbnails, downloads
  all ask `BooruHandlerFactory.mediaHeadersFor(booru)`; `media_headers_test`
  guards the per-source table).
- **Images:** `CustomNetworkImage` (`widgets/image/custom_network_image.dart`)
  fetches through Dio into the cache folder; it validates JPEGs
  (`looksLikeJpeg` before `hasJpegEndMarker`, because some hosts serve WebP
  under `.jpeg`). Its `==` compares the `headers` map **by identity** — pass
  the same map instance across rebuilds or every rebuild refetches.
- **Logging:** `Logger.Inst().log(msg, className, method, LogTypes.x)`;
  everything passes `LogRedaction` (api keys, cookies, passwords, the
  kemono session). The user exports logs from Settings → Debug → Logger.
- **Paging rule:** `SearchHandler.runSearch` increments `pageNum` *before*
  the first fetch. A handler's first page number is `startingPage` from
  `BooruHandlerFactory` (default `-1` → first request page 0). Sites that
  count from 1 return `0`. Getting this wrong skips the first page (r25 bug).

## 4. Handlers and the capability surface

`BooruHandler` (`handlers/booru_handler.dart`) is the base every source
extends. The factory (`booru_handler_factory.dart`) maps `BooruType` →
handler and caches per-booru helpers (`mediaHandlerFor`, `mediaHeadersFor`,
`mediaOutageNoticeFor`, `onMediaErrorFor`, `beforeMediaRetryFor`).

Override points, grouped:

| Area | Members |
|---|---|
| Search | `makeURL(tags)`, `parseListFromResponse`, `parseItemFromResponse(item, i)`, `afterParseResponse`, `validateTags`, `translateOrSyntax`, `searchCount`, `countIsQuestionable`, `hasSizeData` |
| Post | `makePostURL(id)`, `loadItem({item, withCapctha})` + `hasLoadItemSupport`, `shouldUpdateIteminTagView`, `shouldPopulateTags` / `populateTagHandler` |
| Tags | `hasTagSuggestions`, `makeTagURL`, `parseTagSuggestionsList/parseTagSuggestion`, `tagTypeMap`, `tagNamespace(tag)`, `tagNamespaceSections`, `tagCatalog` (§4.3), `availableMetaTags()`, `metatagsCheatSheetLink`, `getTagDisplayString` |
| Comments / notes | `hasCommentsSupport`, `makeCommentsURL`, `parseCommentsList/parseComment`; `hasNotesSupport`, `makeNotesURL`, `parseNotesList/parseNote` |
| Account | `hasSignInSupport`, `canSignIn/signIn/isSignedIn/signOut`, `usesUserId/usesApiKey`, `userIdLabel/apiKeyLabel`, `hasSiteFavourites` + `setSiteFavourite(item, value)`, `getCookies` |
| Requests | `getHeaders()`, `getMediaHeaders()`, `mediaOutageNotice(url)`, `onMediaError(url, e)`, `beforeMediaRetry(url)` |
| Doujin | `hasReader` (posts are books → `ReaderHandler`), `readerImageQualities`, `supportsLanguageFilter/TitleLanguage`, `relatedVersionsQuery` |
| Misc | `searchModifiers()`, `animatedPreviewFilters`, `storeTagsGlobally`, `hasNativeOrSupport`, `liveFilter` exemptions |

Per-source knowledge that is *not* a handler override lives in these layers:

- **`SiteProfile`** (`data/site_profile.dart`, instances in
  `data/site_profiles/`): per-HOST deviations from a handler family (bakemono
  is gelbooru-compatible but has its own autocomplete route and multi-file
  posts; kemono's profile tells `PostFilesHandler` how to read a post's
  files). Every hook defaults to "no opinion". Resolved by host.
- **`PostFilesHandler`**: sites where one post holds several files
  (carousel). Fetches the post page as **plain text**
  (`ResponseType.plain`, `bodyText()` re-encodes if Dio decoded it),
  `parsePostFiles` via the profile, caches, sets `downloadFileName` per file
  (honoured by `ImageWriter.getFilename`). The viewer shows a burst badge and
  a toolbar action when `displayable(files)` has more than one.
- **`PoolSource`** (`handlers/pool_source.dart`): per-site pool routes
  (e621, Danbooru family, gelbooru HTML); `forBooru()` null = no pools entry.
- **`TagIndexSource`** / **`BooruTagStore`** (§4.3).
- **`ReaderHandler`**: per-post ordered page lists + `ReaderProgress` table.
- **`SuggestionEngine`** + **`InterestsHandler`** + `foryou_handler`: the
  For You feed and post-page suggestions (facet blend modelled on
  rule34.xyz; interest signals with a 30-day half-life, local only).
- **`TagAliasResolver`**: cross-booru tag translation via the target's
  autocomplete (find-elsewhere, tag preview).
- **`DownloadsReconciler`**: the Downloads list is the DB, not a directory
  scan; this finds rows whose file vanished.
- **`DrawerRefresh.tick`**: bump it after anything that changes drawer
  content; sections listen and reload.
- **`SourceCaptureHandler`** (Settings → Debug → Source capture): records
  a site's pages, in-page fetches, headers and refusals from the phone's
  WebView into a journal file the user shares; this is how sites behind
  Cloudflare (hentaipaw, niyaniya) were written without reaching them from
  here. Redaction shared with the logger.

### 4.3 Tag database and the tag builder
- `BooruTag` (snapshot of a site's tags: type, count, `sourceId`, and the
  site's own `namespace` on doujin/kemono rows) and `BooruTagOverride` (user
  corrections) tables, managed by `BooruTagStore`. Filled by `TagIndexSource`
  walks, opportunistic lookups, snapshot import, or the tag builder's pulls.
- **The tag builder** is the "Tag builder" card under the Metatags card of
  both query editors (`TagBuilderBlock` in `main_search_query_editor_page.dart`;
  since r27 — before that the chips sat inside the Metatags card). One
  `TagCatalogChip` per namespace of `BooruHandler.tagCatalog`; tapping opens
  `TagCatalogPickerSheet` (`widgets/preview/tag_type_strip.dart`), which lists
  the local snapshot most-used first, filter-as-you-type, and starts a paced,
  resumable pull through `TagCatalogPuller` when the namespace holds nothing.
  A picked row inserts `catalog.searchTerm(row)`. With the database off the
  card says so (pulls store nothing without it).
- **Doujin/kemono catalogs** (`TagCatalogSource` implementations beside their
  handlers: `schale_tag_catalog`, `hitomi_tag_catalog`, `asmhentai_tag_catalog`,
  `hentaipaw_tag_catalog`, `nhentai_tag_catalog`, `kemono_tag_catalog`) file
  rows under the site's own namespace. A namespace is offered only if the
  site enumerates it AND the handler's search accepts the term `searchTerm`
  produces.
- **Booru catalogs** (r27): `BooruTagCatalog` (`handlers/booru_tag_catalog.dart`)
  adapts the family's `TagIndexSource`. Namespaces are the site's tag
  categories (Artists, Characters, Copyrights, Species, Meta, Tags), each
  `byType` — read from the snapshot rows with an EMPTY namespace and that
  `tagType` (`BooruTagStore.filterFor / browseNamespace / countNamespace /
  clearNamespace / catalogCounts`), so a list pulled through the Tag browser
  feeds the chips and the other way round. Families: gelbooru 0.2 (one
  shared walk of the count-ordered HTML list, 20 or 50 rows a page with
  `pid` counting rows, 100 pages a pull; gelbooru.com has its own row markup
  and alias rows to skip; realbooru's `model` = artist), danbooru
  (`search[category]`, 1000/page), e621 (`search[category]`, 320/page,
  1 req/s), philomena (`q=artist:*` and `category:…`; names underscored,
  artists typed by their `artist:` name, `origin` = meta), moebooru
  (`tag.json?type=`, 500/page), sankaku (`sankakuapi.com/tags?type=`,
  1000/page, `tagName`). Overrides live on the eight handlers
  (`late final TagCatalogSource? tagCatalog = BooruTagCatalog.forHandler(this)`);
  `SiteProfile.hasTagCatalog` vetoes a host (bakemono). IdolSankaku, Shimmie,
  Hydrus and rule34.xyz have none. A category page whose rows are mostly
  another type logs "ignored the … category filter" once.
- **Tube catalogs:** `rule34video_tag_catalog` (r28, namespace-keyed like
  hentaipaw: the site's tag / model / category async blocks, id or slug as
  `sourceId`) and `hanime1_tag_catalog` (r29): hanime1's whole vocabulary is
  the built-in `HanimeDictionary` (240 tags, each now carrying its
  `HanimeGroup` — the seven search-form groups — plus nine genres), so the
  chips are one instant shard per group (`shards: 1`, no request; the "pull"
  writes the dictionary into the snapshot under the host). Tags insert bare
  (the grammar maps `creampie` back to `tags[]=內射`), genres `genre:mmd`.
- **Tube and gallery catalogs (r31):** `ehentai_tag_catalog` (the site has no
  tag index, so one markdown file per namespace from the EhTagTranslation
  database on raw.githubusercontent.com, parsed in `compute` because
  `character.md` is 718 KB — `shards: 1` per chip, always
  qualified `ns:name` terms, NO `reclass` chip because those rows are the
  gallery categories and the `category:` metatag already covers them; the
  request carries no site headers and no session), `tikporn_tag_catalog`
  (the 84 tags and 131 acts the handler already loads for every search),
  `kusowanka_tag_catalog` (five paged HTML indexes, 42 entries a page,
  20 pages a pull because the lists run to thousands — Artists reports
  8,802 pages; a row keeps the site's display name and routes by the slug
  in `sourceId`, and `lastPageOf` is anchored to the index being walked so
  a sidebar pager cannot truncate it) and `civitai_tag_catalog`
  (`/api/v1/tags?limit=100&page=N` — the API caps a page at 100 whatever
  `limit` asks — 10 pages a pull, walked until an empty page because the
  site's own paging metadata is wrong).
- **The guard** (`tag_catalog_sources_test`, 'every source has a decided
  answer'): every `BooruType.saveable` either offers a catalog or is in the
  `noCatalog` map with a reason. r30 shipped e-hentai with no chips because
  nothing failed; now it would. The map also records what is still to be
  probed (idol sankaku, Shimmie/Szurubooru instances, gelbooru v1,
  rule34hentai, rule34.us, AGNPH, twibooru).
- The **Tag browser** (drawer) reads the same snapshot; its "Pull tag index"
  runs through `TagCatalogPuller` under the `''` namespace (one loop, one
  resume point, progress shared with the chips on shared families).
- Tests: `tag_catalog_sources_test` ("each source offers exactly what it can
  enumerate"), `tag_index_sources_test` (family parsers and exact page URLs
  against fixtures), `booru_tag_catalog_test` (which handlers, the walk),
  `booru_tag_store_test` (byType rows against an in-memory sqlite),
  `tag_builder_block_test` (the card), `tag_catalog_puller_test`,
  `tag_index_live_test` (tagged `live`: one real page per family).


### 4.4 The recommender (r33) — `lib/src/handlers/recommender/`

**The user's standing rule:** no Explore/Plan agents unless strictly needed;
the adversarial reviewer over a diff is the one agent that is always run.

- **Two worlds, two models.** `RecommenderHandler` (GetIt singleton;
  `RecommenderHandler.maybe` is null when unregistered — every caller uses
  that) keeps one `FtrlModel` per `RecommenderWorld` (booru, doujin). A
  doujin item (post-URL host, `DoujinDataHandler.isDoujinItem`) can never
  train the booru model and vice versa — the same wall the classic
  `InterestsHandler` profile keeps.
- **The model** (`ftrl_model.dart`): hashed-feature logistic regression
  trained online with FTRL-Proximal (alpha 0.3, beta 1, l1 0.001, l2
  0.0001), 2^18 buckets, Float32 accumulators; `predict`, `update(label,
  weight)`, `novelty`, `topWeights`, `toBytes`/`fromBytes` (magic `LSRM`,
  version 1). ~2 MB per world at `<path>recommender/<world>.bin`, written
  every 30 s while dirty and at once on `AppLifecycleState.paused`
  (`main.dart`; `flush()` writes now). A missing, corrupt or foreign-bucket
  file is rebuilt by replaying the log.
- **Features** (`item_features.dart`): `tag:<name>` for every tag;
  `type:<tagType>:<name>` (booru) / `ns:<namespace>:<name>` (doujin, from a
  namespaces map, the source handler's `tagNamespace`, or the tag type);
  `site:<host>`, `media:<image|video|animation|book>`, `score:<bucket>`,
  doujin `pages:<bucket>` and `title:<token>`. `ofQuery` (a search as a
  pseudo-item), `ofDoujinParts` (a history entry's namespaced tags),
  `isSeedable`/`seedTerm` (what retrieval may ask for), `describe`
  (readable names). Feature names are kept in `RecommenderFeature` for the
  reports.
- **Rewards** (`rewards.dart`): `InteractionKind` → label + weight; a view
  is graded by seconds (≥ 8 +1, 3–8 +½, < 1.5 = a flick past, −1; 1.5–3
  teaches nothing), a read by fraction (≥ ½ → +2), favourite/collect/finish
  +3, snatch/follow/star +2, unfavourite/blacklist −3, forget −2,
  search/preview/open +½, exposeLapsed −0.3, expose nothing.
- **The log** (`Interaction` table, `database_handler.dart`): every event
  that teaches, with the item's feature hashes — the training set; 20,000
  rows per world kept. Nothing leaves the device.
- **Event sources:** `InterestsHandler`'s entry points forward (views for
  both worlds; favourite/snatch/collect for booru items only — the doujin
  side reports its own through `DoujinDataHandler.toggleFavourite`,
  `addToCollection`, `toggleFollow`, `starTag`, `addSearchHistory`,
  `addHistory` (open)); `SourceSettingsHandler.addBlacklistTag`;
  `DoujinReaderPage` (`gallery:` → `read` at ½, `finish` at the end, once
  each); `DoujinDetailPage._saveAll` (snatch). Exposures: every surface calls
  `onExposed(items, surface)`; an item of the previous batch of that surface
  whose `Thumbnail` was built (`onRendered`, hooked in `thumbnail.dart` —
  a strip hands over thirty and draws four) and never interacted with is a
  quiet no when the next batch arrives, learned but NOT logged (the log is
  what the user did).
- **Surfaces (the rule, guarded by `recommendation_surfaces_test`):** a
  surface that produces recommendations calls `RecommenderHandler.maybe?.rerank`
  (or `scorer`) and `onExposed`. `ForYouHandler` ('foryou'):
  seeds from `seedTerms` first, source posts ordered by score, pages
  reranked; `SuggestionHandler` ('suggested', mix 0.5); `DoujinForYouHandler`
  ('foryou-doujin'); `DoujinRecommendationEngine.rankPersonal` (every doujin
  handler; taste = `personalWeight` 0.5 × (p − 0.5) on top of similarity);
  `NHentaiHandler.afterParseResponse` (its own row ranking, `_recScores`).
  `rerank`: mix of score and incoming order, every 5th slot to the most
  novel item (≥ 60 % unseen features).
- **Switches** (`aiRecommendations`, `aiLearning`, both default true,
  Settings → Recommendations): independent — learning writes and trains
  whatever the ordering shown; a frozen model keeps serving. Learning also
  needs `dbEnabled`. The classic `enableInterestTracking` keeps gating the
  classic profile (the fallback when recommendations are off).
- **The doujin For You** (`doujin_foryou_handler.dart`,
  `BooruType.ForYouDoujin`, in `DoujinDataHandler.doujinTypes`; virtual
  booru 'For You (doujin)', `ensureForYouDoujinBooru`): sources = the
  configured doujin boorus; history mode builds facets from
  `DoujinEntry.tags` (`facetsForEntry`: character, parody, artist quota 3,
  two acts) blended with `SuggestionEngine.blend`; seed mode round-robins
  sources; the dominant reading language (≥ 60 %) is appended on nhentai,
  e-hentai and hitomi (`understandsLanguage`); requests are serialised per
  source (`_lanes` — a handler's search is not re-entrant; the lane waits
  for the real answer while the page stops after `searchTimeout`, counted
  from the real start), each question empties the source's `fetched` and
  keeps the whole answer, and each (source, query) has its own page counter
  (`_pagesAsked` — a cursor-paged site can only serve page 0 of a new
  query; `EHentaiHandler` keeps cursors per query, the last 32, for the
  same reason); `sources` is refreshed per page from
  `DoujinDataHandler.doujinSources()` (`isDoujinSource` = a doujin booru
  that is not the virtual feed — the pickers, Source settings, search
  history hosts and download attribution use it); `handlerForItem` (new
  `BooruHandler` hook, default `this`) hands each card to its source for
  `loadItem`, `relatedVersionsQuery`, page thumbnails; the detail page
  resolves `handler`/`booru` through it. `lastRequests` is the live-test
  diagnostic. `DoujinEntry` carries `tags` (namespaced) and `pages`;
  `updateHistoryTags` fills them when the detail page loads a gallery
  (history writes go through `saveSoon()`, gathered 800 ms, flushed on
  pause). Long-press menu and double-tap resolve a card through
  `handlerForItem` like the detail page; `filterFetched` applies each
  card's own source blacklist on the virtual feed.
- **Tests:** `recommender_ftrl_test`, `recommender_features_test`,
  `recommender_rewards_test`, `recommender_handler_test` (in-memory sqlite),
  `doujin_foryou_test` (fake sources), `doujin_history_tags_test`,
  `recommendation_surfaces_test`, `recommendations_page_test`, the reader
  milestones in `doujin_reader_test`; live: `doujin_foryou_live_test`.
- **r35 adds** the downloadable encoder (§4.5), "Not interested" and video
  completion as a signal.


### 4.5 The encoder, "Not interested", video completion (r35)

- **The encoder** (`recommender/encoder_handler.dart`, GetIt singleton
  `EncoderHandler`, `maybe` when unregistered; registered in `main.dart`
  after the settings, then `refresh()`): a Hugging Face ONNX sentence model
  the user downloads from Settings → Recommendations → Downloaded encoder.
  Presets `EncoderPreset.english` (`Xenova/all-MiniLM-L6-v2`,
  `onnx/model_quantized.onnx` 22,972,370 bytes, dim 384, uncased, BERT with
  `token_type_ids`) and `multilingual`
  (`Xenova/distiluse-base-multilingual-cased-v2`, 135,317,281 bytes, dim
  768, cased, DistilBERT), or any repo with the same layout (`vocab.txt`
  WordPiece, `tokenizer_config.json`, `config.json`). Files live at
  `<path>encoder/<slug>/` (`model.onnx`, the three side files,
  `manifest.json`); a download goes to `.download-<slug>/` first and is
  renamed into place. Settings: `encoderModel` ('' | preset id | repo id),
  `aiEncoder` (default true). `enabled` = switch on and status ready.
  `status` is a `ValueNotifier<EncoderStatus>` (none / downloading with
  progress / ready with dim, bytes, date / error). Test seams: `fetcher`
  (Dio download) and `runnerFactory` (the ONNX runner).
- **Tokenizer** (`wordpiece_tokenizer.dart`): HuggingFace's BertTokenizer
  in Dart — clean, CJK ideographs one per token, lowercase + NFD-style
  accent stripping (uncased), punctuation split, greedy `##` pieces,
  `[UNK]`, `encode` → `[CLS] … [SEP]` at most 96 ids. `fromVocabText`: line
  index = id. Verified against the real English vocabulary live
  (`encoder_live_test`).
- **Runner** (`onnx_embedding_runner.dart`, `flutter_onnxruntime` 1.8.5):
  `OnnxRuntime().createSession(path)`, `Int64List` inputs (`OrtValue.fromList`
  infers int64 from `Int64List` — a plain `List<int>` would become int32),
  `input_ids` / `attention_mask` / `token_type_ids` by the session's own
  input names, first output flattened; the handler mean-pools under the mask
  and L2-normalises (`_pool`), batches of 8 padded to the longest.
  **Inference has never run off a phone** — the plugin is native; the PC
  suite uses fake runners. R8 keeps `ai.onnxruntime.**`
  (`android/app/proguard-rules.pro`, wired in `build.gradle.kts`).
- **Cache**: memory LRU (`_memory`, 4000 entries, keys `k:<item key>` /
  `t:<text>`) and the `ItemEmbedding` table (`putEmbeddings`,
  `getEmbeddings`, `clearEmbeddings(model)`, `pruneEmbeddings(keep 6000)` on
  the learner's prune tick). `embedItems` = memory → DB → model;
  `cached(item)` is the sync lookup a scorer loop uses. Text:
  `EncoderHandler.textOf(item, world)` (title for doujins, then names, then
  tags as words, ≤ 32) and `textOfDoujinParts`.
- **In the learner**: `FeatureVector` gained `values` (real-valued
  features) and `logged` (how many leading binary features go to the log —
  the encoder's components are never logged); `FtrlModel.predict/update`
  take `values`. `ItemFeatures.withEmbedding(base, vector, model, taste)`
  appends `emb:<model>:<i>` (value `e_i·√dim`) and one binary
  `taste:<model>:<tenth>` (cosine with the world's centroid).
  `RecommenderHandler._featuresFor` builds that for `onEvent`, `onExposed`,
  `score`, `rerank`, `scoreDoujinParts`; `scorer(world, items:)` pre-embeds
  the candidates so the sync closure reads `cached()`. The taste centroid
  (`_Taste`, EMA rate 0.1, first vector as is) learns from positive rewards
  of weight ≥ 2 and is saved as `recommender/<world>.taste.json` with the
  model slug it belongs to; `report` exposes `encoderFeatures` (emb hashes
  with weight) and `tasteCount`. nhentai's raw-row ranking has no vectors.
- **Not interested**: `InteractionKind.notInterested` (−, weight 3);
  `RecommenderHandler.dismiss(item)` → the event + `_dismissed[world]`;
  `isDismissed`, `withoutDismissed(items)` — applied by every surface
  (guarded by `recommendation_surfaces_test`); `_load(world)` reads the
  dismissed keys back from the log (`DBHandler.interactionKeys`), so they
  survive restarts as long as the log rows do (20,000 per world). UI: the
  doujin card menu row `doujin-menu-not-interested` on recommendation-feed
  tabs; the booru viewer's `GalleryButton.notInterested` (`'not_interested'`,
  shown only on recommendation-feed tabs, in the button-order settings
  too). Both remove the item from the tab's `fetched` and re-filter.
- **Video completion**: `VideoCompletionTracker` (`handlers/`), once per
  item at ≥ 0.9 or on a wrap from ≥ 0.5 to < 0.1; hooked in
  `video_viewer.dart` (`updateVideoState`, only while `isViewed`) and
  `better_player_view.dart` (`progress`/`finished` events, `widget.isViewed`)
  → `InterestsHandler.onVideoCompleted` → `videoComplete` (+, weight 2) and
  the classic profile +4.
- **The doujin tab's error screen** (`doujin_tab_view.dart`): Grok's r34
  (Close tab, `DoujinMiniTabEdgeHandle` shared from the mini tab manager,
  Retry through `retrySearch`) plus a Tabs button, Open in browser, Copy
  link and the tab handler's `errorString` as the reason.
- **Tests:** `wordpiece_tokenizer_test`, `encoder_handler_test` (fake
  runner: presets, download/manifest/delete, text, pooling, caches),
  `video_completion_test`, `doujin_tab_view_test`, additions in
  `recommender_handler_test` (dismissals through the log; an encoder makes
  "alice_liddell" read like "alice"), `recommender_ftrl_test` (values),
  `recommender_rewards_test`, `recommendation_surfaces_test`
  (`withoutDismissed`), `doujin_menu_test`, `recommendations_page_test`
  (the Encoder section); live: `encoder_live_test` (vocabulary, file sizes).
- **Next:** run the encoder on a phone (the first real evidence); if the
  UI-isolate conversion of the output list is felt, move pooling to an
  isolate; a "why this" line on cards from the taste cosine.
- **r36, exhentai access re-check** (`ehentai_session_handler.dart`,
  `ehentai_handler.dart`, `source_settings_page.dart`): exhentai's
  `igneous=mystery` is the site's refusal of an account from an address
  (too new, or a distrusted address such as a VPN exit). The session file
  keeps `igneousAt`; `needsRecheck` (logged in, no access, > 24 h — 1 h
  after a probe that got no answer); `EHentaiHandler.usingExHentai`
  starts one `fetchIgneous()` behind the page when due (`_recheck`,
  `pendingRecheck` for tests); the settings row has "Check again". The
  user's standing rule since r35: no agents without asking, no test runs
  beyond the touched files plus one full suite before a build.


### 4.6 Doujin browse filters and the doujin search window (r37)

- **The model** (`boorus/doujin/doujin_filters.dart`): `DoujinFilterSpec`
  = groups (`DoujinFilterGroup(key, label, options, multi, defaultValue)`),
  declared per source through `BooruHandler.doujinFilters` (null = none).
  A choice travels IN THE QUERY as the source's term (`sort:popular`,
  `category:manga`, `language:english`, hitomi's `popular:week` and
  `type:manga`); `DoujinFilters.selected/apply/strip` read and rewrite
  those terms; an option value of '' means "no term" (a Latest that is the
  plain listing). `defaultValue` = what the source does when the query
  names nothing (read from the per-source `defaultSort` where one exists).
- **Per source:** hdoujin/niyaniya (`SchaleHandler`): `sort:latest` →
  `/books?page=`, `sort:popular` → `/books/popular` (the API's only two
  shelves — named `sort=` parameters answer 400, numeric ones are silently
  accepted with unknown meaning; probed 2026-09-14 with the app's headers
  against `api.hdoujin.org`, 429 after ~8 requests); an empty query still
  opens Popular unless `defaultSort` is `latest` (`defaultShelfIsPopular`);
  language. e-hentai: `sort:popular` → `$site/popular` when the query is
  otherwise empty (one list of 50, same `itg glte` table, page 2 locks),
  categories multi (`EHentaiQuery.categoryBits`), language. hitomi: key
  `popular` (today/week/month/year, '' = latest index), `type`, language.
  nhentai: its existing sort/category/language grammar, default from
  `defaultSort`. asmhentai, hentaipaw: language. eahentai, faccina: none.
- **The window** (`main_search_query_editor_page.dart`):
  `SuggestionsMainContent` takes `queryText`/`onQueryReplaced` (both
  editors pass them; the tag editor only with `allowMultipleTags`); on a
  doujin source it shows `DoujinFiltersBlock` (FilterChips with checkmarks,
  keys `doujin-filter-<key>-<value|none>`) first and hides History, Pinned
  and Popular; booru tabs unchanged.
- **Tests:** `doujin_filters_test` (grammar, each source's spec and URL
  mapping, the card's tapping rules).
- **Next:** hdoujin's numeric sort codes (title/pages/views/favourites) and
  its category filter once known; filters as a saved per-source preference.


### 4.7 The tab cards, the tab pill, the tab manager's doujin rows (r38)

- **`FlowTabCarousel`** (`widgets/preview/flow_tab_carousel.dart`): every
  tab has a card (`KeyedSubtree` key `flow-card-<index>`); the active one
  is wide and the list jumps to `active × (peekWidth + gap)` (clamped to
  the scroll extent) when the active tab changes, so the earlier tabs are a
  scroll to the right away. Each card shows `coverUrlOf(tab)` — the doujin
  tab's saved `doujinThumb`, else the first loaded item's thumbnail.
  `large: true` (taller cards, bigger covers) and `onPicked` are for the
  pill's sheet.
- **`TabPill`** (`widgets/preview/tab_pill.dart`, setting `tabPill`, default
  off, Settings → User interface "Tab pill (experimental)"): a floating pill
  in the feed (`waterfall_view.dart`, at the scroll buttons' height on the
  other side) showing the tab's cover and "n/total"; tap →
  `TabPill.openStrip` (a modal sheet with the large carousel; a pick closes
  it), horizontal fling → previous/next tab (`changeTabIndex(byUser)`),
  long-press → `TabManagerPage`. The idea is the phone browsers' tab-count
  button plus swipe-the-address-bar switching.
- **`TabRow.doujinCoverHeight`** (default 32; 0 = no inline cover): the tab
  bar keeps 32; `TabManagerItem` passes 0 and draws a 76-pixel cover at the
  row's left, in a 104-pixel row (r39, see §4.8).
- **Tests:** `tab_cards_test` (both directions on a phone-wide surface,
  covers, the pill's tap/pick/fling, the big cover).


### 4.8 The request storm and the slowness (r39)

From the log of 2026-09-15 03:10 (about 10,000 error lines in 40 s):

- **The tab strip built every card.** r38's `FlowTabCarousel` had cards of
  different widths in a `ListView.separated`, and jumped to the active card:
  a list without fixed extents lays out every child before the target, so
  with 4,529 tabs each tab switch built thousands of cards, each starting a
  `BooruFavicon` load. Now `ListView.builder` with `itemExtentBuilder`
  (active 280 / others 180 / add 54, each + 10 gap; large 320/220), the
  jump is `active × (peekWidth + gap)`, and `FlowTabCarousel.cardsBuilt`
  lets `tab_cards_test` assert a far tab builds under 40 cards. The cover
  sits at the card's left, full height (`_withCover`); in the query line
  it overflowed the card on a phone. **Rule: any horizontal or vertical list
  that jumps to an index must have fixed or builder-given extents.**
- **The WebView cookie jar stops answering after the app was in the
  background** (Android reaps the WebView). `Tools.getCookies` runs from the
  Dio interceptor on every request and waited out `cookieJarTimeout` (5 s)
  each time: 6,848 requests in 38 s. Now: one read per host at a time
  (`_cookieReads`), and a timeout pauses the jar for `cookieJarPause` (30 s,
  `cookieJarPaused`) — requests go without jar cookies, `saveCookies`
  skips — then it is asked again. Seams: `cookieJarReaderOverride`,
  `cookieJarTimeoutOverride`, `cookieJarPauseOverride`,
  `resetCookieJarForTests` (`cookie_jar_timeout_test`). A site that needs a
  jar cookie (clearance, login) can fail for up to 30 s after a resume.
- **A tab switch cleared every decoded image** (`forceClearMemoryCache
  (withLive: true)` in `changeTabIndex`): returning to a tab redrew every
  thumbnail. Now `Tools.trimMemoryCacheIfFull()` (only above 80 % of the
  cache's size or count, never live images).
- **Switching back to a doujin tab counted as a new open** (history + the
  recommender's `open`): `DoujinTabView` rebuilds `DoujinDetailPage` on every
  switch. `DoujinDetailPage.claimOpen(tabId, postURL, asTab:)` records a
  tab's open once per session.
- **The tab manager's doujin rows** overflowed their fixed extent with r38's
  88-pixel inline cover: `TabManagerItem.extentFor(tab)` (104 for doujin, 80
  otherwise) feeds `_ensureDisplayCache`; the cover is drawn at the left.
- **Empty spacers** (`SettingsButton(name: '', enabled: false)`) drew blank
  cards since the settings became cards; they are 10-pixel gaps again.
- The favicon chain itself is bounded (url → DuckDuckGo → letter tile, per
  host via `FaviconResolver`); what multiplied it was the number of widgets
  starting it at once.

### 4.9 FurAffinity, and the tab pill kept to its section (r40)

- **No content API.** `status.furaffinity.net/api/v1/` is site status only.
  Every page is read from HTML behind Cloudflare with the browser
  User-Agent. Fixtures in `test/fixtures/furaffinity_*.html`, captured
  2026-09-15.
- **Routes** (`lib/src/boorus/furaffinity_query.dart`): `''` browse,
  words go to `/search/` by GET with `mode=extended`, `user:`/`gallery:`/`artist:`,
  `scraps:`, `favorites:` (paged by the cursor in the "next" form, kept per
  query and page in the handler), `id:N`. Filter terms: `sort:`, `order:`,
  `type:` (default art+photo), `rating:`, `range:`, `category:`/`theme:`/`species:`
  by the site's ids.
- **Handler** (`furaffinity_handler.dart`, parser in `furaffinity_parser.dart`):
  a card is its listing thumbnail (`@600` sample) until opened;
  `loadItem` reads `/view/N/` for the full file. GIF becomes animation,
  audio plays through the video player, anything else is unknown.
  The tag builder reads the `/search/` selects (`furaffinity_tag_catalog.dart`).
- **Login** (`furaffinity_session_handler.dart`, `furaffinity_login_page.dart`):
  a WebView on `/login/` (Turnstile), cookies `a` and `b` copied to
  `furaffinity_session.json` and scrubbed from the jar. The Cookie header
  goes only on the handler's page requests; `sendsJarCookiesToMedia` is
  false. "Content filter" seeds the jar for a visit to `/controls/settings/`.
- **Artist card** (`widgets/preview/furaffinity_artist_header.dart`), in the
  waterfall after the kemono header: avatar and counts from `/user/name/`,
  Gallery/Scraps/Favorites chips, and Strips (three `TagContentPreview` rows).
- **Generic hooks added:** `BooruHandler.mediaIconFor(item)` for the
  thumbnail's bottom-right icon (null keeps `Tools.getFileIcon`);
  `DoujinFilterGroup.defaultValues` (a multi group's defaults show checked
  and a tap starts from them); the Filters card shows for any source that
  declares `doujinFilters`, while History/Pinned/Popular stay hidden only
  for doujin sources.
- **Tab pill** (user request 2026-09-15): `FlowTabCarousel.sectionIndexes`
  splits tabs by `hasReader`, the same split as the tab manager's source
  view. The pill's count and swipe and the carousel's cards use it; card
  keys keep the tab's own index. `TabPillHost` places the pill in the feed:
  hold and drag moves it, the place is saved as fractions in
  `tab_pill.json`, a hold without a move opens the tab manager.
- **r41, planned:** Watch/Unwatch, an `inbox:` feed, the watched artists
  sidebar, favourite sync.

### 4.10 FurAffinity's session in webviews, filter feeds, and Modular UI (r41)

- **The session lost to a webview.** r40 scrubbed `a`/`b` from the shared
  jar after login. A FurAffinity page opened in any webview was then a guest
  visit, the site gave it a guest `b`, and `DioNetwork.cookieInterceptor`
  merges the jar over the handler's `Cookie` header (last value wins), so
  every later request went out as guest (device log 2026-09-15 09:22).
  Now the session stays in the jar. `InAppWebviewView` waits for
  `FurAffinitySessionHandler.prepareWebView` on a FurAffinity URL (it deletes
  host-only and domain `a`/`b`, then sets the account's on
  `.furaffinity.net`), and on dispose calls `syncAfterWebView`: both
  cookies in the jar are taken as newest, a jar without them gets the
  account back (`afterWebView`, pure and tested). Logout scrubs the jar.
  Media still never gets jar cookies (`sendsJarCookiesToMedia` false).
- **Filters on the main feed.** `/browse/` cannot sort or filter by type, so
  filter terms without words route to `/search/` with `q=` empty (checked
  live: 48 results). New terms: `gender:` (sent as `gender-<value>=1`, named
  after the logged-in form's rating/type boxes; not visible logged out, so
  unverified), `mode:`, `perpage:` (24/48/72), `from:`/`to:` (yyyy-mm-dd,
  `range=manual`). A filter key with an unknown value is dropped.
- **Profiles answered with 400** (the site does this for some artists even
  logged out) are cached as null for the session.
- **Modular UI** (user rule 2026-09-15, see Part A): every UI part the user
  asks to remove becomes a switch in Settings → Modular UI
  (`lib/src/data/modular_ui.dart`, `pages/settings/modular_ui_page.dart`).
  Values live in `SettingsHandler.modularUi`, written by `toJson` next to
  `hiddenTagsPerBooru` and read in `loadFromJSON`, so they load before the
  first screen and ride along in settings backups; only values differing
  from the default are stored. Widgets check `ModularUi.isOn(...)` in an
  `if` where they build, never build-then-hide. First switches: the search
  window's History, Pinned tags and Popular tags, all off by default for
  every source (replacing r37's doujin-only hiding).

### 4.11 FurAffinity's sidebar, post page, blocklist, account, Flash; the Drive link (r42)

- **Sidebar** (`widgets/drawers/furaffinity_sidebar.dart`): the kemono look
  (`FaSection`/`FaPill`), chosen in `mobile_home_page.dart` like
  `KemonoSidebar`, switched by `SettingsHandler.furAffinitySidebar` (the
  normal drawer's Quick access switches back). Browse / You (inbox, watched,
  favorites, gallery) / the tab's artist (gallery, scraps, favorites, folders,
  watch) / account (log in, blocklist import, content filter, log out).
- **Post page** (`pages/furaffinity_post_page.dart`, opened from the viewer
  app bar and the tag view): picture, stats, description (`LoliHtml`), the
  submission page's mini gallery with Older/Newer, folders, keywords,
  comments, the site favourite. `fetchPage` is injectable for tests.
- **Parser additions** (`furaffinity_parser.dart`): figure ids are `sid-N`
  on listings and `sid_N` in the mini gallery; `.submission-folder`,
  `.comment_container`, `.minigallery-navigation`; `userFolders` from the
  gallery page's `.user-folders` (h4 = group); `watchLink`/`favLink` need a
  non-empty `?key=`; `loggedInUser` reads the header's
  `.loggedin_user_avatar`; `watchlist` pages 200 at a time (`?page=N`);
  `inboxCursor` reads `/msg/submissions/new~ID@N/`. Dart RegExp has no inline
  `(?s)`: use `dotAll: true`.
- **Blocklist:** logged in, every page's `<body>` carries
  `data-tag-blocklist`, `data-user-blocklist` (`u_name`),
  `data-tag-blocklist-hide-tagless` and `data-tag-blocklist-nonce` for the
  site's `censor.js`, which only blurs. `FurAffinityParser.listing` leaves
  blocked figures out; the session keeps the last blocklist and name.
- **Routes:** `folder:user/id/slug`, `inbox:`, `animated:gif` (adds
  `@filename gif`, forces extended mode; verified live that results are .gif
  files while "animation" also returns stills). Favourites sync through
  `hasSiteFavourites`/`setSiteFavourite`.
- **Flash** (`pages/flash_player_page.dart`): a WebView page with the Ruffle
  script FurAffinity itself serves (`d.furaffinity.net/media/ruffle-0.2.0/`)
  and `player.load({url})`; the SWF host answers
  `access-control-allow-origin: *`. Flash pages have no `#submissionImg`:
  the file is `object#flash_embed[data]`, else the `/download/` link.
- **Drive link** (`services/drive_backup.dart`): the device log showed the
  token exchange failing with "Failed host lookup: oauth2.googleapis.com"
  while the browser was in front. The browser page now says "go back to the
  app"; the exchange waits for `AppLifecycleState.resumed`, tries three token
  addresses twice (`exchange`, tested), and failures open a dialog
  (`friendlyError`).
- **Unverified logged in** (built from the site's script and logged-out
  pages): the inbox Next link, the watch/fav links with a key, the header
  avatar's class, the gender boxes' names.

### 4.12 Source settings for booru sources (r43)

- **Page:** `SourceSettingsPage(booru:)` returns `BooruSourceSettingsView`
  (`pages/settings/booru_source_settings_view.dart`) for any source without a
  reader: account (edit page, or FurAffinity's login), "Always add to
  searches", "Default filters" (a `DoujinFiltersBlock` bound to the stored
  terms), hidden tags (count, `TagsFiltersPage`), About this site. The left
  drawer shows "<source> settings" for booru tabs (Modular UI
  `sidebar.sourceSettings`).
- **Site filters** (`boorus/booru_site_filters.dart`):
  `BooruHandler.siteFilters` is the handler's own `doujinFilters`, else
  `BooruSiteFilters.fromMetaTags(availableMetaTags())`: every
  `SortMetaTag`/`OrderMetaTag`/`rating` metatag with values becomes a single
  choice with "Site default" (`''`) first; values ending in `asc` and
  md5/custom/none/modqueue are dropped. Local DB views, recommendation feeds,
  merge and webview sources get none. The search window shows them (Modular
  UI `search.siteFilters`) through `SourceSettingsHandler.withDefaults`.
- **Search:** `BooruHandler.search` calls `sourceQuery(tags)` before
  `translateOrSyntax`: `SourceSettingsHandler.composeQuery` appends the
  stored default of every filter group the query leaves unset (only values
  the site offers), then the always-add terms not already present. Doujin
  sources are untouched. Stored as `SourceSettings.alwaysAdd` /
  `defaultFilters` in `sourceSettings.json`.
- **Derpibooru:** `filter:`/`sf:`/`sd:` terms are stripped from `q` and sent
  as `filter_id`/`sf`/`sd`. System filters (checked 2026-09-15): Everything
  56027 (the app's default), Default 100073 and Legacy default 37431 hide
  explicit, 18+ R34 37432, 18+ Dark 37429, Maximum spoilers 37430. Those ids
  are derpibooru's only; other Philomena sites get sort/direction.
- **Rundown, live checks 2026-09-15** (`BooruSiteNotes`): danbooru/AiBooru
  `rating:g,s` and `order:` work; AllTheFallen's API answered a Cloudflare
  page; e621/e6ai `rating:`/`order:` work; gelbooru.com returns nothing
  without API key + user ID, rule34.xxx says "Missing authentication";
  tbib/xbooru accept both rating vocabularies (xbooru Cloudflare on
  `sort:score:desc`); realbooru's API is off. Sankaku, Idol, Civitai, RedGifs,
  r34 World, Tik.Porn, xxxtik, xxxfollow, nozomi and Rule34.dev already had
  their own sort/order metatags, which now feed their Filters.

### 4.13 e621 first: contributors, the cheatsheet as filters; the source-aware blur (r44)

- **User plan (2026-09-15):** give every source the tag builder and
  interactive filters for all its search options, source by source; e621
  first (build), then the rest.
- **Tag types:** `TagType.contributor` (after artist) and `TagType.lore`
  (after species) are new enum values; names are stored as strings, so old
  rows stay valid. Their `locName` is English only ("Contributor", "Lore")
  until the translation files get the keys. Colours in `getColour`, icons in
  `tag_hub_page`, similarity weight 5 for contributors, chips in
  `TagIndexSource.catalogOrder`/`typeNamespace`.
- **e621 tags:** posts carry nine groups (general, artist, contributor,
  copyright, character, species, invalid, meta, lore); r43 and before read
  six and dropped the rest. `tagTypeMap` gains '2' contributor, '8' lore,
  '6' invalid→none; `E621TagIndex.categoryCodes` lists contributor '2' and
  lore '8' (live: `warfaremachine_(modeler)`, `incest_(lore)`).
- **Filters:** `e621Handler.doujinFilters` is the cheatsheet's choosable
  options, one choice per group (e621 ANDs repeated metatags): order (15),
  rating s/q/e, type, date, score/favcount `>=N`, duration, status, ischild,
  isparent, inpool, hassource, hasdescription, artverified. Text and number
  metatags (user, fav, commenter, approver, pool, set, source, description,
  note, parent, md5, id, score, favcount, comment_count, tagcount, conttags,
  width, height, mpixels, duration, randseed) are `availableMetaTags`.
- **Blur:** `BooruItem.isHidden` returned `isItemHiddenGlobally`, which never
  honoured `Booru.ignoreGlobalBlacklist` or the per-source list, so a source
  set to ignore the global blacklist still blurred what only the global list
  hid. `filterFetched` now stores `item.hiddenInSource` from
  `isItemHiddenForBooru` (removal and blur share one answer); `isHidden`
  prefers it.
- **Tag types are written asynchronously** (`TagHandler.addTagsWithType` is
  async): a test reads them after `pumpEventQueue()`; `typeOfTag` belongs to
  the tag view, not the handler.

### 4.14 The Danbooru and Gelbooru engines' search help as filters (r45)

- **Where:** `BooruEngineFilters` in `boorus/booru_site_filters.dart`;
  `DanbooruHandler`, `GelbooruHandler` and `GelbooruAlikesHandler` return
  them as `doujinFilters`, so they replace r43's metatag-derived groups.
- **Danbooru engine** (danbooru, AiBooru, AllTheFallen), from
  help:cheatsheet: order, rating (full words kept from r43 so saved
  defaults still apply, plus `g,s`/`q,e`), filetype, age (`<1d` to `<1y`),
  score and favcount `>=N`, status, parent and child (`any`/`none`),
  commentary, duration. Checked live 2026-09-15: age:<1w, filetype:mp4,
  is:parent, has:children, score:>=100, rating:q,e, is:sfw, status:deleted,
  commentary:true.
- **Gelbooru engine:** sort (score, updated, random, id:asc, width,
  height), rating in the site's words (gelbooru.com general/sensitive, the
  booru.org sites safe/questionable/explicit), score, width, height;
  rule34.xxx adds aspectratio. Checked live on tbib and xbooru: score:>=10,
  width:>=1920, sort:random, sort:updated:desc.
- **Order of checks:** `BooruHandler.siteFilters` now rejects local views,
  feeds, merges and the webview before returning a handler's own spec,
  because `DanbooruHandler` also serves the Favourites view.
- **Chip keys:** `DoujinFiltersBlock` keyed the site-default chip
  `doujin-filter-<group>-none`, which collided with danbooru's real `none`
  value in parent:/child: and crashed the whole card (caught by the source
  settings widget test before delivery). The default chip is now
  `-(default)`. `test/filter_chip_keys_test.dart` renders every declared
  spec and checks unique keys; add each new source's spec to it.

### 4.15 The long tail: every handler choice list as a filter; Derpibooru ranges (r46)

- **Derivation widened:** `BooruSiteFilters.fromMetaTags` turns every
  `MetaTagWithValues` with a key and a `:` divider into a single choice, not
  only sort/order and rating. Only sort and order lists drop ascending twins
  and technical values (md5, custom, none, modqueue); a list keeps a real
  `none` (Sankaku parent:). Duplicate values are dropped. This gives filters
  to Civitai (sort, period, nsfw, type, basemodel), Rule34.dev (source), r34
  World (sort, feed), Sankaku (order, rating, parent), Hanime1 (sort, genre),
  Kemono/Pawchive (service, popular, favorites), and sort to RedGifs, nozomi,
  Tik.Porn, xxxtik and xxxfollow.
- **Derpibooru:** `score.gte`, `faves.gte`, `width.gte`, `animated`,
  `duration.gte` groups stay inside `q` (Philomena only swaps `_` for `+`,
  then spaces for commas). Checked live 2026-09-15, comma-joined. No date
  group: relative dates need spaces (`7 days ago`), and the underscore form is
  rejected by the site.
- **Nothing to filter yet:** Idol Sankaku, rule34.paheal, R34US, R34Hentai,
  Kusowanka declare no metatags; they need per-site research.
- **Backup tags buttons:** "Backup tags" and "Restore tags" on the backup
  page are shown only in Debug mode (`if (settingsHandler.isDebug.value)`,
  upstream commit 525e3f8b7, 2026-03-14). Debug mode turns on after six taps
  on the version row at the bottom of Settings and off with a long press.

### 4.16 paheal and rule34.us filters; the filter divider (r47)

- **Divider:** `DoujinFilterGroup.divider` (default `:`) is used by
  `DoujinFilters.selected/apply/strip` (optional named `divider`), the
  Filters card chips, `SourceSettingsHandler.composeQuery` and
  `withDefaults`. Shimmie writes some terms with `=` or `>`.
- **rule34.paheal** (`ShimmieHtmlHandler`): content (`:` video/audio), ext
  (`=`), score (`>`). Checked live 2026-09-15 on "cat": 81 posts;
  content:video 14; ext=webm 1; score>10 16. `order:score_desc` changed
  nothing, so no sort.
- **rule34.us** (`R34USHandler`): sort (score), score (`>10`, `>50`,
  `>100`). Live: `sort:score` and `score:>10` change the first posts;
  `rating:explicit` does not.
- **Left, with reasons (in `BooruSiteNotes`):** Kusowanka browses one tag at
  a time; rule34hentai.net answered the PC with a Cloudflare check; Idol
  Sankaku inherits Sankaku's filters, but its API (`iapi.sankakucomplex.com`)
  returned an empty body to plain requests, so its values are unverified.
- **Backup tags buttons:** "Backup tags" and "Restore tags" show only in
  Debug mode (upstream, 2026-03-14); six taps on the version row at the
  bottom of Settings turn it on, a long press turns it off.

### 4.17 A Flash post in the viewer is a Play button (r48)

- **Before:** a FurAffinity Flash card is `needToLoadItem`; the gallery page
  showed `LoadItemViewer`, `loadItem` set the type to `unknown`, and the last
  `else` branch opened `GuessExtensionViewer`, which ended on "Failed to
  guess the file extension" while the top bar already offered Play.
- **Now:** `gallery_view_page.dart` checks `FlashPlayViewer.shouldShow(item)`
  first (Flash by the listing's `type:flash` or a `.swf` file, and not
  already an image/animation/video). `FlashPlayViewer`
  (`widgets/video/flash_play_viewer.dart`) shows the thumbnail, a Play
  button (`FlashPlayerPage.openFor`) and "Open post in browser", and reads
  the post page in the background (`loadItem`, cancelled on dispose) so the
  details and a download get the real `.swf`.
- **Origin:** `FlashPlayerPage.baseUrlFor(item)` makes the player page's
  origin the post's site. e621 serves its `.swf` with
  `Access-Control-Allow-Origin: https://e621.net` (checked 2026-09-15), so a
  FurAffinity origin would have been refused; FurAffinity answers `*`.
- **Tests:** unit tests have no webview platform, so building
  `FlashPlayerPage`'s `InAppWebView` asserts; `flash_play_viewer_test`
  accepts only that assertion after checking the page opened.

### 4.18 Linked media: the links in a FurAffinity description (r49)

- **Why:** many FurAffinity "animated" posts are a still picture; the
  animation is behind a link in the description (often an e621 post, or a
  file such as an `.mp4`).
- **Resolver** (`boorus/linked_media.dart`, pure): `LinkedMediaResolver.linksIn`
  reads the description's `href`s (http(s), relative ones made absolute,
  `/user/` links dropped, each once, in order); `resolve` makes each one a
  `LinkedMedia` of kind `media` (a video/animation file extension, even on a
  source's file host), `sourcePost` (a post URL of an installed booru:
  e621/Danbooru `/posts/N`, Gelbooru family `page=post&id=N`, FurAffinity
  `/view|full/N`, Philomena, Shimmie `/post/view/N`, Moebooru/Sankaku
  `/post/show/N`) or `page`. The search term is `id:N` (`id=N` on Shimmie).
- **Opening** (`widgets/linked_media_sheet.dart`, `LinkedMediaOpener.open`):
  a source post is searched by id in a standalone `SearchTab` and shown in
  `GalleryViewPage` pushed on top (the floating tag preview's pattern); not
  found → a snackbar and the link as a page. A file or a page opens in
  `LinkedMediaPage` (`pages/linked_media_page.dart`): black full screen,
  Reload and Open in browser; a file is played from `mediaHtml` (a
  `<video controls autoplay loop>` or an `<img>`, the address escaped).
- **Where:** the FurAffinity post page's "Linked media" section under the
  description (`LinkedMediaList`, keys `linked-media-<i>`); the viewer's
  link button (`furaffinity-linked-media`) on posts with a tag containing
  "animat" whose file is not a video/GIF/Flash (`LinkedMediaButton.offerFor`),
  reading the post page once per session and listing the links in a sheet.
  The button is Modular UI `viewer.linkedMedia` (area Viewer, on).
- **Tests:** `linked_media_test` (links, resolution, player markup),
  `linked_media_ui_test` (button condition, list labels, a file opening the
  player, the post page section). The description markup is FurAffinity's
  `auto_link` form; a live sample of 24 popular animation posts had no
  external links (those are likely on mature posts, which need the login).

### 4.19 Tag types, hubs, the whole tag index, pinned tags, the top inset (r50)

- **Types in preview tabs:** `BooruHandler.addTagsWithType` also fills
  `ownTagTypes` (kept when `storeTagsGlobally` is off: strips, the floating
  preview, hub tabs). `TagTypeLookup.resolve` (`handlers/tag_type_lookup.dart`)
  is the one answer: your correction → the handler's own parse → the shared
  store (not on doujin) → the tag's own type. `TagView.typeOfTag` delegates;
  "More from" also checks it.
- **Hubs:** `showTagDialog(knownType:)` receives the row's type and passes it
  to `TagHubPage(knownType:)`, so an artist the shared store never stored
  opens the Artist hub. `HubTagQuery.forBooru` (`utils/hub_tag_query.dart`)
  strips tag-type namespaces (`artist:` …) for other sources, except sites
  whose tags carry them (FurAffinity, Philomena, Civitai, Hanime1, InkBunny,
  Rule34Video, XXXTik).
- **Tag index:** `BooruTagCatalog.maxShardsPerPull` is null and booru
  category namespaces have no `maxShards`: a pull runs to `maxIndexPages`.
  `TagCatalogPuller.pullEverything` walks every category (or the one shared
  walk) in turn; `overallState` adds the jobs up (shard = lists finished);
  `cancelEverything` stops the run. The tag browser's Pull tag index uses them,
  so it fills the same lists as the tag builder's chips. Doujin catalogs keep
  their per-pull caps.
- **Pinned tags:** `pages/pinned_tags_page.dart` (`PinnedTagsStore`: database
  for boorus, the doujin store for doujin sources; `PinBuilderSheet`: chips,
  name, scope). `PinnedTag.title` (DB column `title`, added by migration),
  `displayName`, `tags`; `DBHandler.updatePinnedTag`. Follow pins are hidden.
  Quick access row behind Modular UI `sidebar.pinnedTags` (on).
- **Top inset:** `main.dart` used to strip the top inset while the status
  bar is hidden, putting back arrows in Android's swipe-to-reveal edge.
  `StatusBarInset.apply` (`utils/status_bar_inset.dart`) keeps it; Modular UI
  `app.drawUnderHiddenStatusBar` (off) restores the old layout.
- **Linked media:** `LinkedMediaResolver.unwrap` follows FurAffinity's
  `/externalurl/?q=`; `anchorsIn` keeps each link's words; rows show
  `title`, `destination` and `badge`.

### 4.20 Dependencies: the media_kit leak fix, image, dio (r51)

- **media_kit** is a `dependency_overrides` git pin to media-kit/media-kit
  `c533e446` (path `media_kit`), the merge of #1446 (2026-08-30): native leaks
  in the mpv bindings (`getProperty` strings, `setProperty` name pointers and
  async request entries on error paths, the `Media` reference map). Checked
  before pinning: every `media_kit/lib` commit since the 1.2.6 release is
  internal or additive; `Media(...)` became a factory with the same named
  parameters (both our calls use `resource` + `httpHeaders`). media_kit_video
  and the native libs stay on pub (libmpv build v1.1.7; v1.1.8-v1.1.11 only
  changed the encoder bundles). Drop the override when pub has a newer release.
- `flutter pub upgrade image dio`: image 4.10.1, dio 5.11.1. Lockfile changed
  only for these three.
- Still pinned on purpose (commit 1714e278): html 0.15.6 (0.15.7 breaks
  flutter_html 3.0.0's `src/` import) and dynamic_color 1.8.1 (1.9.0's Kotlin
  DSL needs the toolchain upgrade).
- Survey notes for later: the newest video_player(_android), chewie, sqflite
  and app_links need Flutter 3.44+ (flex_color_picker 4 needs 3.47 and
  material_ui); fvp 0.38.1 and better_player_plus 1.4.1 resolve today but the
  user asked to leave the engines alone. `dio_http2_adapter` and
  `native_dio_adapter` are declared but not imported (the HTTP/2 adapter was
  tried upstream in 72a3963e and reverted in 54ee82fe); the app uses
  `IOHttpClientAdapter` on the shared pooled `HttpClient` (dio_network.dart),
  whose self-signed setting a native adapter would not honour.
- The media_kit viewer has no disk cache (only the warm in-memory pool);
  better_player has one, and VideoViewer has `VideoCacheMode`.

### 4.21 Media links everywhere, hidden pins, the keyboard, video swipes (r52)

- **Media links:** `LinkedMediaResolver.mediaLinksIn(html, boorus, base:,
  self:)` keeps posts on installed sources, files, and media pages
  (`isMediaPage`: site + path table); drops profiles, personal sites and the
  post itself. Plain-text addresses are found by blanking anchors and tags to
  spaces (offsets kept); a link without words of its own is named by the text
  before it on its line (`LinkedAnchor.label`). Post URLs are rebuilt from the
  id (`…/posts/2197699Character(s)` → `/posts/2197699`).
- `LinkedMediaStore` (per post URL, `revision` notifier): filled by
  `FurAffinityHandler.applySubmission` (every viewed FA post passes loadItem),
  read by `LinkedMediaButton.offerFor` (any file type now).
- **Toolbar:** Modular UI `viewer.linkedMediaReplacesShare` (on): the share
  `GalleryButton` shows only when the post has links, as the link button
  (icon, label, tap/long-press open the sheet); the r49 separate FA action
  only when that switch is off. `HideableAppbar` listens to the store.
- **"Not found on e621":** paging was right (SearchTab sets the handler's
  `startingPage`, the opener adds one). The id lookup carried the source's
  default filters (`BooruHandler.applySourceSettings` false for it), and
  `LinkedMediaOpener.showFetched` shows `fetched` when the filters emptied
  `filteredFetched`. Live check: `test/linked_media_live_test.dart`.
- **Hidden pins:** `PinnedTagVisibility` (`data/pinned_tag_visibility.dart`),
  keys `id:N` / `tag:x` in `SourceSettings.hiddenPins`; the pinned tags page's
  eye button; `PinnedTagsBlock` filters with `visible()`.
- **Pin autocomplete:** `PinTagSuggestions.forBooru` (BooruTagStore.browse,
  then `dbHandler.getTags`, then the handler's `getTagSuggestions`),
  injectable as `PinnedTagsPage.suggest`.
- **Keyboard:** `main.dart`'s page tree sits in an Overlay entry built once,
  so the hidden-status-bar MediaQuery made in the app builder froze the first
  frame's insets (no keyboard insets anywhere while the status bar is hidden).
  `HiddenStatusBarInsets` (`utils/status_bar_inset.dart`) reads them where it
  is built.
- **Video swipes:** `MediaKitPlayerView` was a black box until its player
  attached (a neighbour page attaches only once viewed unless preloadVideos).
  It now shows the post `Thumbnail` above the video until
  `controller.waitUntilFirstFrameRendered` (`showCover`, reset in `_release`);
  Modular UI `viewer.videoCoverWhileLoading` (on).

### 4.22 Instant page swipe (r53)

- **Why:** the user wants page changes with no animation. The viewer slid
  pages three ways, none new: `slidePageTransition` (since 2024, the page
  shifted by half the drag; Settings > Viewer > "Viewer page change
  animation"), `_SnappyPageSpringPhysics` (June 2026, the settle after
  release) and two 100 ms `AnimatedSwitcher` cross-fades per page. Black pages
  hid the motion; the r52 thumbnail cover made it visible.
- **Now:** `InstantPageSwipe` (`widgets/gallery/instant_page_swipe.dart`):
  the pager gets `NeverScrollableScrollPhysics`, and each page's existing
  tap/long-press `GestureDetector` also takes the drags of the paging axis;
  a swipe past 48 px (or a 700 px/s flick) jumps one page during the drag
  (`controller.jumpToPage`), once per gesture; blocked while
  `viewerHandler.isZoomed`. The slide transform is skipped and the
  cross-fades are zero-length. Deeper drag recognizers (a zoomed photo_view
  pan, the video seek bar) still win their gestures.
- Modular UI `viewer.instantPageSwipe` (on); off restores the sliding pager.

### 4.23 On-device profiling; settled post data (r54)

- **Profiling (2026-09-15, S24 Ultra, r53 profile builds over USB):** frame
  timings via the Dart VM service (`getVMTimeline` returns `traceEvents`; the
  ring recorder holds about 2 s, so fetch and clear every 1.2 s and pair
  begin/end per chunk). Profile builds are signed with the release key
  (`android/app/build.gradle.kts`: `findByName("profile")` gets the release
  signing config, because Flutter creates "profile" from "debug" before the
  app's block runs), so `adb install -r` updates the installed app and keeps
  its data; check `apksigner verify --print-certs` first.
- **Impeller A/B** (manifest `EnableImpeller` flipped for a test build only;
  a launch flag cannot win: FlutterLoader appends the manifest flag after the
  intent's, and fml keeps the last value): grid Dart-side long stalls gone,
  but the viewer gets repeated 150-200 ms `SurfaceFrame::Submit` stalls and
  tabs/sheets miss 30% of draws. Impeller stays off.
- **App-side costs seen on both renderers:** the viewer page change builds
  and lays out the page in one frame (50-80 ms, ~55-60 builds, ~10 ms
  scavenges); every grid thumbnail fades in (AnimatedOpacity) even when
  cached, each fade a saveLayer; the semantics tree is rebuilt every frame
  while an accessibility service runs (the user's Dictate app). Not fixed yet.
- **r54 fix:** after the reinstall the user swiped fast through rule34.xxx
  videos: each post's hidden details panel (`TagView`, built for every page)
  called `reloadItemData(initial: true)` in `initState`, fetching the post
  page; rule34.xxx answered 429 and its CAPTCHA page, and answers arriving
  after the panel was disposed threw at the `setState` in `reloadItemData`.
  The first load now waits `SettledCall.itemDataDelay` (800 ms,
  `utils/settled_call.dart`, cancelled in `dispose`), and `reloadItemData`
  returns when `!mounted` after the await.
- Proposed, not done: a longer media_kit `_initDelay` (200 ms) so flicked-past
  video posts create no player; cached thumbnails without a fade; a lighter
  page change; semantics exclusion; a renderer switch.

### 4.24 Back to r50's engine, packages and swipes (r55)

- **The user (2026-09-15):** the app worked until r51; revert every package,
  media engine and swipe change since then and keep only the functional
  features. No dependency, media_kit pin or Flutter upgrades without an
  explicit request.
- **Reverted:** r51 entirely (`pubspec.yaml` and `pubspec.lock` equal r50's:
  no media_kit git pin, image and dio back); r52's video thumbnail cover
  (`MediaKitPlayerView.showCover`, `_firstFrame`, Modular UI
  `viewer.videoCoverWhileLoading`, `test/media_kit_cover_test.dart`); r53
  entirely (`InstantPageSwipe`, Modular UI `viewer.instantPageSwipe`, the
  gallery drag handlers and zero-duration switchers); r54's code
  (`SettledCall` and the TagView `mounted` guards, the profile build's release
  signing config). Values stored for the two removed Modular UI keys stay in
  settings.json and are ignored.
- **Kept from r52:** linked media on every post and the share-slot button,
  hidden pins and pin suggestions, `HiddenStatusBarInsets`.
- **Evening profiling (S24U, r54 on Flutter 3.42 beta):** with the Dictate
  accessibility service off the grid, viewer and tabs miss far fewer frames;
  Skia beats Impeller on the grid and tabs; an 8K (4320x7680) video froze Skia
  drawing (media_kit sizes the Android surface to the video). A Flutter 3.47.4
  trial (Impeller and Skia) grew the app to 2.9 GB PSS with big videos in the
  warm pool and lmkd killed it; no memory kill on any 3.42 build that evening.
  Not applied.
- Profile builds are debug-signed again: before installing one over the
  user's app, give "profile" the release signing config in
  `android/app/build.gradle.kts` (`findByName("profile")`), or the install
  fails.

### 4.25 Seen thumbnails at once; details built on open (r56)

- From the profiling (§4.23, §4.24), app code only, each behind a Modular UI
  switch that brings the old behaviour back.
- **Seen thumbnails** (`widgets/thumbnail/thumbnail_reveal.dart`, switch
  `grid.seenThumbnailsAtOnce`): a grid thumbnail waited 200 ms before loading
  and faded in over 300 ms (200 ms for the low-quality one under a sample)
  even when the picture was in memory. `ThumbnailReveal` remembers the last
  4000 thumbnail URLs shown this session: a remembered URL skips the wait,
  and a remembered one or a memory-cache answer (`syncCall`) skips the fade.
- **Details on open** (`widgets/gallery/item_info_bottom_sheet.dart`, switch
  `viewer.detailsWhenInfoSheetOpens`): the bottom info sheet built a TagView
  for every post the viewer landed on while closed; TagView loads the post
  (`loadItem`) for sources with `shouldUpdateIteminTagView` (danbooru,
  gelbooru, rule34.xxx, kemono, ...). Closed, the sheet now holds an empty
  `ListView` on its scroll controller (the controller must stay attached or
  `animateTo` does nothing); the TagView is built once the extent is above
  zero and kept for that post while the sheet closes. FurAffinity's linked
  media does not depend on it (its handler does not load in TagView). The
  right-side endDrawer was already built only when opened.

### 4.26 Resolution caps: video to screen size, pictures to 4K (r57)

- **Why:** §4.23-§4.25. media_kit_video gives the Android surface the video's
  native size, so an 8K post (4320x7680) made Skia draws take 600-925 ms and
  the warm pool held ~2.1 GB of graphics memory (EGL mtrack 1.13 GB).
- **`utils/media_size_cap.dart`** (pure, tested): `videoSurface` fits a video
  inside the screen taken in its best orientation (a landscape video may be
  watched fullscreen sideways, so 1080p is left alone while 8K is cut down),
  keeps the shape, even pixels, never upscales; `imageDecodeSize` mirrors
  `ResizeImage(policy: fit, allowUpscaling: false)` with the 4K ceiling.
- **`widgets/video/video_surface_cap.dart`:** there is no API for this on
  Android (`AndroidVideoController.setSize` throws; the width/height in
  `VideoControllerConfiguration` are read only by the desktop controller), so
  the app repeats media_kit's own call on its channel
  `com.alexmercerind/media_kit_video` -> `VideoOutputManager.SetSurfaceSize`
  (Java side: `surfaceProducer.setSize`, i.e. the texture buffer), then sets
  mpv's `android-surface-size` - the plugin only refreshes that when the
  surface is recreated.
- **In the pool** (`media_kit_player_view.dart`): per entry, a `videoParams`
  subscription caps 100 ms after the event (the plugin does its own work
  inside a `Lock`), plus a `controller.rect` listener so a surface recreated
  at full size is capped again; both stopped in `stopCap()` wherever
  `errorSub` is cancelled. Switch `viewer.videoCapToScreen`.
- **Pictures** (`image_viewer.dart`): the existing `ResizeImage` also gets a
  height of `MediaSizeCap.imageLongEdge`, which is what bounds very tall
  pictures; the width limit (about twice the screen width) is unchanged and
  the user's overrides (`disableImageScaling`, per-post `isNoScale`) still
  load the full picture. Switch `viewer.imageCap4k`.
- Unverified on the device: that mpv renders correctly into a capped surface
  (no crop or stretch), seeking and looping, and that the cap survives an app
  resume. Both switches restore the old behaviour.

### 4.27 The video cap and the lazy info sheet, reverted (r58)

- **r57's video cap does not work and must not come back this way.** On the
  device (talker log 2026-09-16 02:54): `video surface cap failed: Assertion
  failed: "[Player] has been disposed"` and errors from
  `AndroidVideoController.widListener`. Resizing the surface from outside
  makes the plugin's `VideoOutput.onSurfaceAvailable` hand out a **new**
  `wid`, and its `widListener` then rebuilds the whole video output
  (`vo=null` -> `android-surface-size` -> `wid` -> `vo=gpu`) and re-seeks.
  Small videos survive it; anything that needed scaling never rendered (the
  thumbnail stayed) and the app turned sluggish. Reverted whole:
  `widgets/video/video_surface_cap.dart`, the pool's `_startSurfaceCap`,
  `stopCap`, `paramsSub`/`rectListener`, switch `viewer.videoCapToScreen`,
  `MediaSizeCap.videoSurface`. **Doing this properly needs a patched
  media_kit_video (a fork), which the user's no-package rule forbids.**
- **r56's details-on-open, reverted too.** With the details built only once
  the sheet opened, the info button needed two taps (the first opened an
  empty, see-through sheet) and a drag on the closed sheet often did nothing:
  the placeholder list on the sheet's controller does not behave like the
  TagView the sheet was built around. Switch
  `viewer.detailsWhenInfoSheetOpens` gone; the sheet builds its TagView for
  the post on screen again, as in r55.
- **Kept:** the seen-thumbnail change (r56, `grid.seenThumbnailsAtOnce`) and
  the picture ceiling (r57, `viewer.imageCap4k`, `MediaSizeCap`).

### 4.28 The video cap, done inside our own copy of media_kit_video (r59)

- **The user allowed patching the package** (2026-09-16), asking only that it
  stay easy to undo. `third_party/media_kit_video` is media_kit_video 2.0.1
  verbatim plus one change, pinned by `dependency_overrides` in `pubspec.yaml`;
  `third_party/media_kit_video/LOLISNATCHER_PATCH.md` says what changed and how
  to undo it (delete four lines and the folder).
- **The change:** `PlatformVideoController.androidSurfaceSizeCap` (a static
  hook) and, in `android_video_controller/real.dart`, the `videoParams`
  listener asks it for the size before `VideoOutputManager.SetSurfaceSize` and
  before it publishes `rect`. The surface is therefore created once, at the
  capped size: no second resize, no new `wid`, no `widListener` rebuild — which
  is exactly what made r57 fail (§4.27).
- **The app** installs the hook in `_MediaKitPlayerPool.acquire`'s init
  (`widgets/video/video_surface_cap.dart`), reading the Modular UI switch
  `viewer.videoCapToScreen` per video, so turning it off works without a
  restart. The size comes from `MediaSizeCap.videoSurface`: the screen in its
  best orientation for that video (fullscreen landscape keeps 1080p intact),
  shape kept, even pixels, never upscaled.
- **Not verified on the device yet:** that mpv renders correctly into the
  capped surface, that seeking, looping and fullscreen still work, and that
  graphics memory drops. The switch brings the old behaviour back.
- `flutter pub upgrade` will not touch media_kit_video while the override is
  there; re-apply the two edits when moving to a newer version.

### 4.29 Custom arm64 libmpv + pool hwdec (r60)

- **Path A** of the engine choice: keep media_kit, do **not** ship mpv 0.41
  (Android `vo=gpu` flickers, media-kit #1091), do **not** switch the gallery
  to FVP yet. Work only in `C:\clone-bodu-apk`; never write `C:\bodu-apk`.
- `third_party/libmpv-android/default-arm64-v8a.jar` is libmpv-android-video-build
  **v1.1.11 default** (0.36 ABI). `third_party/media_kit_libs_android_video`
  copies that jar instead of downloading v1.1.7 for every ABI. Drop a
  self-built jar there later; keep mpv below 0.37.
- The gallery pool now uses Settings → Video hwdec/vo/hwaccel (those used to
  hit only Chewie's media_kit plugin) and can write a demuxer cache under
  `SettingsHandler.path/mpv_cache`. Init delay 200→300 ms.
- Tests: `test/media_kit_engine_options_test.dart`. Device: turn on
  "Use media_kit engine", play a tube video, seek/loop/mute; confirm About
  shows r60-mpv-libs. FVP/MDK gallery view is B, only if this is not enough.

### 4.30 The link button stands alone; the tab history scrolls (r61)

- **Visited tabs history** (`widgets/tabs/tab_selector.dart`): the dialog would
  not scroll. `SettingsDialog` already scrolls its content, and the inner
  `ListView` (shrinkWrap, built at full height) ate the drag without having
  anything to scroll. The list moved into `VisitedTabsHistoryList` with
  `NeverScrollableScrollPhysics`, so the dialog scrolls it; the widget takes
  its entries and callbacks, which is what the test drives.
- **Linked media** is now `GalleryButton.linkedMedia`: its own entry in
  Settings → Viewer → the toolbar list, orderable and switchable like the
  rest, shown on any post whose description links to media. It used to be the
  share button wearing a link icon, so turning share off in that same list
  took the link sheet away — the user found that. Gone with it:
  `LinkedMediaButton.replacesShare`, the Modular UI switch
  `viewer.linkedMediaReplacesShare`, and the r49 FurAffinity-only toolbar
  action (the real button covers every source). `ModularUi.viewerLinkedMedia`
  still switches the feature off entirely.
- A toolbar saved before this build gains the button automatically:
  `SettingsHandler.loadFromJSON` appends enum values missing from a stored
  `buttonOrder`.

### 4.31 A video waits before it gets a player (r62)

- **Measured (r60 profile build, 25 s of swiping):** 42 `VideoOutputManager`
  creates and 38 disposes, about two a second, with the warm pool at 4. Every
  post that stayed on screen longer than the old fixed 300 ms built a player,
  and building one evicted another.
- **Now:** `SettingsHandler.videoStartDelayMs` (default **333**, 0-5000,
  Settings → Video → "Video start delay (ms)", shown with the media_kit
  engine on) feeds `MediaKitEngineOptions.startDelay`, which
  `_MediaKitPlayerView._scheduleInit` uses instead of the old constant. The
  timer is cancelled on dispose and on item change, so a post swiped past
  before the delay builds nothing - and builds nothing to evict either.
- 0 keeps the old behaviour; the user asked for the value to be theirs to
  tune, so the number is a setting rather than a constant.
- Unverified on the device: that a third of a second feels right, and that
  fast swiping no longer churns players (count `VideoOutputManager.create` /
  `dispose` in logcat over a fixed swipe run).

### 4.32 Doujin feeds can use list cards (r63)

- **Source settings → GRID → Feed cards: Grid | List** (`SourceSettings.
  feedCardStyle`, resolved by `SourceSettingsHandler.feedCardStyle`, default
  `grid`), per source with the usual global layer. Asked for with a screen
  recording of another reader's list layout.
- **`widgets/thumbnail/doujin_list_card.dart`:** one row per gallery - cover
  (116 px) on the left, then the title on a line that **scrolls sideways**
  (long titles are read, not truncated), the uploader, the tags in three rows
  inside a **horizontal scroller**, and a bottom row with the kind badge
  (Doujinshi / Western / Artist CG ...), the language code and the page count.
  Row height 176.
- **`widgets/thumbnail/doujin_card_meta.dart`** holds what both card layouts
  read (title, language, category, pages, which tags and in what order), for
  namespaced and plain tags alike; the page count comes from
  `item.fileCountHint`, which the doujin handlers set while parsing listings.
- `GridBuilder` returns a `SliverList` of these instead of its grid when the
  source asks for it, and `waterfall_view._computeIsStaggered` returns false
  in that case (the staggered grid gives cells no height).

### 4.33 The player pool juggles its players instead of rebuilding them (r64)

- **Idea from the user (via Grok):** treat players as a scarce resource and
  re-point them rather than destroy them. Measured before: 42
  `VideoOutputManager` creates and 38 disposes in 25 s of swiping.
- **`widgets/video/player_pool_planner.dart`** (pure, tested) decides per
  acquire: **reuse** the slot already holding the URL, **create** while under
  `mediaKitMaxPlayers`, or **rebind** the oldest idle slot - `player.open()`
  on the same `Player`, so its decoder, Android surface and Flutter texture
  survive. A slot that errored on its current file is re-opened rather than
  handed back; when every slot is on screen an extra player is built instead
  of stealing one, and `PlayerPoolPlanner.disposable` names slots above
  capacity for disposal once they are free.
- **`_MediaKitPlayerPool`** now holds a `List<_PooledPlayer>` (the slot's
  `url` is mutable) instead of a URL-keyed map; `_evictIfNeeded` became
  `_disposeOverflow`. The playlist mode and mpv cache properties are set when
  a slot is built and survive rebinding.
- Together with r62's start delay, swiping past a video should create nothing
  and destroy nothing; landing on one re-points a slot.
- Unverified on the device: count `VideoOutputManager.create` / `dispose` in
  logcat over a fixed swipe run (was 42 / 38), and check that a rebound player
  plays, seeks, loops and goes fullscreen normally.

### 4.34 A trace recorder inside the app (r65)

- **Why:** measuring over USB with a profile build and the Dart VM service
  perturbed the app enough to invent freezes that were not there (§4.27 and
  the 2026-09-16 session). The app can measure itself in a release build.
- **`utils/perf_trace.dart`:** `PerfTrace.instance.start()/stop()` listens to
  `SchedulerBinding.addTimingsCallback` - available in release - and records
  per frame the app's own work (`build`) and the drawing (`raster`), with
  medians, 95ths, worsts and the counts over 8.3 / 16.7 / 33.3 / 100 ms, plus
  the twelve slowest frames. `event(kind, detail)` puts what the app did on
  the same timeline (capped at `maxEvents`, counts keep everything).
  `report()` writes it as text. Nothing is collected while it is stopped.
- **Hooks:** the player pool (`video.create` / `video.rebind` / `video.reuse`
  / `video.dispose`), the viewer's `onPageChanged` (`viewer.page`), and
  `PerfTraceRouteObserver` in `main.dart`'s `navigatorObservers`
  (`route.push` / `route.pop`).
- **Settings → Debug → "Record a trace"** starts and stops it (the button
  shows the frame count while running); stopping saves the report to
  `<settings path>/traces/trace-<stamp>.txt`, logs it to talker so it travels
  with a log export, and shows it with a Copy button.
- The recorder costs a callback per frame and a list append per event, so it
  disturbs the app far less than the VM service did - but it is still a
  measurement: compare traces with each other, not with an unrecorded run.

### 4.35 The feed loads on its own scrolling only; list card height and shadow; tab manager title (r66)

- **Next-page trigger** (`widgets/preview/waterfall_view.dart`): the feed's
  `NotificationListener<ScrollNotification>` acted on every notification that
  bubbled up, including a horizontal scroll inside a card (the list card's tag
  rows and title, the tab cards), and one at its own end satisfied "near the
  bottom" - so pages were fetched while the user read tags. `FeedScroll.
  isFeedScroll` (`widgets/preview/feed_scroll.dart`, tested) admits only depth
  0 and a vertical axis; the scroll stream that hides the bars gets the same
  filter.
- **List card:** `SourceSettings.listCardHeight` (per source, 120-320, default
  176, Source settings → GRID → "List card height"), passed by `GridBuilder`;
  the card's `Material` has `elevation: 3` over an opaque blend so the shadow
  shows. Test keys `doujin-list-card-row` / `doujin-list-card-surface`.
- **Tab manager app bar:** the two-line title (title + filtered/total count)
  overflowed the 56 px toolbar, so the first line was pushed above the screen
  edge and cut, and the count used `colorScheme.onPrimary` - the colour for
  text on the lavender accent - which is near black on the dark bar. Now
  `toolbarHeight: 64`, single-line title, count in the bar's foreground colour.
- **Feed scrollbar:** the thin bar at the feed's side is the app's standard
  `Scrollbar(thumbVisibility: true)`; it became Modular UI `grid.feedScrollbar`
  (on by default) after the user noticed it with the list cards.

### 4.36 The trace records the UI too (r67)

- **Asked for:** a capture that shows what the UI did and what triggered it -
  widgets created and destroyed, taps, swipes, drawers, scrolls, buttons - to
  find leaks and needless work without a cable.
- **`utils/perf_trace.dart`:** `TraceLifecycle` (a mixin on `State`) reports
  `widget.init` / `widget.dispose` with the state's type; `built(name)` counts
  rebuilds (counts only - a scroll rebuilds hundreds); `PerfTraceGestureLayer`
  at the root (in `main.dart`'s builder, inside `HiddenStatusBarInsets`)
  records `ui.tap`, `ui.swipe left|right|up|down` (a finger that moved under
  24 px is a tap) and `ui.scroll <axis>, depth N` once per scroll from
  `ScrollStartNotification`. The timeline holds 2000 events. The report gained
  "WIDGET BUILDS" and "WIDGETS ALIVE" (created / disposed / alive per widget).
- **Hooks:** the InnerDrawer callback (`ui.drawer open|close`),
  `SettingsButton.onTapAction` (`ui.button <name>`), `ToolbarAction`
  (`ui.toolbar <tooltip>`). `TraceLifecycle` is mixed into `_TagViewState`,
  `_MediaKitPlayerViewState`, `_GalleryViewPageState`, `_WaterfallViewState`,
  `_TabManagerPageState`, `_ItemInfoBottomSheetState`, `_FlowTabCarouselState`,
  `_DoujinTabViewState`; `DoujinListCard` and `ThumbnailCardBuild` count builds.
- Reading a trace: a `ui.scroll horizontal, depth 1` followed by a search is
  exactly the r66 bug; a widget with more created than disposed after leaving
  its screen is a leak; builds far above the number of cards on screen are
  needless rebuilds.

### 4.37 Trace names that cannot be misread (r68)

- The user's 15-minute trace showed `viewer.page × 6` and was read (by Claude)
  as "six posts opened". It counted swipes to a neighbouring post; the 13
  posts opened from the feed were only visible as `route.push
  PageRouteBuilder<dynamic>` among 43 pushes. The user browses by opening a
  post, watching, closing and scrolling on - so swipes undercount badly.
- Now: `viewer.open <index>` from `_GalleryViewPageState.initState`,
  `viewer.swipe <index>` from `onPageChanged`; the viewer route is named
  `viewer` and the post-files route `post files` (`RouteSettings`), which the
  route observer prefers over the type name; the report's WHAT HAPPENED block
  starts with `posts opened N · swipes between posts M`.

### 4.38 List-card cover options, e-hentai sharpness, eahentai on its API (r69)

- **List cards:** `coverDisplay` (fit / crop / adapt) applies to
  `DoujinListCard` (`_cover`): crop = `BoxFit.cover`, fit = `BoxFit.contain`
  on a `surfaceContainerHighest` column, adapt = column width `height ×
  aspect` from `DoujinCoverAspects.notifierFor(item.displayThumbnailURL)`,
  clamped to `[minCoverWidth 48, coverWidth]`; capped or provisional → cover
  fit. New `SourceSettings.listCoverWidth` (72–240, default 116; resolver
  `listCoverWidth`), row "List cover width"; `GridBuilder` passes it. Column
  key `doujin-list-card-cover`.
- **Thumbnail decode box** (`widgets/thumbnail/thumbnail_decode_box.dart`,
  `ThumbnailDecodeBox.of`): a standalone doujin cover (`isDoujinCover =
  DoujinDataHandler.isDoujinBooru(booru)`) in a bounded box decodes for that
  box × `coverSlack` 1.5 (fit policy, never upscaled); everything else keeps
  the square/rectangle/staggered rules verbatim. Before: the app-wide square
  preview shape sized the decode, so a 450×629 cover in a 116×176 column
  decoded to 290×406 and was drawn 1.4× larger (self-inflicted blur). Doujin
  covers/tiles draw with `FilterQuality.high` (bicubic) — e-hentai's 250-px
  covers and 200-px tiles are upscaled 1.6–2.8× on the S24 Ultra.
- **e-hentai facts (verified 2026-09-17 with the built-in browser + curl):**
  extended-listing cover `ehgt.org/w/…webp` is 250×375; `_l`, `-500`, `?w=`
  variants 404/ignored; gallery tiles `#gdt.gt200` 200×283 sprites;
  `inline_set=ts_l|ts_m` set no cookie any more (only `dm_e` → `sl=dm_2`);
  `uconfig.php` bounces to login, so a larger tile size, if the account
  setting still exists, is unverified — the app parses whatever size the
  page declares.
- **Detail cover from page 1:** `BooruHandler.detailCoverImage(item)` (null
  by default) → `EHentaiHandler` resolves the registered book's page 1
  through `loadItem(page)` (page view / showpage, paced) once and returns a
  cover-only `BooruItem` (thumbnail = sample = file = the hath image, size,
  `fileNameExtras <gid>_cover`); `SourceSettings.detailCoverFromFirstPage`
  (default true, e-hentai's Detail page row). `DoujinDetailPage._loadSharpCover`
  after `_load`; `_coverImage` stacks the sharp `Thumbnail` over the site cover
  (no blank while it loads); `bigCoverBox` takes the sharp size.
- **eahentai (`boorus/doujin/eahentai_handler.dart`, `eahentai_query.dart`,
  `handlers/eahentai_session_handler.dart`):** the site's JSON API, found in
  its own scripts (`30amskxbf3cfb.js`: `getApiBaseUrl` = `/api/`) and
  fetched: `image/latest/?page&take` (`{items,totalPages,totalResults}`),
  `image/search/v2/?type=gallery|artist|character|parody|tag&q&take&page&orderby=date_desc|views_daily|views_weekly|views_monthly|views_alltime`,
  `image/popular/?page&take&orderby` (bare array, endless), `image/random/?take`,
  `image/album/<id>` (`[album]` with `images[]{imageUri,thumbnailUri,sort}`),
  `image/search/suggestions?q&type=all&limit` (`items[]{value,type,albumCount}`),
  `image/recommendations` (POST `{seedAlbumIds,take}`); account, Bearer:
  `auth/login` (POST JSON `{login,password[,turnstileToken]}` →
  `{accessToken}`; 401 `{error}`; wrong field names → 400 validation
  `errors.Login`; no Turnstile needed for the API — a fake pair answered 401),
  `auth/me`, `bookmarks`, `bookmarks/albums?type=all&page&take&orderby=bookmarked…&q&addedDays`,
  `bookmarks/sync`, `bookmarks/<id>` POST/DELETE, `lists/mine[?albumId]`,
  `lists/mine/album-ids`, `lists` POST, `lists/<id>` PATCH/DELETE,
  `lists/<id>/albums/<albumId>` PUT/DELETE, `lists/users/<user>[/<id>?page&take&orderby&desc]`,
  `lists/<id>/vote` PUT/DELETE, `comments/album/<id>`, `image/view/<id>` PUT.
  Pages count from 0; `take` capped ~100–200. Quick-filter buttons append
  their words to `q` (`q=santa Full Color`); `q` matches title, tags, kind,
  author, parody, characters. `image1t.jpg` thumbnails are 450×629; full
  first page `image1.webp` ~1280 px; the site's own cover route
  `/_next/image?url=<encoded imageUri>&w=640&q=75` (640/384 only).
  Items: `albumID`, `thumbnailUri` (cover), `imageUri` (sample), `tags|`,
  `author|` → artist, `from` → parody, `characters|` → character,
  `albumType` (`Doujinshi|Lolicon`, `Manga|Yaoi`, `Colored|Doujinshi`) →
  `category:` for doujinshi/manga, the rest plain tags; `addDt` ISO →
  `postDateFormat 'iso'`; `language:english` on everything. Grammar:
  `sort:latest|today|weekly|monthly|alltime` (alone → popular), `type:`,
  `filter:` (multi, `EaHentaiQuery.filterWords`), one namespaced term →
  typed search, mixed → gallery search, `random:`, `id:`. `signIn` → API;
  token + username in `eahentai_session.json`; `getHeaders` adds the Bearer
  header (API only; media headers stay Referer); a 401 on an API call drops
  the token. `DoujinListingTagBackfill` removed from the handler. Old:
  `POST /login` (HTML route) with `username`+`email`+`password` → 405 on
  every search, 16× in the 2026-09-17 05:23 log.
- **Redaction:** the talker Dio logger no longer prints request bodies
  (`printRequestData: false`); `Logger.requestDataInterceptor` writes one
  line through `Logger.requestDataLine` (redacted); `redactSecrets` also
  redacts JSON fields (password, tokens, login, username, email); the log
  export (`settings_page.dart`) redacts every history line. The uploaded log
  had the eahentai password in clear.
- Tests: `thumbnail_decode_box_test`, `doujin_eahentai_test` (rewritten
  around fixtures `eahentai_api_*.json`), `eahentai_live_test`, additions in
  `doujin_list_card_test`, `doujin_list_card_size_test`, `doujin_ehentai_test`,
  `log_redaction_test`, `booru_source_settings_test`,
  `doujin_listing_tag_backfill_test`.
- r70 (planned): bookmarks / lists feeds and add/remove, the site's
  recommendations endpoint.

### 4.39 Doujin parity sweep (r70)

- The rule: every doujin source has nhentai's base (reader, tags on cards,
  Tag builder, autocomplete, the site's sorts/shelves/categories as chips,
  the per-source language and title settings), plus its own site's quirks.
  `test/source_matrix_report_test.dart` prints the capability matrix (one
  row per source: reader, catalog, suggestions, filter groups, metatags,
  comments, notes, site favourites, login, blacklist, variants, reader
  qualities, language/title support, content types, credential fields).
- **Autocomplete:** `boorus/doujin/catalog_suggestions.dart` (mixin
  `CatalogSuggestions`: `hasTagSuggestions` true, `getTagSuggestions` from
  `BooruTagStore.browse` in the catalog's `searchTerm` spelling) on hitomi,
  asmhentai, hentaipaw, hentalk. e-hentai: `api.php` `tagsuggest`
  (`{"method":"tagsuggest","text"}` → `{"tags":{id:{ns,tn}}}` or `[]`),
  `EHentaiHandler.parseTagSuggest`. eahentai: `hasTagSuggestions` now true.
- **Tag builders:** `eahentai_tag_catalog.dart` (index pages
  `/artists|characters|parodies?q=<L>&p=<n>` 100 a page, 404 past the end;
  `/tags?q=<L>` one page; 27 letter shards; `EaHentaiHandler.fetchForCatalog`)
  and `faccina_tag_catalog.dart` (`GET /__data.json`, SvelteKit devalue
  decoded by `FaccinaTagCatalog.devalue`, node with `tagList`
  `{namespace,name}`: artist 2470, magazine 944, circle 451, tag 332, parody
  137, event 58, publisher 35; one shared shard).
- **Site features as chips:** e-hentai `sort:` latest | popular (takes
  `f_cats`) | watched (`/watched`) | favorites (`/favorites.php`, `favcat:N`)
  | toplist_yesterday|month|year|alltime (`toplist.php?tl=15|13|12|11&p=N-1`,
  numbered, compact rows - `itemsFromListing` now reads `td.gl1c/gl2c/gl3c/
  gl4c`); `options:` expunged (`f_sh=on`) | torrent (`f_sto=on`)
  (`EHentaiSearch.showExpunged/requireTorrent`, `listingUrl(path:, favcat:)`,
  `toplistUrl`). hentalk `sort:released|added|title|pages|random` →
  `sort=created_at|title|pages|random`, `order:asc`. asmhentai `category:`
  (taxonomy path) and `random:` (`/random/` → 302 to a gallery; parsed from
  `realUri`). hentaipaw `sort:rank` → `/articles/rank/?t=daily&page=N` (weekly
  and monthly answer 308 to daily). koharu `category:doujinshi|manga|
  illustration` → `&cat=4|2|8` (verified: `/books?cat=4` lists doujinshi;
  a category alone browses `/books`, not the popular shelf).
- **Language / title settings:** `supportsLanguageFilter` +
  `withLanguageFilter` on e-hentai (`language:"x"$` via `qualifyQuery`) and
  hitomi (`language:x` term, an index the search intersects);
  `supportsTitleLanguage` + `titlesFor` on both (`#gn`/`#gj`;
  `galleryinfo.title/japanese_title`).
- **eahentai account:** `hasSiteFavourites` when logged in,
  `setSiteFavourite` → `POST|DELETE /api/bookmarks/<id>` (`accountWriter`
  seam); `bookmarks:recent|latest|alltime` → `GET /api/bookmarks/albums?type=all
  &page&take&orderby=bookmarked|date_desc|views_alltime[&q]`; `list:<id>` →
  `GET /api/lists/users/<username>/<id>?page&take`; lists learned at login
  from `GET /api/lists/mine` (`listID|id`, `name|title`), kept in
  `eahentai_session.json` (`lists`), offered as the `list` filter group. A
  401 on `/api/lists/mine` or `/api/auth/*` never drops the token (only a
  listing 401 does). Orderby values for bookmarks other than `bookmarked`
  and the list-items shape are UNVERIFIED (no account here).
- **Browser sweep notes:** nhentai, e621 and gelbooru are refused by both
  the built-in browser and Chrome ("safety restrictions"); those were
  worked from their APIs and the code. Sites seen: e-hentai (advanced
  options, toplists, watched, favourites), eahentai (indexes, API), niyaniya
  / hdoujin (`/browse?cat=`, `/popular`), asmhentai (`/random/`,
  `/category/x/`, `/language/x/`, indexes, `/login/`), hentalk (sort/order,
  per-page 24, `/series`, users + collections enabled), hitomi (order-by:
  date added, published, popular today/week/month/year, random; indexes),
  hentaipaw (Tags/Parodies/Characters/Artists/Groups, `/articles/rank`,
  Favorites).
- Tests: `doujin_parity_catalogs_test`, `doujin_parity_filters_test`,
  `doujin_parity_live_test` (live), `source_matrix_report_test`; updated
  `source_capabilities_test`, `doujin_filters_test`, `tag_builder_block_test`,
  `tag_catalog_sources_test`, `doujin_eahentai_test`.
- Still missing vs the rule, by choice or by site: hentalk collections
  (login; API paths unverified), asmhentai/hentaipaw language filter (the
  sites cannot combine a language with a search), comments outside nhentai
  (e-hentai and eahentai have comment APIs; not built), hitomi "date
  published" and random orders (nozomi paths not identified).

### 4.40 Booru parity sweep (r71)

- The rule, second half: every booru source has its family's base (the
  site's search syntax as metatags and chips, comments, notes where the site
  has them), plus its own quirks. Live checks 2026-09-17 (curl + browser;
  nhentai / e621 / gelbooru are refused by both browsers, so their APIs).
- **Comments** (`hasCommentsSupport`, `makeCommentsURL`, `parseCommentsList`,
  `parseComment`; `comments_dialog.dart` counts pages from 0 and stops on an
  empty answer): moebooru `/comment.json?post_id=` (one answer; page > 0 →
  '' → `[]`); e621 `/comments.json?search[post_id]=ID&group_by=comment&
  page=N+1`
  (`creator_name`, `is_hidden` skipped); Philomena
  `/api/v1/json/search/comments?q=image_id:ID&per_page=50&page=N+1[&key=]`
  (`author`, `avatar` only when http - default avatars are inline SVG);
  twibooru `/api/v3/posts/ID/comments` → `{comments:[{id, created_at,
  hidden_from_users, body}]}` (anonymous, one answer); szurubooru
  `/api/post/ID` → `comments[]` `{id, postId, user{name, avatarUrl}, text,
  creationTime, score}`. Dates go to the dialog exactly as sent
  (`comments_dialog.dart` `formatDate` parses ISO with its zone and shows
  local time; `safeIsoDateMinusTimezone` cut the zone off and the dialog
  then read UTC as local - no longer used for comment dates, danbooru
  included; it still serves post dates). Items carry
  `hasComments` from `comment_count` / `commentCount` (fills the icon) and
  moebooru `hasNotes` from `last_noted_at != "0"` (the notes button is
  gated on it).
- **Notes:** moebooru `/note.json?post_id=` (`{id, x, y, width, height,
  is_active, post_id, body}`, inactive skipped) - `hasNotesSupport`.
- **Metatags → chips** (`BooruSiteFilters.fromMetaTags`; sort/order lists
  drop `*asc` values and names containing "ascending"): moebooru (rating;
  order id / id_desc / score / score_asc / mpixels / mpixels_asc / landscape /
  portrait / vote; ComparableNumber id / score / width / height / mpixels;
  string ratio / date / vote / md5 / source / parent; user - the yande.re
  cheat sheet); szurubooru (sort ×19, order, safety, type, special, flag,
  string ranges `n..` / `..n` / `a..b`; `doujinFilters` rebuilt from the
  metatags with a real Direction group because the generic card drops "asc";
  `withDirection`: `order:asc` + `sort:x` → `-sort:x`, `order:desc` unflips
  a typed `-sort:`, URL-encoded input decoded and re-encoded); kusowanka
  (`sort:popular|random|top` → `/popular/`, `/random/`, `/top-rated/`, one
  page each: page > 0 locks without an error; a shelf beside other terms
  gives way to the search, so a Sort saved as a source default cannot break
  typed queries; an unknown shelf errors; facets as StringMetaTags);
  inkbunny (`type:`
  picture / sketch / series / comic / portfolio / video / charactersheet /
  photo → ids 1 / 2 / 3 / 4 / 5 / 8,9 / 13 / 14, several add up, else the
  full supported list; `scraps:no|only` → `&scraps=`); hydrus (sort ×20 =
  `getSortType`, order; `validateTags` now keeps the text raw - the base
  validator percent-encoded it into the JSON tag list - and `sort:`/`order:`
  are lifted by regex from the space-joined query before the comma split, so
  "blue eyes sort:random" keeps its tag; no `system:` chip, predicates are
  typed with commas); RedGifs (`type:gifs|images` → `type=g|i` on the
  search, creator and niche endpoints, `verified:yes` → `verified=y` on the
  search, both dropped from the tag list); realbooru (sort score / score:asc / id /
  id:asc - verified; `rating:` and `score:>n` do nothing on the site).
- **twibooru:** `doujinFilters` sf (score, faves, upvotes, comment_count,
  tag_count, width, height, random - score and random verified to reorder),
  sd (asc), score.gte and faves.gte 10/25/50/100 (top scores ~200;
  score.gte:100 = 83 posts); `makeURL` takes sf:/sd: out with
  `DoujinFilters.selected/strip` into `&sf=&sd=`, range terms stay in q
  (`score.gte:100`), an empty rest → `q=*`; metatags uploader / id /
  score.gte / faves.gte / width.gte / height.gte / source_url / description
  / sha512_hash.
- **Page bases:** `BooruHandlerFactory` seeds 1-based sites (moebooru,
  danbooru, e621, philomena, twibooru, RedGifs) with `startingPage 0`, so the
  app's first fetch is page 1. RedGifs answers 400 "Invalid page number" and
  e621 410 to page 0; danbooru and twibooru alias page 0 to page 1. A live
  test that calls `search()` directly must seed `pageNum` the same way, or it
  reports a failure the app never sees.
- Not changed: rule34.us (had sort / score since r47; `rating:` is a no-op),
  Shimmie / paheal (`order:` changed nothing, r45), r34hentai (Cloudflare),
  agn.ph (no sort control on the site), gelbooru v1 (no operators), nyanpals
  (404), rainbooru (522), nozomi and rule34.dev (no query syntax of their
  own). Booru site favourites (danbooru / e621 / moebooru / sankaku) later.
- Tests: `booru_parity_test` (fixtures `moebooru_comments`,
  `moebooru_notes`, `e621_comments`, `philomena_comments`,
  `twibooru_comments`), `booru_parity_live_test` (live: yande.re comments +
  notes + order:score, e621 / derpibooru / twibooru comments, twibooru
  sf:score, kusowanka shelves, RedGifs images, realbooru sort:id:asc),
  `filter_chip_keys_test` registers the new specs.
- Contrarian review (one agent, read-only), ten findings, all applied:
  moebooru notes never showed (the viewer gates on `item.hasNotes`);
  e621/Philomena comment pages were 1-based against the dialog's 0 (only the
  first page ever loaded); the zone-stripping date helper shifted every
  comment time by the UTC offset (danbooru's older helper too); hydrus Sort
  chips discarded the typed tag (comma split) and the `system:` chip could
  not work; a kusowanka Sort saved as a default broke every search; RedGifs
  `type:` was dropped on the creator and niche endpoints (both accept it);
  twibooru 500+/1000+ steps could never match; single-answer comment
  endpoints answered page 1 twice; the szurubooru/realbooru URL tests only
  used raw text (production sends percent-encoded); a cosmetic realbooru
  label. Pre-existing, noted only: RedGifs niche feeds answer 400 `BadOrder`
  to `order=trending`, which `_nicheOrder` returns by default.

### 4.41 rule34hentai's own search (r72)

- r71 said "behind Cloudflare, could not be checked"; the user's Chrome gets
  through, so the site was checked there on 2026-09-18 (`/ext_doc` is the
  Shimmie2 engine's extension index, `/ext_doc/index` its search help;
  forty `/post/list/<term>/1` probes compared first ids and page counts).
- **Verified:** the Sort menu is `order=id_desc` (default) and
  `order=score_desc`; every other order form (asc, filesize, width, random,
  and the colon spelling) is ignored. `content:video|audio`, `ext=webm|mp4|
  gif|png|jpg`, `score>`, `favorites>`, `comments>`, `size>=WxH`, `ratio:`,
  `filesize>`, `width>`, `posted>=`, `id<`, `source:any`, `upvoted_by:`,
  `favorited_by:` (American spelling) filter. `rating:` covers only rated
  posts (s 138 pages, q 48, e/u none, of 9,803) - no chip. `/popular_by_day|
  month|year` exist (one page, same `.thumb` markup); `/random` is empty;
  pools / notes / artists not installed. Autocomplete
  `/api/internal/autocomplete?s=` → `{tag: count}`.
- **Handler (`r34hentai_handler.dart`):** `doujinFilters` order (`=`),
  popular, content, ext (`=`), score / favorites / comments (`>`);
  `availableMetaTags` (the typed fields; `ComparableNumberMetaTag` for the
  numeric ones, `DateMetaTag` for posted - `posted:date` alone and `tags=N`
  answer nothing on the site; `score:100`, `size:1920x1080`, `width:1920`,
  `filesize:>10mb` checked); `makeURL` maps `popular:day|month|year` to the
  site page when the rest is only the card's own chip terms (`chipTerm`:
  order= / content: / ext= / score / favorites / comments - saved defaults
  compose the same way), page > 1 locks silently, a typed tag or field beside
  it wins, an unknown value → errorString + locked; rewrites `order:x` →
  `order=x` (the Sort chip does not see the typed form - known, minor);
  `makeTagURL` + Map/String-aware `parseTagSuggestionsList` (a non-JSON
  answer THROWS so the alias resolver records no miss). `usesUserId` /
  `usesApiKey` true with Username / Password labels (the generic Shimmie
  handler hid both fields, so the site login was unreachable - pre-existing);
  the signed-in dummy sets `applySourceSettings = false`. Site note updated.
- Contrarian review (one agent, read-only): a Popular chip was defeated by
  any other chip or saved default; a non-JSON autocomplete answer became an
  alias miss; the login fields were hidden; the site note lacked the Popular
  clause; exact-value spellings unverified (then checked in Chrome: score,
  size, width, filesize fine; posted and tags not). All applied.
- Tests: `r34hentai_parity_test`; `filter_chip_keys_test` registers the spec.
  No live test through the app from this PC (Cloudflare on curl/Dio); the
  checks were made in Chrome and are due on the device.
- Left: site favourites through the app's login (Shimmie `favourite/add`,
  needs a logged-in check); `/random` (empty on the site).

### 4.42 Boards: describe it or show a picture, the app searches the sources (r73)

- **What:** a saved search (`data/board.dart` `Board`: name, description,
  mustTags, excludeTags, sourceNames (empty = every eligible booru),
  imagePath (a copy under `boards/`), imageUrl) kept by
  `handlers/boards_handler.dart` (`boards.json` beside the settings, with
  `sauceNaoApiKey`; `revision` notifier; `importImageBytes/File`; a deleted
  board takes its image copy; `imageBooru` names the booru a post's image
  came from; `matches` / `matchedAt` / `matchedImage` cache the reverse-image
  answer for the image it was made from - `imageKey` = `file:<path>` or
  `url:<address>`, `hasFreshMatches` when they agree; `boards.json` is in the
  backup list). A board opens as a tab of the virtual
  `BooruType.Board` booru (`ensureBoardsBooru`, registered with the other
  virtual entries, excluded from the dropdown / detectable / saveable lists,
  `isRecommendationFeed` true) with the search string `board:<id>`, so tabs
  restore.
- **Query understanding** (`handlers/board_query.dart`, `BoardQueryBuilder`):
  `tokens` (lowercase words minus stop words) and `bigrams`; `deriveTags`
  scores candidates: an image match's names +4, an exact tag-list name +3,
  a name starting with the word +1.5, containing it +0.5, the site's own
  suggestions for words no list knows (+2 first, +1 others), then the
  encoder adds 2 × cosine(description, tag) when it is downloaded; top 8.
  `accepts(item, must, exclude, aliases)` enforces the must-have tags (as
  typed or in the site's spelling) and the exclusions. Seams: `storeLookup`
  (BooruTagStore.browse), `siteSuggest` (handler.getTagSuggestions),
  `embed` (EncoderHandler.embedText).
- **Reverse image search** (`handlers/reverse_image_search.dart`): SauceNAO
  `POST search.php` (`api_key`, `output_type=2`, `numres`, `db=999`, `file`
  upload or `url`) → `parseSauceNao` (header.status ≠ 0 → the site's
  message as an error; results ≥ 55 similarity; site + post id from the
  `<site>_id` keys in preference order danbooru, gelbooru, yandere,
  konachan, sankaku, e621, anime-pictures, idol; `alsoOn` for the rest;
  tags = characters, material, creator as booru names). The anonymous
  account may not use the API (checked 2026-09-18), so the key is the
  user's own (Settings → Recommendations → Boards); with a key the API path
  answers JSON even to curl (no Cloudflare page). e621's own iqdb:
  `POST /iqdb_queries.json` `search[file]` → rows ≥ 60 score; the REAL answer (post 5000000,
  2026-09-18, `test/fixtures/e621_iqdb.json`) wraps the post as
  `post.posts` with a space-separated `tag_string` (the parser reads that,
  and `post.tags` by category if a site ever sends it). e621 refuses
  `search[url]` for foreign hosts. SauceNAO's anonymous HTML page works in
  a browser (seen in Chrome: similarity, creator, characters) - a keyless
  route through `OriginPageClient` is possible later. danbooru's own
  reverse image could not be reached from the PC (both browsers refuse
  danbooru by policy, curl meets Cloudflare) - out. iqdb.org stays the
  Find-elsewhere path.
- **The feed** (`boorus/board_handler.dart`, `BoardHandler`): `_init` reads
  the board, builds one handler per source (max 8; `sourceFactory` seam),
  runs the image matcher unless the board holds fresh matches for the same
  image (then the cache answers and SauceNAO's quota is untouched; a fresh
  answer is saved on the board; a failure is not cached; 45 s cap; a
  failure is logged and kept in `imageError`, the feed goes on), derives
  the tags, resolves each
  must-have tag per source through `TagAliasResolver.resolve` (a confirmed
  miss = null → the source is skipped, `skippedSources`; nothing left → an
  error naming the tags), and embeds the description. A page asks up to 4
  sources (rotating), each for `must (site spelling) + one derived tag`
  (rotating), deepening per (source, query) pair; page 0 also asks `id:<n>`
  for every image match on its own site (by host, else by type; only
  danbooru, gelbooru and alikes, moebooru and e621, whose `id:` is known -
  sankaku is out until checked), in a wave of its own before the derived
  queries (sub-handlers are not re-entrant). Answers
  go through `accepts`, seen/duplicate checks, then `scoreItem` = 100 if
  exact + 10 × cosine(description, post) + the weights of the derived tags
  the post carries + jitter; `withoutDismissed`; exposures logged under
  surface `board`. Two empty rounds lock the feed (an error only when
  nothing was ever found).
- **UI** (`pages/boards_page.dart`): `BoardsPage` (drawer → Boards, booru
  tabs; list, New board, per-board menu Open / Edit / Duplicate / Delete;
  `opener` seam) and `BoardEditPage` (name, description, must / never tags,
  reference image: `image_picker` gallery pick copied under `boards/`, or
  an address; sources as chips; a board created from a post copies the
  post's image at save time through `Tools.getFileCustomHeaders(source)`
  (`BoardEditPage.imageFetcher` seam), keeping the address as the fallback;
  the menu's "Refresh image matches" clears the cache). `BoardEditPage.
  openFromItem` (post menu → "Find posts like this (new board)") prefills
  from the post: characters / series / artists first, then tags as words
  (14), the sample as the reference url, the booru as `imageBooru`.
  `_BoardsSection` on the Recommendations page holds the SauceNAO key
  (debounced save).
- **Dependency:** `image_picker` 1.2.3 (plus its platform packages); no
  other package moved (checked in the lockfile diff).
- Tests: `boards_store_test`, `board_query_test`, `reverse_image_search_test`
  (SauceNAO shape from the documented format - a real answer needs the
  user's key; e621 from the real answer), `board_handler_test` (fake
  sources, resolver, matcher, encoder; the cache; the id: sites; no
  re-entry), `boards_page_test`. No live test: SauceNAO needs the key, the
  boorus are already covered.
- The plan for this round went through the user's plan-revision checklist
  (2026-09-18) after being built first - see the plan file and
  [[plan-before-changes]] in memory: plan, approval, then work.
- Contrarian review (one agent, read-only), twelve findings, ten applied:
  a restored `board:<id>` tab found no board because nothing had loaded
  `boards.json` (`_init` now loads the store); a tab switch during the
  first load searched again, found nothing set up and locked the feed
  (one init future and one page future are shared by concurrent callers,
  `_ensureInit` / `_pageInFlight`); a match's id was asked of any site of
  the same engine (rule34.xxx for a gelbooru id) - now by host only, and
  a match's `alsoOn` ids are used; a restore from backup left the store
  stale (`reloadFromDisk`, called with the doujin stores); a positive
  SauceNAO status (an index down) threw away the results (only a negative
  status is a refusal now; an empty cached answer is trusted for a day);
  the first page embedded every candidate one by one and scanned the tag
  lists source by source (one batch of the top 24 through `embedTexts`,
  lookups per source in parallel, at most four site suggestions; the
  match cap is 100 s over 20 + 30 + 30 s parts); the editor's Remove kept
  the address and Save copied it back, Duplicate lost a picked image, a
  picked file was copied before Save (the copy happens on Save, the old
  copy goes); the handler kept a stale board after caching (it keeps its
  own copy); the reference post itself was dropped as "seen"; the key
  field lost the last keystrokes on leave; the tokeniser's range and the
  prefix rule (`girl` no longer proposes `girls_und_panzer` as a prefix);
  "Find posts like this" from a board tab passed the virtual source as the
  image's booru. Left as is: `-x` typed into Must means `x` (documented),
  and the pre-existing cross-site `serverId` duplicate rule of
  `filterFetched` (For You has it too).
- Left: tags from pixels (an on-device tagger, r74), visual re-ranking,
  showing `imageError` / `skippedSources` on the board tab.

### 4.43 Image tagger: tags from the pixels, as an optional download (r74)

- **What:** an on-device booru tagger the user downloads from Hugging Face
  (`handlers/recommender/image_tagger_handler.dart`, `ImageTaggerHandler`,
  modelled on the encoder): the WD v3 taggers by SmilingWolf as presets
  (`TaggerPreset`: `wd-vit` 378,536,310 B (default), `wd-convnext`
  394,990,732 B, `wd-swinv2` 467,460,978 B; sizes from the Hugging Face API
  on 2026-09-18), any repo with `model.onnx` + `selected_tags.csv` through the
  custom field. Files under `<settings.path>tagger/<slug>/` (model, csv,
  `config.json` when the repo has one, `manifest.json`: repo, setting, bytes,
  inputSize, tagCount, downloadedAt); download into `.download-<slug>/` then
  rename; `fetcher` and `runnerFactory` seams; `status`
  (`TaggerStatus`: none / downloading / ready / error, progress, tagCount,
  inputSize); `refresh()` at startup (`main.dart`, beside the encoder) and
  after a download; `delete()`; `enabled` = `settings.aiImageTagger` and ready.
  Settings: `imageTaggerModel`, `aiImageTagger` (true), `taggerOnReactions`
  (false).
- **Reading a picture** (`tag(bytes)` → `TaggerResult`): `prepareTensor`
  follows the author's reference code (space SmilingWolf/wd-tagger `app.py`,
  read 2026-09-18): transparency onto white, the picture in a white square
  padded from the top-left half (`(max - w) ~/ 2`), cubic resize to the
  model's size (448; `config.json` `model_args.img_size` or
  `pretrained_cfg.input_size` when present), float32 0-255, **BGR**, NHWC
  batch of one; it runs through `compute`. `interpret` reads the answer by
  the csv's categories: 9 = rating (argmax), 4 = character (> 0.85), anything
  else general (> 0.35, strongest first, 24 at most); tags keep their
  underscores (the demo replaces them for display only). The csv (10,861
  rows: 8,106 general, 2,751 characters, 4 ratings) is parsed by header name.
  `OnnxTagRunner` (`onnx_tag_runner.dart`): one session,
  `intraOpNumThreads` = half the cores (max 4), plain CPU — XNNPACK was
  planned but the plugin cannot set that provider's own thread count, which
  would leave it single-threaded; the session's own input name; the first
  output. The session closes 120 s after the last picture (`idleClose`) and
  reopens on the next; a runtime failure sets an error status until a
  refresh; a picture that cannot be decoded is a `FormatException`. One log
  line per run: `tagger: N general, M characters, rating r p; decode X ms,
  model Y ms (provider)` — the S24 Ultra timing lives there.
- **Boards** (`boorus/board_handler.dart`): `pixelTagger` / `pixelModelId`
  seams; `_init` reads the reference image through the tagger when one is
  enabled (`referenceImageBytes`, the reading shared with the reverse-image
  matcher), 30 s cap; `seedsFrom`: a character seeds at 4 (as a SauceNAO
  name), the top 10 general tags at 3 × confidence; `deriveTags` takes them
  as `weightedSeeds`. Cached on the board (`Board.pixelTags`, `pixelImage` =
  `<imageKey>@<modelId>`, `hasFreshPixelTags(model)`), cleared by
  "Refresh image matches" (`clearMatches`), re-read for a new image or a
  new model; a failure is logged, not cached. With a tagger the "no reverse
  image search available" error is not raised: an image board needs no
  SauceNAO key. Editor (`pages/boards_page.dart`): "Tags from the picture"
  (`board-tag-image`; `taggerReady` / `pixelTagger` seams) reads the picked
  file, the copy or the address into chips (`board-pixel-<tag>`, characters
  first, confidence shown); a tap appends the tag to Must-have once; without
  a tagger the row (`board-tag-hint`) says where to download one.
- **Reactions** (`RecommenderHandler.onEvent`, `pixelTagsFor` seam,
  `resetSeamsForTests`; `handlers/recommender/pixel_tags.dart`): with
  `taggerOnReactions` on, a booru-world event whose reward weighs 2 or more
  (favourite, unfavourite, collect, snatch, videoComplete, Not interested)
  reads the post's thumbnail (the grid's cache through
  `ImageWriter.getCachePath`, else a download with the booru's headers) and
  the tags join the site's as ordinary `tag:` features (`ItemFeatures.of`
  `extraTags`; duplicates dropped by the builder). Candidates are still
  ranked by their site tags, so the learned weights apply to every post.
  Views and skips never tag (cost); doujins never; a failure or a 30 s
  timeout leaves the site's tags alone. Log: `tagger: reaction <kind>, N tags
  from the picture, M new`. Honest limit: this does not change how a
  disliked post shares the blame between its tags (r75).
- **Settings page** (`pages/settings/recommendations_page.dart`,
  `_TaggerSection` between the encoder and Boards): presets
  (`tagger-preset-<id>`, `tagger-preset-custom`, `tagger-custom-repo`),
  Download / Cancel / Delete (`tagger-download`, `tagger-cancel`,
  `tagger-delete`), status (`tagger-status`), **Try it on a picture**
  (`tagger-try`; `RecommendationsPage.pickImageBytes` / `tagImage` seams;
  the picker from r73) showing the tags, the rating and the time
  (`tagger-try-result`), "Use the image tagger" (`ai-tagger-toggle`), "Tag
  reactions with the picture" (`tagger-reactions-toggle`).
- **Tests:** `test/image_tagger_handler_test.dart` (presets and paths,
  download / failure / cancel / bad csv, config sizes, refresh, delete,
  `tag()` through a fake runner, `interpret`, `parseTagsCsv`, the idle
  close, the switch, a runtime failure, a bad picture),
  `test/image_tagger_preprocess_test.dart` (BGR, padding sides, resize,
  transparency, a broken picture), additions to `board_handler_test`
  (seeds, cache by image and model, failure, `seedsFrom`),
  `boards_page_test` (chips, the hint), `recommender_handler_test`
  (reaction tagging and its limits), `recommendations_page_test` (the
  section end to end).
- **Not verified from the PC:** the model has never run here (no
  onnxruntime for Python was installed, no model downloaded — permission
  was asked); the phone is the first real run, as for the encoder. Cut:
  the frame on screen for videos (a hook in the video player), tagging feed
  candidates at ranking time, the large 1.26 GB models as presets, the
  thresholds as settings, the rating's use.

### 4.44 Looks: posts that look alike, explanations and corrections, tabs that stay put (r75)

- **Why:** after r74 the user said "similar" means how a picture looks (their
  image server: CLIP smart search), not shared tags; the tagger round had
  not given that, and did not make For You more accurate. Approved plan:
  visual similarity on device, the recommender explaining itself and taking
  corrections, tabs that never switch the user away, and the blank seeded
  tab. Report style: plain words, few blocks (the r74 report overwhelmed).
- **Looks model** (`handlers/recommender/look_model_handler.dart`,
  `LookModelHandler`, modelled on the encoder): presets `LookPreset.s0`
  (Xenova/mobileclip_s0: `onnx/vision_model_quantized.onnx` 11,846,843 B +
  `onnx/text_model_quantized.onnx` 42,799,238 B) and `s2`
  (Xenova/mobileclip_s2: 36,735,889 + 64,117,260 B); any CLIP export with
  those two files, `tokenizer.json` and `preprocessor_config.json` through the
  custom field. Files under `<settings.path>look/<slug>/` as
  `vision_model.onnx`, `text_model.onnx`, `tokenizer.json`,
  `preprocessor_config.json`, `manifest.json` (repo, setting, bytes,
  inputSize, mean/std when the config normalises, dim, downloadedAt).
  `prepareImage`: shortest edge to the size (256 for MobileCLIP; from
  `crop_size`/`size`), centre crop, RGB planes channels-first, 0-1,
  `(x-mean)/std` only when `do_normalize` (MobileCLIP: no; OpenAI CLIP:
  yes), through `compute`. `imageVector(bytes)` and `textVector(text)`
  answer unit vectors; `imageVectors(items)` reads memory, then the
  `ItemEmbedding` table under model `look:<slug>` (shared with the encoder's
  table; `putEmbeddings/getEmbeddings/clearEmbeddings`), then the thumbnails
  (`PixelTags.thumbnailBytes`, the grid's cache first) through the model,
  one log line per batch `look: N thumbnails in X ms`. `OnnxLookRunner`
  (`onnx_look_runner.dart`): one session per half, plain CPU with half the
  cores (max 4), the sessions' own input names (`pixel_values`;
  `input_ids` + `attention_mask` int64), first output; idle-closed after
  120 s like the tagger; a runtime failure is an error status until a
  refresh. Settings `lookModel` ('' / preset id / repo), `aiLook` (true).
  Registered in `main.dart` beside the encoder and the tagger.
- **CLIP tokenizer** (`handlers/recommender/clip_tokenizer.dart`,
  `ClipTokenizer`): what a Hugging Face `tokenizer.json` of the CLIP family
  describes — whitespace collapsed, lowercase, the split regex
  (contractions, `\p{L}+`, one `\p{N}`, runs of anything else), the GPT-2
  byte-to-unicode alphabet, merges by rank with `</w>` on a word's last
  piece, `<|startoftext|>` 49406 … `<|endoftext|>` 49407 (also the unknown
  id), padded with 0 to 77 with a mask, the end mark kept when cut. NFC is
  not applied (Dart has none built in; accents already composed encode
  right). `test/fixtures/clip_tokenizer_small.json` is cut from the real
  MobileCLIP tokenizer (110 vocab entries, 58 merges, the ids a Python
  re-implementation produced, validated on the known "a photo of a cat" =
  320 1125 539 320 2368); the cut keeps every merge on the paths taken, so
  the small file encodes those sentences exactly as the full one does.
- **Boards by looks** (`boorus/board_handler.dart`): seams `referenceLook`,
  `lookText`, `lookItems`, `lookModelId`; `_init` puts the reference
  image's vector in `_refLook` (cached on the board as `Board.lookVector` +
  `lookImage` = `<imageKey>@<model>`, `hasFreshLook`, cleared by
  `clearMatches`), or the description's text vector when there is no image;
  `_searchPage` embeds the page's thumbnails (`lookItems`, per source by
  the item's host, 20 s bound) and `scoreItem` adds `lookWeight` (20) ×
  cosine — above the text-encoder term (10) and the derived-tag weights
  (3-4), so looks decide the order among tag matches; a failing model
  leaves the tags in charge.
- **Posts like this** (`pages/boards_page.dart`, `widgets/gallery/tag_view.dart`):
  `BoardsPage.openSimilar(context, item, source)` makes a *hidden* board
  (`BoardEditPage.similarFromItem`: the post's image, its lead tags as the
  words, `Board.hidden = true`, name "Like: …"), copies the image through
  the source's headers when it can, saves, and opens it in the background
  with the "Opened in a new tab" notice. `BoardsHandler.visibleBoards`
  keeps hidden boards off the page; `load()` prunes hidden boards older
  than `hiddenLifetime` (3 days), image copy included. The tile sits in the
  post info sheet before "Recommend more like this" (booru context only).
- **For You by looks** (`item_features.dart`, `recommender_handler.dart`):
  `ItemFeatures.withLook(base, vector, model:, taste:)` adds
  `look:<model>:<i>` valued features (`lookScale` 1.5, like the encoder's)
  and `ltaste:<model>:<bucket>`; stacks with `withEmbedding`, logged count
  unchanged. `RecommenderHandler.lookVectorsFor` seam (default
  `LookModelHandler.imageVectors`), `_looks()` bounded 8 s, booru world
  only; vectors join `onEvent`, `rerank`, `score`, `scorer` and `explain`;
  a strong like also moves a visual taste centroid (`_lookTaste`, saved as
  `<world>.look-taste.json`, `RecommenderReport.lookTasteCount`). The
  model id in feature names is the looks model's slug, or `look` when a
  test seam supplies vectors without a model.
- **Pairs, why, corrections:** `ItemFeatures.of` adds `pair:<lead>|<tag>`
  (booru world; leads = character / copyright / artist, 3 at most, × every
  other tag, 40 at most). `RecommenderHandler.explain(item)` →
  `Explanation` (top 4 positive, 3 negative contributions weight × value,
  grouped by plain label: `tag:` as words, `type:artist:x` "artist x",
  `pair:a|b` "a with b", the encoder block "how it reads", the looks block
  "how it looks", `site:` "from …"); shown as "Picked because" in the info
  sheet on recommendation feeds. `FtrlModel.setWeight(i, w)` (z solved
  from the closed form at the feature's n) and `nudge(i, delta)`;
  `RecommenderHandler.adjust(world, name, how: more|less|forget)` (±0.5 /
  zero, counted as an update, saved). The Recommendations page's learned
  tags are `ActionChip`s (`feature-<name>`) opening a sheet with More of
  this / Less of this / Forget it (`feature-more|less|forget`).
- **Tabs never kidnap:** `BoardsPage.open(context, board, switchTo:)` (the
  `opener` seam takes the flag); `openFromItem` and `openSimilar` open in
  the background with the notice; "Recommend more like this" too
  (`switchToNew: false`, no `popUntil`). The Boards page's own Open and the
  Collections page still switch (the user chose from a list).
- **The blank seeded tab:** the live test
  (`test/foryou_seed_live_test.dart`, gelbooru + yande.re,
  `seed:hatsune_miku seed:vocaloid`) came back with 20 posts once the test
  set the network inspector the app sets at startup — the seed mode itself
  works. What does come back empty: seeds a site does not know. Now a
  resolver answer of null (the site confirmed the miss) skips that site for
  that seed instead of searching it (`ForYouHandler.resolveTag` seam; a
  resolver that fails leaves the seed as typed); `from:<host>` (added by
  "Recommend more like this" with the post's own site) moves that source
  first and zeroes the rotation offset (`preferredHost`); and an empty feed
  sets `errorString` ("No source answered for: …" in seed mode, "Nothing
  new to show" in profile mode) through `_sayWhyEmpty` in both search
  paths. `sourceFactory` seam for tests.
- **Tests:** `clip_tokenizer_test`, `look_model_handler_test` (download /
  refresh / delete, `prepareImage` planes, crop and normalisation,
  `imageVector`, `textVector` with the real tokenizer, `imageVectors` cache
  levels, idle close, failure), `foryou_seed_test` (fills, says why, skips
  a confirmed miss, `from:` first) + the live one, and additions to
  `board_handler_test` (looks order, cache, text side, failure),
  `boards_store_test` (hidden pruning), `boards_page_test` (Posts like
  this, background opens), `recommender_features_test` (pairs, `withLook`),
  `recommender_ftrl_test` (`setWeight`/`nudge`), `recommender_handler_test`
  (`explain`, `adjust`, looks + taste), `recommendations_page_test` (the
  section). One older encoder test moved its bar from 0.5 to the tags-only
  score: with pairs in the mix the site and media features carry a little
  net liking, and the claim it protects is the encoder's pull, not 0.5.
- **Not verified from the PC:** the looks model has never run here or on
  the phone; the tokenizer and the preprocessing are checked against the
  reference, the ONNX halves are not. Cut: video frames (player hook),
  faces, per-site image search (none offers it).

### 4.45 Frames from the playing video (r76, build 95)

- **Why:** the user asked for "the frames from a playing video" (listed as
  not done in r75): every model read a video through its preview picture.
  Plan approved through the user's checklist; they added the switch.
- **Player (pooled media_kit viewer only, the user's setup):**
  `MediaKitFrameSource.showing(url)` at the end of
  `widgets/video/media_kit_player_view.dart` is a read-only lookup in
  `_MediaKitPlayerPool._slots` (entry with that url and no error) returning
  `(player, stillShowing)`; nothing else in the player file changed.
- **The grab** (`handlers/recommender/video_frames.dart`, `VideoFrames`,
  GetIt, `register().attach()` in `main.dart` after `LookModelHandler`):
  mpv's `screenshot-to-file <tmp>/f<n>.jpg video` through
  `NativePlayer.command` (media_kit builds that argument list as
  `calloc<Pointer<Utf8>>(128)` and sends it with `mpv_command_async`; the
  pool keeps the default async=true). **Not** `Player.screenshot()`: in
  media_kit 1.2.6 it allocates `args.join().length` bytes (19) for mpv's
  NULL-terminated `char**`, so mpv reads past the end (issues #569, #1222,
  #1075). mpv 0.36: `screenshot-to-file` has `.spawn_thread = true`,
  format from the extension (JPEG q90), reply after the write. Safety:
  media_kit's `dispose` sets `disposed = true` and calls
  `mpv_terminate_destroy` 5 s later; `command()`/`getProperty()` refuse a
  disposed player; `stillShowing()` after the reply drops a frame the pool
  re-pointed. No media_kit lock is taken (its `lock` is one static lock for
  every player).
- **Schedule:** follows `ViewerHandler.instance.current` through
  `addListener` (NOT `.listen`: GetX 5 builds `stream` with
  `StreamController.broadcast(onCancel: addListener(...))`, so once the
  last stream listener cancels the stream is never fed again — found by a
  test). A timer ticks every second while a qualifying item is current:
  first grab after `firstDelay` 2.5 s, then every `gap` 6 s, `maxFrames` 5,
  none while paused after the first, `maxFailures` 4 per video. Qualifies:
  a video (`mediaType`), not a doujin item, not `isHidden`; wanted:
  `settings.videoFrames` and (looks model enabled, or tagger enabled with
  `taggerOnReactions`). No grabs with the `mediacodec_embed` output (mpv
  can't read that picture back; logged once). Frames: shrunk to 512 px
  (`shrinkJpeg`, average filter, JPEG q88) off the main thread, kept for 24
  videos in memory; temp files deleted, late ones swept after a minute.
  After each frame the looks model reads it (`lookOf`) and the normalised
  mean of the video's frame vectors is stored with the new
  `LookModelHandler.putItemVector` (memory + `ItemEmbedding` under
  `look:<slug>`, over the preview picture's vector); `LookModelHandler.meanOf`.
- **Decoder line:** once per video, `video: decoder <hwdec-current> ·
  output <current-vo> · codec <video-codec>` ("no" → "no (software)"),
  read with `getProperty`. Why: the user's MPV: HWDEC is "vulkan"; the
  bundled libmpv (`third_party/libmpv-android/default-arm64-v8a.jar`,
  libmpv-android-video-build v1.1.11, mpv commit 78d43740, 14 Oct 2023) was
  built with FFmpeg `--disable-vulkan` and mpv `-Dvulkan=disabled
  -Dlibplacebo=disabled` (both strings embedded in libmpv.so; no
  `*_vulkan` decoders, no `vkCreateInstance`; the MediaCodec decoders and
  AImageReader are there). mpv's `vd_lavc.c` keeps only hwdecs named like
  the option (503–504), warns "Unsupported hwdec" (581) and decodes in
  software (599). So "vulkan" = software decoding; "auto-safe" = MediaCodec.
  The pooled players log errors only, so those lines never reached the
  user's log. `gpu-next` isn't in this build either.
- **Consumers:** `PixelTags.forItem` tags up to three kept frames (first,
  middle, last) and merges them (`mergeNames`: best confidence, characters
  first, first-seen on ties), else the thumbnail; seams `taggerReady`,
  `framesFor`, `tagBytes`, `thumbnail`. `BoardsPage.openSimilar` and
  `BoardEditPage.openFromItem` use `BoardsPage.videoFrame` (→
  `VideoFrames.frameNow`: a fresh grab when its player shows it, else the
  newest kept frame) for a video; the editor's copy is deleted
  `frameCleanupDelay` (2 s) after a cancel or a changed picture, through
  `deleteCopy` (a seam: Windows, where tests run, keeps a shown picture's
  file memory-mapped, so a real delete fails there).
- **Setting:** `videoFrames` (true), toggle `look-video-frames-toggle` in
  the Looks model section.
- **Tests:** `test/video_frames_test.dart` (the exact command to the
  player the lookup returns for that address, the decoder properties once,
  maxFrames, the stored mean, no grabs for switch off / picture / hidden /
  doujin / no consumer / mediacodec_embed / an item left early / paused,
  moved-on / no file / timeout then retry, `frameNow`), `pixel_tags_test`,
  and additions to `look_model_handler_test`, `boards_page_test`,
  `recommendations_page_test`.
- **Not verified:** mpv writing the file on the phone (first real run there).

### 4.46 The Suggested strip's new tab fills (r76, build 96)

- **Cause:** `TagContentPreview` (in `widgets/gallery/tag_view.dart`) runs
  the Suggested strip with a `SuggestionHandler` built around the post, and
  a placeholder tag "suggestions"; its "open in new tab" (and the long-press
  variant) passed `_effectiveTag` ("suggestions") to `addTabByString`, so
  the new tab searched the site for that tag. On e621 it is a real tag with
  2 unrelated posts (checked through `tags.json`); the user's screenshot
  showed "Error, no results loaded". r75's change to "Recommend more like
  this" had aimed at the wrong list (harmless; kept).
- **Fix:** `SuggestionHandler.queryFor(item, {filter, boorus})` →
  `suggest: c:<character>… f:<copyright>… a:<artist>… t:<act>… s:<style>
  [with:<filter>] [on:<booru>] post:<address>` (spaces and `%` escaped; the
  first 12 act tags in `actTags` order; the style only when not already an
  act). `isQuery` (the marker first, a `post:` term), `fromQuery(booru,
  limit, query)` rebuilds the post with the same typed tags (acts get
  ascending counts so `actTags` keeps their order), the `on:` sources
  (else the tab's own booru) and the filter. `SearchTab`'s constructor
  builds that loader for such a query right after the custom-handler
  branch, so a restored tab and a re-run search get it too; any other
  query is a normal search. `SearchHandler.isPlainSearch` keeps these
  queries out of `SearchHistoryStore.record` (both call sites) and out of
  `InterestsHandler.onSearch`. `TagContentPreview.newTabQuery` is what both
  open actions use.
- **Tests:** `test/suggestion_query_test.dart` (facets of the rebuilt post
  equal the original's for rounds 0-5, booru and doujin; escaping, filter
  and sources; the marker rule; `SearchTab` picks the loader, also from a
  `TabBackup` JSON round trip; `newTabQuery`; history through an in-memory
  database). Live (`test/suggestion_tab_live_test.dart`): the screenshot
  post (e621 6717654) → 27 posts, every one carrying a facet tag.
- **Left:** tabs opened before this build hold only "suggestions".

### 4.47 Models out of the way: measure, fewer threads, quiet moments (r77, build 97)

- **Evidence (the user's 19 Sep log, 14:12-14:31):** the dips were not proven to
  be the models - 8 of the trace's 12 slowest frames sat next to a page, dialog
  or viewer opening/closing with no model run near; 2 lined up with model work.
  Proven: closing the viewer fires a view event (`_flushDwell`, viewer
  `dispose`) whose learning step ran the encoder (no thread count = ORT default
  = every core), the looks model and, for favourites, the tagger (4 threads)
  right as the feed came back; frame grabs went on under other pages.
- **`handlers/recommender/model_work.dart` (new):** `ActivityClock` (a global
  `pointerRouter` route, root scroll notifications in `PerfTraceGestureLayer`,
  page changes in `PerfTraceRouteObserver` incl. remove/replace) and
  `ModelWork`, a one-at-a-time queue: a step runs after `quiet` (1.5 s) without
  activity; `heavy` steps (the tagger) wait while `videoPlaying()` (the pool's
  `MediaKitPlayerView.anyPlaying`) up to `maxVideoWait` (60 s) while lighter
  steps behind them go first; when the app pauses/hides, waiting steps run at
  once with `lite = true` (no models). Steps are logged when they waited 3 s+,
  and go on the trace as `model.start` / `model.end <label> <ms>`. Errors are
  logged, never rethrown. `ModelWork.instance.attach(...)` in `main.dart`.
- **Recommender:** `onEvent` = cheap checks + `ModelWork.run('learn <kind>',
  _learnEvent, heavy: _wantsPixelTags)`; `onExposed` = `ModelWork.run('exposed
  <surface>', _exposedNow)`. Lite skips the encoder, looks and pixel tags; the
  timeouts now start when the step starts. User-facing model work (score,
  rerank, explain, boards, Posts like this, Try it) is not queued; it can still
  wait for the running step (the plugin serialises every call).
- **Threads:** `OnnxEmbeddingRunner` 1 (new `threads`/`options`), `OnnxLookRunner`
  1, `OnnxTagRunner` 2 (`defaultThreads`, `options`). A session's pool is fixed
  at creation, so one count per model for every caller. The encoder returns the
  plugin's `Float32List` as is (it was copied value by value on the UI isolate).
- **Frames (`video_frames.dart`):** `_tick` also needs `onScreen()`
  (`ViewerHandler.viewerOnScreen`, claimed/released by the viewer's RouteAware
  `didPush`/`didPopNext` vs `didPushNext`/`didPop`/`dispose`; only the owner can
  release) with the app resumed, and `quiet()`. `frameNow` skips both. The
  frame's looks run is a `ModelWork` step (`frame look`), outside `_inFlight`,
  skipped for a post hidden meanwhile. `MediaKitFrameSource.showing` needs
  `refCount > 0`.
- **Measure:** `encoder: N texts in X ms (CPU x1)` log line; `model.encoder`,
  `model.tagger`, `model.look` trace events; the pool logs `video: N frames
  dropped by the output, M by the decoder (<url>)` when a played video is
  released (mpv `frame-drop-count` / `decoder-frame-drop-count`).
- **Tests:** `test/model_work_test.dart` (thread counts; quiet gate with a fake
  clock; touches, moves, route pops and fling scrolls count; no overlap; 20
  steps in order; the tagger held by video, released by the limit or the video
  stopping; lite flush on pause; a throwing step; trace events), 3 new
  `video_frames_test` cases (covered / away / touching; frameNow does not wait
  for the looks run; a post hidden meanwhile gets no vector), 3 new
  `recommender_handler_test` cases (learned only after the quiet window; lite
  on pause writes the row without model calls; exposures never overlap a step).
- **After one contrarian review:** `dismiss()` no longer awaits the queued
  step (the viewer and doujin menus await it; with the tagger held by a video
  it could wait 60 s), and a "Not interested" whose step finds learning off
  is logged by `_logDismissal`; `reset(world)` bumps `_generation[world]` so a
  step queued before the reset is dropped; `away` = paused/hidden/detached only
  (inactive - the notification shade - is not leaving); `stepTimeout` 60 s;
  `onDrainedAway` (set in `RecommenderHandler.register`) flushes the models once
  lite steps drained; the clock is monotonic (a Stopwatch); `drained()` for
  tests; fullscreen claims the screen for its lifetime (frames go on in
  fullscreen); the encoder runner falls back to default options like the
  others. The r34 dismissal test now awaits `ModelWork.instance.drained()`.
- **Not verified on a phone:** whether the dips were the models (the user's
  A/B traces answer it), real run times with fewer threads.

### 4.48 Frame grabs no longer break videos (r77, build 98)

- **Evidence (19 Sep log):** 37 of 49 grabs worked; all 12 failures were a
  video's first grab, 2.6-6.6 s after the player was bound, answered by mpv in
  1-11 ms with "Taking screenshot failed." (the output was being rebuilt after
  the first video-size event: vo=null -> gpu -> seek in media_kit_video's
  Android `real.dart`). media_kit puts error-level mpv messages on
  `stream.error`; the pool set `hasError`; `_onPlayerError` stamped its 2-min
  cooldown; the next visit re-opened the same file on that player (planner
  `rebind` of the errored slot): one of two such re-opens showed no size in
  7.8 s. The emulator's 0:00 stall was NOT this: there mpv has no video output
  at all, and every rebind stalls, frames on or off (checked with one pooled
  player).
- **Readiness (`video_frames.dart`):** before `screenshot-to-file`, `current-vo`
  must be non-empty and not "null", and `video-frame-info/interlaced`
  non-empty (the VO's current frame, what the screenshot copies); otherwise no
  command, one log line per video ("look: waiting for the picture from mpv
  (...)"). The decoder line is read after the first check passes. "No file
  written" counts `notReady` (max `maxNotReady` = 10 per video), not failures.
- **Error filter (`media_kit_player_view.dart`):**
  `MediaKitPlayerView.isScreenshotNoise(message, lastGrabAt:, now:)` = exactly
  "Taking screenshot failed." or "Error writing screenshot!" within
  `screenshotWindow` of the entry's `lastGrabAt`, which
  `MediaKitFrameTarget.command` sets through `MediaKitFrameSource.noteGrab`
  before a screenshot command. The pool's `errorSub` and the widget's
  `_onPlayerError` (before the cooldown stamp) skip it. Error lines name
  `entry.url`.
- **Replace (`player_pool_planner.dart` `PoolAction.replace`):** an errored free
  slot with the requested URL is disposed (`cancelSubs`, `dispose`) and a new
  player is built (`entry.replaced`, logged "replacing a broken player").
  `release(_PooledPlayer entry)` goes by identity (all three widget call
  sites). Errored slots of other URLs are still re-pointed at capacity.
- **Diagnostics:** `_watchForPicture` logs "video: no picture 8 s after start
  (idle, output, codec, waiting for cache, cached s)" for a viewed video with
  no width; `logSub` logs mpv's fatal-level messages ("mpv fatal (...)").
- **Tests:** planner (replace slot 0; errored in use -> create; errored other
  URL -> rebind), `test/media_kit_error_filter_test.dart` (exact messages in
  and out of the window; lookalikes stay errors), frames (no command while the
  output is none/"null" or no frame is drawn, exactly one once ready; more "no
  file" answers than the failure limit, then a kept frame; frameNow sends
  nothing while not ready and answers with the kept frame).
- **After one contrarian review:** the view's `Video` is keyed by its
  controller (`ObjectKey`), since media_kit_video's state does not rebind to
  the new controller of a replaced player (in-place recovery via
  `_onPlayerError` -> `markErrored` -> `_release` -> `_scheduleInit`);
  fullscreen holds its player (`holdForFullscreen` / `endFullscreenHold`:
  refCount and `fullscreenHolds`), and `_onPlayerError` does nothing while a
  hold exists; at capacity an errored idle slot is replaced, never re-pointed;
  grab times use a monotonic clock (`MediaKitPlayerView.monoNow`) and the
  window is 15 s; readiness checks every `waitGap` (2 s), at most
  `maxWaitsPerVisit` (30); "no picture yet" answers grow the gap
  (`gap * (1 + visitNotReady)`), 5 per visit, 10 per video, reset by a
  successful frame; the 8 s picture watch is re-armed when a preloaded
  player becomes the viewed one. Pool-level identity tests (replace disposes
  once, release by identity) would need a player factory seam over media_kit's
  Player; not added.
- **Not verified on a phone:** first-grab success rate, a replaced player's
  picture (the emulator has no video output).

### 4.49 Tag previews: the icon reacts at once, previews belong to their page, Back order (r77, build 99)

- **Evidence (19 Sep):** twice (14:16:28, 14:25:13) the viewer closed 0.1-0.2 s
  after a tap on a chip's preview icon; the preview's first request came
  0.3 s after each icon tap (the chip's `InkWell.onDoubleTap` holds the arena
  for `kDoubleTapTimeout`), and `FloatingPreviewHandler.open` bound the window
  to the top page - the feed. Nothing in the icon's path pops the viewer; the
  closer is still unknown. Back with a window open acted on the page under it.
- **`widgets/gallery/tag_chip_shell.dart` (new):** `TagChipShell` = the chip's
  Material + a Stack of the body's `InkWell` (tap = menu, double tap =
  editor, hold = tab) and a `Positioned` preview zone
  (`previewZoneWidthFor()` = 11 + 16 + 8 + 2) over the icon the body draws:
  hit first and alone, so no double-tap wait. The zone has onTap (a 500 ms
  repeat guard via a Timer, off in selection mode) and onLongPress, and a
  button semantics label. `buildTagChip` uses it; the long-press body is
  `_openTagInNewTab`, used by the tag name and the icon, with `tagBooru`
  (was `possibleBooruHandler?.booru ?? searchHandler.currentBooru`, the main
  feed's site for a nested viewer on another site).
- **`FloatingPreviewHandler`:** `open`/`openDoujinPreview` take `owner`
  (`_pageFor`: a page still in `_pageRoutes`, or the top page under a dialog
  still up; a closed owner opens nothing and logs "preview ... dropped");
  `hasWindowFor(route)`; `_syncBackEntries` registers a `_PreviewBackEntry`
  (a `PopEntry` with canPop false) on every page that owns a window: Back is
  blocked and the newest window of that page closes in a microtask (every pop
  entry of the page hears the same Back first). Code pops (back arrow,
  swipe-down) are not blocked and take the windows with the route. The
  viewer's `PopScope` (closes the info sheet) and the feed's `_onPopInvoked`
  (exit prompt, drawer) stand down while `hasWindowFor` their route. Callers:
  the chip (`ModalRoute.of(context)`), the tag menu's Preview (the top page
  taken before the menu pops), the strip header's floating-window button.
- **`utils/navigation_trace.dart` (new):** `ViewerCloseObserver` (in
  `navigatorObservers`) logs "viewer closed by: <app frames>" for the route
  named `viewer` (Flutter/dart frames dropped; "the system" when none);
  `BackGestureLogger` (added in `main()` before `runApp` - `handlePopRoute`
  asks observers in order and stops at the first that handles it) logs
  "Back pressed (system)" and "Back gesture started (<edge> edge)".
  `PerfTraceGestureLayer` keeps each pointer (`ui.fingers` when more than
  one) and logs `ui.cancel`.
- **`TagContentPreview.loadPreview`:** returns when unmounted after its search
  (the 14:23:53 "Null check operator" in `setState`).
- **Tests:** `test/tag_chip_shell_test.dart` (icon fires on the first frame and
  not the chip; tap/double tap/hold on the name; hold on the icon; repeat
  guard; semantics label; same height), `test/floating_preview_owner_test.dart`
  (owner page; closed owner opens nothing; dialog -> page under it; Back
  closes the window and the page's own Back stands down; next Back pops;
  back arrow takes the window), `test/navigation_trace_test.dart` (the
  caller's frame in the line; other pages log nothing; system Back logged
  before the close).
- **After one contrarian review:** no `ModalRoute.of(context)` in callbacks
  (it subscribes the element to every route change: the whole tag list and
  the feed's `MobileHome` would rebuild on each page change) - the chip and
  the strip header open for the top page, and the viewer's / feed's Back
  handlers check `hasWindowFor(topPageRoute)`; the viewer app bar's
  `PopScope` (share cancel + cache delete) stands down for a preview Back;
  the strip's, the preview windows' and linked media's viewer pushes are
  named `ViewerCloseObserver.viewerRoute` too; `<asynchronous suspension>`
  and elided lines are dropped from the close line; `SuggestionHandler` and
  `BoardHandler` count as virtual feeds (the post's real site for previews,
  related strips, the source row); the zone's `Semantics` has onTap and
  onLongPress, labelled with `loc.tagView.preview`. Known: pages that pop with
  `maybePop` (a doujin's AppBar, the reader, post files) close their window
  first when they own one; a chip whose row overflows the list width puts the
  zone over its count/dot (pre-existing overflow).
- **Not verified on a phone:** the closer (the new lines will name it),
  Samsung's predictive Back.

### 4.50 Try it: no silent failure (r77, build 100)

- **Evidence (19 Sep):** no Try-it run in the user's log (19 tagger runs = 19
  favourites). Cause NOT proven. Candidates: (1) `_tryIt` returned silently on
  a null pick; (2) Android ended the process while the picker was open and
  image_picker kept the pick for `retrieveLostData()`, which the app never
  called; (3) after a folder chooser in the same process, `MainActivity`'s
  catch-all `onActivityResult` answered the picker's return on the stale
  `methodResult` ("Reply already submitted"). image_picker's README note on
  `singleInstance` (always RESULT_CANCELED) is contradicted here: the SAF
  folder links in the user's settings came back to this same activity, and
  on the emulator GET_CONTENT worked - the launch mode is left as it is.
- **`utils/photo_picker.dart` (new):** `PhotoPicker.useSystemPicker()` in
  `main()` sets `ImagePickerAndroid.useAndroidPhotoPicker` (PICK_IMAGES on
  Android 13+: the media library and the cloud provider, no other apps' file
  browsers); `systemPickerOn` for the log. image_picker's platform packages
  were already in the lockfile (transitive); no pubspec change.
- **Try it:** a null pick shows a neutral note "No picture came back from the
  picker." (`tagger-try-message`; errors stay red) and logs how long the
  picker was open and which picker; `lostPick` (a seam over
  `retrieveLostData`, Android only) runs on the section's `initState` and
  reads a recovered picture. The board editor goes through
  `BoardEditPage.pickImagePath` and logs every outcome.
- **`MainActivity.onActivityResult`:** answers only `SAF_REQUEST` (4273, the
  three folder/file requests), once (`methodResult` taken and cleared).
- **Tests:** `test/photo_picker_test.dart` (an `ImagePickerAndroid` instance and
  the registered instance as `main()` calls it), the r74 Try-it widget test
  (null and throwing picks), a lost-pick test (read on open),
  `boards_page_test` (null pick). Checked on the emulator: folder chooser,
  then the photo picker - cancel shows the note, a pick reads, no crash.
- **Not done:** a "the tagger is busy" message (nothing to hook: `tag()` just
  waits); the Kotlin change has no unit test.

### 4.51 Try it cannot stop without a word (r78, build 101)

- **Two holes, both read off the code (not guessed):** (1) the Try it button
  was `ready && !trying ? _tryIt : null`, so a pick whose future never
  completed - which the pre-r77 catch-all `onActivityResult` could cause by
  answering the picker on a used `methodResult` - left `trying` true for the
  life of the State: a grey button, every tap silent, nothing logged. That
  fits the 19 Sep report exactly (no `tagger:` Try-it line at all).
  (2) A tap with no tagger, a downloading tagger or one already reading did
  nothing at all.
- **The permission theory was checked and dropped.** targetSdk is 36 (Flutter
  3.42 beta's `FlutterExtension.kt:34`); READ/WRITE_EXTERNAL_STORAGE are dead
  there and `requestLegacyExternalStorage` has been ignored since Android 11.
  Neither picker route needs a runtime permission: both hand back a
  `content://` uri with a transient read grant read through ContentResolver
  (`FileUtils.java:63`), and image_picker's PermissionManager is only ever
  asked for CAMERA (`ImagePickerDelegate.java:383-385`, `:545-547`). Do NOT
  add READ_MEDIA_IMAGES or a `<queries>` entry.
- **Also dropped:** "the picker decodes the photo at full size". Its resizer
  reads the bounds first and decodes with `inSampleSize`
  (`ImageResizer.java:56`, `:139`), so `maxWidth/maxHeight/imageQuality` stay:
  they are what keeps a 200 MP photo out of our own `img.decodeImage`
  (`image_tagger_handler.dart:584`), which decodes at full size in a compute
  isolate.
- **`utils/picker_watch.dart` (new):** `PickerWatch.run<T>(pick, {onLate})`
  returns a `PickResult<T>` (`picture | nothing | lost | failed`, `openMs`,
  `reason`). While the picker is in front the app is away and the wait is
  unbounded; on the first `resumed` after that, the answer is due within
  `afterResume` (6 s), else the pick is given up on. `hardLimit` (5 min) is
  the backstop when nothing ever opened. A late answer goes to `onLate`
  instead of being dropped. Seams: `afterResume`, `hardLimit`,
  `resetForTests()`.
- **Try it:** every tap answers - "Download an image tagger first." / "The
  image tagger is still downloading." / "Still reading the last picture…" -
  and logs `tagger: Try it - the tagger is not ready (<state>)`. A lost pick
  says "The picker closed without giving a picture. Try again.", after asking
  `lostPick()` whether the picker kept it. `_keptPicture()` logs the failure
  that `_recoverLostPick` used to swallow. The button's `onPressed` is never
  null.
- **Boards:** `_pick` runs through the same watch, with the same four
  outcomes and a log line each.
- **Tests:** `test/picker_watch_test.dart` (8, including the lifecycle
  paused/resumed give-up, the backstop, the late answer, and no timer or
  observer left behind), two r78 widget tests in `recommendations_page_test`
  (a picker that never answers; taps that cannot read), one in
  `boards_page_test`. Lifecycle in tests is driven through the
  `flutter/lifecycle` platform message, not the protected binding method.
- **Checked on the emulator (build 101):** with no tagger, Try it says
  "Download an image tagger first." (it was a dead button before) and logs
  `the tagger is not ready (none)`; with one ready, Android's photo picker
  opens and a cancel gives `no picture came back from the picker (open 16.7 s,
  Android's photo picker)`. The give-up path cannot be forced there - it needs
  a picker that never answers.

### 4.52 Learning is never dropped (r78, build 102)

- **The flaw, from the code:** `ModelWork._pump` had no deadline. A step waited
  for `quiet` (1.5 s with no touch, scroll or route change) for ever; the only
  escape was `away()`, and that path runs every step lite -
  `_learnEvent(lite: true)` passes no embedding, no look vector and no pixel
  tags (`recommender_handler.dart:459-461`), and the event is learned once, so
  it cannot be undone. A person who never pauses would get that for
  everything.
- **Measured from the user's 19 Sep log** (a full PerfTrace recording, 914 s,
  ~540 gestures, one per 1.19 s): the 1.5 s gate would still have opened about
  11 times a minute, ~46 % of the time overall but only ~27 % while a video
  played; the worst wait was 8.1 s. The real brake was `maxVideoWait` 60 s: a
  video was on screen 56 % of the session and all 19 tagger runs were
  favourites.
- **`ModelWork`:** `maxWait` (20 s) is a deadline on the quiet gate - past it a
  step runs regardless, and `lite` stays tied to `away()` alone, so a deadline
  run is a full run. `maxVideoWait` 60 s -> 10 s. A run past the deadline logs
  `model: <label> ran after waiting N s (the screen never went quiet)` and
  adds a `model.deadline` trace event, so the next phone log says how often it
  happens.
- **`run(..., defer:)`:** when the app leaves with a step still waiting and the
  step has a `defer`, `_runOne` calls it instead of running lite, logs
  `kept for later` and emits `model.kept`. A step without `defer` (exposures,
  frame looks) still runs lite as before.
- **`recommender/deferred_learning.dart` (new):** `DeferredLearning.keep(map)`
  appends and writes `<config>/recommender/deferred.json` synchronously (the
  app is usually about to be ended), capped at 200, oldest first;
  `takeAll()` hands them over once and empties the file. Seams: `fileFor`,
  `resetForTests()`.
- **`recommender_handler`:** `onEvent` passes a `defer` that keeps
  `{v, kind, value, key, world, item.toJson(), ns}` - the reward is recomputed
  from kind+value on replay, so it is not stored. `replayKept()` queues each
  kept event as a normal step (so it still waits for quiet, and can be kept
  again), with `handler: null`.
- **Where the replay is triggered, and why not in `register()`:** `register()`
  runs at `main.dart:105`, BEFORE SettingsHandler is registered - calling
  `learningEnabled` there threw `GetIt: Object/factory with type
  SettingsHandler is not registered` on the device (seen in the emulator log
  of the first build 102). It now runs from `_maybeReplayKept()` at the first
  `onEvent` of a run, guarded by `_replayedKept` and
  `GetIt.isRegistered<SettingsHandler>()`. Consequence: kept work waits until
  the person reacts to something in the next run.
- **Tests:** five r78 tests in `model_work_test` (deadline with the models and
  a `model.deadline` event; still held before it; the 10 s video hold; kept
  instead of lite; lite when there is nothing to keep),
  `test/deferred_learning_test.dart` (4: round trip through a new run, the
  cap, a broken file, nowhere to write), four in `recommender_handler_test`
  (kept then learned later, kept picked up by itself on the next run,
  exposures still lite, the deadline end to end). The r77 tests that asserted
  lite learning were rewritten to the r78 truth; the flush test now uses an
  exposure, since a learning event is no longer lite.
- **Checked on the emulator (build 102):** a favourite then Home writes
  `deferred.json` with that event and logs `model: learn favourite kept for
  later (the app is leaving)`; after a force-stop and a restart, the first
  reaction consumes the file. The 20 s deadline could not be exercised there -
  adb input cannot keep the screen busy that long - so it rests on the tests.

### 4.53 Why the viewer closed - a reason, not a stack (r79, build 104)

- **r77's line lied in release builds.** `ViewerCloseObserver` logged
  `callerOf(StackTrace.current)`. On 20 Sep all 34 closes named
  `_BackupRestorePageState._linkDrive.<anonymous closure>` (the "Google Drive
  was not linked" dialog's OK button, backup_restore_page.dart:528), back-arrow
  taps included. The back arrow (hideable_appbar.dart, `() =>
  Navigator.of(context).pop()`) has the same shape; AOT release builds share
  one copy of machine code between identical functions (dedup_instructions),
  and the VM names any one of them. JIT tests could not see it. Inference from
  the VM source plus the log, not disassembled. `callerOf` is removed.
- **`NavigationTrace.closing(reason, close)`** holds the reason only while
  `close` runs; a pop and a popUntil notify observers inside the call
  (navigator.dart), so every viewer pop of that call gets it. The observer
  logs `viewer closed by: <reason>` and a `viewer.close` trace event.
  Otherwise: `Back gesture (system)` within `gestureWindow` (5 s) of a
  gesture start (the app's predictive-back detector commits with a plain pop
  that never passes `didPopRoute`), `Back button (system)` within
  `systemBackWindow` (1 s) of `didPopRoute`, else `unmarked - ...`.
- **Marked sites:** back arrow, swipe down, Escape (gallery_view_page), Not
  interested emptying the list, tab list "exit viewer" and the new-tab notice's
  button (tag_view), the tag previews breadcrumb, FurAffinity and Kemono post
  pages' `_openTab`. Unmarked on purpose: the fullscreen video's `maybePop`
  (reaches a viewer only through a stale flag) - an "unmarked" line would show
  it.
- **Two ways a viewer closed by mistake, closed:** (1) the tag previews
  breadcrumb popped until `tagDialog/$tag` OR the first route; the chain's
  dialogs are popped as it goes on, so a gone dialog fell through to the feed -
  `NavigationTrace.tagDialogOrViewer` also stops at the `viewer` route. (2) The
  snatch dialog's two buttons and the share dialog's Hydrus button popped
  after an await; a dialog dismissed meanwhile meant the viewer was popped -
  `NavigationTrace.popIfOnTop(dialogContext, what)` pops only while the
  dialog's route is current, else logs `<what> was already closed`.
- **Tests:** `test/navigation_trace_test.dart` rewritten (13): the reason,
  one line through a dialog-to-feed popUntil, a reason not outliving its
  close, unmarked, system Back and its window, the gesture, the trace event,
  the breadcrumb with its dialog gone and present, the dialog pop after its
  dialog closed and while open.
- **Not verified on a device:** the emulator froze after boot on 21 Sep (see
  the emulator memory); the phone check is the user's.

### 4.54 The tagger's threads follow who is waiting (r79, build 105)

- **Evidence:** tagger model time 1096-1933 ms at CPU x4 (19 Sep log) against
  1753-4012 ms, median 2862, at CPU x2 (20 Sep log). The looks model (0.24-0.55
  s per thumbnail at x4 vs 0.30-0.57 at x1, the per-thumbnail time includes the
  thumbnail fetch) and the encoder (44-80 ms a text at x1) show no thread
  effect; the 18-23 s looks batches overlapped For You's first-load burst of 60
  `score()` calls. So only the tagger changed.
- **`TaggerUse { waiting, background }`**, `tag(bytes, {use = waiting})`. The
  plugin fixes the thread count when a session opens (no per-run option,
  flutter_onnxruntime 1.8.5 RunOptions), so the call that OPENS the session
  decides: `waitingThreads` 4, `backgroundThreads` 2. An open session is used
  as it is - never a second one (each copy ~379-467 MB; the plugin runs every
  call under one lock anyway). `PixelTags._defaultTagBytes` passes
  `background`; Try it, `BoardHandler.defaultPixelTagger` and the board
  editor use the default. `TagRunnerFactory` is now `(modelPath, threads)`.
- **Idle-close race fixed:** `_touch`'s 120 s timer was never cancelled when a
  run started, so it could close the session under a run - the plugin answers
  INVALID_SESSION, `_fail` sets TaggerState.error, and the tagger stays off
  until a refresh. `_inFlight` counts runs from before the decode; the timer
  skips the close while it is above 0 and the run's own `_touch` re-arms it.
  (The looks model has the same timer shape - not changed in this build.)
- The log line ends `(<provider>, waiting|background)`.
- **Tests:** four r79 tests in `image_tagger_handler_test` (4 vs 2 threads by
  who opens; a background run reuses the open session; PixelTags is
  background; the idle close waits for a slow run, with a fake that fails a
  closed session like the plugin does).

### 4.55 A pin hidden on a source stays out of its sidebar (r79, build 106)

- **Why the hide did nothing for the user:** the hide (r52) lives in that
  source's `SourceSettings.hiddenPins` (`id:N` for database pins, `tag:x` for
  doujin pins) and only `PinnedTagVisibility.visible()` reads it - called by
  the search window's `PinnedTagsBlock` alone, a Modular UI part that is off by
  default. `DrawerQuickAccess._load` read the same pins and never filtered.
- **Fix:** both branches of `_load` (doujin store, database) pass their list
  through `PinnedTagVisibility.visible(pins, current)`. The sidebar already
  reloads on drawer open, tab change and the editor's close. Hides are per
  source entry (keyed by the base URL's host), so For You, merged and
  favourites tabs still show the pin.
- **Id reuse:** `PinnedTag.id` is `INTEGER PRIMARY KEY` without AUTOINCREMENT,
  so SQLite hands a deleted pin's id to the next pin, which inherited its hide.
  `DBHandler.removePinnedTag` now calls `PinnedTagVisibility.forgetId(id)`
  (every source, via `SourceSettingsHandler.dropHiddenPins`), and the pins
  editor's database store runs `forgetMissing(getAllPinnedTags())` when it
  lists (only with an open database), dropping `id:` hides of pins that no
  longer exist; `tag:` hides are left alone.
- **Tests:** `test/pinned_hide_sidebar_test.dart` (5, real in-memory SQLite):
  hidden pin absent and a visible pin present (the loader swallows errors), the
  same pin present on another source, a doujin pin, delete-then-reuse of an id,
  and the orphan cleanup. The first fails against the r78 sidebar.

### 4.56 Post actions as buttons in the info sheet (r79, build 107)

- **User request (21 Sep, annotated screenshot):** "Find this post elsewhere",
  "Find posts like this (new board)", Comments, "Posts like this" and
  "Recommend more like this" move from full-width rows into the compact block
  with Favorite / Save / Collect / Details, icon + one word. "More from
  artist/uploader", the Suggested strip and the Tags block stay.
- **`widgets/gallery/flow_action_grid.dart` (new):** `FlowActionTile` (the
  r74 tile, with the label in a scale-down `FittedBox`), `FlowActionGrid`
  (`shapeFor(n)`: n<=5 one row, else rows = ceil(n/5), columns =
  ceil(n/rows); the last row padded with empty `Expanded` slots so every tile
  keeps one width: 4, 5, 3+3, 4+3, 4+4, 5+4), `FlowExtras.of(doujin,
  comments, hasPicture, recommend)` with each old row's gate, and one-word
  labels Comments / Elsewhere / Board / Similar / Recommend.
- **`tag_view.dart`:** `_flowActionRow` builds the grid. The taps and gates
  are shared methods (`_openComments`, `_openFindElsewhere`, `_openNewBoard`,
  `_openSimilar`, `_openRecommend`, `_commentsAvailable`, `_hasPicture`,
  `_recommendSeeds`) used by the buttons and by the old rows. Comments keeps
  the FEED handler's `hasCommentsSupport` (doujins too); the other four are
  booru-only (`isDoujinContext`). Comments' icon is `Symbols.chat_bubble_rounded`,
  filled when the post has comments.
- **Modular UI:** `viewer.postActionsAsButtons` (Viewer, default on). Off:
  the block has the four and the old rows build as before - one form only.
- **Tests:** `test/flow_action_grid_test.dart` (the gates and order, one-word
  labels, the shapes, nine tiles at 412 and 330 dp without overflow and at
  least 48 dp each with an equal-width last row, a 1.3x font, four tiles in
  one row, the switch). No test pumps TagView itself (none did before).

### 4.57 The left sidebar scrolls in landscape (r79, build 108)

- **Report (22 Sep, AYN Thor held sideways):** the left sidebar did not
  scroll; nothing above QUICK ACCESS was visible and the last rows were cut.
  `DrawerQuickAccess.build` was a `Column`: header, `Expanded(pins ListView)`,
  then the Quick access rows at full height. When those rows alone exceed the
  height, the pins get 0 and the column overflows; nothing scrolls.
- **Fix:** one `CustomScrollView`: header `SliverToBoxAdapter`, the pins
  `SliverList` (or the empty text), then `SliverFillRemaining(hasScrollBody:
  false)` holding the divider, the label and the rows in a `Column` aligned to
  the end - with room to spare Quick access stays at the bottom edge as before;
  otherwise the whole panel scrolls. Behaviour change only when the pins alone
  overflow a portrait panel: everything scrolls instead of the pins alone.
- **Tests:** `test/drawer_landscape_test.dart` (480x400: no overflow,
  Collections reachable, pins reachable again - fails on the r78 layout;
  400x1400: Quick access within 60 dp of the bottom, the first pin near the
  top). Note: `scrollUntilVisible` stops when a row peeks in; `ensureVisible`
  before `hitTestable` checks.

### 4.58 Backup & restore: one list, named Drive backups, the database in parts (r80, build 109)

- **Asked (21-22 Sep):** every file selectable for backup and restore
  (multi-select), the recommender's folder too; the database back whole or
  in parts (pulled tags, the recommendation log and For You interests, the
  vector cache); Google Drive usable on a fresh install (it was gated behind
  choosing a backup folder); the Drive buttons appearing only after a
  restart once linked; named snapshot folders on Drive with dates, the old
  root files shown as an earlier backup.
- **Link bug cause:** `_refreshDriveState` read `isLinked`, then listed the
  Drive files, then called `setState` - with no try/catch. A listing that
  threw right after the sign-in lost the whole update. Now the linked state
  is set first; the listing runs after it inside try/catch
  (`DriveBackup.list` is also wrapped whole).
- **Core (UI-free, tested):** `lib/src/services/backup_plan.dart` -
  `BackupItem` (settings, sources, doujinLibrary, sourceSettings, bookmarks,
  boards, boardPictures, tagTypes, database, recommender), file names
  (`recommender.<file>`, `board-picture.<file>` prefixes for folders),
  `BackupTarget` (folder or Drive), `BackupHooks` (everything app-side),
  `BackupRunner.backup/restore`. Restore order: files first, database last;
  the recommender restore calls `hooks.stopRecommenderWrites()` first
  (`RecommenderHandler.stopWritingForRestore()` + `DeferredLearning.stop()`:
  memory dropped, no flush/keep until restart - otherwise the exit flush
  writes the old models over the restored ones). A whole-DB attempt forces a
  restart even when it failed (the DB was closed).
- **Database parts:** `lib/src/services/db_parts.dart` - the backup's
  store.db is copied to `restore-parts.db`, ATTACHed, and per table the
  common columns are copied with `INSERT OR REPLACE`; the recommendation
  log (`Interaction`, `RecommenderFeature`, `TagSignal`) is DELETEd first
  (replaced, so reactions are not counted twice on a rebuild); pulled tags
  (`BooruTag`, `BooruTagOverride`, `TagAliasCache`) and the vector cache
  (`ItemEmbedding`) are merged. A backup is checkpointed first
  (`PRAGMA wal_checkpoint(TRUNCATE)`).
- **Drive:** `DriveSnapshot`, `snapshots()` (folders in LoliSnatcher newest
  first; top-level files become one `earlier` entry named "Earlier backup",
  dated by its newest file), `createSnapshot(name)` (unique name),
  `deleteSnapshot`, and `folderId` on `list/upload/download`. Query strings
  are escaped (`quoted`).
- **App side:** `lib/src/services/backup_app.dart` - `appBackupHooks()`,
  `FolderBackupTarget` (SAF; every file passes through the cache's
  `backup/` scratch folder under its own name; an old copy is deleted first
  because SAF writes "name (1)"), `DriveBackupTarget`.
- **Page:** `backup_restore_page.dart` rewritten: the checklist (All/None,
  keys `backup-item-<name>`), the folder section, the Drive section (always
  shown on Android), snapshot-name dialog (default
  `DriveBackup.defaultSnapshotName`), snapshot picker (dates, delete),
  item picker (only items present), database mode dialog (whole / parts),
  confirm, restart after 3 s when needed (not for tag types alone). Tag
  types are no longer debug-only. Test seams: `BackupRestorePage.isAndroid`,
  `driveHasCredentials`, `driveIsLinked`, `driveSnapshots`, `driveLink`.
- **Tests:** `backup_plan_test` (12: ticked items only, the journal
  checkpoint, empty items skipped, restore into place with the recommender
  stopped first, the loaders, missing items, the whole database, parts
  merged vs replaced, a backup older than a table), `drive_snapshots_test` (4),
  `backup_page_test` (6: fresh install shows Drive, the checklist, link with a
  failing listing, the snapshot picker), a freeze test in
  `recommender_handler_test`. The page tests need an app-bar title of 20 px:
  `MarqueeText` asserts on the default 22 px (22 x 0.85 is not a whole number
  of 0.1 steps in floating point). The page's widget tests were written after
  the page (the core's tests came first).
- **Not verified here:** SAF and Drive on the phone (no emulator on 22 Sep).

### 4.59 Debug mode kept, captures as files, the Models page (r80, build 110)

- **Debug mode** (`isDebug`) is a declared setting now (default
  `kDebugMode`); `settings_page.dart` saves on the 6th tap and on the
  long-press. It was in `deviceSpecificSettings` only, never saved.
- **Why the trace report was "not in the log":** `Logger.log` cuts every
  entry at 10,000 characters. `Logger.logParts(text, ..., title:)` redacts
  the whole text once, then logs it in parts of at most 9,000 characters
  cut at a line end in the part's second half, each headed
  "<title> (part i/n)"; `Logger.splitParts` joins back to the input.
- **`lib/src/services/capture_files.dart`:** `CaptureFiles.save(name, text)`
  writes to `capturesPath` (a SAF tree picked in Debug → Captures folder),
  else `getOrCreateSAFDirectory(extPathOverride, 'captures')`, else (no
  folder, or the folder refused) `<ext dir>/LoliSnatcher/captures/`
  (`fellBack`). SAF writes go through a scratch file in the cache and
  `copyFileToSafDir`; an existing file of that name is deleted first (SAF
  would write "name (1)"). Off Android the download folder is a plain path.
  `keepTraceReport(report)` = `logParts` + `trace-<yyyy-MM-dd-HH-mm-ss>.txt`.
  The Debug page's trace dialog shows at most 20,000 characters; Copy
  catches the Binder failure. The old `<config>/traces/` copy is gone.
- **Source capture:** `SourceCaptureHandler._startedAt` (restored from the
  journal header) names one file per capture
  (`source-capture-<host>-<stamp>.txt`); `saveToCaptures()` runs when the
  recording browser closes, after "Fetch the response bodies" and from the
  new "Save to the captures folder" button.
- **Models page** (`lib/src/pages/settings/models_page.dart`, from the
  Recommendations page's "Models: jobs and threads"):
  `lib/src/data/model_tasks.dart` holds `ModelUse` (waiting/background;
  `TaggerUse` is now a typedef of it), `ModelKind`, the nine `ModelTask`s
  (text: learning, forYou, boards; look: learning, forYou, similar, boards;
  tagger: tryIt, boards) and the thread counts. Stored as `modelTasks`
  (only jobs switched off) and `modelThreads` (only counts changed from
  today's: text 1/1, look 1/1, tagger 4/2), written next to the declared
  settings like `modularUi`, plus the declared `aiModelsOff`. The frames
  (`videoFrames`) and reactions (`taggerOnReactions`) switches are the old
  ones, shown on the page too. `modelThreads` and `capturesPath` are
  device-specific (not synced).
- **Gates:** each handler's `enabled` includes `!aiModelsOff`. Recommender:
  `_embeddings`/`_looks` take a `task` (learning in `_learnEvent` and
  `_exposedNow`; For You in `score`, `scorer`, `rerank`, `explain`, the
  doujin-parts scorers; the scorer's in-memory vectors follow For You too).
  Boards: `BoardHandler._init` gates the tagger (taggerBoards), the looks
  model (`b.hidden` → lookSimilar, else lookBoards) and the description
  vector (textBoards); `BoardQueryBuilder.deriveTags` gates `embed`
  (textBoards); the board editor shows `board-tag-off`; Try it is not built
  when tryIt is off (`tagger-try-off`). `lookVectorsFor` now takes the
  `ModelUse`.
- **Threads:** the work that opens a model decides its count
  (`ModelTasks.threads(kind, use)`, clamped to 1..cores). The text and
  looks models record `openedThreads`; their default runners read it (the
  test fakes' factory signatures are unchanged). `threadsChanged()` on all
  three: closes an idle session at once, else when the last run ends
  (`_inFlight`, `_closeWhenIdle`) - never under a run. The video frames
  code was not touched (as asked), so frames open the looks model with the
  "while you wait" count.
- **Tests:** `model_tasks_test` (7), `capture_files_test` (10),
  `models_page_test` (3), r80 groups in the tagger/looks/encoder tests,
  recommender (looks and text jobs), board handler (3), board query,
  Recommendations page (Try it off, Models opens), board editor. Written
  before the code (they could not compile without it; not run red).
- **Not verified here:** SAF writes into the download folder's
  subfolder and the new thread counts on the phone.

### 4.60 Frames by place, remembered looks, vectors in their own database (r81, build 111)

- **Asked (22-23 Sep):** a larger vector store whose disk space the user
  picks; frame grabs switchable on For You and, in other tabs, only on a
  reaction - with today's behaviour as the default ("do not change the
  behaviour the app has now"); "remember the looks of posts you open"
  reusing the frames already taken; the vectors in a database of their own
  that a backup can take or leave.
- **Frames:** `FrameMode {playing, reaction, off}` (model_tasks.dart);
  settings `framesForYou` / `framesOtherTabs` (`stringFromList`, default
  'playing'). `VideoFrames` reads the place at `_onCurrent` (`inForYou`
  seam: `SearchHandler.currentBooru.type.isForYou`; boards, Posts like this
  and everything else are "other tabs"). 'playing' = the old schedule;
  'reaction' starts no timer; `onReaction(item)` takes the frame on screen
  at once (skipping the quiet/on-screen checks - the person's own act),
  then the timer takes more, `reactionFrames` (3) in all; 'off' nothing.
  `frameNow` (Posts like this, the board editor) only follows the master
  `videoFrames` switch, as before.
- **Reaction hook:** `RecommenderHandler.reactionFrames` (favourite, snatch,
  collect) returns null unless `VideoFrames.takesReactionFrame(item)` - so
  every other event is queued exactly as before. When a frame is taken,
  `onEvent` captures the world generation first, then awaits the frame
  (its 'frame look' step is queued ahead of the learning step), then queues
  the learning. Found by the r77 reset test: awaiting before the
  generation capture let a step queued before a reset leak into the fresh
  model.
- **Remember looks** (`lib/src/handlers/recommender/look_memory.dart`,
  attached in main.dart; setting `rememberLooks`, off by default): leaving
  a post looked at for 2.5 s+ queues a ModelWork step
  `LookModelHandler.imageVectors([item], use: background)` - memory and the
  database answer first, so frames' averages and For You's vectors are not
  read again; once per post per run; not for doujin items or hidden posts.
- **Vectors database:** `DBHandler.vectorsDb` = `vectors.db` beside
  store.db, opened in `dbConnect` (`openVectors`); rows in store.db's
  ItemEmbedding move over with ATTACH + `INSERT OR IGNORE` on every start
  that finds some (first r81 start, a whole restore of an older backup);
  `vectorDatabase` falls back to `db` when none is open (tests).
  `putEmbeddings` prunes every `pruneEvery` (200) writes to
  `vectorSpaceMb` (default 250, choices 25 MB-2 GB on the Models page):
  least recently used first (`getEmbeddings` refreshes `at` for rows older
  than a day), down to 90%. `vectorUsage` splits text/looks by the
  `look:` model prefix; `compactVectors` = VACUUM + checkpoint, run when the
  space is lowered. The encoder's own count prune (6,000) and the
  recommender's are gone.
- **Backup:** `BackupItem.vectors` ("Vector cache", vectors.db): backup
  after `checkpointVectors`; restore merges via `DbParts.mergeVectors`
  into the open database, no restart. `DbPart.vectorCache` now means an
  older backup's store.db vectors and goes into `vectorDatabase`.
- **Tests:** `vector_store_test` (6), `look_memory_test` (4), five r81
  frame tests in `video_frames_test`, settings in `model_tasks_test`, the
  hook in `recommender_handler_test`, two in `backup_plan_test`, three on
  the Models page; the encoder prune test moved to bytes.
- **Not verified here:** the move of the phone's existing vectors, SAF and
  frames on the phone.

## 5. Sources catalogue (`BooruType`, `boorus/booru_type.dart`)

Each type has an `isX` getter; `isKemono` is true for Kemono AND Pawchive.
`booru_edit_page.dart` carries per-type default URL, favicon and the
instruction text shown when adding one. `test/source_capabilities_test.dart`
has a row per source stating which capabilities it claims.

**Classic boorus** (unchanged upstream families): AGNPH, BooruOnRails,
Danbooru, e621, Gelbooru, GelbooruV1, GelbooruAlike, Hydrus, InkBunny,
Moebooru, Nozomi, NyanPals, Philomena, Rainbooru, Realbooru, Rule34Dev,
R34Hentai, R34US, Sankaku, IdolSankaku, Shimmie, Szurubooru, WildCritters,
World, Civitai (official API), WebView (browser tab), Autodetect.
Bakemono.app rides on Gelbooru + `BakemonoProfile`.

**Video / tube sources:** Hanime1 (`hanime1.me`, Chinese→English tag
dictionary in `data/hanime_dictionary.dart`, domain fallback; since r29 the
Tag builder lists the dictionary by group, §4.3), Kusowanka,
TikPorn, XXXTik, XXXFollow (login), RedGifs (`redgifs_login_page`),
Rule34Video (r28; `rule34video.com`, a KVS tube behind DDoS-Guard, no
account). rule34video serves ONE list per query — newest, the site's text
search, one tag by id (`/tags/{id}/`), one artist (`/models/{slug}/`), one
category, one uploader — so `rule34video_query.dart` parses the query into a
route and refuses combinations; a bare word the tag snapshot knows opens the
tag page, anything else is a text search. The `type:` chip is the site's
Straight / Gay / Futa / Music / Iwara filter (tag ids on `?flag1=a,b`), which
the text-search block ignores — there the phone drops cards, and only Gay and
Futa carry a badge. A per-source default lives in Source settings
(`SourceSettings.contentTypes`, offered where `contentTypeOptions` is
non-empty). Videos are `needToLoadItem`: the mp4 links (`get_file/…
?v-acctoken=`) are IP-bound and expire, so the page is read on open and Retry
re-resolves. The tag builder (`rule34video_tag_catalog.dart`, namespace-keyed
like hentaipaw) walks the site's tag / model / category async blocks; the
site's own autocomplete is switched off, so suggestions come from the snapshot.
`Tools.hasCaptchaStrings` knows `ddos-guard` for this host.

**Doujin sources** (`DoujinDataHandler.doujinTypes`): EHentai (r30;
`e-hentai.org` + `exhentai.org`, ONE type, the host picked per source in
Source settings — `SourceSettings.siteVariant`, offered through the new
`BooruHandler.siteVariants`; exhentai is used only when the session has a
usable `igneous`. Forward-only `next=<gid>` cursor paging; the extended
listing is forced with the cookie `sl=dm_2` (the `inline_set=dm_e`
parameter only SETS that cookie, which a client sending its own Cookie
header never keeps). Pages are resolved ONE AT A TIME — the only source
that does: `loadItem(gallery)` registers N `needToLoadItem` page items and
the reader/snatcher resolve each through `/s/<key>/<gid>-<n>` or the
`showpage` API, paced 300 ms. Page PREVIEWS (r32) are tiles of the site's
sprite strips, one strip per block of 20 pages: `pageEntriesFromHtml`
reads key + tile (`strip.webp#xywh=x,y,w,h`, a `SpriteTile`) from the same
`#gdt a` anchors; `_fetchBlock` reads a block once for every tile asking
(static in-flight map, waiters' cancel tokens as interest only, bulk lane,
30 s backoff per refused block, `_blocksRead` for tile-less blocks) and is
also what `_resolvePage` uses for keys; the `BooruHandler.ensurePageThumbnail`
hook (default no-op) is called by `PageThumbnailLoader` around every grid
tile and filmstrip cell. Tiles go to the SESSION-ONLY
`BooruItem.transientThumbnailURL` (`displayThumbnailURL` is what `Thumbnail`
and the filmstrip load; `thumbnailURL` stays the cover and is what the DB
keeps) because strip links expire within days — a 4-day-old one answered
404 on 2026-09-13. `SpriteTileImage` (`widgets/image/sprite_tile_image.dart`)
resolves the strip through the ordinary image cache once (one headers map
per source, fixed timeouts, `fileNameExtras: ''`, so `CustomNetworkImage.==`
holds across tiles) and cuts its rectangle in a completer that survives
being disposed before the strip lands. Login: §8. My Tags can be imported
as the source blacklist through the new `hasAccountBlacklist` capability),
HDoujin (r30; `hdoujin.org`, the Schale software on its own network — see
NiyaNiya below and `SchaleNetwork`), NHentai (official v2
API; API key optional; account favourites sync), NiyaNiya (Schale Network
JSON API + Turnstile clearance, §8.3), AsmHentai (HTML; login form),
EaHentai (r69: the site's JSON API — latest, typed/sorted search, popular,
random, album with pages, suggestions; bearer login; HTML parsers as the
fallback), Faccina =
hentalk.pw (REST API; query translation), Hitomi (`gg.js` hosts + packed
binary indexes; throws a visible "hitomi changed" error rather than
guessing), HentaiPaw (Next.js server-rendered; fetched through
`OriginPageClient`, §8.4). Quirks and endpoints are in each handler's doc
header — read them before changing a handler.

**Kemono-style:** Kemono (kemono.cr), Pawchive (pawchive.pw) — §7.

`SchaleNetwork` (`boorus/doujin/schale_network.dart`) maps a configured site
to its API and auth hosts: hdoujin.org → `api.hdoujin.org` /
`auth.hdoujin.org`, everything else → the Schale network. Clearance tokens
are kept per network key, so niyaniya's check does not answer for hdoujin.

**Virtual boorus** (local, no network): Merge (several boorus in one tab),
Downloads, Favourites, Collections, ForYou, History. `isLocalDb` groups
the DB-backed ones.

## 6. The doujin system

### 6.1 What "doujin" means in the code
A doujin source is one where a post is a **book** (ordered pages, read
front to back), not one file. `BooruHandler.hasReader` is true for it, its
`loadItem` pushes the page list into `ReaderHandler`, and its `BooruType`
is in `DoujinDataHandler.doujinTypes` (nhentai, niyaniya, asmhentai,
eahentai, faccina, hitomi, hentaipaw). `DoujinDataHandler.knownDoujinHosts`
identifies items by post-URL host when no booru is at hand
(`isDoujinItem(item)`); `isDoujinBooru(booru)`; `sameDomain(a, b)` says
whether switching a tab between two boorus stays inside one domain.

### 6.2 Separation: the rule and where it is enforced
Doujin and booru personal data never mix. Concretely:

| Data | Booru side | Doujin side |
|---|---|---|
| favourites | `BooruItem.isFavourite` in store.db | `doujinData.json` (`DoujinDataHandler`), synced to the account when the site supports it (`toggleFavouriteSynced` — the ONLY path UI may use) |
| history | `ViewedPost` table | doujin history list in doujinData.json |
| search history | `SearchHistory` table | doujin saved queries; routed by `SearchHistoryStore` (the one place that decides) |
| blacklist / hidden tags | `settingsHandler.hiddenTags` | `SourceSettingsHandler` global + per-source blacklist (`hiddenTokensOverride` in `parseTagsList`) |
| starred / marked tags | `Tag` table + marked list | doujin starred tags (`markedTokensOverride`) |
| pinned tags / saved searches | `PinnedTag` / `SavedSearch` tables | doujin pins / saved searches in doujinData.json |
| collections | `Collection`/`CollectionItem` | doujin collections in doujinData.json (bookmarks became collection entries; `BookmarkHandler` + `bookmarks.json` remain as the local bookmark layer) |
| settings | settings.json | `sourceSettings.json` — global `_global` layer + per-source overrides (reading direction, quality, blacklist, card display…) |
| downloads | flat files in the download root | `<root>/Doujin/<host>_<id>/001.ext…` + `doujin.json` manifest (`DoujinDownloadHandler`), listed in `DoujinDownloadsPage` |

- `DoujinMigration` moved pre-split entries out of the booru stores once
  (pure planner + DB applier; re-armed by a backup restore in
  `backup_restore_page.dart`).
- Drawer surfaces branch on the current tab's domain
  (`drawer_quick_access.dart`: doujin library rows vs booru rows).
- Tag preview, tag hub, "More from artist", Related/Recommended all take the
  item's domain into account (`ab74c7d` "one shared predicate for
  cross-domain source switching").
- **Tests that guard it:** `doujin_separation_test`, `doujin_domain_scoping_test`,
  `doujin_favourite_tags_test`, `doujin_drawer_refresh_test`,
  `booru_switcher_domain_test`, `interests_guard_test` (For You never learns
  from doujin views). Three adversarial "leak" audits found 8 + 5 + 12 leaks
  after the first split (commits `28c7942`, `cb67e4a`, `dfb5178`, `0883d0c`);
  assume a new surface leaks until a test says otherwise.

### 6.3 The doujin surfaces
- **Cards** (`widgets/preview/doujin_tab_view.dart`, card widgets):
  per-surface rendering (feed / strip / library), cover display modes
  fit / crop / **adapt** (adapt sizes the card to the decoded cover through
  `DoujinCoverAspectHandler`, because most sources send no dimensions),
  tag strip below the cover, tag chips with popup + tap/long-press setting
  (`doujin_tag_chip.dart`), item menu (`doujin_item_menu.dart`), big-cover
  height capped at ~45–55 % of the viewport.
- **Tabs:** a doujin tab is a real tab type — `SearchTab.doujinPostURL /
  doujinTitle / doujinThumb`, `isDoujinDetail`; backed up as `dp/dt/dth` in
  `TabBackup`. The **mini tab manager** (`widgets/tabs/doujin_mini_tab_manager.dart`)
  is a swipe-in sidebar with the tab manager's full working set (drag zone
  widened twice on request; `doujin_edge_drag_test`).
- **Detail page** (`pages/doujin_detail_page.dart`): cover + titles, meta
  row, Read / save / bookmark / favourite, tags grouped by the site's own
  namespaces (`doujin_tag_namespaces.dart` — tags are stored as bare names
  with `tagNamespace()` on the side; storing `artist:x` as the name broke
  chips, language badge, blacklist and favourites at once), Related
  (chapters & versions via `relatedVersionsQuery`), Recommended
  (`DoujinRecommendationEngine`, title + tags, works on BooruItem so one
  engine serves all sources; diversity + endless-count setting), pages grid.
- **Reader** (`pages/doujin_reader_page.dart`): follows the **layout
  contract** in its header — opaque MaterialPageRoute, no Scaffold slots, a
  Stack with Positioned bars, `ClipRect` around the page view, tap zones on
  their own layer, stock `InteractiveViewer`, filmstrip scrubber, per-source
  reading direction and quality from `SourceSettingsHandler`, progress in
  `ReaderProgress` ("Continue reading"). It shipped broken twice before the
  contract; do not restructure it without re-reading that header and
  `doujin_reader_test` / `doujin_strip_geometry_test`.
- **Library pages** (`doujin_library_pages.dart`, `doujin_favourites_page`,
  `doujin_favourite_tags_page`, `doujin_downloads_page`): favourites,
  collections, history, saved searches, starred tags, downloads.
- **Listing tag backfill** (`doujin_listing_tag_backfill.dart` mixin): for
  sources whose listing has no tags (niyaniya, asmhentai, eahentai) the grid
  paints first, then each gallery's page fills tags in — needed because
  blacklist, starred tags and hidden/marked checks all read `tagsList`.
- **Favicons:** fallback chain site `/favicon.ico` → DuckDuckGo ip3 →
  letter tile, cached per host (`favicon_fallback_test`).

### 6.4 How the doujin source got fixed — the history in one place
Read the commit bodies (`git log --format=%B <sha>`) for detail; this is
the map.

1. `4aceff7` **doujin** — reading system + nhentai (v2 API) : ReaderHandler,
   reader page, detail sheet, per-source settings.
2. `9748d2e` doujin-ux, `b2389dc` doujin-fix — native namespaces, book
   header, pages grid; the first reader rebuild.
3. `c79b705`…`e38c725` **the 7-item batch** — reader rebuilt with the layout
   contract + tests; detail page replaces the viewer; card tags below cover
   with fit/crop/adapt; Related self-heals + real Recommended; favourite
   syncs to the nhentai account while bookmark stays local; top-level Doujin
   settings (global + per-source); drawer quick access + `id:` queries.
4. `f8fb939`…`c8e469a` **R2** — Item 1 separated the data systems (then two
   leak audits); per-surface cards; recommendation diversity; card
   interactions; tag chip popup; doujin tabs + mini tab manager +
   three-view tab manager; big-cover toggle; filmstrip scrubber; drawer
   cleanup + account blacklist import; bookmarks as collection entries.
5. `29ac01b`…`0883d0c` **R3** — booru blacklist can no longer touch doujin
   items; doujin tag stars in their own store; doujin tabs as a real tab
   type; mini tab manager parity; reactive drawers (`DrawerRefresh`); strip
   header button; cover cap; favicon fallback; gate round 5 (12 leaks).
6. `59707d1`…`abea0ac` **R4** — drag strip, strip cards, one domain
   predicate; then six sources: niyaniya (Schale), asmhentai (login),
   eahentai (login), hentalk (faccina API), hitomi (gg.js + binary indexes;
   four cross-source fixes), meta tags for the HTML sources.
7. `9077da6`…`5762f5b` **source capture** — the tool that let hentaipaw and
   niyaniya be written from the phone's view of the site.
8. `a15067f`…`0f3b93b` **fixes 1–3** — thumbnails on new sources (two
   causes), tag parsing on every source, card styling.
9. `712c8c2`…`3f07e4c` — erocdn JPEGs wrongly rejected as truncated (the
   JPEG integrity check, `jpeg_integrity_test`); niyaniya reader showed
   thumbnails not pages; covers fill the card; **adapt** finally wired up.
10. `9efc2d9`…`4f126b8` niyaniya rounds: the site detects WebViews (UA), a
    refused clearance locked the challenge out, asking for a clearance must
    not take the reader down.
11. `e48d07e`…`04dc4ad` **parity walk** (`doujin_parity_walk_test`): every
    source queried at its own starting page through the same checks.
12. `25f14ed` r9 — Suggested/Recommended filters, "More from artist" booru,
    background hang. `1714e27` r10 — dependency upgrade (html pinned 0.15.6,
    dynamic_color 1.8.1, run `dart run slang` after locale changes).
13. `4d4c81f`…`8326484` r10b–r17 niyaniya: accept the re-issued clearance,
    instrument the challenge window, **Koharu-parity reader**, r13 split
    downloads + capability-gated settings + observe Turnstile instead of
    hooking it, gated calls made from inside the site's page, lean page
    client, agent version from the real engine.
14. `1a539ae`…`e73b15e` **hentaipaw** from the capture, then pages fetched
    from a WebView on the site's origin (`OriginPageClient`).
15. `6e2fee8`, `f2ee2ed` r19–r20 **tag builder**: catalog store, puller,
    picker; chips moved inside the Metatags card; niyaniya address trace;
    hentaipaw tag index (5 namespaces, `BooruTag.sourceId`).
16. `772b88a`…`e15d17e` r21–r26 **kemono / pawchive** (§7).

Lesson that repeats through all of it: the phone sees the site, this
container does not. Every round that guessed at markup or at Cloudflare's
behaviour failed; every round that started from a capture or a log worked.

## 7. Kemono-style sources (kemono.cr, pawchive.pw)

- **`KemonoSite`** (`boorus/kemono_site.dart`) is the single description of
  each site: hosts, Accept header, media headers, services, whether the
  detail is an envelope, which endpoints exist (`hasRandom/Popular/TagList/
  Dms/UpdatedArtists/ApiLogin/SearchCount`), min query length, creator DB
  table, and every URL builder (`postsUrl`, `creatorPostsUrl`, `popularUrl`,
  `postUrl`, `thumbUrl`, `fileUrl(path, {server})`, `iconUrl`, `bannerUrl`,
  `loginUrl`, `logoutUrl`, `favicon`, `sidebarSummary`). `KemonoSite.of(booru)`.
  Add a third site by adding a `BooruType`, a `KemonoSite` constant and a DB
  creator table; the handler, pages and sidebar are shared.
- **kemono.cr facts (2026-09-04):** API base `/api/v1`; needs
  `Accept: text/css` (DDoS-Guard 403s a browser Accept); `/posts?q=&o=&tag=`
  50 a page; detail is `{post, attachments[{server,name,extension,
  name_extension,path}], previews, videos, props}`; files live on
  `n1..n4.kemono.cr` picked by murmur2 of `/data{path}`
  (`KemonoApi.fileServer`, verified 13/13 against the site's JS); thumbnails
  `img.kemono.cr/thumbnail/data{path}` (800 px). **The file hosts are
  unreachable from the user's network and from this container** (Chrome on
  the phone hangs too) — so the viewer shows `mediaOutageNotice`, the
  `KemonoFileHosts` probe (HEAD per host, 10-min freshness) reports status
  in the sidebar, and `sampleURL` falls back to the thumbnail.
- **pawchive.pw facts (2026-09-05):** the older kemono API, plain JSON;
  `/creators` is one 93k-row array (patreon + fanbox); post detail is flat
  (no envelope; `has_full`, `preview_state`); no random / popular / tag list /
  DMs / updated (404); comments 404 when none; login is a form POST
  `/account/login` (username, password, location) answering 302 + session
  cookie; one file host `file.pawchive.pw` behind DDoS-Guard that answers
  heavy fetching with a 403 "stop… I will block your IPs" — **never prefetch
  files there**; thumbnails `img.pawchive.pw/thumbnail/data{path}.jpeg` are
  **WebP bytes** under a `.jpeg` URL.
- **Handler** (`kemono_handler.dart`): `KemonoQuery.parse` (site-aware min
  length; `creator:`, `service:`, `tag:` terms; `unsupportedReason`),
  `makeURL`, `postOf(detail)`, `parseItemFromResponse` (cover via
  `KemonoProfile.coverPath`), `availableMetaTags` gated by `site.has*`,
  media hooks, `getMediaHeaders => site.mediaHeaders`.
- **API** (`kemono_api.dart`): `headersFor(site)`, `request` (401 → one
  re-login), `getJson`, `describeStatus`, `postDetail` cache (10 min / 50),
  `comments` (404 → empty).
- **Session** (`handlers/kemono_session_handler.dart`): password stays in
  the booru config `apiKey` like every source; the session cookie lives in
  `kemono_session.json` beside settings, keyed `'<site>|<username>'`
  (r24). `ensureLoaded` migrates pre-r24 bare-username keys to
  `kemono|<user>` (r26). One login attempt per user per minute. Say this
  in reports when the user asks where credentials go.
- **Creator index** (`KemonoCreatorStore.forSite`, tables `KemonoCreator` /
  `PawchiveCreator`, meta files `kemono_creators.json` /
  `pawchive_creators.json`): the full creators list pulled once, searched
  locally; Artists page (`kemono_artists_page.dart`) with service chips,
  favourites, updated list; `kemono_creator_header.dart` above a creator's
  feed.
- **Post page** (`pages/kemono_post_page.dart`, toolbar action
  `Symbols.article_rounded` in `hideable_appbar.dart`, button in
  `tag_view.dart`): title, meta, content HTML (`LoliHtml`, `/data` links
  made absolute), embed, poll, pictures as full-width tiles (thumbnail
  first, real file on top when the **Full** chip / `kemonoPostFullImages`
  is on and the host is not known down), videos, attachments, comments,
  prev/next. Pushed pages use `resizeToAvoidBottomInset: false` (the
  Samsung recorder hides the keyboard, so a "dead area" at the bottom was
  the inset). Holds ONE media-headers map (`_mediaHeaders`) — see §3.2.
- **Sidebar** (`widgets/drawers/kemono_sidebar.dart`): replaces the
  downloads drawer on kemono-style tabs when `kemonoSidebar` is on;
  `Material` + `SafeArea` (without a Material ancestor text gets yellow
  underlines and InkWell throws), coloured stadium pills grouped ARTISTS /
  POSTS / FAVORITES / MESSAGES, rows gated by `site.has*`, a status card
  (index + file hosts), tag picker with error snackbar, "Use the app
  sidebar" → the quick-access drawer has the reverse row.
- **DMs / announcements** (`kemono_messages_pages.dart`), kemono only.
- Tests: `kemono_test.dart` (33), `pawchive_test.dart` (15); fixtures
  `kemono_*.json`, `pawchive_*.json`.
- **Unverified on device:** everything from r22 on (media outage flow, post
  page, pawchive feed/thumbnails/post files, sidebar pills, popular and tags
  on kemono — the last two need a log with the request visible). Pawchive
  login is untested (no account).

## 8. Sessions and logins, per pattern

- **Config fields:** `Booru.userID` / `Booru.apiKey` (labels via
  `userIdLabel/apiKeyLabel`; `usesUserId/usesApiKey` hide them). Cookies
  from WebView logins are merged through the shared cookie jar
  (`cookie_jar_timeout_test`; header merge, not concatenation — `5db59b1`).
- **API-key sources:** Danbooru family, Gelbooru, e621, nhentai (key
  optional; needed for favourites/blacklist sync), Civitai.
- **WebView / cookie logins:** Sankaku, rule34.xyz, RedGifs
  (`redgifs_login_page`), XXXFollow, Cloudflare-fronted boorus (a 403 on
  media triggers the captcha page; `44bd311`).
- **Form logins done by the app:** asmhentai (`/login/`), hentalk/faccina,
  pawchive (`/account/login`) — result visibility for asmhentai and hentalk
  is an open item (the user could not tell whether login succeeded).
- **eahentai (r69):** `POST /api/auth/login` (JSON) → bearer token in
  `eahentai_session.json` (`handlers/eahentai_session_handler.dart`), shown
  on its Source settings page with the site's own refusal text.
- **API login:** kemono (`POST /api/v1/authentication/login` → `session`
  cookie).
- **niyaniya / Schale clearance** (`handlers/schale_clearance_handler.dart`,
  `schale_clearance.json`): reading needs a `crt` token the site gets by
  solving a Turnstile and POSTing to `auth.schale.network/clearance`, kept
  in `localStorage['clearance']`. The app uses **two windows** (the design
  Keiyoushi's Koharu extension uses): a visible **solver** (Chrome's
  reduced UA, pop-ups allowed, main-frame-only navigation filter; the
  person solves by hand) and a headless **harvester** (loads `robots.txt`
  on the site origin, reads localStorage once, destroys itself). They share
  WebView storage; that sharing is the mechanism. Gated API calls are made
  from inside the site's page (page client on the robots.txt origin),
  `/cdn-cgi/trace` ip/colo is logged at issue and refusal, `x-ratelimit`
  headers pace requests, a refused token is dropped (not retried silently).
  **Still unverified end to end on the user's phone** — next log should show
  the trace lines. Tests: `schale_clearance_flow_test`, `schale_reader_test`,
  `doujin_niyaniya_test`.
- **hentaipaw** (`handlers/origin_page_client.dart`): the plain client gets
  a WAF 403, so pages are fetched by a headless WebView parked on
  `robots.txt` of the site origin doing same-origin fetches with the
  engine's own headers/cookies. Sibling routes (artists/groups/parodies)
  still need a capture.
- **e-hentai** (`handlers/ehentai_session_handler.dart`, `ehentai_session.json`;
  the page is `pages/settings/ehentai_login_page.dart`): the forum login runs
  in a WebView (like JHenTai/EhViewer). The page copies `ipb_member_id` and
  `ipb_pass_hash` out of the cookie jar into its own file and DELETES them
  from the jar, then fetches exhentai.org once for `igneous` (`mystery` = the
  account has no access). **Why not the jar:** `Tools.getFileCustomHeaders`
  attaches the booru host's jar cookies to every media request, and e-hentai
  images come from volunteer hath.network nodes — a session in the jar would
  be handed to strangers. The handler puts the cookies in its own header for
  site requests only; `getMediaHeaders` sends a Referer and no cookie. The
  Source-settings buttons (site settings / My Tags / Watched) seed the jar
  for the visit and scrub it afterwards.
- **Log redaction** (`utils/log_redaction.dart`) strips keys, cookies,
  passwords and session values from logs and captures; `log_redaction_test`.

## 9. Persistence

**store.db** (`handlers/database_handler.dart`; DDL in `updateTable()` runs
on every open, so adding a table/index there is enough):

| Table | Owner / purpose |
|---|---|
| BooruItem, ImageTag, Tag | posts, their tags, tag types (favourites = `isFavourite`, downloads = `isSnatched`) |
| SearchHistory, TabRestore, TabVisitHistory, SeenPost, ViewedPost | booru search history, tab backup, visit order, seen/viewed |
| PinnedTag, SavedSearch | pins (follows are pins carrying `followLabel`), saved searches |
| Collection, CollectionItem | booru collections |
| BooruTag, BooruTagOverride | tag snapshot + corrections (§4.3) |
| TagAliasCache, TagSignal | cross-booru alias cache; For You interest scores |
| ReaderProgress | doujin reading position |
| KemonoCreator, PawchiveCreator | creator indexes (whitelisted in `creatorTable()`) |

**Files beside settings.json** (`SettingsHandler.instance.path`):
`doujinData.json`, `sourceSettings.json`, `bookmarks.json`,
`kemono_session.json`, `schale_clearance.json`, `kemono_creators.json` /
`pawchive_creators.json` (index meta), `update.json`; the source-capture
journal `source-capture-session.jsonl` in the cache dir. Backup/restore
(`backup_restore_page.dart`) and the Drive backup (`services/drive_backup.dart`)
cover settings, boorus, the DB and the doujin files; restore re-arms the
doujin migration.

## 10. Tests and fixtures

Run: `flutter test $(ls test/*_test.dart | grep -v booru_test)` (offline).
`booru_test.dart` = live-network smoke cases, run by hand only.

| Area | Files |
|---|---|
| doujin sources | `doujin_asmhentai_test`, `doujin_eahentai_test`, `doujin_hentalk_test`, `doujin_hitomi_test`, `doujin_hentaipaw_test`, `doujin_niyaniya_test`, `doujin_parity_walk_test`, `schale_clearance_flow_test`, `schale_reader_test` |
| doujin UI/data | `doujin_card_*`, `doujin_cover_height_test`, `doujin_detail_*`, `doujin_download_layout_test`, `doujin_reader_test`, `doujin_strip_geometry_test`, `doujin_tabs_test`, `doujin_menu_test`, `doujin_tag_*`, `doujin_recommend*`, `doujin_bookmark_test`, `doujin_listing_tag_backfill_test`, `doujin_edge_drag_test` |
| separation | `doujin_separation_test`, `doujin_domain_scoping_test`, `doujin_favourite_tags_test`, `doujin_drawer_refresh_test`, `booru_switcher_domain_test`, `interests_guard_test` |
| kemono | `kemono_test`, `pawchive_test` |
| e-hentai / hdoujin (r30) | `doujin_ehentai_test` (grammar, cursor URLs, listing, gallery blocks, page resolution with a fake fetcher, session file, site choice; fixtures `ehentai_*.html|json`), `doujin_hdoujin_test` (network table, per-network clearance, JSON parsing); live: `ehentai_live_test` |
| video sources | `rule34video_test` (grammar, URLs, listing, badges, video page, catalog, store-backed routing; fixtures `rule34video_*.html`), `hanime1_tag_catalog_test` (dictionary groups, the instant catalog, every chip term round-trips through makeURL); live: `rule34video_live_test` |
| tag builder | `tag_index_sources_test`, `booru_tag_catalog_test`, `booru_tag_store_test`, `tag_builder_block_test`, `tag_catalog_sources_test`, `tag_catalog_puller_test`; live: `tag_index_live_test` |
| cross-cutting | `source_capabilities_test`, `media_headers_test`, `metatags_block_merge_test`, `tag_catalog_sources_test`, `tag_catalog_puller_test`, `source_capture_test`, `source_capture_inpage_test`, `log_redaction_test`, `jpeg_integrity_test`, `favicon_fallback_test`, `suggestion_filter_test`, `downloads_reconcile_test`, `cookie_jar_timeout_test` |

Conventions: a source test constructs the handler with a `Booru` and feeds
it a fixture from `test/fixtures/` (a body captured with curl or from the
source-capture journal, trimmed, never containing credentials); it asserts
parsed items, URLs for page 1 and 2, tag namespaces, and the capability
rows. `setUp` usually seeds `SettingsHandler` for the DB-less path. When a
handler changes an endpoint, capture a new fixture rather than editing the
old one by hand.

## 11. How to add a source or a feature

1. Failure analysis / probe first: `curl -sS -A "$UA"` the site, or ask for
   a source capture. Record what you verified and when in the handler's doc
   header (every handler here starts with one).
2. `BooruType` value + `isX` getter; factory case (`startingPage` if the
   site counts from 1); `booru_edit_page.dart` defaults + instructions;
   `Autodetect` detection if the host is fixed (`isDetectable`).
3. Handler: `makeURL`, parse list/item, `makePostURL`, tags/namespaces,
   `getMediaHeaders` if the CDN needs a Referer, `availableMetaTags`,
   comments/notes/login if the site has them. Doujin: `hasReader`, push
   pages into `ReaderHandler` from `loadItem`, add the type to
   `doujinTypes` and the host to `knownDoujinHosts`, mix in the listing tag
   backfill if the listing carries no tags, a `TagCatalogSource` if the site
   enumerates tags.
4. Tests + fixture; rows in `source_capabilities_test`, `media_headers_test`
   (and `tag_catalog_sources_test` for a catalog).
5. Parity artifact row; changelog; build; report (§2).

For a UI feature: find the existing widget (the feed, viewer chrome and
drawers all have one owner file, §3.1), keep the Flow look (rounded
`surfaceContainer` cards, Material Symbols Rounded icons, pill buttons,
the theme's `colorScheme`), add a setting only if the user asked for a
choice, and add a widget test where geometry matters (the reader and the
cards have had regressions).

## 12. Open items (as of r77)

- r77 (build 100) is unverified on the device: Try it through Android's photo picker
  on Samsung; the log says "tagger: Try it ..." per outcome (cause not proven).
- r77 (build 99) is unverified on the device: if the viewer closes by itself again,
  the user's log names the closer ("viewer closed by").
- r77 (build 98) is unverified on the device: first grabs should now wait for a picture;
  a replaced player's picture and the grab success rate need the user's log.
- r77 (build 97) is unverified on the device: the user's two traces (models on / off)
  decide whether the dips were the models; builds 98-100 follow (videos, tag preview, Try it).

- r70 is unverified on the device: e-hentai chips (Watched / Favourites +
  category, the four toplists, Show expunged / With a torrent), typed
  suggestions while typing; eahentai Tag builder pulls (Artists 27 letters),
  the heart as the site bookmark, My bookmarks / My lists shelves (shapes
  unverified without an account); hentalk Tag builder (one pull) and
  sort/order chips; asmhentai Category + Random; hentaipaw Daily ranking;
  niyaniya Category; "Only show language" and "Title language" rows on
  e-hentai and hitomi; autocomplete on hitomi/asmhentai/hentaipaw/hentalk
  after a pull.
- r76 (build 96) is unverified on the device: Suggested → open in new tab
  fills in the background and after a restart (checked live from the PC).
- r76 (build 95) is unverified on the device: `look: frame n/5` lines while
  a video plays in the pooled media_kit viewer; the `video: decoder` line
  (expected "no (software)" with MPV: HWDEC vulkan, "mediacodec" with
  auto-safe); the board editor opening on the frame on screen; the switch.
- r75 is unverified on the device: the Looks model download (55 MB) and
  its first run (the `look:` timing line); Posts like this from a
  favourite; a words-only board ordered by the words; "Picked because"
  on a For You post; More / Less / Forget on a learned tag; the
  background opens with their notice; a seeded feed that says why it is
  empty. The seeded feed itself was checked live from the PC (20 posts).
- r74 is unverified on the device: the Image tagger section (download of
  a 379 MB preset, Ready with 10,861 tags, Try it on a picture and the
  `tagger:` timing line - the model has never run off the PC, and the
  PC never ran it either); Tags from the picture in the board editor; an
  image board without a SauceNAO key; Tag reactions with the picture.
- r73 is unverified on the device: Boards in the drawer; a description board
  fills; must-have tags hold; a picked image and a pasted address work with
  the SauceNAO key; "Find posts like this (new board)" from a post; the
  key field under Recommendations. The image picker has never run on the
  phone (the plugin is new).
- r72 is unverified on the device: rule34hentai's Filters card (Sort: Top
  voted reorders; Popular: Today / This month / This year; Content; File
  type; Score; Favorites; Comments), typed fields in the query editor,
  suggestions while typing.
- r71 is unverified on the device: the comments button on yande.re / e621 /
  derpibooru / twibooru / a szurubooru post; notes drawn on a yande.re post;
  the Filters card on yande.re (Order, Rating), twibooru (Sort, Direction,
  Score, Favorites), szurubooru (Sort, Direction, Safety, Type, Special,
  Flag), kusowanka (Sort: Popular / Random / Top rated), inkbunny (Type,
  Scraps), hydrus (Sort, Direction), RedGifs (Type, Verified creators),
  realbooru (Sort); the query editor's new metatags.
- Left for a later round: booru site favourites (danbooru / e621 / moebooru /
  sankaku APIs); comments on e-hentai and eahentai; hentalk collections.
- r69 is unverified on the device: eahentai Log in (Source settings →
  Account) shows "Logged in as …" or the site's refusal; feed cards carry
  tags at once; the search window's Sort / Search in / Quick filters change
  the results; page 2 differs; a gallery opens and reads; no `POST /login`
  and no clear-text password in the log. e-hentai: the detail cover sharpens
  after a gallery opens (switch off → site cover); covers and tiles crisper.
  List cards: Fit / Crop / Adapt visibly different; the cover width stepper
  resizes the column. Site settings on e-hentai: is there a thumbnail-size
  option (unverified; the app would honour it).
- r70: eahentai bookmarks (`bookmarks/albums`) and lists (`lists/mine`,
  `lists/users/<me>/<id>`) as feeds, Bookmark / Add to list actions,
  Related via `image/recommendations`. Response shapes need a logged-in
  check on the device.
- The r69 contrarian review's verdicts are recorded in the r69 commit
  message / changes.txt.
- r68 is unverified on the device: a trace after opening a few posts from the
  feed shows `viewer.open` lines, `route.push viewer`, and the summary line.
- r67 is unverified on the device: Settings → Debug → Record a trace, then open
  a drawer, tap around, swipe, scroll a feed and a list card's tags, open the
  viewer; the report should show ui.* lines in order, widgets alive per type,
  and build counts.
- r66 is unverified on the device: scrolling a list card's tags or title
  sideways no longer fetches the next page (watch the page pill); the list card
  height setting applies; the cards cast a shadow; the tab manager's title is
  whole and its count readable; the feed scrollbar switch hides the bar.
- Next (asked for): a much wider in-app trace - widgets created and disposed,
  builds counted, gestures (taps, swipes, drawer), scrolls with axis and depth,
  buttons pressed - on the same timeline as the frames (r67).
- r65 is unverified on the device: Settings → Debug → Record a trace, use the
  app, stop, and the report should show frames and a timeline of video
  players, posts and screens - saved under `traces/` and copyable.
- r64 is unverified on the device: swiping through videos should show almost
  no `VideoOutputManager.create` / `dispose` in logcat (was 42 / 38 in 25 s),
  and videos must still play, seek, loop and go fullscreen after their slot
  has been re-pointed a few times.
- r63 is unverified on the device: Source settings → GRID → Feed cards → List
  on a doujin source, then the feed shows a row per gallery with a scrollable
  title and scrollable tag rows, the kind/language/pages read right, and Grid
  brings the old cards back.
- The list card's chips are display-only for now; the grid card's chips are
  tappable (`tagChipTap`). Ask the user before making them tappable here too.
- r62 is unverified on the device: with the default 333 ms, flicking through
  videos should create no players (check `VideoOutputManager.create` in
  logcat), and a video you stay on should start about a third of a second
  later. The user will tune the value in Settings → Video.
- r61 is unverified on the device: the visited-tabs history scrolls; the link
  button appears on posts with links, can be moved and switched off in
  Settings → Viewer, and still works with the share button switched off.
- Next (asked for, not started): video players are created and destroyed on
  every swipe past a video (42 created / 38 destroyed in 25 s at 4 warm
  players). A post should have to stay on screen before its player is built,
  and eviction should wait until swiping stops.
- r59 is unverified on the device: the 8K video plays, with the right shape, no
  freeze and far less graphics memory; 1080p videos unchanged, fullscreen and
  seeking fine; the switch off restores the old behaviour.
- r58 is unverified on the device: videos of every resolution play again
  (nothing caps them), the info button opens the sheet with one tap and the
  drag works, seen thumbnails still appear at once, a very tall picture still
  decodes bounded.
- Still open from the profiling: the viewer's page-change build cost (35-68 ms
  for ~55 widgets), the grid's stall when a page of posts arrives (163-177 ms),
  the tab manager's build cost, and the video controls' rebuild when a video
  starts. The 8K video's cost stays as it is unless the user allows a patched
  media_kit_video (§4.27).
- r57 is unverified on the device: the 8K video plays with no freeze and the
  right shape, `VideoOutputManager.setSurfaceSize` in logcat shows the capped
  size, graphics memory stays far below the 2.1 GB seen before, a very tall
  picture still looks right, and both switches bring the old behaviour back.
- r56 is unverified on the device: scrolling back through the grid shows seen
  thumbnails at once; the info sheet opens (button and swipe up) with the
  post's details loading as it opens; both switches bring the old behaviour
  back.
- r55 is unverified on the device: the r50 swipe, video playback with the warm
  pool and big videos on the released media_kit, linked media, hidden pins,
  pin suggestions and the keyboard above sheets still working.
- Asked, not decided: the recommender weights (`config/recommender/`) and the
  downloaded encoder model (`config/encoder/`) are in neither backup.
- Proposed after the profiling, not approved: cached thumbnails without a
  fade, a lighter page change, a video surface capped to the screen (would
  patch media_kit_video; needs the user's explicit OK, §4.24).
- r52 is unverified on the device: the link button in the share slot (FA GIF
  posts too), e621 post 2197695 opening in the app with the user's filters,
  the media-only list, hidden pins, pin autocomplete, the keyboard above sheets
  with the status bar hidden.
- r50 is unverified on the device: types in preview tabs, the Artist hub
  from FurAffinity, the full index pull, the pinned tags page, the back arrow
  with the status bar hidden (the inset kept is the likely cause, not proven),
  the unwrapped linked media rows.
- r49 is unverified on the device: the linked media button and sheet on
  FurAffinity animated posts, an e621 link opening in the viewer on top, an
  `.mp4` link playing in the linked media player, the post page section.
- r48 is unverified on the device: the Flash Play screen (FurAffinity and
  e621 .swf posts), the background load filling the details.
- r47 is unverified on the device: the paheal and rule34.us Filters cards.
- Left of the user plan: pools in the tag builder (danbooru, e621); Idol
  Sankaku and rule34hentai.net filters need checks from the phone.
- r46 is unverified on the device: the Filters cards of Civitai,
  Rule34.dev, Sankaku, r34 World, Hanime1, Kemono, and Derpibooru's ranges.
- r45 is unverified on the device: the danbooru and gelbooru-engine Filters
  cards, their defaults in the source settings.
- Next (user plan): the other sources, source by source: Sankaku and Idol,
  Derpibooru beyond sort/filter, Rule34.dev, R34US, r34 World, R34Hentai,
  paheal, the video sites and Civitai; pools in the tag builder where a site
  has them (danbooru, e621).
- r44 is unverified on the device: e621 Contributors/Lore sections and
  chips, the e621 Filters card and metatags, the blur with "ignore global
  blacklist" on.
- Next (user plan): the tag builder and filters for every other source,
  source by source, from each site's own search help.
- r43 is unverified on the device: the booru source settings page from the
  left sidebar, default filters and always-add terms changing results, the
  Filters card on booru search windows, Derpibooru's site filter.
- Later: per-site options beyond sort/order/rating (Sankaku content
  thresholds, Civitai NSFW level as a source default, e621 blacklist import
  from the account), and a media-type default per source.
- r42 is unverified on the device: the FurAffinity sidebar and its switch,
  the post page, Animated only, the blocklist leaving submissions out, the
  inbox paging, watch and favourite sync, Flash through Ruffle, and the
  Google Drive link finishing after the return from the browser.
- r41 is unverified on the device: a FurAffinity webview logged in and the
  feed still logged in after it; filters on an empty FurAffinity search;
  the gender filter's parameter names (guessed, see 4.10); the Modular UI
  page and the search window without History/Pinned/Popular.
- r40 is unverified on the device: FurAffinity browse, search and artist
  tabs with their icons, the WebView login (cookie names `a` and `b` are
  the site's known ones; confirm after a login), mature results with the
  account filter, music through the video player, the artist Strips, and
  the tab pill's drag and section scope.
- r39 is unverified on the device: thumbnails after a resume from the
  background, tab switches keeping their thumbnails, the doujin rows in
  the tab manager, the Debug page's spacers. The detail page cut off below
  its buttons in the user's screenshot of 2026-09-15 had no error in the
  log; assumed to be a frame the storm never finished — check it on r39.
- r38 is unverified on the device: the two-way tab strip with covers, the
  big doujin rows in the tab manager, and the tab pill (its placement
  beside the scroll buttons, its sheet, the swipe). The pill is opt-in.
- r37 is unverified on the device: the Filters card on doujin tabs, the
  hdoujin Latest/Popular switch, e-hentai's popular page and multi-category
  choice, hitomi's periods and types. Verified from the PC: hdoujin's two
  shelves and e-hentai's popular markup, live.
- r36 is unverified on the device: Check again from the home network
  should confirm access when exhentai.org itself is reachable there; the
  automatic re-check is a day away by design. The log of 2026-09-14 22:02
  also showed the user's network dropping exhentai's addresses and some
  Cloudflare ranges (Hentai Haven) — the VPN is the workaround, not an
  app matter.
- r35 is unverified on the device, and one part has no evidence at all:
  the ONNX inference (the runner is a native plugin the PC suite cannot
  run). Device steps in the r35 changelog: download the English preset,
  open a For You, favourite a few galleries, check the settings card's
  "encoder: N vector components carry weight". Also unverified: Not
  interested on both worlds, video completion on both players. If the
  runner fails, the learner keeps working from tags alone and the logger
  has the error.
- r34 (stuck doujin-tab retry) is unverified on the device: restored HDoujin
  detail tabs should open the detail page from the persisted `doujinPostURL`
  (the gallery key lives in that URL, not in an auth token); the empty
  "Could not load this doujin" screen now has Close tab, the mini-tab
  handle, and Retry that does not drop `dp`. Observed offline: 785 tests
  including the new restore/seed, searchAction-preserve, escape-hatch and
  Schale missing-key cases. Not verified: a real phone force-stop with
  several HDoujin background tabs, or the clearance dialog if `loadItem`
  then needs a fresh check.
- The ONNX encoder shipped in r35 (§4.5).
- r33 is unverified on the device: the doujin For You (drawer → For You on
  a doujin tab), the learner behind the four surfaces, the two switches,
  Settings → Recommendations, the reader's read/finish milestones. Verified
  live from the PC (`doujin_foryou_live_test`): a history-mode page of 20
  galleries from nhentai AND e-hentai (six facet queries all answered once
  requests were serialised per source and paged per query), a seeded page
  of 20 mixed from both, a card resolving through e-hentai. The learner
  itself has only synthetic evidence: expect 20–50 real interactions before
  the ordering visibly differs from the classic one.
- r33 not done, by choice: booru-side hidden-tag edits and a download
  started from the reader are not signals yet; the classic profile and the
  model coexist (the profile is the fallback); no "Not interested" action;
  video completion became a signal in r35, and the encoder shipped in r35.
- r32 is unverified on the device: e-hentai page previews (the detail
  page's Pages grid and the reader's filmstrip) cut from the sprite strips,
  blocks read as the grid scrolls, and the Pages grid made a real lazy
  sliver for EVERY doujin source. Verified live from the PC
  (`ehentai_live_test`, 'page previews'): the 17-page fixture gallery gave
  17 distinct tiles, its strip served 200 `image/webp` with no cookie and
  decoded to 3400×300; the 2026-09-09 strip answered 404 (the expiry the
  session-only design rests on). Unverified: logged-in layouts (40 per
  block, `gt100`/`gt400` tile sizes, the `#gdt img` mode — parsed, never
  seen) and exhentai's strip hosts.
- r32 review findings FIXED, with tests: a failed strip (they expire) made
  error tiles and a retry storm — `Thumbnail._fellBackFromTile` shows the
  cover and `forgetPageThumbnail` drops the block (held for the backoff);
  a failed tile was sticky in the image cache — `SpriteTileCompleter.onFailed`
  evicts; a page being read waited behind queued bulk block reads —
  `_fetchBlock` overtakes on the priority lane and `_readBlock` rides an
  in-flight request or stands down; a null waiter counted as no interest —
  pinned with a fresh token; a thrown request skipped the backoff; tiles
  polluted `DoujinCoverAspects`; a view-form page guessed the block size.
- r32 review findings NOT fixed, by choice: `ResizeImage`/pixelation are
  no-ops for tiles (the crop ignores the decode callback; a 200 px tile is
  smaller than any cell); the strip Referer is frozen to the host of first
  use; expired strips leave cache files under `thumbnails/` (the name
  carries the rotating node segment) until cleanup; a dead tile blinks the
  shimmer once while the cover loads.
- r31 is unverified on the device: the e-hentai paging fix, the four new
  Tag builder catalogs (e-hentai, tik.porn, kusowanka, civitai) and the
  chips on hdoujin. All were verified live from the PC
  (`ehentai_live_test`): a tag search paging 25 + 25 with no overlap;
  e-hentai's Language (87) and Cosplayers (165) lists and a picked term
  searching; tik.porn 84 tags + 131 acts; kusowanka 42 artists a page;
  civitai 100 tags a page; hdoujin's three shards (1,189 / 18,086 / 10,425
  rows).
- r31 review findings FIXED, with tests: kusowanka rows stored the URL slug
  as the display name (rows now carry the site's name and route by
  `sourceId`); civitai was asked for 200 rows a page and the API caps at 100
  (now `pageSize = 100`, 10 pages a pull); `lastPageOf` read any pager on
  the page, so a sidebar link to another index could truncate the walk (now
  anchored to `/<index>/?page=`); the EhTagTranslation files were parsed on
  the UI isolate and `character.md` is 718 KB (now `compute`); the chip
  tests all shared one fixture though namespaces differ in row shape (each
  has its own slice now).
- r31 review findings NOT fixed, by choice: kusowanka's indexes are far
  deeper than a pull (Artists alone reports 8,802 pages; a pull is 20 pages
  = 840 names, resumable through `TagCatalogPuller._resume`), so the chip is
  a filterable head of the list, not a full mirror. And a merge tab fetches
  e-hentai's page 1 three times — pre-existing merge-path behaviour for
  every source, not introduced here; fixing it belongs in `SearchHandler`,
  not the handler.
- Sources still to probe for a tag builder, listed in the guard test's
  `noCatalog` map so they cannot be forgotten: IdolSankaku
  (`iapi.sankakucomplex.com/tag/index.json`), Shimmie and Szurubooru (the
  instance is the user's), GelbooruV1, R34Hentai (Cloudflare blocks this
  machine), R34US, AGNPH, BooruOnRails.
- r30 (e-hentai/exhentai, hdoujin) is unverified on the device, and **the
  login was never run**: no e-hentai account was available here, so the
  WebView capture, `igneous`, the exhentai variant, the My Tags import and
  the account pages are all UNVERIFIED. Anonymous e-hentai was verified live
  from the PC (`ehentai_live_test`): listing with tags, the cursor page,
  a 42-page gallery, page 1 through the page view and page 2 through the
  showpage API, and a hath image answering 200 with no cookie. hdoujin's
  popular shelf and search answered; its clearance-gated READER is
  unverified (no clearance was solved here).
- r30 review findings left unfixed, by choice: `BooruHandlerFactory`'s media
  header/handler caches are keyed `type|baseURL`, so switching the e-hentai
  host mid-session keeps the first Referer until a restart; the resolve pass
  in `SnatchHandler._resolveThenQueue` has no progress, dedup or cancel (a
  second Save all doubles the request rate); `doujin_detail_page`'s
  `_metaLine` only formats a date when `postDateFormat == 'unix'`, so an
  e-hentai gallery shows one through `related:` but not from a search;
  `_extOf` guesses `jpg` for an unknown extension; the listing and gallery
  paths put a star rating in `score`, which the detail page labels with a
  heart. The My Tags and `#gnd` (newer versions) parsers have no fixture —
  no account, and no gallery with newer versions was captured.
- e-hentai out of scope this round, by design: site favourites (favcat),
  comments, the original-size download (`fullimg`, costs GP), tag
  suggestions, the watched list as a feed, torrents/archives, the
  multi-page viewer.
- The booru "Source settings" button stays as it is; the user asked to
  adapt that page to boorus in a LATER build (options that affect boorus
  only).
- r29 (hanime1 Tag builder from the dictionary; the r28 review fixes) is
  unverified on the device. A second review, of the r29 fixes themselves,
  found that the unlocked-but-empty grid after a filter walk was a dead end
  ("no results — tap to retry"), so `search()` now runs up to
  `maxEmptyRounds` further walks itself and then sets an `errorString` that
  names the pages searched (Retry looks further); a changed per-source
  default now applies to the next list, not the one on screen; an index
  fragment with neither rows nor pagination is an error, not a 40-request
  walk of blanks. Review findings NOT fixed, by choice: after a
  phone-side filter walk on rule34video the page number the app shows lags
  the handler's (`SearchHandler.pageNum` is separate); two artists whose
  names collapse to one underscored name keep one slug; `loadItem` ignores
  `withCapcthaCheck` (a challenge shows a message, not the WebView); a
  manually retyped tag is excluded from its chip's list on every source
  (`BooruTagStore.record` skips overridden names). A grid download of an
  unopened rule34video card saves the thumbnail (as .jpg now); resolving
  `needToLoadItem` items in `SnatchHandler.queue` would fix that for every
  such source (hanime1, kusowanka, r34us too) and is the natural next step.
- Tag builder candidates among the other tube sources (the user asked about
  hanime1 "for example"): TikPorn has `GET /gettaglist` (84 tags, trivial);
  Kusowanka has five browse routes (tags / parodies / artists / characters /
  metadatas) that likely paginate; XXXTik, XXXFollow and RedGifs document
  no index (live suggestions only).
- r28 (rule34video) is unverified on the device. From the PC, through the
  app's own client (`rule34video_live_test`): the newest list, `type:futa`
  via `flag1`, text search page 2, a video page to its 720p mp4 and the
  CDN redirect without cookies, and the first fragment of each index all
  answered. Not verified anywhere: playback on the phone (media_kit with the
  302 to boomio-cdn), the DDoS-Guard WebView path on mobile data, the
  members' video list past page 1, the Source-settings content-types row,
  and the Tag builder pull on the phone.
- r27 (tag builder on classic boorus) is unverified on the device: the Tag
  builder card, one pull per family, the opaque picker sheet, the Tag
  browser on the shared puller. Every family, danbooru included, answered
  the first builder page from the PC through the app's own client
  (`tag_index_live_test`); if a phone log ever shows "ignored the …
  category filter", flip `DanbooruTagIndex.walksByCategory` to false.
- niyaniya clearance: unverified end to end on the phone; the next log
  should carry the `/cdn-cgi/trace` lines and the harvest result.
- hentaipaw: artists/groups/parodies/characters routes need a capture.
- asmhentai / eahentai / hentalk: login success is not shown to the user.
- kemono.cr: file hosts unreachable for the user (network side); popular
  and the tag picker on a kemono tab need a retest with a log.
- pawchive: login untested (no account); post files, thumbnails, sidebar
  pills untested on device.
- r26 itself: single-fetch of post pictures, pre-r24 session migration,
  the pawchive swap-row label — all unverified on device.
- Device verification of r19–r25 as a whole was never confirmed by the user
  item by item; the parity artifact marks what is verified.
- Task #14 in the session's task list ("6 new doujin sources with full
  parity") is effectively done except the open items above.

---

# PART B — chronological build log (history, verbatim)

Everything below was written build by build from 2026-07 to 2026-08-29 and
is kept as it was. Where it contradicts Part A (branch name, build command,
version), Part A is current.

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

## Build `ua-parity` (2026-08-14)

### The invariant: ONE User-Agent for the whole app
The captcha WebView signs in with `Tools.browserUserAgent`, and
Cloudflare-style clearance cookies are bound to (IP + User-Agent). If the
app's HTTP requests use a DIFFERENT UA from the one that solved the captcha,
the cookie is rejected — loosely tolerated on a trusted home-wifi IP, firmly
refused on a rotating mobile-data (CGNAT) IP. This is already documented on
`Tools.deviceWebViewUserAgent`; it is why the old fake `LoliSnatcher_Droid/x.y`
UA "only worked on wifi".

The `thumb-fix` build broke that invariant for rule34.us by hardcoding
`Constants.defaultDesktopBrowserUserAgent` in `R34USHandler.getHeaders()` to
force the desktop layout. Reverted. **Never send a UA other than
`Tools.browserUserAgent` from a handler** (sankaku's app UAs are the
deliberate exception — a private API with no captcha/webview flow).

### rule34.us now parses BOTH layouts instead of forcing one
- grid: `data-src` accepted alongside `src` (mobile lazy-loads), selection via
  `querySelector` rather than raw node walking;
- post media: `.content_push > img|video` (desktop) else the first `<img>`
  whose src matches `rule34\.us/(images|videos)/` or the bare `<video>`
  (mobile puts media directly in `.container`); mp4 `<source>` preferred over
  first-child order;
- tags: **the desktop id is `"tag-list "` WITH A TRAILING SPACE**, so
  `getElementById('tag-list')` has always returned null and desktop posts
  never got tag types at all. Now selected by `.tag-list-left`. The mobile
  layout has no sidebar — one `<a class="card-light">` per tag with an empty
  type div as a child and the underscored name in the href `q=` param — and
  gets its own branch.
Verified against saved desktop + mobile image and video post pages: media OK
on all three, desktop tags 1 artist / 1 copyright / 44 general / 4 meta,
mobile equivalent.

### rule34hentai.net captcha on mobile data — NOT reproduced, NOT fixed
Nothing in this session touched `dio_network.dart`, the cookie layer,
`Tools.browserUserAgent`, or `r34hentai_handler.dart` (which does not
override `getHeaders`, so it uses the shared UA). The r34us UA divergence
above was the only UA change and it is a different site. The remaining
mechanism is IP reputation: mobile-data CGNAT addresses are shared and
frequently poisoned, and the app cannot influence which IP the carrier gives
you. If it recurs, the thing to capture is whether the app request that fails
carries the same `cf_clearance`/`shm_session` cookie AND the same UA as the
webview that solved it.

## Build `cookie-merge` (2026-08-16)

### rule34hentai.net "captcha only passes on wifi" — ROOT CAUSE FOUND
From the user's talker log (Samsung S24 Ultra, mobile data):
  - the login POST to `/user_admin/login` SUCCEEDS — 302 with
    `Set-Cookie: shm_user` + `shm_session`, and the handler does capture them
    from the DioException path, so login was never the problem;
  - every subsequent `GET /post/list/...` returns **403 with Cloudflare's
    "Just a moment..." interstitial**;
  - the outgoing `Cookie` header is **6255 bytes with `cf_clearance` sent
    TWICE** and most other cookies four times over.

Cause: cookie headers were assembled by STRING CONCATENATION from two
sources that each already contained the whole jar —
`BooruHandler.getCookies()` (and the identical
`GelbooruAlikesHandler.getCookiesForPost()`) did
`cookieString += headers['Cookie']!`, where `getHeaders()` had already been
filled by `Tools.getFileCustomHeaders()` -> `Tools.getCookies()`. On top of
that `Tools.getCookies()` itself emitted every entry the WebView jar held,
and that jar can hold one name twice (host vs domain scope, and Cloudflare
rotating `cf_clearance` -> `cf_clearance_old`).

A repeated `cf_clearance` reads as cookie replay/tampering to Cloudflare, so
the request gets challenged. On a trusted home-wifi IP that is often waved
through; on a CGNAT mobile-data IP it is not — which is precisely the
"works on wifi, never on data" shape, and why clearing cookies used to
"fix" it (a freshly emptied jar has nothing to duplicate yet).

Fix: `Tools.parseCookieString` / `buildCookieString` / `mergeCookieStrings`.
`Tools.getCookies` now builds through a map so the jar cannot yield the same
name twice, and both handlers MERGE (last value wins) instead of
concatenating. Verified on the exact header from the log: 6255 -> 2192 bytes,
`cf_clearance` 2 -> 1, zero duplicate names.

CAVEAT: that duplicated clearance cookie is a very strong suspect for the
403, but Cloudflare's decision is opaque and IP reputation is also in play —
this is not proven causation. If it still challenges on data, the next thing
to check is whether the 403 persists with a *single* clean cookie set.

Related, NOT changed: the login POST 302 is thrown by Dio's validateStatus
and only works because the handler reads `set-cookie` off the exception.
Fragile but functional; left alone deliberately.

## Build `clean-cookie` (2026-08-16)

`cookie-merge` fixed the WRONG LAYER. The duplication was never in the
handlers — it is in the Dio interceptor pipeline in `dio_network.dart`, so
the previous build changed nothing and the user's second log was identical
(7979 bytes, cf_clearance twice, everything else four times).

Three concatenation sites, all now `Tools.mergeCookieStrings`:
1. `cookieInterceptor.onRequest` — `'$oldCookie $newCookie'`. Runs on EVERY
   request; `oldCookie` already came from `Tools.getFileCustomHeaders` (full
   jar) and `newCookie` re-reads the same jar, so the header was doubled
   before anything else touched it.
2. `onResponse` captcha retry — same concatenation, doubling it again.
3. `onError` captcha retry — likewise. Hence 4x after a retry.

Second, independent bug at all three: the join was a bare SPACE, not `'; '`.
Cookie pairs must be `; `-separated, so the header was genuinely malformed —
16 boundaries like `...h0 _ga=` in the log.

Third: `oldCookie.replaceAll('cf_clearance', 'cf_clearance_old')` renames by
SUBSTRING, so an existing `cf_clearance_old` becomes `cf_clearance_old_old`
on the next pass. Now renamed by KEY after parsing.

Verified by replaying the log's own worst header through the real pipeline:
7979 -> 2608 bytes, cf_clearance 2 -> 1, zero duplicate names, zero
space-joined boundaries, and STABLE across the captcha retry instead of
growing.

STILL NOT PROVEN to be the cause of the 403. Cloudflare's decision is opaque
and carrier IP reputation remains a factor. What is certain is that the app
was sending a malformed, duplicated, multi-KB cookie header on every request,
which no browser would ever do.

## Build `drive-backup` (2026-08-16)

Google Drive as a backup target, alongside the existing folder backup.

`lib/src/services/drive_backup.dart` + a section in `backup_restore_page.dart`.

### Credentials are NOT compiled in — on purpose
The OAuth client id/secret are entered once by the user and kept in
`FlutterSecureStorage` (`SecureStorageKey.driveClientId/driveClientSecret/
driveRefreshToken`). A client secret committed to a public GitHub repo is
detected and auto-revoked by Google, and it would be a shared secret across
every install of the build. The user already has a Desktop-app client (the
one the build uploader uses) and can paste that.

### Flow
Installed-application loopback, which is what Google mandates for native
clients:
  1. `HttpServer.bind(loopbackIPv4, 0)` — OS-assigned port;
  2. consent screen opened in the SYSTEM BROWSER via url_launcher. It cannot
     be the app's own webview: Google rejects OAuth in embedded webviews with
     `disallowed_useragent`;
  3. browser redirects to `http://127.0.0.1:<port>/?code=…`, the local server
     answers with a small "you can close this" page;
  4. code -> refresh token, only the refresh token is persisted.
`access_type=offline` AND `prompt=consent` are both required — without the
latter Google omits the refresh token on every authorisation after the first,
so linking would appear to work once and never again.

Scope is `drive.file`, so the app can only see files it created itself.

### Storage
Uploads settings.json, boorus.json and store.db into a `LoliSnatcher` folder,
replacing the previous copies (looked up by name within the folder). Resumable
upload rather than simple: store.db runs to tens of MB, which is past what one
request should carry on a phone connection, and it gives real progress. The
restore order matches the folder restore — settings, boorus, then database
last, since the database triggers the restart.

NOT DONE / NOT TESTED FROM HERE: no device test of the OAuth round trip. The
loopback listener needs the browser and the app on the same device (true on
Android). No automatic/scheduled backup — it is manual, same as the folder
one. tags.json is not included (the DB already carries the tags when the
database is enabled).

## Build `kusowanka` (2026-08-16)

New source: **kusowanka.com** (`BooruType.Kusowanka`,
`lib/src/boorus/kusowanka_handler.dart`). Bespoke PHP site, not a booru
engine, and its tag model drives every decision in the handler.

### Tags: FIVE namespaces, ids in the grid, names only on the post page
`tags | parodies | artists | characters | metadatas`, each with its own id
space and browse route, mapping onto general/copyright/artist/character/meta.

The grid exposes ONLY numeric ids:
`<div class="box_thumb" data-tags="1 11 16 …" data-artists="548284" …>`

Those numbers mean nothing outside this site, so they are deliberately NOT
emitted as tags — writing `1988` into the shared tag store would poison
colouring, the tag browser, cross-booru translation and For You seeds with
tokens that can never match anything. Grid items therefore carry NO tags and
are marked `needToLoadItem`; `loadItem` reads the post page, which spells
names out with their namespace
(`<button type="artist" data_id="548284" name="chun jian he">`) and produces
properly typed tags.
**Consequence: the tag blacklist cannot act on this booru until a post is
opened.** Emitting placeholder tags would be worse — it would filter wrongly.

### Search: the form does NOT work, the slug routes do
`/search/?qt_key=<id>,` accepts ids and ignores them. Caught by verifying
that returned posts actually carry the requested id: `qt_key=30` -> 55 posts,
0 matching; `qt_key=1` "matched" 41/55 only because `1girl` is on most posts.
It presumably needs the site's session/CSRF dance. `&submit=Filter` does not
help.

`/tag/{slug}/`, `/artist/{slug}/`, `/character/{slug}/`, `/parody/{slug}/`,
`/metadata/{slug}/` (+`?page=N`) all work, verified the same way — 100% of
returned posts carry the requested id on every route tested.

ONE facet only: `/tag/1girl+solo/`, `/tag/1girl/solo/` and `/tag/1girl,solo/`
all 404. A multi-term query is refused with an explanatory error rather than
silently searching just the first word.

Query grammar: bare word = tag; `artist:` `character:` `parody:` `metadata:`.
The prefix is matched against the WHOLE query before splitting on spaces —
`artist:chun jian he` is one three-word name, and splitting first rejected
every multi-word name (caught in simulation).

### Media
Grid `data-bg` is the thumb; `thumbs/` -> `samples/` gives the preview
(same directory tree and hash, verified). Full size follows the site's own
viewer: strip the sample's extension, `samples` -> `original`, append
`data-type` (the real extension, also the media type). `/images/` 404s.

### Autocomplete
`/inc/search.php?type=<tags|parodies|artists|characters|metadatas>&name=<q>`
-> `[{id,name}]`. All five are queried in parallel and returned as typed,
prefixed suggestions. Site's own minimum is 3 characters; honoured.

### Verified live
Routing + 2-page pagination for empty / `1girl` / `artist:` / `character:` /
`parody:` / `metadata:animated`; every route's posts verified to carry the
requested id; thumb, sample and original all return 200; post page yields
2 copyright / 1 character / 1 artist / 3 meta / 46 general typed names.

KNOWN QUIRK: the FRONT page (empty query) repeats heavily across pages
(~50/56 overlap p1 vs p2); the app's existing duplicate filter absorbs it, so
it shows as fewer new items per page rather than duplicates. Tag routes
paginate correctly. Not autodetectable — fixed host, like tik.porn/xxxtik.
NOT device-tested from here.

## Build `hanime1` (2026-08-17)

New source: **hanime1.me** (`BooruType.Hanime1`,
`lib/src/boorus/hanime1_handler.dart`) — a Chinese-language hentai video
site, presented in English via a built-in dictionary.

### The translation approach
The site's `/search` form enumerates its ENTIRE tag vocabulary: 240 tags in
7 groups, 9 genres, 7 sort orders. A fixed vocabulary means no translation
service is needed for tags — `lib/src/data/hanime_dictionary.dart` is a
complete hand-translated zh<->en map (`HanimeTag{zh,en,type}`):
  - display: watch-page zh tags -> EN tokens at parse time (unknown zh tags
    pass through visibly rather than being dropped);
  - search: EN tokens -> exact zh strings in `tags[]` (raw zh also accepted);
  - autocomplete: local dictionary filter matching BOTH languages.
影片屬性 group -> TagType.meta, all else general; artist -> `artist:` typed.
Titles/artist names are FREE TEXT — dictionary can't cover them. Original is
kept; an English line is added best-effort via the keyless
`translate.googleapis.com/translate_a/single?client=gtx` endpoint (cached
per title incl. misses, never blocks the post; note: unofficial endpoint).

### Site behaviour (verified live via hanime1.com — .me Cloudflare-blocks
### datacenter IPs, SAME site, so the handler uses booru.baseURL)
- `GET /search`: `query=` free text, `genre=`, repeated `tags[]=` (AND;
  `broad=on` = OR -> exposed as `mode:any`), `sort=`, `page=` (1-based).
- Sorts (all verified to change results): 最新上市 newest / 最新上傳
  latest_upload / 本日排行 daily / 本週排行 weekly / 本月排行 monthly /
  觀看次數 views / 他們在看 trending.
- Genres (verified): 裏番 hentai / 泡麵番 shorts / Motion Anime / 3DCG /
  2.5D / 2D動畫 2d / AI生成 ai / MMD / Cosplay.
- TWO grid layouts chosen per genre: horizontal `video-item-container`
  (title attr + img.main-thumb) for most queries, vertical
  `home-rows-videos-div` (link WRAPS card, `.home-rows-videos-title`) for
  裏番 pages. Both parsed; sponsor cards (same markup, outbound links)
  skipped by requiring `watch?v=`.
- Watch page: `<video id=player>` with up to three mp4 `<source size=…>`
  (480/720/1080, signed EXPIRING urls — highest wins), poster, tags as
  `search?tags[]=` links, `#video-artist-name`, `觀看次數：N萬次 date`
  (萬 = x10000 -> score), `.video-caption-text` -> description.
- Grid has NO tags -> needToLoadItem + loadItem pattern.

### Verified end to end
creampie / +chinese_subtitles / mode:any / genre:hentai sort:views /
artist:ADLER / free text "love live" / tentacles genre:3dcg — all with
2-page pagination, zero overlap; loadItem yields 1080p mp4 (206 reachable) +
15 typed tags + artist + views/date; gtx translation returns correct EN.

NOT DONE: no device test. The `?secure=` URLs expire — snatching must happen
reasonably soon after load (same caveat as tik.porn). H漫畫/新番預告/無碼18禁遊
sections are not genres and are NOT covered. Not autodetectable.

## Build `hanime1-fix` (2026-08-26)

hanime1.me "doesn't load" — user's log showed every request answered with
Cloudflare's HARD block page ("Sorry, you have been blocked", no captcha to
solve) from their RESIDENTIAL IP, which browses the site fine in Chrome. So
the block keys on the client, not the address: .me's WAF rejects non-browser
TLS fingerprints (Dart's HttpClient), which no header change can disguise
and the captcha webview cannot fix (nothing to solve on that page).

Two fixes:

1. **Global: `DioNetwork.separateUrlAndQueryParams` produced malformed URLs
   for EVERY handler.** `Uri.replace(queryParameters: {})` leaves a dangling
   `?`, and Dio appends its own params after it, so every request went out
   as `path?&a=b` (visible verbatim in the user's log:
   `search?&query=&page=1`). Most servers tolerate it; Cloudflare documents
   "malformed data" as a block trigger. The dangling `?` is now stripped.
   App-wide change, but strictly makes URLs MORE correct.

2. **Hanime1Handler: automatic .me <-> .com domain fallback.** hanime1.com
   serves the identical site but its Cloudflare config accepted plain HTTP
   clients in every test (from an IP that .me hard-blocks). On a response
   that is 403 + `cf-error-details`, the same request is retried on the
   other domain; success is remembered in a session-static `_workingHost`
   that `_base` applies, so subsequent searches/loadItems go straight to
   the working domain. Applied in fetchSearch and loadItem.

CAVEAT: not verified from the user's network — the .com domain's laxer WAF
is an observation from this container's (datacenter) IP. If .com ever gets
the same strict rules, the remaining option is routing this site's requests
through the WebView (real browser TLS), which is a much bigger change.

## Build `hanime1-tags` (2026-08-26)

hanime1 "now it loads but the tags dont". The domain fallback and the URL fix
from `hanime1-fix` both worked (log shows the .me 403, the .com retry, and 8
successful `watch?v=` fetches). The failure was one line inside `loadItem`.

**Root cause: `Uri.decodeQueryComponent` throws on raw non-ASCII input.**
Not just on a malformed `%` sequence — on ANY unencoded byte >= 128. hanime1
writes its tag links with literal UTF-8 in the query string
(`/search?tags%5B%5D=同人作品`, verified in the served HTML), so the decode
threw `Illegal argument(s): Illegal percent encoding in URI` on the FIRST
Chinese tag of every item. The outer `try/catch` turned that into
`failed: true`, so the item got no tags at all — only pure-ASCII tags like
`1080p` ever survived, and they were discarded with the rest. Reproduced on
all 15 watch pages from the user's log; the log's own stack trace points at
`hanime1_handler.dart:350`, exactly the decode call.

Fix: `_decodeParam` decodes only values that actually contain `%`, and
swallows a malformed one back to the raw string. Never throws.

**Also found while verifying: the `#` tags were being dropped entirely.**
The tag strip carries two link shapes, both inside `div.single-video-tag`:

    /search?tags[]=<zh>   the site's 240 attribute tags  -> dictionary
    /search?query=<zh>    `#`-prefixed work + characters -> was ignored

The old code only looked for `tags[]`, so the source work and character names
— the most useful tags on the site — never reached the app. Both shapes are
now read, and the loop is scoped to the strip instead of scanning the whole
document for `tags[]` anchors.

Typing the `query=` tags: the DOM does NOT distinguish work from character
(identical markup, identical `#` span). Verified across the 15 pages that the
site lists the work first and its characters after, so the first entry is the
franchise (copyright) and later ones are characters — with one refinement,
that a later entry which extends the first is a sub-series, not a character
(偶像大師 -> 偶像大師 閃耀色彩). That rule is correct on all 29 named tags in
the sample (Arknights/Yvonne, Genshin/Citlali, Honkai:Star Rail/Silver Wolf,
LoL/Ahri, Blue Archive, ZZZ with two characters, ...).

These stay in CHINESE deliberately, unlike the attribute tags. They are proper
nouns, and the site searches them via free-text `query=`; a machine-translated
character name would find nothing when tapped. Searchable beats readable —
the title already carries an `EN:` translation line. Spaces become underscores
so a tag does not split in two; `_parse` already turns them back into spaces.

## Build `doujin` (2026-08-27) — doujin reading system + nhentai.net

New branch `claude/experimental-doujin` (from megabuild head). First DOUJIN
source: galleries of ordered pages with a real reader, not single files.

### nhentai API research (all verified live from this container)
The old unofficial endpoints (`/api/galleries/...`) are DEAD — they answer
403 "Use new API https://nhentai.net/api/v2/docs". The v2 API is an official,
OpenAPI-documented REST API:

  * auth OPTIONAL: `Authorization: Key <api key>` (user generates at
    nhentai.net/user/settings#apikeys). EVERY read endpoint worked without
    auth from this container: search, galleries, gallery detail, related,
    tagged, popular, tags. A key adds favorites (GET/POST/DELETE
    /api/v2/galleries/{id}/favorite) and blacklist flags. Full login
    (/auth/login) needs PoW + captcha — not worth it; key covers everything.
  * `GET /api/v2/search?query&sort&page` — 25/page, `num_pages` for paging,
    full site search syntax passes through the query param verbatim
    (verified: `tag:"school swimsuit" language:english`, `pages:>100`,
    `artist:shindol`, `-tag:x` exclusions).
    sort: date|popular|popular-today|popular-week|popular-month.
  * `GET /api/v2/galleries?page` — newest feed (empty-query default).
  * `GET /api/v2/galleries/{id}?include=related,comments` — ONE call returns
    the whole book: pages[] (path, width, height, per-page thumbnail), typed
    tags (tag/artist/parody/character/group/language/category), title
    (english/japanese/pretty), related[5], comments. Works keyless.
  * `GET /api/v2/cdn` (open) → image_servers i1-i4.nhentai.net, thumb_servers
    t1-t4.nhentai.net. Image = `{server}/{path}` verbatim. COVERS ARE ON THE
    T-SERVERS ONLY (i-server 404s cover paths).
  * `POST /api/v2/tags/search {query,limit}` (open) — typed autocomplete
    with counts.
  * List items carry `tag_ids` (ints), not names → resolved via open
    `GET /api/v2/tags/ids?ids=csv`, session-cached.
  * Cloudflare: HTML pages are challenge-gated, but /api/v2/* and the image
    CDNs answered plainly, browser UA or custom. UA: Tools.browserUserAgent
    (one-UA invariant) — verified accepted. CAVEAT: like hanime1, the user's
    residential IP may still get challenged where this container is not; the
    captcha webview + cookie path stays available.

### Design
One gallery = ONE BooruItem in the grid (cover-backed; fileCountHint =
num_pages so the grid badge shows immediately). loadItem upgrades it (page-1
full image as fileURL, typed tags, title EN/JP in description) and caches the
page list. A new READER opens the ordered pages on top of the viewer.

  * `ReaderHandler` (new): session cache postURL -> List<BooruItem> pages +
    persistent per-gallery progress in new DB table ReaderProgress
    (booru, galleryId, page, totalPages, updatedAt; memory fallback when DB
    off). Handlers push pages in from loadItem; UI asks it.
  * `DoujinReaderPage` (new): PreloadPageView of ImageViewer pages (same
    zoom/media-cache pipeline as the main viewer; preloadCount from
    settings), registered as a nested viewer via ViewerHandler like
    PostFilesPage. RTL toggle (reverse:), page slider, resume to saved page,
    progress written on every turn. Menu: save this page / save all pages
    (pages are real BooruItems -> existing SnatchHandler.queue unchanged).
  * Entry points: viewer toolbar action "Read · N pages" (replaces the
    burst-carousel action for reader handlers), "Read"/"Continue p.X" row in
    the item drawer.
  * Related: nhentai's native related endpoint is exposed as a QUERY —
    `related:<id>` in makeURL — so the existing TagContentPreview strip
    machinery serves a "More like this" strip in the drawer with zero new
    strip code, and the query is even typeable by hand.
  * Recommended: sort:popular[-today|-week|-month] metatags; typed
    artist/parody/character tags feed the existing SuggestionEngine strips
    automatically.
  * Comments: getComments via gallery?include=comments (works keyless).

## Build `doujin-ux` (2026-08-27)

User sent a 43s recording of a reference app (browser-tab style multi-source
doujin reader: nhentai/asmhentai/hitomi.la) and picked "Doujin detail UX"
from the adoption options. Changes, all scoped to reader-handler sources:

1. **Native namespace tag sections.** New BooruHandler API:
   `tagNamespace(tag)` + `tagNamespaceSections` (ordered key/label pairs).
   NhentaiHandler records every API tag's site namespace + count in a static
   `_tagSiteInfo` (fed from /tags/ids, gallery detail, and autocomplete).
   tag_view's `tagChipSectionSlivers` now sections by native namespace
   (Parodies / Characters / Artists / Groups / Categories / Languages /
   Tags) when the handler provides them; section tuple generalized from
   `(TagType?, List<Tag>)` to `(String? label, Color? color, List<Tag>)` —
   the TagType path still works for every other booru. Chip colours still
   follow TagType.
2. **Counts on chips.** `buildTagChip` ALREADY rendered `Tag.count` (dead
   data until now) — nhentai populates it, so chips read
   "big breasts 231k" like the reference.
3. **Book header.** The old "Read · N pages" ListTile is replaced by
   `_doujinBookHeader`: an info line (languages · category · N pages ·
   ♥ favs, from the namespaces) + a full-width FilledButton that reads
   "Read · N pages" or "Continue reading · page X of N".
4. **Pages grid.** `_pagesGridSlivers` after the tag sections: 3-column grid
   of every page's own thumbnail (per-page thumbs come with the nhentai
   detail response) with page-number badges; tapping opens the reader AT
   that page (`openDoujinReader(startAt:)` skips saved progress).

Reference features NOT adopted yet (user chose detail UX only): vertical/
webtoon reading modes, tap zones, keep-screen-on, nhentai account
favourites/blacklist sync, per-source settings overrides layer.

## Build `doujin-fix` (2026-08-28)

User's 5-min recording of the doujin-ux build + a list. THE READER WAS BLACK
ON EVERY PAGE (title bar + slider fine, images never appeared) while the
MAIN viewer rendered the very same i-server URL fine — so the failure was in
the reader's widget wiring, not the network. Root cause could not be pinned
statically (ImageViewer is welded to gallery machinery: hero tags,
viewer-handler state, notes, tiling — and renders black with no error
surface).

1. **Reader rebuilt on a self-contained image path.** _ReaderPageSlide =
   PhotoView over CustomNetworkImage (same provider the thumbnails use,
   same headers via Tools.getFileCustomHeaders, media cache on). Explicit
   per-page loading progress, and failures print URL + error ON the page
   with a Retry button — a broken page is now diagnosable from a
   screenshot. Reader open + every page failure also goes to the talker
   log. Wrapped in PhotoViewGestureDetectorScope(axis: Axis.values) exactly
   like the main viewer so zoom-pan vs page-swipe negotiate.
2. **Reader features**: tap zones (edges turn pages, middle toggles the
   chrome — via PhotoView's own onTapUp, no competing recognizers),
   reading direction now cycles LTR -> RTL -> VERTICAL (paged) and the
   choice persists per source, instant vs animated turns, keep-screen-on
   via ServiceHandler.disableSleep.
3. **Per-source settings** (reference's "<source> settings" screen):
   SourceSettingsHandler persists sourceSettings.json keyed by host;
   SourceSettingsPage reachable from booru edit ("Source settings").
   Reading direction / page-turn animation / tap zones / preload pages /
   keep screen on / default sort (applied in makeURL when the query has no
   sort:) / grid tag strip toggle.
4. **Grid cards (doujin sources)**: language badge top-right (EN/JP/CH/KR
   from the language namespace, 'translated' ignored); bottom gradient
   strip with the 5 most relevant tags (favourited/marked first in GOLD,
   rest by site count); a +N button that opens a bottom sheet with ALL tags
   grouped by native namespace — tags visible without opening the doujin,
   tapping one in the sheet opens a background tab.
5. **Drawer**: "More like this" renamed Recommended and OPEN BY DEFAULT;
   new "Related — chapters & versions" (collapsed): a `versions:<id>` query
   that quoted-phrase-searches the gallery's base pretty title
   (_versionsBaseTitle strips trailing ~subtitles~, brackets, volume
   markers; "Mesu no Ie III ~...~" -> "Mesu no Ie" = 16 live hits covering
   all chapters + languages).

NOT done from the user's list: webtoon CONTINUOUS scroll (vertical paged
shipped instead), account favourites/blacklist sync. If pages are STILL
black in this build, the on-page error text + talker log now say exactly
why — ask for either.

## Build `reader-r1` (2026-08-29) — item 1 of the 7-item batch

Reader STILL broken in the field (3rd recording): pages render now, but the
slider floats at EXACTLY 50% height over the image, the top-bar buttons are
dead, and taps land on the floating slider (scrubbing) instead of turning
pages. The image fills the whole screen even though the chrome is misplaced.

Diagnosis (code-traced; the exact half-height trigger could not be
reproduced in this container, so the fix removes the MECHANISM CLASS):
- the old route was PageRouteBuilder(opaque: false) with a Scaffold using
  appBar/bottomNavigationBar/extendBody slots — Scaffold slot placement is
  what floated the bar; the transparent route kept the gallery + open info
  sheet (extent 0.5 — matching the 50% bar position exactly) live below;
- PhotoView UNCLIPPED paints AND HIT-TESTS beyond its bounds — that is both
  the full-screen image over a misplaced layout and the dead top buttons
  (taps fell into PhotoView's oversized gesture surface).

The rebuilt page (doujin_reader_page.dart) has a written layout contract:
opaque MaterialPageRoute (same type the comments page uses from the same
drawer, known-good); NO Scaffold slots — a Stack with Positioned(top:0) /
Positioned(bottom:0) chrome; resizeToAvoidBottomInset:false; ClipRect around
the page view AND around each PhotoView; tap zones on their own transparent
layer (single-tap only) above the pages and below the chrome, so they work
even while a page is loading/failed and can't fight PhotoView's
pinch/pan/double-tap or the PageView's swipes.

test/doujin_reader_test.dart pins the class: slider DOCKED at the bottom
(and stays docked under a 250px bottom view inset), edge taps turn pages
both directions, middle tap toggles chrome, direction/menu/close buttons
all fire, slider scrubs. 6/6 pass; the 10 pre-existing booru_test failures
are live-site probes and fail identically on the previous commit.

## Builds `reader-r1` … `doujin-item7` (2026-08-29) — the 7-item batch

User sent a strict, ordered 7-item work list with per-item builds. All on
claude/experimental-doujin, one commit+build+Drive upload per item:

1. `reader-r1` — reader rebuilt against a written layout contract (opaque
   MaterialPageRoute, Stack chrome, ClipRects, raw-pointer tap zones,
   InteractiveViewer instead of photo_view whose fork force-registers a
   double-tap recognizer). 8 widget tests in test/doujin_reader_test.dart.
   Adversarial subagent review confirmed no surviving path to the recorded
   symptoms and surfaced the double-tap steal + re-entrancy + keepScreenOn
   + bar-gap issues, all fixed. DEVICE VERIFICATION IMPOSSIBLE in this
   container — flagged to user, tests + review are the evidence.
2. `doujin-item2` — DoujinDetailPage on card tap (viewer untouched
   elsewhere); BookmarkHandler (bookmarks.json, local-only).
3. `doujin-item3` — card = cover + tag strip BELOW; coverDisplay
   fit/crop/adapt (adapt routes through the staggered grid; nhentai now
   hasSizeData=true); staggered cells reserve footer height.
4. `doujin-item4` — versions: self-heals via detail-endpoint bounce (the
   silent firehose degrade WAS the "Related returns unrelated stuff" bug);
   recommend:<id> engine (related seeds + artist + distinctive-tag
   searches, overlap-scored, versions excluded, count setting);
   showDoujinItemSheet long-press menu on strip cards.
5. `doujin-item5` — hasSiteFavourites/setSiteFavourite (POST/DELETE
   /api/v2/galleries/{id}/favorite, Key auth), sync-state line on the
   detail page, favorites:me feed, DioNetwork.delete added. NOT verified
   with a real key (user's key unavailable here) — code-vs-spec only.
6. `doujin-item6` — Settings root DOUJIN section; SourceSettingsHandler
   gained a GLOBAL layer ('_global' in sourceSettings.json), effective =
   source ?? global ?? default; per-source page shows "Overridden for this
   source · tap to reset"; new working settings: language filter, tag
   blacklist (merged layers, -tag:"x" per search), title language, feed
   columns override (grid+staggered builders), page-preview columns (both
   Pages grids). Webtoon/wifi-only/rec-thumb-size deliberately NOT offered.
7. `doujin-item7` — drawer block on doujin sources (favourites & bookmarks
   page, favourite tags, one-tap source settings); id:<n> single-gallery
   query (bookmarks reopen through it).
