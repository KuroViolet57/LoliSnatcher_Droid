import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:get/get.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/core/ui/image/custom_network_image.dart';
import 'package:lolisnatcher/sources/local/mergebooru_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/ui/buttons/cancel_button.dart';
import 'package:lolisnatcher/core/ui/buttons/delete_button.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/kaomoji/kaomoji.dart';
import 'package:lolisnatcher/core/ui/loli_dropdown.dart';
import 'package:lolisnatcher/core/ui/text/marquee_text.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/core/ui/image/booru_favicon.dart';
import 'package:lolisnatcher/features/feed/ui/main_appbar.dart';
import 'package:lolisnatcher/core/ui/booru_selector_item.dart';
import 'package:lolisnatcher/features/tabs/ui/manager/tab_filters_dialog.dart';
import 'package:lolisnatcher/features/tabs/ui/manager/tab_move_dialog.dart';
import 'package:lolisnatcher/features/tabs/ui/widgets/tab_row.dart';

part 'tab_selector/tab_selector_button.dart';
part 'tab_selector/tab_manager_item.dart';
part 'tab_selector/sorting.dart';
part 'tab_selector/visited_tabs_history.dart';

class TabManagerPage extends StatefulWidget {
  const TabManagerPage({super.key});

  @override
  State<TabManagerPage> createState() => _TabManagerPageState();
}

class _TabManagerPageState extends State<TabManagerPage> with TraceLifecycle {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  List<SearchTab> tabs = [], filteredTabs = [], selectedTabs = [];
  late final ScrollController scrollController;

  final TextEditingController filterTextController = TextEditingController();
  TabSortingMode sortingMode = TabSortingMode.none;
  bool? loadedFilter;
  Booru? booruFilter;
  TagType? tagTypeFilter;
  bool duplicateFilter = false, duplicateBooruFilter = true, emptyFilter = false;
  bool? isMultiBooruMode;
  bool selectMode = false;

  /// The three-view source toggle: 'doujins' | 'boorus' | 'all'. Defaults by
  /// CONTEXT — opened from a doujin tab it shows doujin tabs, from a booru
  /// tab the booru ones; 'all' shows everything. Groups work in all three.
  late String sourceView = () {
    if (searchHandler.tabs.isEmpty) return 'all';
    return searchHandler.currentTab.booruHandler.hasReader ? 'doujins' : 'boorus';
  }();

  // App-session persistence of the sort + filter state. The tab manager is a
  // transient page (built on each open), and the user reported that the sort
  // mode and filters reset every time it's reopened. Stashing them on the
  // class itself survives close/reopen while the app is running.
  static TabSortingMode _savedSortingMode = TabSortingMode.none;
  static bool? _savedLoadedFilter;
  static Booru? _savedBooruFilter;
  static TagType? _savedTagTypeFilter;
  static bool _savedDuplicateFilter = false;
  static bool _savedDuplicateBooruFilter = true;
  static bool _savedEmptyFilter = false;
  static bool? _savedIsMultiBooruMode;
  static String _savedFilterText = '';

  void _persistSortingMode() {
    _savedSortingMode = sortingMode;
  }

  void _persistFilters() {
    _savedLoadedFilter = loadedFilter;
    _savedBooruFilter = booruFilter;
    _savedTagTypeFilter = tagTypeFilter;
    _savedDuplicateFilter = duplicateFilter;
    _savedDuplicateBooruFilter = duplicateBooruFilter;
    _savedEmptyFilter = emptyFilter;
    _savedIsMultiBooruMode = isMultiBooruMode;
    _savedFilterText = filterTextController.text;
  }

  static const double tabHeight = 72 + 8;
  // Fixed height of the inline group header row — rows must have known
  // heights so scroll-to-index math stays exact.
  static const double groupHeaderHeight = 44;

  // Collapsed groups (chevron on the header). Survives close/reopen of the
  // manager within the app session.
  static final Set<String> _collapsedGroups = {};

  bool _isGroupCollapsed(String? g) => g != null && _collapsedGroups.contains(g);

  void _toggleGroupCollapsed(String groupName) {
    setState(() {
      if (!_collapsedGroups.remove(groupName)) {
        _collapsedGroups.add(groupName);
      }
    });
  }

  // Display cache: the display list, per-row extents and prefix offsets are
  // computed together in one O(n) pass and then read O(1) from anywhere.
  // itemExtentBuilder queries extents per index during EVERY layout/scroll
  // frame, so recomputing the display list per query (as a plain getter did)
  // was O(n²) with a group collapsed — with thousands of tabs that froze
  // swiping. The cache is invalidated at the top of build(); any data change
  // (filtering, collapse toggle, group edits, reorder) goes through
  // setState/Obx and thus rebuilds before the next layout reads it.
  List<SearchTab>? _displayCache;
  List<double>? _extentCache;
  List<double>? _offsetCache; // prefix sums, length n+1

  void _invalidateDisplayCache() {
    _displayCache = null;
    _extentCache = null;
    _offsetCache = null;
  }

  void _ensureDisplayCache() {
    if (_displayCache != null) return;

    // Rows actually rendered: filteredTabs minus the member rows of collapsed
    // groups (a collapsed group keeps only its run-start header row). Omitting
    // the members entirely — rather than giving them zero extent — is what
    // keeps a collapsed group from leaving a tall dead bordered gap.
    final List<SearchTab> out;
    if (_collapsedGroups.isEmpty) {
      out = filteredTabs;
    } else {
      out = [];
      for (int i = 0; i < filteredTabs.length; i++) {
        final String? g = (filteredTabs[i].groupName?.isNotEmpty ?? false) ? filteredTabs[i].groupName : null;
        if (g != null && _collapsedGroups.contains(g)) {
          final bool runStart = i == 0 || filteredTabs[i - 1].groupName != g;
          if (!runStart) continue; // hide members; keep only the header row
        }
        out.add(filteredTabs[i]);
      }
    }

    // Extents + prefix offsets in the same pass. A collapsed group's single
    // header row is header-height only; a normal run-start carries header +
    // tab; other rows are one tab tall. Exact known heights keep the
    // fixed-extent fast path and scroll-to-index math correct.
    final List<double> extents = List<double>.filled(out.length, tabHeight);
    final List<double> offsets = List<double>.filled(out.length + 1, 0);
    String? prevGroup;
    for (int i = 0; i < out.length; i++) {
      final String? g = (out[i].groupName?.isNotEmpty ?? false) ? out[i].groupName : null;
      final double rowH = TabRow.isDoujinTab(out[i]) ? TabManagerItem.doujinRowHeight : tabHeight;
      final double extent;
      if (g != null && _collapsedGroups.contains(g)) {
        extent = groupHeaderHeight;
      } else if (g != null && g != prevGroup) {
        extent = rowH + groupHeaderHeight;
      } else {
        extent = rowH;
      }
      extents[i] = extent;
      offsets[i + 1] = offsets[i] + extent;
      prevGroup = g;
    }

    _displayCache = out;
    _extentCache = extents;
    _offsetCache = offsets;
  }

  List<SearchTab> get displayTabs {
    _ensureDisplayCache();
    return _displayCache!;
  }

  double rowExtentForIndex(int index) {
    _ensureDisplayCache();
    if (index < 0 || index >= _extentCache!.length) return tabHeight;
    return _extentCache![index];
  }

  void _jumpToGroup(String groupName) {
    final int idx = displayTabs.indexWhere((t) => t.groupName == groupName);
    if (idx == -1 || !scrollController.hasClients) return;
    scrollController.animateTo(
      offsetForTabIndex(idx).clamp(0, scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // Scroll offset of the display row at [index] = sum of extents above it.
  double offsetForTabIndex(int index) {
    _ensureDisplayCache();
    final List<double> offsets = _offsetCache!;
    if (offsets.length <= 1) return 0;
    return offsets[index.clamp(0, offsets.length - 1)];
  }

  int get totalTabs => searchHandler.total;
  int get totalFilteredTabs => filteredTabs.length;
  bool get isFilterActive => totalFilteredTabs != totalTabs || filterTextController.text.isNotEmpty || filtersCount > 0;
  int get currentTabIndex => displayTabs.indexOf(searchHandler.currentTab);

  int get filtersCount {
    int count = 0;
    if (loadedFilter != null) {
      count++;
    }
    if (booruFilter != null) {
      count++;
    }
    if (tagTypeFilter != null) {
      count++;
    }
    if (duplicateFilter) {
      count++;
    }
    if (isMultiBooruMode != null) {
      count++;
    }
    if (emptyFilter) {
      count++;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();

    // Restore the persisted sort + filter state from the previous open.
    sortingMode = _savedSortingMode;
    loadedFilter = _savedLoadedFilter;
    booruFilter = _savedBooruFilter;
    tagTypeFilter = _savedTagTypeFilter;
    duplicateFilter = _savedDuplicateFilter;
    duplicateBooruFilter = _savedDuplicateBooruFilter;
    emptyFilter = _savedEmptyFilter;
    isMultiBooruMode = _savedIsMultiBooruMode;
    filterTextController.text = _savedFilterText;

    // Heal any group blocks split by pre-fix inserts before rendering.
    searchHandler.compactGroupBlocks();

    getTabs();

    scrollController = ScrollController(
      initialScrollOffset: currentTabIndex <= 0 ? 0 : offsetForTabIndex(currentTabIndex),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await jumpToCurrent();
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    filterTextController.dispose();
    super.dispose();
  }

  void getTabs() {
    tabs = searchHandler.tabs;
    filteredTabs = tabs;
    filterTabs();

    setState(() {});
  }

  Future<void> jumpToCurrent({bool animated = false}) async {
    if (scrollController.hasClients) {
      if (currentTabIndex == -1) {
        return;
      }

      // final double viewport = scrollController.position.viewportDimension;
      final double maxScroll = scrollController.position.maxScrollExtent;
      final double itemOffset = offsetForTabIndex(currentTabIndex);
      double scrollOffset = 0;
      if (itemOffset > maxScroll) {
        scrollOffset = maxScroll;
      } else {
        scrollOffset = itemOffset;
      }

      if (animated) {
        await scrollController.animateTo(
          scrollOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        scrollController.jumpTo(scrollOffset);
      }
    }
  }

  void scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToCurrent(animated: true);
    });
  }

  void jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.jumpTo(0);
    });
  }

  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void filterTabs() {
    filteredTabs = [...tabs];

    // Source view: doujin tabs and booru tabs live in separate views (with
    // 'all' as the everything view).
    if (sourceView == 'doujins') {
      filteredTabs = filteredTabs.where((t) => t.booruHandler.hasReader).toList();
    } else if (sourceView == 'boorus') {
      filteredTabs = filteredTabs.where((t) => !t.booruHandler.hasReader).toList();
    }

    if (booruFilter != null) {
      filteredTabs = filteredTabs.where((t) => t.selectedBooru.value == booruFilter).toList();
    }

    if (loadedFilter != null) {
      filteredTabs = filteredTabs
          .where(
            (t) => loadedFilter == true
                ? t.booruHandler.filteredFetched.isNotEmpty
                : t.booruHandler.filteredFetched.isEmpty,
          )
          .toList();
    }

    if (tagTypeFilter != null) {
      filteredTabs = filteredTabs.where((tab) {
        // Tag types come from the shared BOORU store, so a doujin tab can
        // never be classified by it — filtering by type is a booru filter.
        if (DoujinDataHandler.isDoujinBooru(tab.selectedBooru.value)) return false;
        final List<String> tags = tab.tags.toLowerCase().trim().split(' ');
        for (final tag in tags) {
          if (tagHandler.getTag(tag).tagType == tagTypeFilter) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    if (duplicateFilter) {
      // tabs where booru and tags are the same
      final Map<String, List<SearchTab>> freqMap = {};

      for (final tab in filteredTabs) {
        final tags = tab.tags.toLowerCase().trim();
        final key = duplicateBooruFilter ? '${tab.selectedBooru.value.name}+$tags' : tags;

        if (freqMap.containsKey(key)) {
          freqMap[key]!.add(tab);
        } else {
          freqMap[key] = [tab];
        }
      }

      final List<SearchTab> duplicateTabs = freqMap.entries
          .where((e) => e.value.length > 1)
          .expand<SearchTab>((e) => e.value)
          .toList();
      filteredTabs = searchHandler.tabs.where(duplicateTabs.contains).toList();
    }

    if (isMultiBooruMode != null) {
      filteredTabs = filteredTabs
          .where(
            (tab) => isMultiBooruMode == false
                ? (tab.secondaryBoorus.value?.isEmpty ?? true)
                : tab.secondaryBoorus.value?.isNotEmpty == true,
          )
          .toList();
    }

    if (emptyFilter) {
      filteredTabs = filteredTabs.where((tab) => tab.tags.trim().isEmpty).toList();
    }

    if (filterTextController.text.isNotEmpty) {
      filteredTabs = filteredTabs.where((t) {
        final String filterText = filterTextController.text.toLowerCase().trim();
        // Matches the query OR the tab's group name, so typing "disney"
        // narrows the list to that group.
        return t.tags.toLowerCase().contains(filterText) ||
            (t.groupName?.toLowerCase().contains(filterText) ?? false);
      }).toList();
    }

    if (!sortingMode.isNone) {
      filteredTabs.sort(
        (a, b) {
          final cleanAtags = a.tags.toLowerCase().trim();
          final cleanBtags = b.tags.toLowerCase().trim();

          final aBooru = a.selectedBooru.value;
          final bBooru = b.selectedBooru.value;

          if (sortingMode.isAnyBooru && aBooru.name != bBooru.name) {
            if (sortingMode.isAnyReverse) {
              return bBooru.name!.compareTo(aBooru.name!);
            } else {
              return aBooru.name!.compareTo(bBooru.name!);
            }
          }

          // "By booru, open order" modes group by booru name but keep tabs
          // inside each group in the order they were opened (searchHandler
          // insertion index). Skip the alphabetic-within-group comparison so
          // the index fallback below decides ordering.
          if (!sortingMode.isAnyBooruOpenOrder && cleanAtags != cleanBtags) {
            if (sortingMode.isAnyReverse && !sortingMode.isAnyBooru) {
              return cleanBtags.compareTo(cleanAtags);
            } else {
              return cleanAtags.compareTo(cleanBtags);
            }
          }

          return searchHandler.tabs.indexOf(a).compareTo(searchHandler.tabs.indexOf(b));
        },
      );
    }
  }

  Future<void> openFiltersDialog() async {
    final String? result = await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      page: (_) => TabManagerFiltersDialog(
        loadedFilter: loadedFilter,
        loadedFilterChanged: (bool? newValue) {
          loadedFilter = newValue;
        },
        booruFilter: booruFilter,
        booruFilterChanged: (Booru? newValue) {
          booruFilter = newValue;
        },
        tagTypeFilter: tagTypeFilter,
        tagTypeFilterChanged: (TagType? newValue) {
          tagTypeFilter = newValue;
        },
        duplicateFilter: duplicateFilter,
        duplicateFilterChanged: (bool newValue) {
          duplicateFilter = newValue;
          if (!duplicateFilter) {
            duplicateBooruFilter = true;
          }
        },
        duplicateBooruFilter: duplicateBooruFilter,
        duplicateBooruFilterChanged: (bool newValue) {
          duplicateBooruFilter = newValue;
        },
        isMultiBooruMode: isMultiBooruMode,
        isMultiBooruModeChanged: (bool? newValue) {
          isMultiBooruMode = newValue;
        },
        emptyFilter: emptyFilter,
        emptyFilterChanged: (bool newValue) {
          emptyFilter = newValue;
        },
      ),
    ).open();

    if (result == 'apply') {
      if (duplicateFilter) {
        sortingMode = TabSortingMode.alphabet;
      }
    }
    // A dismissed sheet (result == null) changes nothing, the sort included.
    if (result == 'clear' ||
        (result != null &&
            loadedFilter == null &&
            booruFilter == null &&
            tagTypeFilter == null &&
            duplicateFilter == false &&
            isMultiBooruMode == null &&
            emptyFilter == false)) {
      loadedFilter = null;
      booruFilter = null;
      tagTypeFilter = null;
      duplicateFilter = false;
      duplicateBooruFilter = true;
      isMultiBooruMode = null;
      emptyFilter = false;

      if (!sortingMode.isNone) {
        sortingMode = TabSortingMode.none;
      }
    }

    if (result != null) {
      _persistFilters();
      _persistSortingMode();
      getTabs();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (filteredTabs.contains(searchHandler.currentTab) && !duplicateFilter) {
          jumpToCurrent();
        } else {
          scrollToTop();
        }
      });
    }
  }

  /// Groups the current tab list by the same key the duplicate filter uses
  /// and returns the tabs that should be removed to leave exactly one copy of
  /// each duplicate (the earliest-opened — i.e. the one with the lowest index
  /// in [SearchHandler.tabs]).
  List<SearchTab> _computeDuplicateTabsToRemove() {
    final Map<String, List<SearchTab>> groups = {};
    for (final tab in searchHandler.tabs) {
      final tags = tab.tags.toLowerCase().trim();
      final key = duplicateBooruFilter ? '${tab.selectedBooru.value.name}+$tags' : tags;
      (groups[key] ??= []).add(tab);
    }

    final List<SearchTab> toRemove = [];
    for (final entry in groups.entries) {
      if (entry.value.length <= 1) continue;
      // Keep the earliest-opened tab (smallest index). entry.value already
      // arrived in insertion order because we iterated searchHandler.tabs
      // top-down — drop everything past the first.
      toRemove.addAll(entry.value.skip(1));
    }
    return toRemove;
  }

  Future<void> removeDuplicateTabs() async {
    final List<SearchTab> toRemove = _computeDuplicateTabsToRemove();
    if (toRemove.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove duplicate tabs'),
        content: Text(
          'Keep one copy of each duplicate and delete the other ${toRemove.length}? '
          'The earliest-opened copy in each group is kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Symbols.delete_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    searchHandler.removeTabs(toRemove);
    getTabs();
  }

  Widget filterBuild() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The three-view source toggle — always visible so the split between
        // doujin tabs and booru tabs is one tap away.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: 'doujins',
                  label: Text('Doujins'),
                  icon: Icon(Symbols.menu_book_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'boorus',
                  label: Text('Boorus & other'),
                  icon: Icon(Symbols.image_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'all',
                  label: Text('All'),
                  icon: Icon(Symbols.select_all_rounded, size: 16),
                ),
              ],
              selected: {sourceView},
              onSelectionChanged: (selection) {
                sourceView = selection.first;
                getTabs();
              },
            ),
          ),
        ),
        _filterRowBuild(),
      ],
    );
  }

  Widget _filterRowBuild() {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      width: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: SettingsTextInput(
              title: context.loc.search,
              titleAsLabel: true,
              controller: filterTextController,
              inputType: TextInputType.text,
              clearable: true,
              pasteable: true,
              onlyInput: true,
              drawBottomBorder: false,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              // margin: const EdgeInsets.fromLTRB(2, 8, 2, 5),
              onChanged: (_) {
                _savedFilterText = filterTextController.text;
                getTabs();
              },
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
          ),
          const SizedBox(width: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                iconSize: 30,
                onPressed: openFiltersDialog,
                icon: const Icon(Symbols.filter_alt_rounded),
              ),
              if (filtersCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: openFiltersDialog,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Center(
                        child: Text(
                          filtersCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget proxyDecorator(Widget child, int index, Animation<double> animation) {
    return child;
  }

  // After a drag, sync the moved tab's group with its new neighbours:
  // dropped inside a group block -> join it; dragged away from its own
  // group's block -> leave it; hovering at a block's edge -> keep as-is.
  void _normalizeMovedTabGroup(int newIndex) {
    final int idx = newIndex.clamp(0, searchHandler.total - 1);
    final SearchTab moved = searchHandler.tabs[idx];
    final String? prevG = idx > 0 ? searchHandler.tabs[idx - 1].groupName : null;
    final String? nextG = idx < searchHandler.total - 1 ? searchHandler.tabs[idx + 1].groupName : null;
    if (prevG != null && prevG == nextG) {
      moved.groupName = prevG;
    } else if (moved.groupName != null && moved.groupName != prevG && moved.groupName != nextG) {
      moved.groupName = null;
    }
  }

  Future<String?> _promptGroupName({String? initial}) async {
    final TextEditingController controller = TextEditingController(text: initial ?? '');
    final String? name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'New tab group' : 'Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(initial == null ? 'Create' : 'Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _createNewGroup() async {
    final String? name = await _promptGroupName();
    if (name == null) return;
    // A group is its tabs — creating one starts it off with a fresh empty
    // tab on the current booru, placed right after the active tab so the new
    // block appears where the user is looking.
    searchHandler.addTabByString(
      '',
      customBooru: searchHandler.currentBooru,
      addMode: TabAddMode.next,
      group: name,
    );
    getTabs();
  }

  void _addTabToGroup(String groupName) {
    searchHandler.addTabByString(
      '',
      customBooru: searchHandler.currentBooru,
      addMode: TabAddMode.end,
      group: groupName,
    );
    getTabs();
  }

  Future<void> _onGroupMenuAction(String groupName, String action) async {
    switch (action) {
      case 'rename':
        final String? newName = await _promptGroupName(initial: groupName);
        if (newName != null && newName != groupName) {
          searchHandler.renameTabGroup(groupName, newName);
          getTabs();
        }
        break;
      case 'ungroup':
        searchHandler.dissolveTabGroup(groupName);
        getTabs();
        break;
      case 'close':
        final List<SearchTab> members = searchHandler.tabsInGroup(groupName);
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Close group "$groupName"?'),
            content: Text('${members.length} ${members.length == 1 ? 'tab' : 'tabs'} will be closed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.loc.no),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(context.loc.yes),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          selectedTabs.removeWhere(members.contains);
          searchHandler.removeTabs(members);
          getTabs();
        }
        break;
    }
  }

  // Select mode: move the selected tabs into an existing or freshly named
  // group.
  Future<void> _addSelectedToGroup() async {
    if (selectedTabs.isEmpty) return;

    final List<String> groups = searchHandler.tabGroupNames;
    const String newGroupSentinel = ' new-group';
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${selectedTabs.length} ${selectedTabs.length == 1 ? 'tab' : 'tabs'} to group'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final g in groups)
                ListTile(
                  leading: Icon(Symbols.folder_open_rounded, color: Theme.of(ctx).colorScheme.secondary),
                  title: Text(g),
                  subtitle: Text(
                    '${searchHandler.tabsInGroup(g).length} ${searchHandler.tabsInGroup(g).length == 1 ? 'tab' : 'tabs'}',
                  ),
                  onTap: () => Navigator.of(ctx).pop(g),
                ),
              ListTile(
                leading: const Icon(Symbols.add_rounded, color: Colors.green),
                title: const Text('New group…'),
                onTap: () => Navigator.of(ctx).pop(newGroupSentinel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.loc.cancel),
          ),
        ],
      ),
    );
    if (chosen == null) return;

    String groupName = chosen;
    if (chosen == newGroupSentinel) {
      final String? name = await _promptGroupName();
      if (name == null) return;
      groupName = name;
    }

    searchHandler.moveTabsToGroup([...selectedTabs], groupName);
    setState(() {
      selectedTabs.clear();
      selectMode = false;
    });
    getTabs();

    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'tabs_grouped',
      duration: const Duration(seconds: 2),
      title: Text('Added to group "$groupName"', style: const TextStyle(fontSize: 20)),
      leadingIcon: Symbols.create_new_folder_rounded,
      sideColor: Colors.green,
    );
  }

  Widget _groupHeader(BuildContext context, String groupName) {
    final theme = Theme.of(context);
    final int count = searchHandler.tabsInGroup(groupName).length;
    final bool collapsed = _isGroupCollapsed(groupName);
    return Container(
      height: groupHeaderHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 0),
      child: Row(
        children: [
          // Collapse/expand — the name area toggles too.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleGroupCollapsed(groupName),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Symbols.chevron_right_rounded : Symbols.expand_more_rounded,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Icon(Symbols.folder_open_rounded, size: 17, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'New tab in this group',
            icon: const Icon(Symbols.add_rounded),
            onPressed: () => _addTabToGroup(groupName),
          ),
          PopupMenuButton<String>(
            iconSize: 18,
            tooltip: 'Group options',
            onSelected: (action) => _onGroupMenuAction(groupName, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'ungroup', child: Text('Ungroup (keep tabs)')),
              PopupMenuItem(value: 'close', child: Text('Close all tabs')),
            ],
          ),
        ],
      ),
    );
  }

  Widget itemBuilder(BuildContext context, int index) {
    final List<SearchTab> d = displayTabs;
    final SearchTab tab = d[index];

    final bool isCurrent = tab == searchHandler.currentTab;
    final bool isSelected = selectedTabs.contains(tab);

    // Group-block framing: a run of consecutive same-group tabs renders
    // inside one bordered container, with the header above the first row.
    // Neighbours are read from the DISPLAY list so a collapsed group (only
    // its header row present) always reads as a self-contained single-row
    // block (run start AND end).
    final String? groupName = (tab.groupName?.isNotEmpty ?? false) ? tab.groupName : null;
    final String? prevGroup = index > 0 && (d[index - 1].groupName?.isNotEmpty ?? false)
        ? d[index - 1].groupName
        : null;
    final String? nextGroup = index < d.length - 1 && (d[index + 1].groupName?.isNotEmpty ?? false)
        ? d[index + 1].groupName
        : null;
    final bool isRunStart = groupName != null && groupName != prevGroup;
    final bool isRunEnd = groupName != null && groupName != nextGroup;

    final Widget tabItem = TabManagerItem(
        tab: tab,
        index: index,
        isFiltered: isFilterActive || !sortingMode.isNone,
        originalIndex: (isFilterActive || !sortingMode.isNone) ? searchHandler.tabs.indexOf(tab) : null,
        isCurrent: isCurrent,
        filterText: filterTextController.text,
        onTap: selectMode
            ? () {
                if (isSelected || isCurrent) {
                  selectedTabs.removeWhere((item) => item == tab);
                } else {
                  selectedTabs.add(tab);
                }
                setState(() {});
              }
            : () {
                searchHandler.changeTabIndex(
                  searchHandler.tabs.indexOf(tab),
                  byUser: true,
                );
                Navigator.of(context).pop();
              },
        optionsWidgetBuilder: selectMode
            ? (_, onTap) {
                if (isCurrent) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (bool? newValue) {
                      if (isSelected) {
                        selectedTabs.removeWhere((item) => item == tab);
                      } else {
                        selectedTabs.add(tab);
                      }
                      setState(() {});
                    },
                  ),
                );
              }
            : null,
        onOptionsTap: () {
          if (!selectMode) {
            showOptionsDialog(index);
          }
        },
        onCloseTap: selectMode
            ? null
            : () {
                selectedTabs.remove(tab);
                searchHandler.removeTabAt(tabIndex: searchHandler.tabs.indexOf(tab));
                getTabs();
              },
    );

    Widget row = tabItem;
    if (groupName != null && _isGroupCollapsed(groupName)) {
      // Collapsed group: only the header row is in the display list, rendered
      // as a self-contained framed header (members are omitted entirely).
      final theme = Theme.of(context);
      final Color frame = theme.colorScheme.secondary.withValues(alpha: 0.55);
      return ReorderableDelayedDragStartListener(
        key: ValueKey('item-${tab.id}'),
        index: index,
        enabled: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            _groupHeader(context, groupName),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: frame, width: 1.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (groupName != null) {
      final theme = Theme.of(context);
      final Color frame = theme.colorScheme.secondary.withValues(alpha: 0.55);
      final BorderRadius radius = BorderRadius.vertical(
        top: Radius.circular(isRunStart ? 16 : 0),
        bottom: Radius.circular(isRunEnd ? 16 : 0),
      );
      // The frame is painted as overlays (tint below, border above) instead
      // of a bordered Container, so the row's height stays EXACTLY what
      // itemExtentBuilder promises.
      row = Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.05),
                  borderRadius: radius,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRunStart) _groupHeader(context, groupName),
              // The row's own height, as _ensureDisplayCache gave it (104
              // for a doujin row, 80 otherwise).
              SizedBox(height: TabRow.isDoujinTab(tab) ? TabManagerItem.doujinRowHeight : tabHeight, child: tabItem),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: frame, width: 1.4),
                    right: BorderSide(color: frame, width: 1.4),
                    top: isRunStart ? BorderSide(color: frame, width: 1.4) : BorderSide.none,
                    bottom: isRunEnd ? BorderSide(color: frame, width: 1.4) : BorderSide.none,
                  ),
                  borderRadius: radius,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ReorderableDelayedDragStartListener(
      key: ValueKey('item-${tab.id}'),
      index: index,
      // Reorder disabled while any group is collapsed so display/real indices
      // stay 1:1 (moveTab works on the real tab list).
      enabled: !selectMode && !isFilterActive && sortingMode.isNone && _collapsedGroups.isEmpty,
      child: row,
    );
  }

  void showOptionsDialog(int index) {
    final SearchTab tab = displayTabs[index];
    final int originalIndex = searchHandler.tabs.indexOf(tab);

    final Widget optionsDialog = SettingsDialog(
      scrollable: false,
      contentItems: [
        TabManagerItem(
          tab: tab,
          index: index,
          isFiltered: isFilterActive || !sortingMode.isNone,
          originalIndex: (isFilterActive || !sortingMode.isNone) ? originalIndex : null,
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: tab.tags));
            FlashElements.showSnackbar(
              context: context,
              duration: const Duration(seconds: 2),
              title: Text(context.loc.copiedToClipboard, style: const TextStyle(fontSize: 20)),
              content: Text(tab.tags, style: const TextStyle(fontSize: 16)),
              leadingIcon: Symbols.content_copy_rounded,
              sideColor: Colors.green,
            );
            Navigator.of(context).pop();
          },
          leading: const Icon(Symbols.content_copy_rounded),
          title: Text(context.loc.tabs.copy),
        ),
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) => TabMoveDialog(
                row: TabManagerItem(
                  tab: tab,
                  index: searchHandler.tabs.indexOf(tab),
                  isFiltered: false,
                  originalIndex: null,
                ),
                index: searchHandler.tabs.indexOf(tab),
              ),
            );
            getTabs();
          },
          leading: const Icon(Symbols.move_down_rounded),
          title: Text(context.loc.tabs.moveAction),
        ),
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () {
            // indexOf is -1 once the tab is gone, and removeTabAt(-1) closes
            // the CURRENT tab: remove only a tab that is still open.
            final int tabIndex = searchHandler.tabs.indexOf(tab);
            if (tabIndex != -1) {
              selectedTabs.remove(tab);
              searchHandler.removeTabAt(tabIndex: tabIndex);
              getTabs();
            }
            Navigator.of(context).pop();
          },
          leading: const Icon(Symbols.close_rounded, color: Colors.red),
          title: Text(context.loc.tabs.remove),
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () {
            Navigator.of(context).pop();
          },
          leading: const Icon(Symbols.cancel_rounded),
          title: Text(context.loc.close),
        ),
        const SizedBox(height: 10),
        // TODO more stuff?
      ],
    );

    showDialog(
      context: context,
      builder: (BuildContext context) => optionsDialog,
    );
  }

  void showDeleteDialog() {
    if (selectedTabs.isEmpty) {
      return;
    }

    // sort selected tabs in order of appearance in the list instead of order of selection
    selectedTabs.sort((a, b) => searchHandler.tabs.indexOf(a).compareTo(searchHandler.tabs.indexOf(b)));

    final Widget deleteDialog = SettingsDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.loc.tabs.deleteTabs),
          Text(
            context.loc.tabs.areYouSureDeleteTabs(count: selectedTabs.length),
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      scrollable: false,
      content: Container(
        height: MediaQuery.sizeOf(context).height * 0.75,
        width: double.maxFinite,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: ListView.builder(
          clipBehavior: Clip.hardEdge,
          shrinkWrap: true,
          itemCount: selectedTabs.length,
          itemBuilder: (_, index) {
            final item = selectedTabs[index];

            final int itemIndex = searchHandler.tabs.indexOf(item);

            return TabManagerItem(
              tab: item,
              index: index,
              isFiltered: true,
              originalIndex: itemIndex,
            );
          },
        ),
      ),
      actionButtons: [
        const CancelButton(withIcon: true),
        DeleteButton(
          withIcon: true,
          action: () {
            searchHandler.removeTabs(selectedTabs);
            selectedTabs.clear();
            getTabs();
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    showDialog(
      context: context,
      builder: (_) => deleteDialog,
    );
  }

  // Opens the tab a history entry points to. Jumps to it if it's still open
  // (matched by tab id); otherwise re-opens a fresh tab with the same query
  // and booru.
  Booru? _booruByName(String name) {
    for (final b in settingsHandler.booruList) {
      if (b.name == name) return b;
    }
    return null;
  }

  void _openVisitedTab(TabVisit visit) {
    final int existingIndex = searchHandler.tabs.indexWhere((t) => t.id == visit.tabId);
    if (existingIndex != -1) {
      searchHandler.changeTabIndex(existingIndex, byUser: true);
    } else {
      final Booru? booru = _booruByName(visit.booruName);
      // Re-open a closed tab right next to the active one (not at the end),
      // reusing the history entry's id so it maps back to the SAME history
      // entry instead of spawning a duplicate once it's tapped/recorded.
      searchHandler.addTabByString(
        visit.tags,
        customBooru: booru,
        switchToNew: true,
        addMode: TabAddMode.next,
        tabId: visit.tabId,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void showVisitHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: const Text('Visited tabs history'),
          contentItems: [
            Obx(() {
              // most-recent first
              return VisitedTabsHistoryList(
                entries: searchHandler.visitedTabsHistory.reversed.toList(),
                isStillOpen: (visit) => searchHandler.tabs.any((t) => t.id == visit.tabId),
                booruFor: _booruByName,
                timeLabel: _formatVisitTime,
                onOpen: _openVisitedTab,
              );
            }),
          ],
          actionButtons: [
            if (searchHandler.visitedTabsHistory.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Symbols.delete_rounded),
                label: const Text('Clear'),
                onPressed: () {
                  searchHandler.clearVisitedTabsHistory();
                  Navigator.of(context).pop();
                },
              ),
            const CancelButton(withIcon: true),
          ],
        );
      },
    );
  }

  String _formatVisitTime(DateTime t) {
    final Duration diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: Text(context.loc.tabs.tabsManager),
          contentItems: [
            Text(context.loc.tabs.scrolling),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.subdirectory_arrow_left_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.scrollToCurrent)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.arrow_circle_up_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.scrollToTop)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.arrow_circle_down_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.scrollToBottom)),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Symbols.filter_alt_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.filterTabsByBooru)),
              ],
            ),
            const Divider(),
            Text(context.loc.tabs.sorting),
            const SizedBox(height: 6),
            Row(
              children: [
                const TabSortingIcon(TabSortingMode.none, withBorder: true),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.defaultTabsOrder)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const TabSortingIcon(TabSortingMode.alphabet, withBorder: true),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.sortAlphabetically)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const TabSortingIcon(TabSortingMode.alphabetReverse, withBorder: true),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.sortAlphabeticallyReversed)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const TabSortingIcon(TabSortingMode.booru, withBorder: true),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.sortByBooruName)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const TabSortingIcon(TabSortingMode.booruReverse, withBorder: true),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.sortByBooruNameReversed)),
              ],
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                TabSortingIcon(TabSortingMode.booruOpenOrder, withBorder: true),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Group by booru, keep tabs in the order they were opened'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                TabSortingIcon(TabSortingMode.booruOpenOrderReverse, withBorder: true),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Same, with booru groups in reverse alphabetical order'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.loc.tabs.longPressSortToSave),
            const Divider(),
            Text(context.loc.tabs.select),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.select_all_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.toggleSelectMode)),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.loc.tabs.onTheBottomOfPage),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.select_all_rounded),
                const Text(' / '),
                const Icon(Symbols.border_clear_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.selectDeselectAll)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Symbols.delete_forever_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(context.loc.tabs.deleteSelectedTabs)),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Symbols.expand_rounded),
                const SizedBox(width: 10),
                Text(context.loc.tabs.longPressToMove),
              ],
            ),
            const Divider(),
            Text(context.loc.tabs.numbersInBottomRight),
            // TODO
            Text(context.loc.tabs.firstNumberTabIndex),
            Text(context.loc.tabs.secondNumberTabIndex),
            const Divider(),
            Text(context.loc.tabs.specialFilters),
            Text(context.loc.tabs.loadedFilter),
            Text(context.loc.tabs.notLoadedFilter),
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(text: context.loc.tabs.notLoadedItalic.replaceAll('italic', '')),
                  const TextSpan(
                    text: 'italic',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const TextSpan(text: ' text'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Any state change that could affect rows/extents rebuilds this widget
    // first (setState/Obx), so refreshing the cache here keeps every
    // per-frame extent/offset query O(1) against fresh data.
    _invalidateDisplayCache();
    return Scaffold(
      appBar: AppBar(
        // r66: two lines need more than the default 56 px, or the title is
        // pushed above the screen edge and cut.
        toolbarHeight: 64,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.tabs.tabsManager,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            RichText(
              text: TextSpan(
                // r66: the count is drawn ON the app bar, so it takes the
                // bar's own text colour; onPrimary is the colour for text on
                // the accent and read as black on the dark bar.
                style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                  color: (Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onSurface)
                      .withValues(alpha: 0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                children: [
                  if (isFilterActive) ...[
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Symbols.filter_alt_rounded, size: 16),
                    ),
                    TextSpan(text: '${totalFilteredTabs.toFormattedString()}/'),
                  ],
                  TextSpan(text: totalTabs.toFormattedString()),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Jump to a group's block in the list.
          if (searchHandler.tabGroupNames.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Symbols.folder_open_rounded),
              tooltip: 'Jump to group',
              onSelected: _jumpToGroup,
              itemBuilder: (_) => [
                for (final g in searchHandler.tabGroupNames)
                  PopupMenuItem(
                    value: g,
                    child: Text('$g (${searchHandler.tabsInGroup(g).length})'),
                  ),
              ],
            ),
          IconButton(
            icon: const Icon(Symbols.create_new_folder_rounded),
            tooltip: 'New tab group',
            onPressed: _createNewGroup,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Symbols.select_all_rounded),
            tooltip: context.loc.tabs.selectMode,
            onPressed: () {
              setState(() {
                selectMode = !selectMode;
                selectedTabs.clear();
              });
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onLongPress: isFilterActive
                ? null
                : () async {
                    final currentTab = searchHandler.currentTab;

                    final res = await showDialog(
                      context: context,
                      builder: (context) {
                        return SettingsDialog(
                          title: Text(sortingMode.isNone ? context.loc.tabs.shuffleTabs : context.loc.tabs.sortMode),
                          contentItems: [
                            Text(
                              sortingMode.isNone
                                  ? context.loc.tabs.shuffleTabsQuestion
                                  : context.loc.tabs.saveTabsInCurrentOrder,
                            ),
                            if (!sortingMode.isNone)
                              Text(
                                '${sortingMode.isAnyBooru ? context.loc.tabs.byBooru : ''} ${context.loc.tabs.alphabetically} ${sortingMode.isAnyReverse ? context.loc.tabs.reversed : ''}'
                                    .trim(),
                              ),
                          ],
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              label: Text(sortingMode.isNone ? context.loc.tabs.shuffle : context.loc.tabs.sort),
                              icon: TabSortingIcon(sortingMode),
                              onPressed: () {
                                Navigator.of(context).pop('allow');
                              },
                            ),
                          ],
                        );
                      },
                    );

                    if (res != 'allow') {
                      return;
                    }

                    if (sortingMode.isNone) {
                      // randomly shuffle all filtered tabs
                      filteredTabs.shuffle();

                      FlashElements.showSnackbar(
                        context: context,
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tabs.tabRandomlyShuffled, style: const TextStyle(fontSize: 20)),
                        leadingIcon: Symbols.sort_by_alpha_rounded,
                        sideColor: Colors.green,
                      );
                    } else {
                      FlashElements.showSnackbar(
                        context: context,
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tabs.tabOrderSaved, style: const TextStyle(fontSize: 20)),
                        leadingIcon: Symbols.sort_rounded,
                        sideColor: Colors.green,
                      );
                    }

                    searchHandler.tabs.value = [...filteredTabs];

                    final int newIndex = searchHandler.tabs.indexOf(currentTab);
                    searchHandler.changeTabIndex(newIndex);

                    getTabs();
                  },
            child: IconButton(
              icon: TabSortingIcon(sortingMode),
              tooltip: context.loc.tabs.sortMode,
              onPressed: () {
                switch (sortingMode) {
                  case TabSortingMode.none:
                    sortingMode = TabSortingMode.alphabet;
                    break;
                  case TabSortingMode.alphabet:
                    sortingMode = TabSortingMode.alphabetReverse;
                    break;
                  case TabSortingMode.alphabetReverse:
                    sortingMode = TabSortingMode.booru;
                    break;
                  case TabSortingMode.booru:
                    sortingMode = TabSortingMode.booruReverse;
                    break;
                  case TabSortingMode.booruReverse:
                    sortingMode = TabSortingMode.booruOpenOrder;
                    break;
                  case TabSortingMode.booruOpenOrder:
                    sortingMode = TabSortingMode.booruOpenOrderReverse;
                    break;
                  case TabSortingMode.booruOpenOrderReverse:
                    sortingMode = TabSortingMode.none;
                    break;
                }
                _persistSortingMode();
                getTabs();
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Symbols.history_rounded),
            tooltip: 'Visited tabs history',
            onPressed: showVisitHistoryDialog,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Symbols.help_center_rounded),
            tooltip: context.loc.tabs.help,
            onPressed: showHelpDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          filterBuild(),
          // Visible only when the duplicate filter is on. One tap removes
          // every extra copy of each duplicate group (keeping the
          // earliest-opened tab).
          if (duplicateFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: removeDuplicateTabs,
                  icon: const Icon(Symbols.cleaning_services_rounded),
                  label: const Text('Remove all duplicates (keep one copy)'),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Scrollbar(
                  controller: scrollController,
                  thickness: 8,
                  interactive: true,
                  scrollbarOrientation: settingsHandler.handSide.value.isLeft
                      ? ScrollbarOrientation.left
                      : ScrollbarOrientation.right,
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    // Per-index extents keep the O(1) fixed-extent layout path
                    // (fast jumps/flings even with thousands of tabs) while
                    // letting run-start rows carry the inline group header.
                    itemExtentBuilder: (index, dimensions) => rowExtentForIndex(index),
                    onReorderItem: (oldIndex, newIndex) {
                      if (oldIndex == newIndex) {
                        return;
                      }
                      // Reorder is only enabled when no group is collapsed,
                      // so displayTabs == filteredTabs == tabs here and the
                      // indices map 1:1.
                      searchHandler.moveTab(oldIndex, newIndex);
                      _normalizeMovedTabGroup(newIndex);
                      getTabs();
                    },
                    buildDefaultDragHandles: false,
                    proxyDecorator: proxyDecorator,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: displayTabs.length,
                    itemBuilder: itemBuilder,
                  ),
                ),
                if (totalFilteredTabs == 0)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Kaomoji(
                          category: KaomojiCategory.indifference,
                          style: TextStyle(fontSize: 36),
                        ),
                        Text(
                          context.loc.tabs.noTabsFound,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              const double iconSize = 28;

              final toTopBtn = ElevatedButton(
                onPressed: scrollToTop,
                child: const Icon(
                  Symbols.arrow_circle_up_rounded,
                  size: iconSize,
                ),
              );

              final filteredTabsMinusCurrent = [...filteredTabs]..remove(searchHandler.currentTab);
              final selectedAll = selectedTabs.length == filteredTabsMinusCurrent.length;

              final selectAllBtn = ElevatedButton(
                onPressed: () {
                  if (selectedAll) {
                    selectedTabs.clear();
                  } else {
                    selectedTabs = [...filteredTabs];
                    selectedTabs.remove(searchHandler.currentTab);
                  }
                  setState(() {});
                },
                child: Icon(
                  selectedAll ? Symbols.border_clear_rounded : Symbols.select_all_rounded,
                  size: iconSize,
                ),
              );

              final toCurrentBtn = ElevatedButton(
                onPressed: currentTabIndex != -1 ? scrollToCurrent : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Symbols.subdirectory_arrow_left_rounded,
                      size: iconSize,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      (searchHandler.currentIndex + 1).toFormattedString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: currentTabIndex == -1 ? Colors.transparent : null,
                      ),
                    ),
                  ],
                ),
              );

              final bool hasSelected = selectedTabs.isNotEmpty;
              final deleteSelectedBtn = ElevatedButton(
                onPressed: hasSelected ? showDeleteDialog : null,
                child: Row(
                  children: [
                    const Icon(
                      Symbols.delete_forever_rounded,
                      size: iconSize,
                    ),
                    const SizedBox(width: 4),
                    Stack(
                      children: [
                        Text(
                          selectedTabs.length.toFormattedString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          '00',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.transparent),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final toBottomBtn = ElevatedButton(
                onPressed: scrollToBottom,
                child: const Icon(
                  Symbols.arrow_circle_down_rounded,
                  size: iconSize,
                ),
              );

              final groupSelectedBtn = ElevatedButton(
                onPressed: hasSelected ? _addSelectedToGroup : null,
                child: const Icon(
                  Symbols.create_new_folder_rounded,
                  size: iconSize,
                ),
              );

              return Container(
                margin: EdgeInsets.fromLTRB(
                  10,
                  10,
                  10,
                  10 + MediaQuery.paddingOf(context).bottom,
                ),
                width: double.infinity,
                child: Row(
                  children: [
                    if (settingsHandler.handSide.value.isLeft) ...[
                      if (selectMode) ...[
                        selectAllBtn,
                        const SizedBox(width: 6),
                        groupSelectedBtn,
                        const SizedBox(width: 6),
                        deleteSelectedBtn,
                        const SizedBox(width: 6),
                      ] else ...[
                        toBottomBtn,
                        const SizedBox(width: 6),
                        toCurrentBtn,
                        const SizedBox(width: 6),
                        toTopBtn,
                        const SizedBox(width: 6),
                      ],
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(
                          Symbols.close_rounded,
                          size: iconSize,
                        ),
                        label: AutoSizeText(
                          context.loc.close,
                          maxLines: 1,
                          overflowReplacement: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    if (settingsHandler.handSide.value.isRight) ...[
                      if (selectMode) ...[
                        const SizedBox(width: 6),
                        deleteSelectedBtn,
                        const SizedBox(width: 6),
                        groupSelectedBtn,
                        const SizedBox(width: 6),
                        selectAllBtn,
                      ] else ...[
                        const SizedBox(width: 6),
                        toTopBtn,
                        const SizedBox(width: 6),
                        toCurrentBtn,
                        const SizedBox(width: 6),
                        toBottomBtn,
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
