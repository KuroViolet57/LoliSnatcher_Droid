part of '../search_handler.dart';

/// Tab groups.
extension SearchTabGroups on SearchHandler {
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

  /// Makes every group's tabs contiguous: each group's block sits where the
  /// group first appears, fragments (from pre-snapping inserts) are folded
  /// into it in their existing relative order. Ungrouped tabs keep their
  /// positions relative to each other. No-op when nothing is fragmented.
  void compactGroupBlocks() {
    if (tabs.isEmpty) return;
    final SearchTab current = currentTab;

    final List<SearchTab> result = [];
    final Set<String> doneGroups = {};
    for (final tab in tabs) {
      final String? g = (tab.groupName?.isNotEmpty ?? false) ? tab.groupName : null;
      if (g == null) {
        result.add(tab);
      } else if (doneGroups.add(g)) {
        result.addAll(tabs.where((t) => t.groupName == g));
      }
    }

    bool changed = false;
    for (int i = 0; i < tabs.length; i++) {
      if (!identical(tabs[i], result[i])) {
        changed = true;
        break;
      }
    }
    if (!changed) return;

    tabs.value = result;
    final int newIndex = tabs.indexOf(current);
    changeTabIndex(newIndex == -1 ? 0 : newIndex);
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
}
