part of '../search_handler.dart';

/// Adding, removing, moving and switching tabs, and finding tabs by tag.
extension SearchTabs on SearchHandler {
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
    // Pool tabs carry the pool as tab state, since several sites can't express
    // "posts in pool N" as a search at all.
    String? poolId,
    String? poolName,
    // Doujin detail tabs: identity + cover of the doujin this tab IS. Set
    // them to make the new tab a real detail-page tab instead of an id:
    // search feed (see SearchTab.isDoujinDetail).
    String? doujinPostURL,
    String? doujinTitle,
    String? doujinThumb,
  }) {
    final Booru booru = customBooru ?? currentBooru;

    final String? groupName = identical(group, SearchHandler.inheritGroup)
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
      poolId: poolId,
      poolName: poolName,
      doujinPostURL: doujinPostURL,
      doujinTitle: doujinTitle,
      doujinThumb: doujinThumb,
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

    // record search query — doujin queries go to the doujin store, booru
    // queries to store.db (SearchHistoryStore routes by source). Opening a
    // doujin DETAIL tab isn't a search, so its `id:<n>` query is not history.
    if (searchText != '' && doujinPostURL == null && SearchHandler.isPlainSearch(searchText)) {
      unawaited(SearchHistoryStore.record(searchText, booru));
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
      // Every tab is gone, so the current tab's source is read from the tab
      // kept above (currentBooru would read an empty list).
      final Booru booru = curTab.selectedBooru.value;
      final String defaultText = booru.defTags?.isNotEmpty == true
          ? booru.defTags!
          : settingsHandler.defTags;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(booru, null, defaultText);
      if (tabs.value.isEmpty) {
        tabs.value.add(newTab);
      } else {
        tabs.value[0] = newTab;
      }
      changeTabIndex(0);
    } else {
      final newIndex = tabs.value.indexWhere((t) => t.id == curTab.id);
      changeTabIndex(newIndex == -1 ? total - 1 : newIndex);
    }

    // The list was changed in place: tell its listeners (tab pill, tab
    // cards, tab count) once the current index points into it again.
    tabs.value = [...tabs];
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
    } else if (toIndex == currentIndex && fromIndex > currentIndex) {
      // if a later tab moved into the place of the current tab, bump index of current tab
      changeTabIndex(toIndex + 1);
    } else if (fromIndex < currentIndex && toIndex >= currentIndex) {
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
      Tools.trimMemoryCacheIfFull();
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
    // The same tab on another page: it keeps its overrides, its pool and its
    // doujin identity, and stays in its group.
    final SearchTab newTab = SearchTab(
      currentBooru,
      currentSecondaryBoorus.value,
      currentTab.tags,
      tabId: currentTab.id,
      tagOverrides: Map<String, String>.from(currentTab.tagOverrides),
      inheritMainTags: Map<String, bool>.from(currentTab.inheritMainTags),
      poolId: currentTab.poolId,
      poolName: currentTab.poolName,
      doujinPostURL: currentTab.doujinPostURL,
      doujinTitle: currentTab.doujinTitle,
      doujinThumb: currentTab.doujinThumb,
    );
    newTab.groupName = currentTab.groupName;
    newTab.booruHandler.pageNum = newPageNum;
    pageNum.value = newPageNum;
    tabs[currentIndex] = newTab;

    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
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

  // run search on current tab
  /// Re-points every open tab at an edited booru config.
  ///
  /// Called after a booru is saved in the editor. Tabs match by name (the
  /// booru's identity in configs and tab backups); only a changed type or
  /// base URL forces a handler rebuild, so ordinary edits (favicon, API key)
  /// don't throw away loaded results.
  void applyBooruEdit(Booru updated) {
    if (updated.name?.isEmpty ?? true) return;

    bool changedAny = false;
    for (final tab in tabs) {
      final Booru current = tab.selectedBooru.value;
      if (current.name != updated.name) continue;
      final bool needsRebuild = current.type != updated.type || current.baseURL != updated.baseURL;
      if (needsRebuild) {
        tab.rebuildHandler(updated);
        changedAny = true;
        Logger.Inst().log(
          'rebuilt tab handler for "${updated.name}": ${current.type?.name} -> ${updated.type?.name}',
          'SearchHandler',
          'applyBooruEdit',
          LogTypes.booruHandlerInfo,
        );
      } else {
        // Same API, new details (key, favicon, ...) — just adopt the object.
        tab.selectedBooru.value = updated;
      }
    }

    if (changedAny) {
      tabs.value = [...tabs];
      if (tabs.isNotEmpty) {
        unawaited(runSearch());
      }
    }
  }
}
