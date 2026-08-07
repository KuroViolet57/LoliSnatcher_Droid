import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;
import 'package:get_it/get_it.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/saved_search.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

Uuid uuid = const Uuid();

EventChannel? volumeKeyChannel = Platform.isAndroid ? const EventChannel('com.noaisu.loliSnatcher/volume') : null;

// special strings used to separate parts of tab backup string
const String tabDivider = '|||', listDivider = '~~~';
List<List<String>> decodeBackupString(String input) {
  final List<List<String>> result = [];
  final List<String> splitInput = input.split(listDivider);
  for (final String str in splitInput) {
    final List<String> booruAndTags = str.split(tabDivider);
    result.add(booruAndTags);
  }
  return result;
}

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
  // current tab index
  RxInt index = 0.obs;
  RxnString tabId = RxnString(null);

  // History of tabs the user personally opened/viewed by tapping them
  // (tab manager, tab nav buttons, desktop tab bar). Tabs auto-created from
  // the tag view / preview strips are deliberately NOT recorded here — only
  // genuine user visits, flagged via changeTabIndex(byUser: true).
  final RxList<TabVisit> visitedTabsHistory = RxList<TabVisit>([]);
  static const int _maxVisitHistory = 150;

  void recordTabVisit(SearchTab tab) {
    final visit = TabVisit(
      tabId: tab.id,
      tags: tab.tags,
      booruName: tab.selectedBooru.value.name ?? '',
      booruType: tab.selectedBooru.value.type,
      visitedAt: DateTime.now(),
    );
    // One entry per tab: drop any existing entry for this tab (same id) so the
    // tab moves to most-recent and reflects its current tags, instead of
    // adding a duplicate when its search changes or it's re-visited.
    visitedTabsHistory.removeWhere((v) => v.tabId == tab.id);
    visitedTabsHistory.add(visit);
    if (visitedTabsHistory.length > _maxVisitHistory) {
      visitedTabsHistory.removeRange(0, visitedTabsHistory.length - _maxVisitHistory);
    }
    // Persist so the history survives app restarts. Fire-and-forget.
    unawaited(_persistTabVisit(visit));
  }

  Future<void> _persistTabVisit(TabVisit visit) async {
    try {
      // Replace any prior persisted rows for this tab so the DB mirrors the
      // one-entry-per-tab, most-recent semantics of the in-memory list.
      await SettingsHandler.instance.dbHandler.deleteTabVisit(visit.tabId);
      await SettingsHandler.instance.dbHandler.addTabVisit(
        tabId: visit.tabId,
        tags: visit.tags,
        booruName: visit.booruName,
        booruType: visit.booruType?.name,
        visitedAt: visit.visitedAt.millisecondsSinceEpoch,
      );
      await SettingsHandler.instance.dbHandler.trimTabVisits(_maxVisitHistory);
    } catch (e, s) {
      Logger.Inst().log(
        'failed to persist tab visit: $e',
        'SearchHandler',
        '_persistTabVisit',
        LogTypes.exception,
        s: s,
      );
    }
  }

  Future<void> loadVisitedTabsHistory() async {
    try {
      final rows = await SettingsHandler.instance.dbHandler.getTabVisits();
      visitedTabsHistory.assignAll(rows.map(TabVisit.fromRow));
    } catch (e, s) {
      Logger.Inst().log(
        'failed to load tab visit history: $e',
        'SearchHandler',
        'loadVisitedTabsHistory',
        LogTypes.exception,
        s: s,
      );
    }
  }

  Future<void> clearVisitedTabsHistory() async {
    visitedTabsHistory.clear();
    try {
      await SettingsHandler.instance.dbHandler.clearTabVisits();
    } catch (_) {}
  }

  // Sentinel for addTabByString's `group` param: inherit the current tab's
  // group. Used by tag-driven opens (tag chips, previews, batch open) so a
  // tab spawned from inside a group lands in the same group.
  static const Object inheritGroup = Object();

  // add new tab by the given search string
  void addTabByString(
    String searchText, {
    bool switchToNew = false,
    Booru? customBooru,
    List<Booru>? secondaryBoorus,
    // null = follow the user's "New tab position" setting. Pass explicitly
    // only when the caller offers its own placement choice.
    TabAddMode? addMode,
    // Tab group to open into: a String places the tab in that group (created
    // if new), [inheritGroup] copies the current tab's group, null = none.
    Object? group,
    int? customPage,
    Map<String, String>? tagOverrides,
    Map<String, bool>? inheritMainTags,
    String? tabId,
  }) {
    final Booru booru = customBooru ?? currentBooru;

    final String? groupName = identical(group, inheritGroup)
        ? (tabs.isNotEmpty ? currentTab.groupName : null)
        : group as String?;

    // Add new tab depending on the add mode
    final SearchTab newTab = SearchTab(
      booru,
      secondaryBoorus,
      searchText,
      tabId: tabId,
      tagOverrides: tagOverrides,
      inheritMainTags: inheritMainTags,
    );
    newTab.groupName = groupName;
    if (customPage != null) {
      newTab.booruHandler.pageNum = customPage;
    }

    TabAddMode resolvedMode = addMode ?? defaultTabAddModeResolved;
    // Opening into an EXISTING group the current tab is not part of:
    // prev/next would drop the tab outside the group's block and fragment
    // it — force end-of-group placement instead. A brand-new group has no
    // block yet, so it honours the requested placement (e.g. next to the
    // current tab).
    final bool groupExists = groupName != null && tabs.any((t) => t.groupName == groupName);
    if (groupExists && (tabs.isEmpty || currentTab.groupName != groupName)) {
      resolvedMode = TabAddMode.end;
    }

    int newIndex = 0;
    switch (resolvedMode) {
      case TabAddMode.prev:
        newIndex = _snapInsertionIndex(currentIndex, groupName, forward: false);
        tabs.insert(newIndex, newTab);
        break;
      case TabAddMode.next:
        newIndex = _snapInsertionIndex(currentIndex + 1, groupName, forward: true);
        tabs.insert(newIndex, newTab);
        break;
      case TabAddMode.end:
        // "End" for a grouped tab means the end of ITS GROUP's block, so the
        // group stays contiguous in the tab list.
        final int lastInGroup = groupName == null ? -1 : tabs.lastIndexWhere((t) => t.groupName == groupName);
        if (lastInGroup != -1) {
          newIndex = lastInGroup + 1;
          tabs.insert(newIndex, newTab);
        } else {
          tabs.add(newTab);
          newIndex = total - 1;
        }
        break;
    }

    // record search query to db
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (searchText != '' && settingsHandler.searchHistoryEnabled) {
      settingsHandler.dbHandler.updateSearchHistory(
        searchText,
        booru.type?.name,
        booru.name,
      );
    }

    // set to last tab if requested
    if (switchToNew) {
      changeTabIndex(newIndex);
    }
  }

  // remove tab (or current if not provided) index and set new index and search text values
  void removeTabAt({int tabIndex = -1}) {
    if (tabIndex == -1) {
      tabIndex = currentIndex;
    }

    if (total > 1) {
      if (tabIndex == currentIndex) {
        // if current tab is the one being removed
        if (currentIndex == total - 1) {
          // if current tab is the last one, switch to previous one
          changeTabIndex(currentIndex - 1);
          tabs.removeAt(currentIndex + 1);
        } else {
          // if current tab is not the last one, switch to next one
          changeTabIndex(currentIndex + 1, switchOnly: true);
          tabs.removeAt(currentIndex - 1);
          changeTabIndex(currentIndex - 1);
        }
      } else {
        // if current tab is not the one being removed
        if (tabIndex < currentIndex) {
          // if tab to be removed is before current tab
          changeTabIndex(currentIndex - 1, switchOnly: true);
        }
        tabs.removeAt(tabIndex);
        changeTabIndex(currentIndex);
      }
    } else {
      // if there is only one tab, reset to default tags
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.removedLastTab, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.loc.searchHandler.resettingSearchToDefaultTags),
          ],
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      final String defaultText = currentBooru.defTags?.isNotEmpty == true
          ? currentBooru.defTags!
          : settingsHandler.defTags;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      tabs[0] = newTab;
      changeTabIndex(0);
    }
  }

  void removeTabs(List<SearchTab> tabsToRemove) {
    final curTab = currentTab;
    final totalTabs = total;

    for (final tab in tabsToRemove) {
      tabs.value.remove(tab);
    }

    if (totalTabs == tabsToRemove.length) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.removedLastTab, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.loc.searchHandler.resettingSearchToDefaultTags),
          ],
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      final String defaultText = currentBooru.defTags?.isNotEmpty == true
          ? currentBooru.defTags!
          : settingsHandler.defTags;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      tabs.value[0] = newTab;
      changeTabIndex(0);
    } else {
      final newIndex = tabs.value.indexWhere((t) => t.id == curTab.id);
      changeTabIndex(newIndex == -1 ? total - 1 : newIndex);
    }
  }

  void moveTab(int fromIndex, int toIndex) {
    // value checks
    if (fromIndex == toIndex) {
      return;
    }
    if (fromIndex < 0 || fromIndex >= total || toIndex < 0 || toIndex >= total) {
      return;
    }

    // move tab
    final SearchTab tab = tabs[fromIndex];
    tabs.removeAt(fromIndex);
    tabs.insert(toIndex, tab);

    // check how index changed and jump to correct tab
    if (fromIndex == currentIndex) {
      // if the current tab is moved, change the current tab index
      changeTabIndex(toIndex);
    } else if (toIndex == currentIndex) {
      // if moved into the place of the current tab, bump index of current tab
      changeTabIndex(toIndex + 1);
    } else if (fromIndex < currentIndex && toIndex > currentIndex) {
      // if tab was before current tab and is moved after current tab, current tab is -1
      changeTabIndex(currentIndex - 1);
    } else if (fromIndex > currentIndex && toIndex < currentIndex) {
      // if tab was after current tab and is moved before current tab, current tab is +1
      changeTabIndex(currentIndex + 1);
    }
  }

  SearchTab? getTabByIndex(int index) {
    if (index < 0 || index >= total) {
      return null;
    }
    return tabs[index];
  }

  int getTabIndex(SearchTab tab) {
    return tabs.indexOf(tab);
  }

  int getItemIndex(BooruItem item) {
    return currentFetched.indexOf(item);
  }

  // grid scroll controller
  AutoScrollController gridScrollController =
      AutoScrollController(); // will be overwritten on the first render because there is hasClients check
  RxDouble scrollOffset = 0.0.obs;
  // stream that will notify it's listeners about scroll events of the grid controller
  StreamController<ScrollNotification>? _scrollStream;
  Stream<ScrollNotification>? get scrollStream => _scrollStream?.stream;

  void sendToScrollStream(ScrollNotification notification) {
    _scrollStream?.sink.add(notification);

    scrollOffset.value = gridScrollController.offset;
    currentTab.scrollPosition = gridScrollController.offset;
  }

  // search box text controller
  final TextEditingController searchTextController = TextEditingController();
  void addTagToSearch(String tag) {
    if (tag.isNotEmpty) {
      if (currentBooru.type?.isHydrus == true) {
        searchTextController.text += ', $tag';
      } else {
        searchTextController.text += ' $tag';
      }
    }
  }

  List<String> get searchTextControllerTags =>
      searchTextController.text.trim().split(' ').where((t) => t.isNotEmpty).toList();

  void removeTagFromSearch(String tag) {
    if (tag.isNotEmpty) {
      searchTextController.text = searchTextController.text
          .replaceAll(RegExp(r'(?:-|~)?\d+#(?:-|~)?' + tag.regexpEscape()), '')
          .replaceAll('-$tag', '')
          .replaceAll('~$tag', '')
          .replaceAll(tag, '');
    }
  }

  // search box focus node
  FocusNode searchBoxFocus = FocusNode();

  final GlobalKey mainDrawerKey = GlobalKey();

  // switch to tab #index
  void changeTabIndex(
    int i, {
    bool switchOnly = false,
    bool ignoreSameIndexCheck = false,
    bool byUser = false,
  }) {
    // change only if new index != current index
    // final int oldIndex = currentIndex;
    int newIndex = i;

    // protection from early execution on start
    if (tabs.isEmpty) {
      return;
    }

    // protection from out of bounds
    if (newIndex > (total - 1)) {
      newIndex = total - 1;
    } else if (newIndex < 0) {
      newIndex = 0;
    }

    // record a personal visit when the switch was user-initiated (tab manager
    // tap, tab nav buttons, desktop tab bar) — not for programmatic switches.
    if (byUser && newIndex >= 0 && newIndex < total) {
      recordTabVisit(tabs[newIndex]);
    }

    // change index only when it's different
    if (!ignoreSameIndexCheck && newIndex != currentIndex) {
      index.value = newIndex;
      tabId.value = tabs[newIndex].id;
      Tools.forceClearMemoryCache(withLive: true);
    }

    // set search text (even if index didn't change)
    searchTextController.text = currentTab.tags;

    /// Get state from (new) current tab (current page, is end of search, did stop on error)
    pageNum.value = currentBooruHandler.pageNum;
    isLastPage.value = currentBooruHandler.locked;
    errorString.value = currentBooruHandler.errorString;

    if (switchOnly) {
      // only used when we need to switch tabs around, but don't trigger new search call (e.g. when removing tabs)
      return;
    }

    // reset search bool
    isLoading.value = false;

    // trigger first search OR just get old filteredFetched list
    final bool isNewSearch = currentFetched.isEmpty;
    // print('isNEW: $isNewSearch ${currentIndex}');
    // trigger search if there are items inside booruHandler
    if (isNewSearch) {
      runSearch().then((_) {
        tabId.value = tabs[currentIndex].id;
      });
    } else {
      tabId.value = tabs[currentIndex].id;
    }

    // print('changed index from $oldIndex to $newIndex');
  }

  // recreate current tab with custom starting page number
  void changeCurrentTabPageNumber(int newPageNum) {
    final SearchTab newTab = SearchTab(
      currentBooru,
      currentSecondaryBoorus.value,
      currentTab.tags,
      tabId: currentTab.id,
    );
    newTab.booruHandler.pageNum = newPageNum;
    pageNum.value = newPageNum;
    tabs[currentIndex] = newTab;

    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  RxBool isRunningAutoSearch = false.obs;
  // search on the current tab until we reach given page number or there is an error
  Future<void> searchCurrentTabUntilPageNumber(
    int newPageNum, {
    int? customDelay,
  }) async {
    if (isRunningAutoSearch.value) {
      return;
    }
    isRunningAutoSearch.value = true;

    if (newPageNum > pageNum.value) {
      int tempNum = pageNum.value;
      while (isRunningAutoSearch.value && tempNum < newPageNum) {
        if (!isLoading.value) {
          await runSearch();
          tempNum++;
          // print('search num $tempNum ${pageNum.value}');

          if (errorString.value.isNotEmpty) {
            break;
          }

          await Future.delayed(Duration(milliseconds: customDelay ?? 200));
        }
      }
    }

    isRunningAutoSearch.value = false;
  }

  HasTabWithTagResult hasTabWithTag(String tag, {Booru? customBooru}) {
    tag = tag.toLowerCase().trim();
    final Booru targetBooru = customBooru ?? currentBooru;

    final onlyTagMatches = tabs.where((tab) => tab.tags.toLowerCase().trim() == tag);
    if (onlyTagMatches.isNotEmpty) {
      if (onlyTagMatches.any((tab) => tab.selectedBooru.value == targetBooru)) {
        return HasTabWithTagResult.onlyTag;
      }
      return HasTabWithTagResult.onlyTagDifferentBooru;
    }

    if (getTabsContainingTag(tag).isNotEmpty) {
      return HasTabWithTagResult.containsTag;
    }

    return HasTabWithTagResult.noTag;
  }

  List<(int, SearchTab)> getTabsWithOnlyTag(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final parts = tab.tags.toLowerCase().trim().split(' ');
      if (parts.length == 1 && parts[0] == tag && tab.selectedBooru.value == currentBooru) {
        result.add((i, tab));
      }
    }
    return result;
  }

  List<(int, SearchTab)> getTabsWithOnlyTagDifferentBooru(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final parts = tab.tags.toLowerCase().trim().split(' ');
      if (parts.length == 1 && parts[0] == tag && tab.selectedBooru.value != currentBooru) {
        result.add((i, tab));
      }
    }
    return result;
  }

  List<(int, SearchTab)> getTabsContainingTag(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      if (tab.tags.toLowerCase().trim().split(' ').contains(tag)) {
        result.add((i, tab));
      }
    }
    return result;
  }

  int get currentIndex => index.value;
  String? get currentTabId => tabId.value;
  int get total => tabs.length;
  SearchTab get currentTab => tabs[currentIndex];
  BooruHandler get currentBooruHandler => currentTab.booruHandler;
  Booru get currentBooru => currentTab.selectedBooru.value;
  Rxn<List<Booru>?> get currentSecondaryBoorus => currentTab.secondaryBoorus;
  RxList<BooruItem> get currentSelected => currentTab.selected;
  RxList<BooruItem> get currentFetched => currentBooruHandler.filteredFetched;
  void filterCurrentFetched() {
    if (tabs.isNotEmpty) {
      currentBooruHandler.filterFetched();
    }
  }

  // runs search on current tab
  Future<void> searchAction(String text, Booru? newBooru) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // Remove extra spaces
    text = text.trim();

    // Record the search as a taste signal (skip virtual/local feeds).
    final BooruType? actionType = (newBooru ?? currentBooru).type;
    if (text.isNotEmpty && actionType?.isLocalDb != true && actionType?.isForYou != true) {
      InterestsHandler.instance.onSearch(text);
    }

    // clear image memory cache
    Tools.forceClearMemoryCache(withLive: true);

    // set new tab data
    if (tabs.isEmpty) {
      if (settingsHandler.booruList.isNotEmpty) {
        final SearchTab newTab = SearchTab(
          settingsHandler.booruList[0],
          currentSecondaryBoorus.value,
          text,
        );
        tabs.add(newTab);
      }
    } else {
      // Preserve per-booru tag overrides + inherit flags across the tab swap
      // so the user's search-bar tap doesn't wipe edits they made.
      final Map<String, String> carriedOverrides = Map<String, String>.from(currentTab.tagOverrides);
      final Map<String, bool> carriedInherit = Map<String, bool>.from(currentTab.inheritMainTags);
      final SearchTab newTab = SearchTab(
        newBooru ?? currentBooru,
        currentSecondaryBoorus.value,
        text,
        tabId: currentTab.id, // keep the same tab identity across the search change
        tagOverrides: carriedOverrides,
        inheritMainTags: carriedInherit,
      );
      // In-place search change keeps the tab in its group.
      newTab.groupName = currentTab.groupName;
      tabs[currentIndex] = newTab;
      // The user changed this tab's search while viewing it — update its
      // visited-history entry in place (same id) instead of duplicating.
      recordTabVisit(newTab);
    }

    unawaited(searchReactions(text, newBooru ?? currentBooru));

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);

    // write to history
    if (text != '' && settingsHandler.searchHistoryEnabled) {
      unawaited(
        settingsHandler.dbHandler.updateSearchHistory(
          text,
          currentBooru.type?.name,
          currentBooru.name,
        ),
      );
    }
  }

  //

  final Map<SearchReaction, int> _reactionsCount = {};
  int getSearchReactionCount(SearchReaction r) => _reactionsCount[r] ?? 0;
  void incrementSearchReactionCount(SearchReaction r) => _reactionsCount[r] = (_reactionsCount[r] ?? 0) + 1;
  bool canSendSearchReaction(SearchReaction r) => getSearchReactionCount(r) < r.limit;

  Future<void> searchReactions(String text, Booru booru) async {
    final context = NavigationHandler.instance.navContext;

    // UOOOOOHHHHH
    if (text.toLowerCase().contains('loli') && canSendSearchReaction(.uoh)) {
      incrementSearchReactionCount(.uoh);
      await FlashElements.showSnackbar(
        duration: const Duration(seconds: 2),
        title: Text(
          context.loc.searchHandler.uoh,
          style: const TextStyle(fontSize: 20),
        ),
        // TODO replace with image asset to avoid system-to-system font differences
        overrideLeadingIconWidget: const Text(
          ' 😭 ',
          style: TextStyle(fontSize: 40),
        ),
        sideColor: Colors.pink,
      );
    }

    // Notify about ratings change on gelbooru and danbooru
    if (text.contains('rating:safe')) {
      final bool isOnBooruWhereRatingsChanged =
          (booru.type?.isGelbooru == true && booru.baseURL!.contains('gelbooru.com')) ||
          (booru.type?.isDanbooru == true && booru.baseURL!.contains('danbooru.donmai.us'));
      if (isOnBooruWhereRatingsChanged) {
        await FlashElements.showSnackbar(
          duration: null,
          title: Text(
            context.loc.searchHandler.ratingsChanged,
            style: const TextStyle(fontSize: 20),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.loc.searchHandler.ratingsChangedMessage(booruType: booru.type?.name ?? ''),
                style: const TextStyle(fontSize: 16),
              ),
              const Text(''),
              Text(
                context.loc.searchHandler.appFixedRatingAutomatically,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          leadingIcon: Symbols.warning_amber_rounded,
          leadingIconColor: Colors.yellow,
          sideColor: Colors.red,
        );
      }
    }
  }

  //

  //
  // Seen posts (already-viewed dimming). In-memory mirror of the SeenPost
  // table for O(1) lookups while building grid cells; the DB is the durable
  // copy. Keyed by postURL (globally unique because it carries the domain,
  // so it's merge-safe with no booru context needed).

  final Set<String> seenPostKeys = <String>{};

  String? seenKeyFor(BooruItem item) {
    if (item.postURL.isNotEmpty) return item.postURL;
    if (item.fileURL.isNotEmpty) return item.fileURL;
    return null;
  }

  bool isPostSeen(BooruItem item) {
    final String? key = seenKeyFor(item);
    return key != null && seenPostKeys.contains(key);
  }

  Future<void> loadSeenPosts() async {
    try {
      final keys = await SettingsHandler.instance.dbHandler.getSeenPostKeys();
      seenPostKeys
        ..clear()
        ..addAll(keys);
    } catch (_) {}
  }

  Future<void> markPostSeen(BooruItem item) async {
    final String? key = seenKeyFor(item);
    if (key == null) return;
    item.isSeen.value = true;
    if (seenPostKeys.add(key)) {
      // only hit the DB the first time we see this key
      try {
        await SettingsHandler.instance.dbHandler.addSeenPost(key);
      } catch (_) {}
    }
    // Viewing history: store the full item every time (a re-view bumps the
    // entry back to the top of the History feed).
    try {
      await SettingsHandler.instance.dbHandler.addViewedPost(
        key,
        DBHandler.serializeHistoryItem(item),
      );
    } catch (_) {}
  }

  Future<void> clearSeenPosts() async {
    seenPostKeys.clear();
    try {
      await SettingsHandler.instance.dbHandler.clearSeenPosts();
    } catch (_) {}
    // Drop the live flag on currently-loaded items so the grid un-dims.
    for (final tab in tabs) {
      for (final item in tab.booruHandler.fetched) {
        item.isSeen.value = false;
      }
    }
  }

  //
  // Saved searches (quick-search favourites). Bookmarks the user's current
  // query (tags + booru + secondaries + per-booru overrides + inherit flags)
  // so they can re-open it later, optionally on a different booru.

  final RxList<SavedSearch> savedSearches = <SavedSearch>[].obs;

  Future<void> reloadSavedSearches() async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    savedSearches.assignAll(await settingsHandler.dbHandler.getSavedSearches());
  }

  // Snapshots the current tab as a SavedSearch and persists it. Returns the
  // new id (or null if persistence failed). Name is optional; empty falls
  // back to the tag string at display time.
  Future<int?> addCurrentTabAsSavedSearch({String? name}) async {
    if (tabs.isEmpty) return null;
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchTab tab = currentTab;
    final entry = SavedSearch(
      id: null,
      name: name?.trim() ?? '',
      tags: tab.tags,
      booru: tab.selectedBooru.value.name ?? '',
      secondaryBoorus:
          tab.secondaryBoorus.value?.map((b) => b.name ?? '').where((e) => e.isNotEmpty).toList() ?? const [],
      tagOverrides: Map<String, String>.from(tab.tagOverrides)..removeWhere((_, v) => v.trim().isEmpty),
      inheritMainTags: Map<String, bool>.from(tab.inheritMainTags)..removeWhere((_, v) => v),
      createdAt: DateTime.now(),
    );
    final int? id = await settingsHandler.dbHandler.addSavedSearch(entry);
    await reloadSavedSearches();
    return id;
  }

  Future<void> deleteSavedSearch(int id) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    await settingsHandler.dbHandler.deleteSavedSearch(id);
    await reloadSavedSearches();
  }

  Future<void> renameSavedSearch(int id, String name) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    await settingsHandler.dbHandler.renameSavedSearch(id, name);
    await reloadSavedSearches();
  }

  // Inserting at [index] must never split another group's contiguous block
  // (e.g. opening a NEW group from inside group A would otherwise cut A in
  // two). When the insertion point falls inside a foreign block, snap it to
  // the block's end (forward) or start (backward).
  int _snapInsertionIndex(int index, String? groupName, {required bool forward}) {
    if (index <= 0 || index >= tabs.length) return index.clamp(0, tabs.length);
    final String? before = tabs[index - 1].groupName;
    final String? at = tabs[index].groupName;
    final bool splitsForeignBlock = before != null && before.isNotEmpty && before == at && before != groupName;
    if (!splitsForeignBlock) return index;

    int i = index;
    if (forward) {
      while (i < tabs.length && tabs[i].groupName == before) {
        i++;
      }
    } else {
      while (i > 0 && tabs[i - 1].groupName == before) {
        i--;
      }
    }
    return i;
  }

  // Ordered distinct tab-group names, in first-appearance order.
  List<String> get tabGroupNames {
    final List<String> names = [];
    for (final tab in tabs) {
      final String? g = tab.groupName;
      if (g != null && g.isNotEmpty && !names.contains(g)) names.add(g);
    }
    return names;
  }

  List<SearchTab> tabsInGroup(String groupName) => tabs.where((t) => t.groupName == groupName).toList();

  void renameTabGroup(String oldName, String newName) {
    for (final tab in tabs) {
      if (tab.groupName == oldName) tab.groupName = newName;
    }
    tabs.value = [...tabs];
  }

  void dissolveTabGroup(String groupName) {
    for (final tab in tabs) {
      if (tab.groupName == groupName) tab.groupName = null;
    }
    tabs.value = [...tabs];
  }

  /// Moves [tabsToMove] into [groupName], keeping their relative order and
  /// the group block contiguous. An existing group receives them at its end;
  /// a new group's block forms where the first moved tab sat.
  void moveTabsToGroup(List<SearchTab> tabsToMove, String groupName) {
    if (tabsToMove.isEmpty || groupName.isEmpty) return;
    final SearchTab current = currentTab;

    // Preserve on-screen order of the moved tabs.
    final List<SearchTab> ordered = tabs.where(tabsToMove.contains).toList();
    if (ordered.isEmpty) return;
    final List<SearchTab> remaining = tabs.where((t) => !tabsToMove.contains(t)).toList();

    int insertAt;
    final int lastMember = remaining.lastIndexWhere((t) => t.groupName == groupName);
    if (lastMember != -1) {
      insertAt = lastMember + 1;
    } else {
      // New group: keep the block where its first tab was.
      final int anchor = tabs.indexOf(ordered.first);
      int before = 0;
      for (int i = 0; i < anchor; i++) {
        if (!tabsToMove.contains(tabs[i])) before++;
      }
      insertAt = before;
      // Don't split a foreign group block in the remaining list.
      if (insertAt > 0 && insertAt < remaining.length) {
        final String? b = remaining[insertAt - 1].groupName;
        final String? a = remaining[insertAt].groupName;
        if (b != null && b.isNotEmpty && b == a && b != groupName) {
          while (insertAt < remaining.length && remaining[insertAt].groupName == b) {
            insertAt++;
          }
        }
      }
    }

    for (final t in ordered) {
      t.groupName = groupName;
    }
    remaining.insertAll(insertAt, ordered);
    tabs.value = remaining;

    final int newIndex = tabs.indexOf(current);
    changeTabIndex(newIndex == -1 ? 0 : newIndex);
  }

  // The TabAddMode matching the user's "New tab position" setting
  // (next / end / prev), falling back to end.
  TabAddMode get defaultTabAddModeResolved =>
      TabAddMode.values.firstWhereOrNull(
        (m) => m.name == SettingsHandler.instance.defaultTabAddMode,
      ) ??
      TabAddMode.end;

  // One-tap "new tab": opens an empty tab in the current booru (or its default
  // tags), honouring the New tab position setting, and switches to it.
  void addNewTabRespectingSetting() {
    final String defaultText = currentBooru.defTags?.isNotEmpty == true
        ? currentBooru.defTags!
        : SettingsHandler.instance.defTags;
    searchTextController.text = defaultText;
    addTabByString(
      defaultText,
      switchToNew: true,
      addMode: defaultTabAddModeResolved,
    );
  }

  // Opens a saved search as a new tab. `customBooru` overrides the saved
  // primary (used by the "open in another booru" action). Respects the
  // user's defaultTabAddMode setting and switches focus to the new tab.
  void openSavedSearch(
    SavedSearch entry, {
    Booru? customBooru,
  }) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<Booru> allBoorus = settingsHandler.booruList;
    final Booru? primary = customBooru ??
        allBoorus.firstWhereOrNull((b) => b.name == entry.booru);
    if (primary == null) return;

    final TabAddMode addMode = TabAddMode.values.firstWhereOrNull(
          (m) => m.name == settingsHandler.defaultTabAddMode,
        ) ??
        TabAddMode.end;
    addTabByString(
      entry.tags,
      switchToNew: true,
      customBooru: primary,
      secondaryBoorus: entry.resolveSecondaryBoorus(allBoorus),
      addMode: addMode,
      tagOverrides: entry.tagOverrides.isEmpty ? null : Map<String, String>.from(entry.tagOverrides),
      inheritMainTags:
          entry.inheritMainTags.isEmpty ? null : Map<String, bool>.from(entry.inheritMainTags),
    );
  }

  //

  // add secondary boorus and run search
  void mergeAction(List<Booru>? secondaryBoorus) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final bool canAddSecondary = secondaryBoorus != null && settingsHandler.booruList.length > 1;
    final List<Booru>? secondary = canAddSecondary ? secondaryBoorus : null;

    // When the merge set changes, drop overrides for boorus that are no longer
    // part of it; keep the rest so the user doesn't lose their edits when
    // toggling boorus on and off.
    final Set<String> keepNames = {
      currentBooru.name ?? '',
      ...?secondary?.map((b) => b.name ?? ''),
    }..removeWhere((e) => e.isEmpty);
    final Map<String, String> carriedOverrides = {
      for (final e in currentTab.tagOverrides.entries)
        if (keepNames.contains(e.key)) e.key: e.value,
    };
    final Map<String, bool> carriedInherit = {
      for (final e in currentTab.inheritMainTags.entries)
        if (keepNames.contains(e.key)) e.key: e.value,
    };

    final SearchTab newTab = SearchTab(
      currentBooru,
      secondary,
      currentTab.tags,
      tabId: currentTab.id,
      tagOverrides: carriedOverrides,
      inheritMainTags: carriedInherit,
    );
    tabs[currentIndex] = newTab;

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  // current page number
  RxInt pageNum = (-1).obs;
  // is currently loading
  RxBool isLoading = true.obs;
  // did search detect last page (usually when response is an empty array)
  RxBool isLastPage = false.obs;
  // did search encounter an error
  RxString errorString = ''.obs;

  // run search on current tab
  Future<void> runSearch() async {
    final startTabId = currentTab.id;
    // do nothing if reached the end or detected an error
    if (isLastPage.value || errorString.isNotEmpty) {
      return;
    }

    // if not last page - set loading state and increment page
    if (!currentBooruHandler.locked) {
      isLoading.value = true;
      currentBooruHandler.pageNum++;
      pageNum++;
    }

    // fetch new items, but get results from booruHandler and not search itself
    await currentBooruHandler.search(currentTab.tags, null);
    // print('FINISHED SEARCH: ${booruhandler.filteredFetched.length}');

    // lock new loads if handler detected last page
    // (previous filteredFetched length == current length)
    if (currentBooruHandler.locked && !isLastPage.value) {
      isLastPage.value = true;
    }

    if (currentBooruHandler.errorString.isNotEmpty) {
      errorString.value = currentBooruHandler.errorString;
    }

    // request total image count if not already loaded
    if (currentBooruHandler.totalCount.value == 0) {
      unawaited(currentBooruHandler.searchCount(currentTab.tags));
    }

    // check to avoid requests from old tab instances resetting loading state
    if (currentTab.id == startTabId) {
      // delay every new page load
      Future.delayed(const Duration(milliseconds: 200), () {
        isLoading.value = false;
      });
    }
    return;
  }

  // reset search to previous page and run again
  Future<void> retrySearch() async {
    currentBooruHandler.errorString = '';
    errorString.value = '';

    currentBooruHandler.locked = false;
    isLastPage.value = false;

    currentBooruHandler.pageNum--;
    pageNum--;
    await runSearch();
    return;
  }

  void reset() {
    tabs.clear();
    index.value = 0;
    pageNum.value = -1;
    isLoading.value = true;
    isLastPage.value = false;
    errorString.value = '';
  }

  // stream that will notify it's listeners when it receives a volume button event
  StreamController<String>? _volumeStreamController;
  Stream<String>? get volumeStream => _volumeStreamController?.stream;

  // listener for native volume button events
  StreamSubscription? _rootVolumeListener;

  // hack to allow global restates to force refresh of everything (mainly used when saving settings when exiting settings page)
  VoidCallback? rootRestate;
  void setRootRestate(VoidCallback? rootSetStateCallback) => rootRestate = rootSetStateCallback;

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

  @Deprecated('Switched to new json format. Remove this after a few versions')
  Future<void> restoreTabsLegacy(String? result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<SearchTab> restoredGlobals = [];

    bool foundBrokenItem = false;
    final List<String> brokenItems = [];
    int newIndex = 0;
    if (result != null) {
      final List<List<String>> splitInput = await compute(decodeBackupString, result);
      for (final List<String> booruAndTags in splitInput) {
        // check for parsing errors
        final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
        if (isEntryValid) {
          // find booru by name and create searchtab with given tags
          Booru findBooru = settingsHandler.booruList.firstWhere(
            (booru) => booru.name == booruAndTags[0],
            orElse: Booru.unknown,
          );
          findBooru = handleFavDlsNameChange(findBooru);
          if (findBooru.name != null) {
            final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
            restoredGlobals.add(newTab);
          } else {
            foundBrokenItem = true;
            brokenItems.add('${booruAndTags[0]}: ${booruAndTags[1]}');
            final SearchTab newTab = SearchTab(
              settingsHandler.booruList[0],
              null,
              booruAndTags[1],
            );
            restoredGlobals.add(newTab);
          }

          // check if tab was marked as selected and set current selected index accordingly
          if (booruAndTags.length > 2 && booruAndTags[2] == 'selected') {
            // if split has third item (selected) - set as current tab
            final int index = splitInput.indexWhere((si) => si == booruAndTags);
            newIndex = index;
          }
        } else {
          foundBrokenItem = true;
          brokenItems.add(
            '${booruAndTags[0]}: ${booruAndTags.length > 1 ? booruAndTags[1] : ""}',
          );
        }
      }
    }

    isRestored.value = true;

    // set parsed tabs OR set first default tab if nothing to restore
    if (restoredGlobals.isNotEmpty) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.searchHandler.restoredTabsCount(count: restoredGlobals.length),
            ),
            if (foundBrokenItem)
            // notify user if there was unknown booru or invalid entry in the tabs
            ...[
              Text(
                context.loc.searchHandler.someRestoredTabsHadIssues,
              ),
              Text(context.loc.searchHandler.theyWereSetToDefaultOrIgnored),
              Text(context.loc.searchHandler.listOfBrokenTabs),
              Text(brokenItems.join(', ')),
            ],
          ],
        ),
        sideColor: foundBrokenItem ? Colors.yellow : Colors.green,
        leadingIcon: foundBrokenItem ? Symbols.warning_amber_rounded : Symbols.settings_backup_restore_rounded,
        duration: Duration(seconds: brokenItems.isEmpty ? 4 : 10),
      );

      tabs.value = restoredGlobals;
      changeTabIndex(newIndex);
    } else {
      Booru defaultBooru = Booru.unknown();
      // Set the default booru and tags at the start
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        tabs.add(newTab);
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
    return;
  }

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void mergeTabsLegacy(String tabStr) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<List<String>> splitInput = decodeBackupString(tabStr);
    final List<SearchTab> restoredGlobals = [];
    for (final List<String> booruAndTags in splitInput) {
      // check for parsing errors
      final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
      if (isEntryValid) {
        // find booru by name and create searchtab with given tags
        Booru findBooru = settingsHandler.booruList.firstWhere(
          (booru) => booru.name == booruAndTags[0],
          orElse: Booru.unknown,
        );
        findBooru = handleFavDlsNameChange(findBooru);
        if (findBooru.name != null) {
          final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
          // add only if there are not already the same tab in the list and booru is available on this device
          if (tabs.indexWhere(
                (tab) => tab.selectedBooru.value.name == newTab.selectedBooru.value.name && tab.tags == newTab.tags,
              ) ==
              -1) {
            restoredGlobals.add(newTab);
          }
        }
      }
    }
    tabs.addAll(restoredGlobals);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsMerged),
      content: Text(
        context.loc.searchHandler.addedTabsCount(count: restoredGlobals.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.settings_backup_restore_rounded,
    );
  }

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void replaceTabsLegacy(String tabStr) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<List<String>> splitInput = decodeBackupString(tabStr);
    final List<SearchTab> restoredGlobals = [];
    int newIndex = 0;

    // reset current tab index to avoid exceptions when tab list length is different
    changeTabIndex(0, switchOnly: true);

    for (final List<String> booruAndTags in splitInput) {
      // check for parsing errors
      final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
      if (isEntryValid) {
        // find booru by name and create searchtab with given tags
        Booru findBooru = settingsHandler.booruList.firstWhere(
          (booru) => booru.name == booruAndTags[0],
          orElse: Booru.unknown,
        );
        findBooru = handleFavDlsNameChange(findBooru);
        if (findBooru.name != null) {
          final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
          restoredGlobals.add(newTab);

          if (booruAndTags[2] == 'selected') {
            final int index = splitInput.indexWhere((si) => si == booruAndTags);
            newIndex = index;
          }
        }
      }
    }
    tabs.value = restoredGlobals;
    changeTabIndex(newIndex);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsReplaced),
      content: Text(
        context.loc.searchHandler.receivedTabsCount(count: restoredGlobals.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.settings_backup_restore_rounded,
    );
  }

  //

  Future<void> restoreTabsNew(String? result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<SearchTab> restoredTabs = [];

    bool foundBrokenItems = false;
    final List<TabBackup> brokenItems = [];
    int newSelectedIndex = 0;
    final List<TabBackup> tabBackups = result != null ? await compute(TabBackup.fromJsonList, result) : [];
    for (final tabBackup in tabBackups) {
      try {
        final newTab = parseTabFromBackup(tabBackup);
        if (newTab.selectedBooru.value.name != null) {
          restoredTabs.add(newTab);
        } else {
          foundBrokenItems = true;
          brokenItems.add(tabBackup);
          restoredTabs.add(
            SearchTab(
              settingsHandler.booruList[0],
              null,
              tabBackup.tags,
            ),
          );
        }

        // get index of selected tab
        // newSelectedIndex == 0 check is to ensure that the first tab with selected:true is used
        if (newSelectedIndex == 0 && tabBackup.selected) {
          final int index = tabBackups.indexWhere((tb) => tb == tabBackup);
          newSelectedIndex = index;
        }
      } catch (e, s) {
        Logger.Inst().log(
          e,
          'SearchHandler',
          'restoreTabs',
          LogTypes.exception,
          s: s,
        );
      }
    }

    isRestored.value = true;

    if (restoredTabs.isNotEmpty) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.searchHandler.restoredTabsCount(count: restoredTabs.length),
            ),
            if (foundBrokenItems) ...[
              // notify user if there was unknown booru or invalid entry in the tabs
              Text(context.loc.searchHandler.someRestoredTabsHadIssues),
              Text(context.loc.searchHandler.theyWereSetToDefaultOrIgnored),
              Text(context.loc.searchHandler.listOfBrokenTabs),
              Text(
                brokenItems
                    .map(
                      (t) => '${tabBackups.indexOf(t)}${t.booru}: ${t.tags.isEmpty ? context.loc.tabs.empty : t.tags}',
                    )
                    .join(', '),
              ),
            ],
          ],
        ),
        sideColor: foundBrokenItems ? Colors.yellow : Colors.green,
        leadingIcon: foundBrokenItems ? Symbols.warning_amber_rounded : Symbols.settings_backup_restore_rounded,
        duration: Duration(seconds: brokenItems.isEmpty ? 4 : 10),
      );

      tabs.value = restoredTabs;
      changeTabIndex(newSelectedIndex);
    } else {
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        tabs.add(
          SearchTab(defaultBooru, null, defaultText),
        );
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
    return;
  }

  void mergeTabsNew(String tabStr) {
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabStr);
    final List<SearchTab> restoredTabs = [];
    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);

      // add only if there are not already the same tab in the list and booru is available on this device
      if (newTab.selectedBooru.value.name != null &&
          tabs.any(
            (tab) =>
                tab.selectedBooru.value.name == newTab.selectedBooru.value.name &&
                tab.secondaryBoorus.value?.map((t) => t.name).toList() ==
                    newTab.secondaryBoorus.value?.map((t) => t.name).toList() &&
                tab.tags == newTab.tags,
          )) {
        restoredTabs.add(newTab);
      }
    }

    tabs.addAll(restoredTabs);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsMerged),
      content: Text(
        context.loc.searchHandler.addedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.settings_backup_restore_rounded,
    );
  }

  void replaceTabsNew(String tabStr) {
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabStr);
    final List<SearchTab> restoredTabs = [];
    int newSelectedIndex = 0;

    // reset current tab index to avoid exceptions when tab list length is different
    changeTabIndex(0, switchOnly: true);

    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);
      if (newTab.selectedBooru.value.name != null) {
        restoredTabs.add(newTab);

        if (newSelectedIndex == 0 && tabBackup.selected) {
          final int index = tabBackups.indexWhere((tb) => tb == tabBackup);
          newSelectedIndex = index;
        }
      }
    }
    tabs.value = restoredTabs;
    changeTabIndex(newSelectedIndex);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsReplaced),
      content: Text(
        context.loc.searchHandler.receivedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.settings_backup_restore_rounded,
    );
  }

  String? generateBackupJson() {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // if there are only one tab - check that its not with default booru and tags
    // if there are more than 1 tab or check return false - start backup
    final int tabIndex = currentIndex;
    final bool onlyDefaultTab =
        tabs.length == 1 &&
        tabs[0].booruHandler.booru.name == settingsHandler.prefBooru &&
        tabs[0].tags == settingsHandler.defTags;
    if (!onlyDefaultTab && settingsHandler.booruList.isNotEmpty) {
      final List<String> dump = tabs.map((tab) {
        final String tags = tab.tags;
        final String booruName = tab.selectedBooru.value.name ?? 'unknown';
        final List<String> secondaryBoorusNames =
            tab.secondaryBoorus.value?.map((b) => b.name ?? 'unknown').toList() ?? [];
        final Map<String, String> overrides = Map<String, String>.from(tab.tagOverrides)
          ..removeWhere((_, v) => v.trim().isEmpty);
        // inherit defaults to true; only persist the explicit-false entries.
        final Map<String, bool> inherit = Map<String, bool>.from(tab.inheritMainTags)
          ..removeWhere((_, v) => v);
        final bool selected = tab == tabs[tabIndex];

        return jsonEncode(
          TabBackup(
            tags: tags,
            booru: booruName,
            id: tab.id,
            group: tab.groupName,
            secondaryBoorus: secondaryBoorusNames,
            tagOverrides: overrides,
            inheritMainTags: inherit,
            selected: selected,
          ).toJson(),
        );
      }).toList();

      return '[${dump.join(',')}]';
    } else {
      return null;
    }
  }

  SearchTab parseTabFromBackup(TabBackup backup) {
    final booruList = SettingsHandler.instance.booruList;

    Booru selectedBooru = booruList.firstWhere(
      (b) => b.name == backup.booru,
      orElse: Booru.unknown,
    );
    selectedBooru = handleFavDlsNameChange(selectedBooru);
    List<Booru> secondaryBoorus = backup.secondaryBoorus
        .map(
          (b) => booruList.firstWhere(
            (booru) => booru.name == b,
            orElse: Booru.unknown,
          ),
        )
        .where((b) => b.name != null)
        .toList();
    secondaryBoorus = secondaryBoorus.map(handleFavDlsNameChange).where((b) => b.name != null).toList();

    return SearchTab(
      selectedBooru,
      secondaryBoorus.isEmpty ? null : secondaryBoorus,
      backup.tags,
      tabId: backup.id,
      tagOverrides: backup.tagOverrides.isEmpty ? null : Map<String, String>.from(backup.tagOverrides),
      inheritMainTags:
          backup.inheritMainTags.isEmpty ? null : Map<String, bool>.from(backup.inheritMainTags),
    )..groupName = (backup.group?.isEmpty ?? true) ? null : backup.group;
  }

  Booru handleFavDlsNameChange(Booru booru) {
    if (booru.name != null) {
      return booru;
    }

    final booruList = SettingsHandler.instance.booruList;
    Booru tempBooru = Booru.unknown();
    // a workaround to fix favs/dls tabs not parsing/restoring correctly due to localized names
    for (final l in AppLocale.values) {
      tempBooru = booruList.firstWhere(
        (b) => b.name == l.translations['favourites'] || b.name == l.translations['downloads'],
        orElse: Booru.unknown,
      );
      if (tempBooru.name != null) {
        break;
      }
    }
    return tempBooru;
  }

  Future<void> restoreTabs() async {
    // TODO restoring database from the backup may have corrupted tab data when there are a lot of tabs?
    final settingsHandler = SettingsHandler.instance;
    // Load the seen-post set once the DB is ready (before tabs paint so the
    // first grid already shows dimming for previously-viewed posts).
    await loadSeenPosts();
    // Restore the personal tab-visit history so it survives app restarts.
    await loadVisitedTabsHistory();
    try {
      final String? result = await settingsHandler.dbHandler.getTabRestore();
      if (result == null || result.startsWith('[')) {
        await restoreTabsNew(result);
      } else {
        // ignore: deprecated_member_use_from_same_package
        await restoreTabsLegacy(result);
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Error restoring tabs: $e',
        'SearchHandler',
        'restoreTabs',
        LogTypes.exception,
        s: s,
      );
      // await settingsHandler.dbHandler.clearTabRestore();
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        tabs.clear();
        tabs.add(newTab);
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }

    // allow backup only after restoring to avoid long operations (i.e. database fixes) delaying restore and therefore causing backup to run before tabs were restored
    canBackup.value = true;
  }

  void mergeTabs(String tabStr) {
    if (tabStr.startsWith('[')) {
      mergeTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      mergeTabsLegacy(tabStr);
    }
  }

  void replaceTabs(String tabStr) {
    if (tabStr.startsWith('[')) {
      replaceTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      replaceTabsLegacy(tabStr);
    }
  }

  Future<void> backupTabs() async {
    if (!canBackup.value) {
      return;
    }

    final String? backupString = generateBackupJson();
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // print('backupString: $backupString');
    if (backupString != null) {
      await settingsHandler.dbHandler.addTabRestore(backupString);
    } else {
      await settingsHandler.dbHandler.clearTabRestore();
    }

    lastBackupTime = DateTime.now();
  }
}

/// A lightweight record of a tab the user personally visited. Keeps a
/// snapshot (tags + booru) so it stays meaningful even after the underlying
/// tab is closed, plus the live tab id so we can jump straight back if it's
/// still open.
class TabVisit {
  TabVisit({
    required this.tabId,
    required this.tags,
    required this.booruName,
    required this.booruType,
    required this.visitedAt,
  });

  factory TabVisit.fromRow(Map<String, Object?> row) {
    final String? typeName = row['booruType'] as String?;
    BooruType? type;
    if (typeName != null) {
      for (final t in BooruType.values) {
        if (t.name == typeName) {
          type = t;
          break;
        }
      }
    }
    return TabVisit(
      tabId: (row['tabId'] as String?) ?? '',
      tags: (row['tags'] as String?) ?? '',
      booruName: (row['booruName'] as String?) ?? '',
      booruType: type,
      visitedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['visitedAt'] as int?) ?? 0,
      ),
    );
  }

  final String tabId;
  final String tags;
  final String booruName;
  final BooruType? booruType;
  final DateTime visitedAt;
}

class SearchTab {
  SearchTab(
    Booru selectedBooru,
    List<Booru>? secondaryBoorus,
    this.tags, {
    Map<String, String>? tagOverrides,
    Map<String, bool>? inheritMainTags,
    String? tabId,
  }) : id = (tabId != null && tabId.isNotEmpty) ? tabId : uuid.v4() {
    this.selectedBooru = selectedBooru.obs;
    this.secondaryBoorus = Rxn<List<Booru>?>(secondaryBoorus);
    if (tagOverrides != null && tagOverrides.isNotEmpty) {
      this.tagOverrides.addAll(tagOverrides);
    }
    if (inheritMainTags != null && inheritMainTags.isNotEmpty) {
      this.inheritMainTags.addAll(inheritMainTags);
    }

    final List<Booru> tempBooruList = [];
    tempBooruList.add(selectedBooru);
    if (secondaryBoorus?.isNotEmpty == true) {
      tempBooruList.addAll(secondaryBoorus!);
    }
    final temp = BooruHandlerFactory().getBooruHandler(tempBooruList, null);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    final handler = booruHandler;
    if (handler is MergebooruHandler) {
      handler.tagOverrides = Map<String, String>.from(this.tagOverrides);
      handler.inheritMainTags = Map<String, bool>.from(this.inheritMainTags);
    }
  }
  // unique id to use for booru controller. Preserved across in-place search
  // changes and app restarts (see SearchTab tabId param + TabBackup.id) so the
  // visited-tabs history can track a tab as one entry rather than duplicating.
  final String id;
  String tags = '';
  // Tab group this tab belongs to (null = ungrouped). Groups are rendered as
  // bordered blocks in the tab manager; tabs opened from within a grouped tab
  // (tag taps etc.) inherit the group. Persisted via TabBackup.
  String? groupName;
  // Per-booru tag overrides used when this tab is in merge mode. Keyed by
  // child booru name. Reactive so the per-booru text fields refresh when
  // a new tab is restored from a backup.
  final RxMap<String, String> tagOverrides = <String, String>{}.obs;
  // Per-booru inherit flag. Missing key means inherit (additive, the default).
  // Explicit false means the override replaces the main tags for that booru.
  final RxMap<String, bool> inheritMainTags = <String, bool>{}.obs;

  // Pushes the current tagOverrides snapshot onto the merge handler. Called
  // by the search bar when the user triggers a new search so per-booru edits
  // made since the tab was created take effect on the next page-1 fetch.
  void syncTagOverridesToHandler() {
    final handler = booruHandler;
    if (handler is MergebooruHandler) {
      handler.tagOverrides = Map<String, String>.from(tagOverrides);
      handler.inheritMainTags = Map<String, bool>.from(inheritMainTags);
    }
  }

  late final Rx<Booru> selectedBooru;
  late final Rxn<List<Booru>?> secondaryBoorus;
  late final BooruHandler booruHandler;

  double scrollPosition = 0;
  RxList<BooruItem> selected = RxList<BooruItem>.from([]);

  BooruItem? itemWithKey(Key? key) {
    return booruHandler.filteredFetched.firstWhereOrNull((item) => item.key == key);
  }

  Future<bool?> toggleItemFavourite(
    int itemIndex, {
    bool? forcedValue,
    bool skipSnatching = false,
  }) async {
    final BooruItem item = booruHandler.filteredFetched[itemIndex];
    if (item.isFavourite.value != null) {
      if (item.tagsList.isEmpty || item.mediaType.value.isNeedToLoadItem) {
        // try to update the item before favouriting, do nothing on fail
        if (!booruHandler.hasLoadItemSupport) {
          return item.isFavourite.value;
        }

        final res = await booruHandler.loadItem(
          item: item,
          withCapcthaCheck: true,
        );
        if (res.failed ||
            res.item == null ||
            res.item!.tagsList.isEmpty ||
            res.item!.mediaType.value.isNeedToLoadItem) {
          return item.isFavourite.value;
        }
      }

      if (forcedValue == null) {
        await ServiceHandler.vibrate();
      }

      final bool newValue = forcedValue ?? (item.isFavourite.value == true ? false : true);
      item.isFavourite.value = newValue;
      InterestsHandler.instance.onItemFavourited(item, nowFavourite: newValue);

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue && item.isSnatched.value != true) {
        SnatchHandler.instance.queue(
          [item],
          booruHandler.booru,
          settingsHandler.snatchCooldown,
          false,
        );
      }
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // update filtered items list in case user has favourites filter enabled
        await Future.delayed(const Duration(milliseconds: 200));
        booruHandler.filterFetched();
      });
    }
    return item.isFavourite.value;
  }

  Future<void> updateFavForMultipleItems(
    List<BooruItem> items, {
    required bool newValue,
    bool skipSnatching = false,
  }) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue) {
      SnatchHandler.instance.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        booruHandler.booru,
        settingsHandler.snatchCooldown,
        false,
      );
    }

    for (final BooruItem item in items) {
      item.isFavourite.value = newValue;
    }

    await settingsHandler.dbHandler.updateMultipleBooruItems(
      items,
      BooruUpdateMode.local,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // update filtered items list in case user has favourites filter enabled
      await Future.delayed(const Duration(milliseconds: 200));
      booruHandler.filterFetched();
    });
  }

  @override
  String toString() {
    return 'tags: $tags selectedBooru: $selectedBooru booruHandler: $booruHandler';
  }
}

class TabBackup {
  TabBackup({
    required this.tags,
    required this.booru,
    this.id,
    this.group,
    this.secondaryBoorus = const [],
    this.tagOverrides = const {},
    this.inheritMainTags = const {},
    this.selected = false,
  });
  final String tags;
  final String booru;
  // Stable tab id, so a restored tab keeps the same identity the visited-tabs
  // history recorded. Optional for backward-compat with older backups.
  final String? id;
  // Tab group name (null/absent = ungrouped).
  final String? group;
  final List<String> secondaryBoorus;
  // Per-booru tag overrides used in merge mode. Keys are booru names; missing
  // entries (or older backups without this field) fall back to `tags`.
  final Map<String, String> tagOverrides;
  // Per-booru "do not inherit main tags" flags. Only false entries are
  // persisted (true is the default).
  final Map<String, bool> inheritMainTags;
  final bool selected;

  Map<String, dynamic> toJson() {
    return {
      't': tags,
      'b': booru,
      if (id != null) 'i': id,
      if (group != null && group!.isNotEmpty) 'g': group,
      if (secondaryBoorus.isNotEmpty) 'sb': secondaryBoorus,
      if (tagOverrides.isNotEmpty) 'to': tagOverrides,
      if (inheritMainTags.isNotEmpty) 'in': inheritMainTags,
      if (selected) 's': selected, // only true matters, don't include on false
    };
  }

  static TabBackup? fromJson(Map<String, dynamic> json) {
    try {
      return TabBackup(
        tags: json['t'] as String,
        booru: json['b'] as String,
        id: json['i'] as String?,
        group: json['g'] as String?,
        secondaryBoorus: (json['sb'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
        tagOverrides:
            (json['to'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? const {},
        inheritMainTags:
            (json['in'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v == true)) ?? const {},
        selected: (json['s'] as bool?) ?? false,
      );
    } catch (_) {
      try {
        return TabBackup(
          tags: json['t'] as String,
          booru: json['b'] as String,
        );
      } catch (e, s) {
        Logger.Inst().log(
          'Invalid tab backup',
          'TabBackup',
          'fromJson',
          LogTypes.exception,
          s: s,
        );
        throw Exception('Invalid tab backup: $json');
      }
    }
  }

  static List<TabBackup> fromJsonList(String json) {
    final jsonList = jsonDecode(json);

    if (jsonList is! List) {
      return [];
    }

    return jsonList.map((e) => fromJson(e as Map<String, dynamic>)).where((e) => e != null).cast<TabBackup>().toList();
  }

  TabBackup copyWith({
    String? tags,
    String? booru,
    List<String>? secondaryBoorus,
    Map<String, String>? tagOverrides,
    Map<String, bool>? inheritMainTags,
    bool? selected,
  }) {
    return TabBackup(
      tags: tags ?? this.tags,
      booru: booru ?? this.booru,
      secondaryBoorus: secondaryBoorus ?? this.secondaryBoorus,
      tagOverrides: tagOverrides ?? this.tagOverrides,
      inheritMainTags: inheritMainTags ?? this.inheritMainTags,
      selected: selected ?? this.selected,
    );
  }
}

enum HasTabWithTagResult {
  onlyTag,
  onlyTagDifferentBooru,
  containsTag,
  noTag,
  ;

  bool get isOnlyTag => this == HasTabWithTagResult.onlyTag;
  bool get isOnlyTagDifferentBooru => this == HasTabWithTagResult.onlyTagDifferentBooru;
  bool get isContainsTag => this == HasTabWithTagResult.containsTag;
  bool get isNoTag => this == HasTabWithTagResult.noTag;
  bool get hasTagInAnyForm =>
      this == HasTabWithTagResult.onlyTag ||
      this == HasTabWithTagResult.onlyTagDifferentBooru ||
      this == HasTabWithTagResult.containsTag;

  String? locName(BuildContext context) => switch (this) {
    .onlyTag => context.loc.tagView.tabsWithOnlyTag,
    .onlyTagDifferentBooru => context.loc.tagView.tabsWithOnlyTagDifferentBooru,
    .containsTag => context.loc.tagView.tabsContainingTag,
    _ => null,
  };

  Color? color(BuildContext context) => switch (this) {
    onlyTag => Theme.of(context).colorScheme.onSurface,
    onlyTagDifferentBooru => Colors.yellow,
    containsTag => Colors.blue,
    _ => null,
  };
}

enum TabAddMode {
  prev,
  next,
  end,
  ;

  String locName(BuildContext context) {
    switch (this) {
      case prev:
        return context.loc.tabs.addModePrevTab;
      case next:
        return context.loc.tabs.addModeNextTab;
      case end:
        return context.loc.tabs.addModeListEnd;
    }
  }
}

enum SearchReaction {
  uoh,
  ;

  int get limit => switch (this) {
    uoh => 5,
  };
}
