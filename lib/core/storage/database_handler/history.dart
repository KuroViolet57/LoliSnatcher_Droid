part of '../database_handler.dart';

String _syncText(Object? value) {
  if (value == null) return '';
  final String text = value.toString();
  return text == 'null' ? '' : text;
}

/// Tab backup, search history, saved searches, visited tabs, seen and viewed posts.
extension DBHistory on DBHandler {
  Future<String?> getTabRestore() async {
    final result = await db?.rawQuery('SELECT id, restore FROM TabRestore ORDER BY id DESC LIMIT 1;');
    String? restoreItem;
    if (result != null && result.isNotEmpty) {
      restoreItem = result[0]['restore'].toString();
    }
    return restoreItem;
  }

  Future<void> removeTabRestore(String id) async {
    await db?.rawDelete('DELETE FROM TabRestore WHERE id=?;', [id]);
    return;
  }

  /// Get search history entries
  Future<List<HistoryItem>> getSearchHistory() async {
    final metaData = await db?.rawQuery('SELECT * FROM SearchHistory GROUP BY searchText, booruName ORDER BY id DESC');
    final List<Map<String, dynamic>> result = [];
    metaData?.forEach((s) {
      result.add({
        'id': s['id'],
        'searchText': s['searchText'].toString(),
        'booruType': s['booruType'].toString(),
        'booruName': s['booruName'].toString(),
        'isFavourite': s['isFavourite'].toString(),
        'timestamp': s['timestamp'].toString(),
      });
    });
    return List.from(result.map(HistoryItem.fromMap));
  }

  Future<List<HistoryItem>> getLatestSearchHistory() async {
    final metaData = await db?.rawQuery(
      'SELECT * FROM (SELECT * FROM SearchHistory ORDER BY timestamp DESC LIMIT 20)',
    );
    final List<Map<String, dynamic>> result = [];
    metaData?.forEach((s) {
      result.add({
        'id': s['id'],
        'searchText': s['searchText'].toString(),
        'booruType': s['booruType'].toString(),
        'booruName': s['booruName'].toString(),
        'isFavourite': s['isFavourite'].toString(),
        'timestamp': s['timestamp'].toString(),
      });
    });
    return List.from(result.map(HistoryItem.fromMap));
  }

  Future<List<String>> getSearchHistoryByInput(String queryStr, int limit) async {
    final List<String> tags = [];
    final result = await db?.rawQuery(
      'SELECT DISTINCT searchText FROM SearchHistory WHERE lower(searchText) LIKE (?) LIMIT $limit',
      ['${queryStr.toLowerCase()}%'],
    );
    if (result != null && result.isNotEmpty) {
      for (int i = 0; i < result.length; i++) {
        tags.add(result[i]['searchText'].toString());
      }
    }
    return tags;
  }

  /// Delete entry from search history (if no id given - clears everything)
  Future<void> deleteFromSearchHistory(int? id) async {
    if (id != null) {
      await db?.rawDelete('DELETE FROM SearchHistory WHERE id IN (?)', [id]);
    } else {
      await db?.rawDelete('DELETE FROM SearchHistory WHERE id IS NOT NULL');
    }
    return;
  }

  /// Set/unset search history entry as favourite
  Future<void> setFavouriteSearchHistory(int id, bool isFavourite) async {
    await db?.rawUpdate('UPDATE SearchHistory SET isFavourite = ? WHERE id = ?', [Tools.boolToInt(isFavourite), id]);
    return;
  }

  ///////
  /// Saved searches (quick-search favourites)

  Future<int?> addSavedSearch(SavedSearch entry) async {
    return db?.rawInsert(
      'INSERT INTO SavedSearch(name, payload, createdAt) VALUES(?, ?, ?)',
      [entry.name, entry.payloadJson(), entry.createdAt.millisecondsSinceEpoch],
    );
  }

  Future<List<SavedSearch>> getSavedSearches() async {
    final rows = await db?.rawQuery('SELECT * FROM SavedSearch ORDER BY createdAt DESC');
    if (rows == null || rows.isEmpty) return const [];
    return rows.map(SavedSearch.fromRow).whereType<SavedSearch>().toList(growable: false);
  }

  Future<void> deleteSavedSearch(int id) async {
    await db?.rawDelete('DELETE FROM SavedSearch WHERE id = ?', [id]);
  }

  Future<void> renameSavedSearch(int id, String name) async {
    await db?.rawUpdate('UPDATE SavedSearch SET name = ? WHERE id = ?', [name, id]);
  }

  /// Every history row, including ones the grouped history page hides.
  /// A null booru type or name is an empty string so a sync can match it.
  Future<List<({String searchText, String booruType, String booruName, bool favourite})>> listSearchHistoryKeys() async {
    final rows = await db?.rawQuery('SELECT searchText, booruType, booruName, isFavourite FROM SearchHistory');
    if (rows == null) return const [];
    return [
      for (final Map<String, Object?> row in rows)
        (
          searchText: row['searchText']?.toString() ?? '',
          booruType: _syncText(row['booruType']),
          booruName: _syncText(row['booruName']),
          favourite: row['isFavourite']?.toString() == '1',
        ),
    ];
  }

  /// A row that arrived from another phone. The history cap is not applied
  /// here; the next search the user types still applies it.
  Future<void> insertSyncedSearchHistory({
    required String searchText,
    required String booruType,
    required String booruName,
    required bool favourite,
    required String timestamp,
  }) async {
    final int flag = Tools.boolToInt(favourite);
    if (timestamp.trim().isEmpty) {
      await db?.rawInsert(
        'INSERT INTO SearchHistory(searchText, booruType, booruName, isFavourite) VALUES(?,?,?,?)',
        [searchText, booruType, booruName, flag],
      );
      return;
    }
    await db?.rawInsert(
      'INSERT INTO SearchHistory(searchText, booruType, booruName, isFavourite, timestamp) VALUES(?,?,?,?,?)',
      [searchText, booruType, booruName, flag, timestamp],
    );
  }

  /// Marks every copy of this search. Does not clear a favourite.
  Future<void> markSearchHistoryFavourite({
    required String searchText,
    required String booruType,
    required String booruName,
  }) async {
    await db?.rawUpdate(
      "UPDATE SearchHistory SET isFavourite = 1 WHERE searchText = ? AND ifnull(booruType, '') = ? AND ifnull(booruName, '') = ?",
      [searchText, booruType, booruName],
    );
  }

  ///////
  /// Visited tabs history (tabs the user personally opened by tapping)

  Future<void> addTabVisit({
    required String tabId,
    required String tags,
    required String booruName,
    required String? booruType,
    required int visitedAt,
  }) async {
    await db?.rawInsert(
      'INSERT INTO TabVisitHistory(tabId, tags, booruName, booruType, visitedAt) VALUES(?, ?, ?, ?, ?)',
      [tabId, tags, booruName, booruType, visitedAt],
    );
  }

  // Oldest-first, so callers can append straight into an in-memory list.
  Future<List<Map<String, Object?>>> getTabVisits() async {
    final rows = await db?.rawQuery('SELECT * FROM TabVisitHistory ORDER BY visitedAt ASC, id ASC');
    return rows ?? const [];
  }

  Future<void> deleteTabVisit(String tabId) async {
    await db?.rawDelete('DELETE FROM TabVisitHistory WHERE tabId = ?', [tabId]);
  }

  Future<void> clearTabVisits() async {
    await db?.rawDelete('DELETE FROM TabVisitHistory');
  }

  // Keep only the newest [keep] rows.
  Future<void> trimTabVisits(int keep) async {
    await db?.rawDelete(
      'DELETE FROM TabVisitHistory WHERE id NOT IN '
      '(SELECT id FROM TabVisitHistory ORDER BY visitedAt DESC, id DESC LIMIT ?)',
      [keep],
    );
  }

  Future<Set<String>> getSeenPostKeys() async {
    final rows = await db?.rawQuery('SELECT postKey FROM SeenPost');
    if (rows == null || rows.isEmpty) return <String>{};
    return rows.map((r) => r['postKey']?.toString() ?? '').where((k) => k.isNotEmpty).toSet();
  }

  Future<void> addSeenPost(String postKey) async {
    if (postKey.isEmpty) return;
    await db?.rawInsert(
      'INSERT OR REPLACE INTO SeenPost(postKey, viewedAt) VALUES(?, ?)',
      [postKey, DateTime.now().millisecondsSinceEpoch],
    );
    // Best-effort trim of the oldest rows once over the cap.
    await db?.rawDelete(
      'DELETE FROM SeenPost WHERE postKey NOT IN '
      '(SELECT postKey FROM SeenPost ORDER BY viewedAt DESC LIMIT ${DBHandler._seenPostLimit})',
    );
  }

  Future<void> clearSeenPosts() async {
    await db?.rawDelete('DELETE FROM SeenPost');
  }

  Future<void> addViewedPost(String postKey, String itemJson) async {
    if (postKey.isEmpty || itemJson.isEmpty) return;
    // INSERT OR REPLACE so a re-view bumps the entry back to the top.
    await db?.rawInsert(
      'INSERT OR REPLACE INTO ViewedPost(postKey, itemJson, viewedAt) VALUES(?, ?, ?)',
      [postKey, itemJson, DateTime.now().millisecondsSinceEpoch],
    );
    await db?.rawDelete(
      'DELETE FROM ViewedPost WHERE postKey NOT IN '
      '(SELECT postKey FROM ViewedPost ORDER BY viewedAt DESC LIMIT ${DBHandler._viewedPostLimit})',
    );
  }

  // Builds the WHERE clause for a space-separated filter: every term must
  // appear somewhere in the stored item JSON (tags, URLs, artist...). Crude
  // but effective for a local history search.
  (String, List<String>) _viewedPostFilter(String filter) {
    final terms = filter.toLowerCase().split(' ').where((t) => t.trim().isNotEmpty).toList();
    if (terms.isEmpty) return ('', const []);
    final String where = 'WHERE ${List.filled(terms.length, 'LOWER(itemJson) LIKE ?').join(' AND ')}';
    return (where, [for (final t in terms) '%$t%']);
  }

  Future<List<BooruItem>> getViewedPosts(String filter, int offset, int limit) async {
    final (String where, List<String> args) = _viewedPostFilter(filter);
    final rows = await db?.rawQuery(
      'SELECT itemJson FROM ViewedPost $where ORDER BY viewedAt DESC LIMIT $limit OFFSET $offset',
      args,
    );
    if (rows == null || rows.isEmpty) return [];
    final List<BooruItem> items = [];
    for (final row in rows) {
      final BooruItem? item = DBHandler.deserializeHistoryItem(row['itemJson']!.toString());
      // Skip rows that fail to deserialize (e.g. written by a newer build).
      if (item != null && item.fileURL.isNotEmpty) {
        items.add(item);
      }
    }
    return items;
  }

  Future<int> countViewedPosts(String filter) async {
    final (String where, List<String> args) = _viewedPostFilter(filter);
    final rows = await db?.rawQuery('SELECT COUNT(*) as c FROM ViewedPost $where', args);
    if (rows == null || rows.isEmpty) return 0;
    return int.tryParse(rows.first['c']?.toString() ?? '') ?? 0;
  }

  Future<void> clearViewedPosts() async {
    await db?.rawDelete('DELETE FROM ViewedPost');
  }

  /// Removes the History-feed row only. SeenPost (grid dimming) is left
  /// alone: it's a per-post key set, not a history surface.
  Future<void> deleteViewedPost(String postKey) async {
    await db?.rawDelete('DELETE FROM ViewedPost WHERE postKey = ?', [postKey]);
  }
}
