# Dead code: what token 151 removed and kept (2026-10-11)

The `deadCode` lists in this folder's JSON files were written against the pre-M1 paths
(`lib/src/...`). Each entry was re-checked on the 1.0 tree (e98e54b0 + the layer cleanup):
every name grepped over lib/ and test/, the definition read, and the analyzer run after each
group. Removed only when nothing in lib/ or test/ calls it.

## Removed

| Map | What | Where now |
|---|---|---|
| doujin | `SchaleNetwork.byKey` | sources/doujin/schale/schale_network.dart |
| doujin | `SchaleHandler.namespaceCodes` (public getter; the private map stays) | sources/doujin/schale/schale_handler.dart |
| doujin | `SchaleClearanceHandler.obtain`, `.issuedTrace` getter | sources/doujin/schale/schale_clearance_handler.dart |
| doujin | `EHentaiSessionHandler.savedAt`, `EaHentaiSessionHandler.savedAt` getters (the saved value stays) | sources/doujin/{ehentai,eahentai}/ |
| doujin | `NHentaiTagCatalog.queued` | sources/doujin/nhentai/nhentai_tag_catalog.dart |
| feed | `TabBackup.copyWith`, `SearchHandler.reset()` | features/feed/logic/search_handler/ |
| feed | `scrollStream`, `_scrollStream`, `scrollOffset`, `searchBoxFocus`, `lastBackupTime` | features/feed/logic/search_handler*.dart |
| persistence | DioDownloader isolate paths: `start`, `writeToCache`, `readFileFromCache`, `readBytesFromCache`, `runRequestIsolate`, `runRequestDownload`, `IsolateCacheConfig`, and the `isolate`/`receivePort` fields only they used | core/network/dio_downloader.dart |
| persistence | ImageWriterIsolate: everything except `getCacheStat` (used by Save & cache) | features/downloads/logic/image_writer_isolate.dart |
| persistence | `ImageWriter.getCacheStat` | features/downloads/logic/image_writer.dart |
| persistence | `SnatchHandler.writeMultipleFake` | features/downloads/logic/snatch_handler.dart |
| persistence | `removeTabRestore`, `getSearchHistoryByInput`, `updatePinnedTagOrder` | core/storage/database_handler/ |
| persistence | `SourceCaptureHandler.buildJson` | features/debug/logic/source_capture_handler.dart |
| settings | `enumSettingEntry`, `SettingsEnumRegistry.getFromString` | models/settings/settings_enum.dart |
| settings | `DirPicker` (file), `SettingsTemplate` (file) | features/settings/ui/ |
| settings | `containsHidden`, `currentColumnCount`, the empty legacy-keys loop, `_SaveCachePageState.setPath` | core/settings/, features/settings/ui/save_cache_page.dart |
| shell | `ScrollingText`, `DesktopTabs`, `ThemeBuilder`, `ActiveTitle` (files) | core/ui/text, app/shells/desktop, app/theme, app |
| shell | `SavedSearchesDrawerSection` | app/drawers/main_drawer.dart |
| shell | `CustomPredictiveBackFullscreenPageTransitionsBuilder` + its private page transition | core/ui/predictive_back_transition.dart |
| shell | `_ArrowCustomPainter` | core/ui/custom_scroll_bar_thumb.dart |
| shell | ServiceHandler `getFilesByExt`, `getDocumentsDir`, `emptyCache`, `makeVidThumb`, `getCurrentAlias`, `getAvailableAliases` (Dart side; the native handlers are untouched) | core/platform/service_handler.dart |
| shell | `SecureStorageHandler.contains`, `ThemeHandler.getTheme`, `OverlayScreen.removeAll`, `KaomojiData.getAll`/`count` | core/, app/overlays |
| sources | `R34HentaiHandlerOld`, Gelbooru `parseCommentsListOld`/`parseCommentOld`, worldxyz top-level `a` | sources/booru/ |
| sources | KemonoApi `site`/`api`/`img` and the kemono-only URL wrappers (`fileUrl` stays: tests); KemonoSessionHandler `site`/`api` | sources/kemono/ |
| sources | `SegmentBuilderRegistry`, `SegmentBuilderFn`, `defaultSegmentBuilder`; `CommentParser.createMinimal`/`createCustom` | core/utils/text_parser/ |
| sources | `Debounce.fire`, `Debounce.cancelAllStartingWith`; `StringExtras.temploc`, `BoolExtras` | core/utils/ |
| tabs_drawers | DDContent/DDCombinedList, DDControlPanel, DDQueueControls, DDActiveItem, DDQueuedItem, DDRetryableItem/RetryableItemType, DDEmptyState (7 files), DDNavigationButtons | features/downloads/ui/drawer/ |
| tabs_drawers | `jumpToTop`, tags manager `saveTags`, `TagsManagerListItemDialog.onDelete` (and its commented-out tile) | features/tabs/ui, features/tags/ui/manager |
| tags_ml | `tagRelevanceWeight`, `TagIndexSource.orderedByCount` (+7 overrides), `BooruTagStore.namespaceCounts`/`manualCount` | features/recommender/logic, sources/framework/tags, core/storage |
| viewer | interactive_viewer.dart, unknown_viewer_placeholder.dart (files) | features/viewer/ui, features/video/ui |
| viewer | TagView `sourcesList`, `infoText`, `detailsExpanded`, SourceLinkErrorDialog (part file) | features/viewer/ui/info/ |
| viewer | `formatDurationShorter` | features/video/ui/loli_controls.dart |

## Kept, and why

| Map | What | Why |
|---|---|---|
| doujin | `resetDomainsForTests`, `effectiveAspect`, `namespacedTagsOf`, `pageKeysFromHtml` | used by tests (and `namespacedTagsOf` by lib now) |
| feed | thumbnail `onTap: false && ...` | parked feature ("reenable after filters rework") |
| persistence | `NotifyHandler` | snatch_handler and a test use it now |
| persistence | `getTrackedValues`, `countEmbeddings`, `closeVectors`, `vectorFileBytes` | test seams |
| settings | AppMode selector inside `if (false)` | parked feature ("until we rework desktop ui") |
| shell | `LoadItemViewer` branch in desktop_image_listener | desktop shell is off; a test covers the listener |
| sources | `fetchFolders`, `fetchWatchlist` | the FurAffinity sidebar calls them now |
| sources | `ruffleScript`, `KemonoApi.fileUrl` | used by tests |
| sources | `MediaType.fromExtension` case `'loadItem'` | not every caller lowercases the extension, so not provably unreachable |
| tabs_drawers | `DownloadsDrawerController`, `DDSelectionActions` | the downloads drawer uses them now |
| tabs_drawers | `proxyDecorator` identity | removing it switches ReorderableListView to its default (elevated) drag proxy: visible change |
| tabs_drawers | TabSelector `countOnTop`/`withBorder`/`color`, TabRow `withColoredTags`/`fontWeight`/`isExpanded` | parameters with defaults; inlining them is a refactor, not dead code |
| tags_ml | `catalogPagesPerPull`, `pageAt`, `E621PoolSource`, `PhilomenaGallerySource` | used by tests |
| tags_ml | TagHandler `tryGetTagTypes` queue path, `tagFetchActive` | tied to the open queue bug; internal state |
| viewer | `ViewerTutorial` | mounted in the gallery; has a test |
| settings | `SettingDefinition` file | already gone before 151 |
