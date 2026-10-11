part of '../search_handler.dart';

/// Running a search and loading pages (runSearch increments pageNum before the first fetch).
extension SearchPaging on SearchHandler {
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

  void filterCurrentFetched() {
    if (tabs.isNotEmpty) {
      currentBooruHandler.filterFetched();
    }
  }

  // runs search on current tab
  // [isRefresh]: the same query again (pull to refresh), which is not a new
  // search for the search history or the taste profile.
  Future<void> searchAction(
    String text,
    Booru? newBooru, {
    bool isRefresh = false,
    String? mediaFilter,
  }) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // Remove extra spaces
    text = text.trim();

    // Record the search as a taste signal (skip virtual/local feeds AND
    // doujin sources — doujin activity must not feed the booru For You).
    // With no tab yet, the search opens one on the first source (below).
    final Booru? actionBooru =
        newBooru ??
        (tabs.isNotEmpty
            ? currentBooru
            : (settingsHandler.booruList.isNotEmpty ? settingsHandler.booruList[0] : null));
    final BooruType? actionType = actionBooru?.type;
    if (!isRefresh &&
        actionBooru != null &&
        text.isNotEmpty &&
        actionType?.isLocalDb != true &&
        actionType?.isRecommendationFeed != true &&
        !DoujinDataHandler.isDoujinBooru(actionBooru) &&
        SearchHandler.isPlainSearch(text)) {
      InterestsHandler.instance.onSearch(text, booru: actionBooru);
    }

    // clear image memory cache
    Tools.forceClearMemoryCache(withLive: true);

    // set new tab data
    if (tabs.isEmpty) {
      // No source to open a tab on: nothing to search.
      if (actionBooru == null) return;
      final SearchTab newTab = SearchTab(
        actionBooru,
        null, // no current tab to take merge sources from
        text,
      );
      if (mediaFilter != null) newTab.booruHandler.mediaFilter = mediaFilter;
      tabs.add(newTab);
    } else {
      // Preserve per-booru tag overrides + inherit flags across the tab swap
      // so the user's search-bar tap doesn't wipe edits they made.
      final Map<String, String> carriedOverrides = Map<String, String>.from(currentTab.tagOverrides);
      final Map<String, bool> carriedInherit = Map<String, bool>.from(currentTab.inheritMainTags);
      // Retry on a doujin detail tab re-runs the same `id:` query. Dropping
      // doujinPostURL here used to throw away the gallery key that survives
      // a restart. A genuinely new query is no longer that tab.
      final bool keepDoujin =
          currentTab.isDoujinDetail && text.trim().toLowerCase() == currentTab.tags.trim().toLowerCase();
      final SearchTab newTab = SearchTab(
        newBooru ?? currentBooru,
        currentSecondaryBoorus.value,
        text,
        tabId: currentTab.id, // keep the same tab identity across the search change
        tagOverrides: carriedOverrides,
        inheritMainTags: carriedInherit,
        doujinPostURL: keepDoujin ? currentTab.doujinPostURL : null,
        doujinTitle: keepDoujin ? currentTab.doujinTitle : null,
        doujinThumb: keepDoujin ? currentTab.doujinThumb : null,
      );
      // In-place search change keeps the tab in its group.
      newTab.groupName = currentTab.groupName;
      if (mediaFilter != null) newTab.booruHandler.mediaFilter = mediaFilter;
      tabs[currentIndex] = newTab;
      // The user changed this tab's search while viewing it — update its
      // visited-history entry in place (same id) instead of duplicating.
      recordTabVisit(newTab);
    }

    unawaited(searchReactions(text, newBooru ?? currentBooru));

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);

    // write to history (doujin searches never reach the booru history table)
    if (!isRefresh && text != '' && SearchHandler.isPlainSearch(text)) {
      unawaited(SearchHistoryStore.record(text, newBooru ?? currentBooru));
    }
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
    // Toggling merge sources keeps the tab in its group.
    newTab.groupName = currentTab.groupName;
    tabs[currentIndex] = newTab;

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  Future<void> runSearch() async {
    final startTabId = currentTab.id;
    // do nothing if reached the end or detected an error
    if (isLastPage.value || errorString.isNotEmpty) {
      return;
    }

    final BooruHandler handler = currentBooruHandler;
    for (int pages = 1; ; pages++) {
      final int visibleBefore = handler.filteredFetched.length;

      // if not last page - set loading state and increment page
      if (!handler.locked) {
        isLoading.value = true;
        handler.pageNum++;
        pageNum++;
      }

      // fetch new items, but get results from booruHandler and not search itself
      await handler.search(currentTab.tags, null);

      // A tab switched to meanwhile already shows its own state
      // (changeTabIndex), so only this tab's handler writes it.
      final bool sameTab = currentTab.id == startTabId && identical(currentBooruHandler, handler);
      if (sameTab) {
        // lock new loads if handler detected last page
        // (previous filteredFetched length == current length)
        if (handler.locked && !isLastPage.value) {
          isLastPage.value = true;
        }

        if (handler.errorString.isNotEmpty) {
          errorString.value = handler.errorString;
        }
      }

      if (!sameTab || !SearchHandler.ownListLoadsMore(handler, visibleBefore: visibleBefore, pages: pages)) break;
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
}
