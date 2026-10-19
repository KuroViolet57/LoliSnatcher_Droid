part of '../search_handler.dart';

/// Seen posts (dimmed in the feed); doujin items go to the doujin history.
extension SearchSeenPosts on SearchHandler {
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

  /// [tab] is the tab the item actually belongs to — viewers opened off the
  /// current tab (floating previews) must pass their own, or history could be
  /// routed to the wrong store.
  Future<void> markPostSeen(BooruItem item, {SearchTab? tab}) async {
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
    // entry back to the top of the History feed). Doujin ITEMS go to the
    // doujin history store instead — never the booru ViewedPost table — no
    // matter which tab or viewer they were opened from.
    final SearchTab? owner = tab ?? (tabs.isNotEmpty ? currentTab : null);
    if ((owner?.booruHandler.hasReader ?? false) || DoujinDataHandler.isDoujinItem(item)) {
      final Booru? itemBooru = DoujinDataHandler.doujinBooruForItem(item) ?? owner?.selectedBooru.value;
      DoujinDataHandler.instance.addHistory(item, itemBooru);
      return;
    }
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
}
