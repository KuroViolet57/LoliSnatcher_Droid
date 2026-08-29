import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_row.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// The doujin detail page's right-edge sidebar: a MINI tab manager.
/// Full working set — live tab list with group labels, text filter, switch,
/// close, jump-to-current — plus a button into the full manager.
class DoujinMiniTabManager extends StatefulWidget {
  const DoujinMiniTabManager({super.key});

  @override
  State<DoujinMiniTabManager> createState() => _DoujinMiniTabManagerState();
}

class _DoujinMiniTabManagerState extends State<DoujinMiniTabManager> {
  final searchHandler = SearchHandler.instance;
  final TextEditingController filterController = TextEditingController();

  @override
  void dispose() {
    filterController.dispose();
    super.dispose();
  }

  /// Switch to [tab] and unwind to the root so the grid (or the doujin tab
  /// content) is what the user lands on.
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
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
              child: Row(
                children: [
                  Icon(Symbols.tab_rounded, size: 18, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Tabs', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Open full tab manager',
                    icon: const Icon(Symbols.open_in_full_rounded, size: 20),
                    onPressed: _openFullManager,
                  ),
                ],
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
                final List<SearchTab> tabs = [
                  for (final t in searchHandler.tabs)
                    if (filter.isEmpty ||
                        t.tags.toLowerCase().contains(filter) ||
                        (t.groupName?.toLowerCase().contains(filter) ?? false))
                      t,
                ];
                if (tabs.isEmpty) {
                  return const Center(child: Text('No matching tabs'));
                }
                return ListView.builder(
                  itemCount: tabs.length,
                  itemBuilder: (context, i) {
                    final tab = tabs[i];
                    final bool isCurrent =
                        searchHandler.tabs.isNotEmpty && searchHandler.currentTab == tab;
                    final String? group = (tab.groupName?.isNotEmpty ?? false) ? tab.groupName : null;
                    final bool groupStart =
                        group != null && (i == 0 || tabs[i - 1].groupName != group);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (groupStart)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                            child: Text(
                              group,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        Material(
                          color: isCurrent
                              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => _switchTo(tab),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                              child: Row(
                                children: [
                                  Expanded(child: TabRow(tab: tab, filterText: filter.isEmpty ? null : filter)),
                                  IconButton(
                                    tooltip: 'Close tab',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Symbols.close_rounded, size: 18),
                                    onPressed: () => _closeTab(tab),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
