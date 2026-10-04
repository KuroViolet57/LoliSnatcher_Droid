part of '../search_handler.dart';

/// Tab backup and restore (TabRestore table; JSON and the legacy format).
extension SearchTabBackup on SearchHandler {
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

          if (booruAndTags.length > 2 && booruAndTags[2] == 'selected') {
            final int index = splitInput.indexWhere((si) => si == booruAndTags);
            newIndex = index;
          }
        }
      }
    }
    // None of them can open here: keep this device's tabs (an empty tab
    // list breaks every screen that shows the current tab).
    if (restoredGlobals.isNotEmpty) {
      // reset current tab index to avoid exceptions when tab list length is different
      changeTabIndex(0, switchOnly: true);
      tabs.value = restoredGlobals;
      changeTabIndex(newIndex);
    }

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
          // An index into the restored tabs: an entry that failed to parse is skipped.
          newSelectedIndex = restoredTabs.length - 1;
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
          !tabs.any(
            (tab) =>
                tab.selectedBooru.value.name == newTab.selectedBooru.value.name &&
                // No merge sources reads as null on a restored tab and as []
                // on one whose sources were all switched off: the same tab.
                listEquals(
                  (tab.secondaryBoorus.value ?? const <Booru>[]).map((t) => t.name).toList(),
                  (newTab.secondaryBoorus.value ?? const <Booru>[]).map((t) => t.name).toList(),
                ) &&
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

    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);
      if (newTab.selectedBooru.value.name != null) {
        restoredTabs.add(newTab);

        if (newSelectedIndex == 0 && tabBackup.selected) {
          // An index into the restored tabs: tabs of sources missing here are skipped.
          newSelectedIndex = restoredTabs.length - 1;
        }
      }
    }
    // None of them can open here: keep this device's tabs (an empty tab
    // list breaks every screen that shows the current tab).
    if (restoredTabs.isNotEmpty) {
      // reset current tab index to avoid exceptions when tab list length is different
      changeTabIndex(0, switchOnly: true);
      tabs.value = restoredTabs;
      changeTabIndex(newSelectedIndex);
    }

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
            poolId: tab.poolId,
            poolName: tab.poolName,
            doujinPostURL: tab.doujinPostURL,
            doujinTitle: tab.doujinTitle,
            doujinThumb: tab.doujinThumb,
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
      // Passed to the constructor (not assigned after) so the pool handler is
      // rebuilt on restore — otherwise the tab would come back as a plain,
      // broken text search.
      poolId: (backup.poolId?.isEmpty ?? true) ? null : backup.poolId,
      poolName: (backup.poolName?.isEmpty ?? true) ? null : backup.poolName,
      doujinPostURL: (backup.doujinPostURL?.isEmpty ?? true) ? null : backup.doujinPostURL,
      doujinTitle: (backup.doujinTitle?.isEmpty ?? true) ? null : backup.doujinTitle,
      doujinThumb: (backup.doujinThumb?.isEmpty ?? true) ? null : backup.doujinThumb,
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
      // Heal group blocks that were split by pre-fix inserts: each group's
      // stray fragments are pulled back to its first occurrence.
      compactGroupBlocks();
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

    // 1.0: every 30 s this encoded every tab and rewrote the row even when
    // nothing had changed - a hitch on the UI thread with thousands of tabs.
    final int signature = _backupSignature();
    if (!_backupGate.shouldWrite(signature)) {
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
    _backupGate.written(signature);

    lastBackupTime = DateTime.now();
  }
}
