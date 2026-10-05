import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;
import 'package:get_it/get_it.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/sources/local/mergebooru_handler.dart';
import 'package:lolisnatcher/sources/booru/pools/pool_posts_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/suggestion_handler.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/saved_search.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_history_store.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/features/feed/logic/tab_backup_gate.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';

part 'search_handler/search_tab.dart';
part 'search_handler/tab_backup.dart';
part 'search_handler/tab_visit.dart';
part 'search_handler/search_enums.dart';
part 'search_handler/tabs.dart';
part 'search_handler/query.dart';
part 'search_handler/paging.dart';
part 'search_handler/reactions.dart';
part 'search_handler/seen_posts.dart';
part 'search_handler/saved_searches.dart';
part 'search_handler/tab_groups.dart';
part 'search_handler/backup_restore.dart';
part 'search_handler/visit_history.dart';

Uuid uuid = const Uuid();

EventChannel? volumeKeyChannel = Platform.isAndroid ? const EventChannel('com.noaisu.loliSnatcher/volume') : null;

class SearchHandler {
  SearchHandler() {
    _volumeStreamController = Platform.isAndroid ? StreamController.broadcast() : null;
    _scrollStream = StreamController.broadcast();
    _rootVolumeListener = volumeKeyChannel?.receiveBroadcastStream().listen((event) {
      _volumeStreamController?.sink.add(event);
    });
  }
  // alternative way to get instance of the controller
  // i.e. "SearchHandler.to.tabs" instead of "Get.find<SearchHandler>().tabs"
  static SearchHandler get instance => GetIt.instance<SearchHandler>();

  static SearchHandler register() {
    if (!GetIt.instance.isRegistered<SearchHandler>()) {
      GetIt.instance.registerSingleton(
        SearchHandler(),
        dispose: (searchHandler) => searchHandler.dispose(),
      );
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SearchHandler>();

  // search tabs list
  RxList<SearchTab> tabs = RxList<SearchTab>([]);

  /// The tab last removed while another tab was still open, and where it sat.
  /// One step. Closing the only tab resets that tab and clears this.
  SearchTab? _undoTab;
  int _undoIndex = 0;
  // current tab index
  RxInt index = 0.obs;
  RxnString tabId = RxnString(null);

  // History of tabs the user personally opened/viewed by tapping them
  // (tab manager, tab nav buttons, desktop tab bar). Tabs auto-created from
  // the tag view / preview strips are deliberately NOT recorded here — only
  // genuine user visits, flagged via changeTabIndex(byUser: true).
  final RxList<TabVisit> visitedTabsHistory = RxList<TabVisit>([]);
  static const int _maxVisitHistory = 150;

  // Sentinel for addTabByString's `group` param: inherit the current tab's
  // group. Used by tag-driven opens (tag chips, previews, batch open) so a
  // tab spawned from inside a group lands in the same group.
  static const Object inheritGroup = Object();

  // grid scroll controller
  AutoScrollController gridScrollController =
      AutoScrollController(); // will be overwritten on the first render because there is hasClients check
  RxDouble scrollOffset = 0.0.obs;
  // stream that will notify it's listeners about scroll events of the grid controller
  StreamController<ScrollNotification>? _scrollStream;

  // search box text controller
  final TextEditingController searchTextController = TextEditingController();

  // search box focus node
  FocusNode searchBoxFocus = FocusNode();

  final GlobalKey mainDrawerKey = GlobalKey();

  RxBool isRunningAutoSearch = false.obs;

  /// r76: a search the user typed, as opposed to a tab query that carries a
  /// post for its loader (`suggest: …`), which is neither history nor a
  /// search the learner should count.
  static bool isPlainSearch(String text) => !SuggestionHandler.isQuery(text);

  //

  final Map<SearchReaction, int> _reactionsCount = {};

  //

  //
  // Seen posts (already-viewed dimming). In-memory mirror of the SeenPost
  // table for O(1) lookups while building grid cells; the DB is the durable
  // copy. Keyed by postURL (globally unique because it carries the domain,
  // so it's merge-safe with no booru context needed).

  final Set<String> seenPostKeys = <String>{};

  //
  // Saved searches (quick-search favourites). Bookmarks the user's current
  // query (tags + booru + secondaries + per-booru overrides + inherit flags)
  // so they can re-open it later, optionally on a different booru.

  final RxList<SavedSearch> savedSearches = <SavedSearch>[].obs;

  // current page number
  RxInt pageNum = (-1).obs;
  // is currently loading
  RxBool isLoading = true.obs;
  // did search detect last page (usually when response is an empty array)
  RxBool isLastPage = false.obs;
  // did search encounter an error
  RxString errorString = ''.obs;

  /// r85: the most pages one load of your own list reads while they show
  /// nothing (every post hidden, or in Downloads every file gone).
  static const int ownListPagesPerLoad = 10;

  /// r85: your own lists (Downloads, Favourites, Collections, History) cost
  /// no network, so a page that showed nothing is followed by the next one
  /// at once. A site's feed reads one page per load, as before.
  static bool ownListLoadsMore(BooruHandler handler, {required int visibleBefore, required int pages}) =>
      handler.booru.type?.isLocalDb == true &&
      !handler.locked &&
      handler.errorString.isEmpty &&
      handler.filteredFetched.length == visibleBefore &&
      pages < ownListPagesPerLoad;

  // stream that will notify it's listeners when it receives a volume button event
  StreamController<String>? _volumeStreamController;

  // listener for native volume button events
  StreamSubscription? _rootVolumeListener;

  // hack to allow global restates to force refresh of everything (mainly used when saving settings when exiting settings page)
  VoidCallback? rootRestate;

  void dispose() {
    _scrollStream?.close();
    _rootVolumeListener?.cancel();
    _volumeStreamController?.close();
  }

  // Backup/restore tabs stuff

  // special strings used to separate parts of tab backup string
  // tab - separates info parts about tab itself, list - separates tabs list entries
  // example of backup string: "booruName1|||tags1|||tab~~~booruName2|||tags2|||selected~~~booruName3|||tags3|||tab"

  // bool to notify the main build that tab restoratiuon is complete
  RxBool isRestored = false.obs;
  RxBool canBackup = false.obs;

  // keeps track of the last time tabs were backupped
  DateTime lastBackupTime = DateTime.now();

  /// 1.0: lets [backupTabs] skip an unchanged tab list (see [TabBackupGate]).
  final TabBackupGate _backupGate = TabBackupGate();

  @visibleForTesting
  void resetBackupGate() => _backupGate.reset();

  /// What decides the next backup: every field TabBackup writes per tab, the
  /// current tab, and what decides between writing and clearing the row
  /// (the default source and tags, and the first tab's source).
  int _backupSignature() {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final int tabsSignature = TabBackupGate.signatureOf(
      tabs.map(
        (tab) => TabBackupFields(
          tags: tab.tags,
          booru: tab.selectedBooru.value.name ?? 'unknown',
          id: tab.id,
          group: tab.groupName,
          poolId: tab.poolId,
          poolName: tab.poolName,
          doujinPostURL: tab.doujinPostURL,
          doujinTitle: tab.doujinTitle,
          doujinThumb: tab.doujinThumb,
          secondaryBoorus: tab.secondaryBoorus.value?.map((b) => b.name ?? 'unknown').toList() ?? const [],
          tagOverrides: tab.tagOverrides,
          inheritMainTags: tab.inheritMainTags,
        ),
      ),
      currentIndex,
    );
    return Object.hash(
      tabsSignature,
      settingsHandler.prefBooru,
      settingsHandler.defTags,
      settingsHandler.booruList.isNotEmpty,
      tabs.isEmpty ? null : tabs[0].booruHandler.booru.name,
    );
  }
}
