import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_row.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// The doujin detail page's right-edge sidebar: a MINI tab manager with the
/// same working set as the full one — switch, close, reorder, create, filter
/// and group operations — scoped by default to the domain you opened it from,
/// opening scrolled to (and highlighting) the current tab. The full manager
/// is one button away for everything else.
class DoujinMiniTabManager extends StatefulWidget {
  const DoujinMiniTabManager({super.key});

  /// Row metrics — fixed so the initial scroll offset can be computed without
  /// laying the list out first.
  static const double rowHeight = 56;
  static const double groupHeaderHeight = 26;

  @override
  State<DoujinMiniTabManager> createState() => _DoujinMiniTabManagerState();
}

class _DoujinMiniTabManagerState extends State<DoujinMiniTabManager> {
  final searchHandler = SearchHandler.instance;
  final TextEditingController filterController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  /// 'doujins' | 'boorus' | 'all'. Defaults to the domain of the tab this
  /// sidebar was opened from, so a doujin tab doesn't open onto thousands of
  /// booru tabs. The user can switch views by hand.
  late String sourceView = () {
    if (searchHandler.tabs.isEmpty) return 'all';
    return searchHandler.currentTab.booruHandler.hasReader ? 'doujins' : 'boorus';
  }();

  bool _didInitialScroll = false;

  @override
  void dispose() {
    filterController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  /// What a row actually SHOWS — the filter has to match that, not just the
  /// query string: a doujin tab displays its title, which comes from the
  /// fetched item when there is one and from the persisted field otherwise.
  String _labelOf(SearchTab tab) {
    if (tab.isDoujinDetail) {
      final items = tab.booruHandler.filteredFetched;
      if (items.isNotEmpty) {
        final String fromItem = (items.first.description ?? '')
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (fromItem.trim().isNotEmpty) return fromItem;
      }
      if (tab.doujinTitle?.isNotEmpty ?? false) return tab.doujinTitle!;
    }
    return tab.tags;
  }

  List<SearchTab> get _visibleTabs {
    final String filter = filterController.text.trim().toLowerCase();
    return [
      for (final t in searchHandler.tabs)
        if (switch (sourceView) {
          'doujins' => t.booruHandler.hasReader,
          'boorus' => !t.booruHandler.hasReader,
          _ => true,
        })
          if (filter.isEmpty ||
              _labelOf(t).toLowerCase().contains(filter) ||
              t.tags.toLowerCase().contains(filter) ||
              (t.groupName?.toLowerCase().contains(filter) ?? false))
            t,
    ];
  }

  bool _isGroupStart(List<SearchTab> tabs, int i) {
    final String? group = tabs[i].groupName;
    if (group == null || group.isEmpty) return false;
    return i == 0 || tabs[i - 1].groupName != group;
  }

  /// Scrolls so the current tab is visible the moment the drawer opens.
  void _scrollToCurrent(List<SearchTab> tabs) {
    if (_didInitialScroll || searchHandler.tabs.isEmpty) return;
    _didInitialScroll = true;
    final int index = tabs.indexOf(searchHandler.currentTab);
    if (index <= 0) return;

    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += DoujinMiniTabManager.rowHeight;
      if (_isGroupStart(tabs, i)) offset += DoujinMiniTabManager.groupHeaderHeight;
    }
    // Land the current row a little below the top rather than flush against it.
    offset = (offset - DoujinMiniTabManager.rowHeight * 2).clamp(0, double.infinity);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.jumpTo(offset.clamp(0, scrollController.position.maxScrollExtent));
    });
  }

  void _switchTo(SearchTab tab) {
    final int index = searchHandler.tabs.indexOf(tab);
    if (index < 0) return;
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      searchHandler.changeTabIndex(index);
    });
  }

  void _closeTab(SearchTab tab) {
    final int index = searchHandler.tabs.indexOf(tab);
    if (index < 0) return;
    searchHandler.removeTabAt(tabIndex: index);
    setState(() {});
  }

  /// Reorder inside the CURRENT view: positions are translated back to real
  /// tab-list indices through the tab objects, so dragging works the same in a
  /// scoped view as in the full list.
  void _reorder(List<SearchTab> tabs, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    // onReorderItem hands back a newIndex already adjusted for the removal.
    if (oldIndex < 0 || oldIndex >= tabs.length || newIndex < 0 || newIndex >= tabs.length) return;

    final int from = searchHandler.tabs.indexOf(tabs[oldIndex]);
    final int to = searchHandler.tabs.indexOf(tabs[newIndex]);
    if (from < 0 || to < 0) return;

    final SearchTab moved = tabs[oldIndex];
    searchHandler.moveTab(from, to);
    // A tab dragged into a group's block joins that group, matching the full
    // manager's behaviour.
    final int landed = searchHandler.tabs.indexOf(moved);
    final String? before = landed > 0 ? searchHandler.tabs[landed - 1].groupName : null;
    final String? after =
        landed < searchHandler.tabs.length - 1 ? searchHandler.tabs[landed + 1].groupName : null;
    if (before != null && before == after) moved.groupName = before;
    setState(() {});
  }

  Future<void> _newTab() async {
    if (searchHandler.tabs.isEmpty) return;
    searchHandler.addTabByString(
      '',
      customBooru: searchHandler.currentBooru,
      addMode: TabAddMode.next,
      group: SearchHandler.inheritGroup,
    );
    setState(() {});
  }

  Future<String?> _promptGroupName({String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final String? name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'New group' : 'Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.loc.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(context.loc.ok),
          ),
        ],
      ),
    );
    controller.dispose();
    return (name?.isEmpty ?? true) ? null : name;
  }

  Future<void> _newGroup() async {
    final String? name = await _promptGroupName();
    if (name == null) return;
    searchHandler.addTabByString(
      '',
      customBooru: searchHandler.currentBooru,
      addMode: TabAddMode.next,
      group: name,
    );
    setState(() {});
  }

  Future<void> _groupMenu(String groupName) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.w800)),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.add_rounded),
              title: const Text('New tab in group'),
              onTap: () => Navigator.of(ctx).pop('add'),
            ),
            ListTile(
              leading: const Icon(Symbols.edit_rounded),
              title: const Text('Rename group'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Symbols.layers_clear_rounded),
              title: const Text('Ungroup'),
              onTap: () => Navigator.of(ctx).pop('ungroup'),
            ),
            ListTile(
              leading: const Icon(Symbols.close_rounded, color: Colors.redAccent),
              title: const Text('Close group'),
              onTap: () => Navigator.of(ctx).pop('close'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'add':
        searchHandler.addTabByString(
          '',
          customBooru: searchHandler.currentBooru,
          addMode: TabAddMode.end,
          group: groupName,
        );
        break;
      case 'rename':
        final String? newName = await _promptGroupName(initial: groupName);
        if (newName != null && newName != groupName) {
          searchHandler.renameTabGroup(groupName, newName);
        }
        break;
      case 'ungroup':
        searchHandler.dissolveTabGroup(groupName);
        break;
      case 'close':
        final List<SearchTab> members = searchHandler.tabsInGroup(groupName);
        if (members.isEmpty) break;
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Close group "$groupName"?'),
            content: Text('${members.length} ${members.length == 1 ? 'tab' : 'tabs'} will be closed.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(context.loc.no)),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(context.loc.yes)),
            ],
          ),
        );
        if (confirmed == true) searchHandler.removeTabs(members);
        break;
    }
    if (mounted) setState(() {});
  }

  void _openFullManager() {
    Navigator.of(context).pop(); // the drawer
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const TabManagerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
              child: Row(
                children: [
                  Icon(Symbols.tab_rounded, size: 18, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Tabs', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    key: const Key('mini-manager-new-tab'),
                    tooltip: 'New tab',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.add_rounded, size: 20),
                    onPressed: _newTab,
                  ),
                  IconButton(
                    key: const Key('mini-manager-new-group'),
                    tooltip: 'New group',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.create_new_folder_rounded, size: 20),
                    onPressed: _newGroup,
                  ),
                  IconButton(
                    key: const Key('mini-manager-full'),
                    tooltip: 'Open full tab manager',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.open_in_full_rounded, size: 20),
                    onPressed: _openFullManager,
                  ),
                ],
              ),
            ),
            // Domain split — the same three views the full manager offers.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 'doujins', label: Text('Doujins', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'boorus', label: Text('Boorus', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'all', label: Text('All', style: TextStyle(fontSize: 11))),
                  ],
                  showSelectedIcon: false,
                  selected: {sourceView},
                  onSelectionChanged: (selection) {
                    setState(() {
                      sourceView = selection.first;
                      _didInitialScroll = false;
                    });
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                controller: filterController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter tabs',
                  prefixIcon: const Icon(Symbols.search_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: Obx(() {
                final String filter = filterController.text.trim().toLowerCase();
                final List<SearchTab> tabs = _visibleTabs;
                if (tabs.isEmpty) {
                  return const Center(child: Text('No matching tabs'));
                }
                _scrollToCurrent(tabs);

                Widget rowFor(int i) {
                  final tab = tabs[i];
                  final bool isCurrent = searchHandler.tabs.isNotEmpty && searchHandler.currentTab == tab;
                  final String? group = (tab.groupName?.isNotEmpty ?? false) ? tab.groupName : null;
                  final bool groupStart = _isGroupStart(tabs, i);

                  return Column(
                    key: ValueKey('mini-tab-${tab.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groupStart && group != null)
                        SizedBox(
                          height: DoujinMiniTabManager.groupHeaderHeight,
                          child: InkWell(
                            onTap: () => _groupMenu(group),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 8, 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: theme.colorScheme.secondary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Symbols.more_horiz_rounded,
                                    size: 14,
                                    color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: DoujinMiniTabManager.rowHeight,
                        child: Material(
                          color: isCurrent
                              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => _switchTo(tab),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TabRow(tab: tab, filterText: filter.isEmpty ? null : filter),
                                  ),
                                  IconButton(
                                    tooltip: 'Close tab',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Symbols.close_rounded, size: 18),
                                    onPressed: () => _closeTab(tab),
                                  ),
                                  // Drag handle — reordering while a text
                                  // filter hides rows would be guesswork, so
                                  // it only appears on the unfiltered list.
                                  if (filter.isEmpty)
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(
                                          Symbols.drag_indicator_rounded,
                                          size: 18,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (filter.isNotEmpty) {
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: tabs.length,
                    itemBuilder: (context, i) => rowFor(i),
                  );
                }

                return ReorderableListView.builder(
                  scrollController: scrollController,
                  buildDefaultDragHandles: false,
                  itemCount: tabs.length,
                  onReorderItem: (oldIndex, newIndex) => _reorder(tabs, oldIndex, newIndex),
                  itemBuilder: (context, i) => rowFor(i),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
