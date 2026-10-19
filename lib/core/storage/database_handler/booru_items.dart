part of '../database_handler.dart';

/// Posts (BooruItem) and their favourite/snatched flags: the Favourites and Downloads lists, local search, tracked values.
extension DBBooruItems on DBHandler {
  /// Inserts a new booruItem or updates the isSnatched and isFavourite values of an existing BooruItem in the database
  Future<String?> updateBooruItem(BooruItem item, BooruUpdateMode mode) async {
    Logger.Inst().log(
      'updateBooruItem called fileURL is: ${item.fileURL}',
      'DBHandler',
      'updateBooruItem',
      LogTypes.booruHandlerInfo,
    );
    String? itemID = await getItemID(item.postURL);
    String resultStr = '';
    // Doujin favourites live in the doujin store, never in store.db — a
    // snatched doujin must not surface in the booru Favourites feed, and its
    // tags must not seed the booru DB autocomplete. isSnatched IS shared
    // (downloads are one system), so the row itself still gets written.
    final bool isDoujin = DoujinDataHandler.isDoujinItem(item);
    final int favouriteFlag = Tools.boolToInt(!isDoujin && item.isFavourite.value == true);
    final int? snatchedAt = item.isSnatched.value == true ? DateTime.now().millisecondsSinceEpoch : null;
    if (itemID == null || itemID.isEmpty) {
      final result = await db?.rawInsert(
        'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite, snatchedAt) VALUES(?,?,?,?,?,?,?,?)',
        [
          item.thumbnailURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          item.sampleURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          item.fileURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          item.postURL,
          item.mediaType.toJson(),
          Tools.boolToInt(item.isSnatched.value == true),
          favouriteFlag,
          snatchedAt,
        ],
      );
      itemID = result?.toString();
      if (!isDoujin) {
        await updateTags(item.tagsList.map((t) => t.fullString).toList(), itemID);
      }
      resultStr = 'Inserted';
    } else if (mode == BooruUpdateMode.local) {
      await db?.rawUpdate(
        'UPDATE BooruItem SET isSnatched = ?, isFavourite = ?, '
        'snatchedAt = CASE WHEN ? = 1 THEN COALESCE(snatchedAt, ?) ELSE NULL END WHERE id = ?',
        [
          Tools.boolToInt(item.isSnatched.value == true),
          favouriteFlag,
          Tools.boolToInt(item.isSnatched.value == true),
          DateTime.now().millisecondsSinceEpoch,
          itemID,
        ],
      );
      resultStr = 'Updated';
    } else if (mode == BooruUpdateMode.urlUpdate) {
      await db?.rawUpdate(
        'UPDATE BooruItem SET thumbnailURL = ?,sampleURL = ?,fileURL = ? WHERE id = ?',
        [
          item.thumbnailURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          item.sampleURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          item.fileURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
          itemID,
        ],
      );
      resultStr = 'Updated Urls';
    } else {
      resultStr = 'Already Exists';
    }
    await deleteUntracked();
    return resultStr;
  }

  Future<Map<String, int>> updateMultipleBooruItems(List<BooruItem> items, BooruUpdateMode mode) async {
    // TODO rewrite using batch
    final List<String> itemIDs = await getItemIDs(items.map((item) => item.postURL).toList());

    int saved = 0, exist = 0;
    for (final BooruItem item in items) {
      final int itemIndex = items.indexWhere((element) => element.postURL == item.postURL);
      String? itemID = (itemIDs.isNotEmpty && itemIndex != -1) ? itemIDs[itemIndex] : null;

      // Same domain rule as updateBooruItem: doujin favourites and tags never
      // reach store.db.
      final bool isDoujin = DoujinDataHandler.isDoujinItem(item);
      final int favouriteFlag = Tools.boolToInt(!isDoujin && item.isFavourite.value == true);
      final int? snatchedAt = item.isSnatched.value == true ? DateTime.now().millisecondsSinceEpoch : null;

      if (itemID == null || itemID.isEmpty) {
        final result = await db?.rawInsert(
          'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite, snatchedAt) VALUES(?,?,?,?,?,?,?,?)',
          [
            item.thumbnailURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.sampleURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.fileURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.postURL,
            item.mediaType.toJson(),
            Tools.boolToInt(item.isSnatched.value == true),
            favouriteFlag,
            snatchedAt,
          ],
        );
        itemID = result?.toString();
        if (!isDoujin) {
          await updateTags(item.tagsList.map((t) => t.fullString).toList(), itemID);
        }
        saved++;
      } else if (mode == BooruUpdateMode.local) {
        await db?.rawUpdate(
          'UPDATE BooruItem SET isSnatched = ?, isFavourite = ?, '
          'snatchedAt = CASE WHEN ? = 1 THEN COALESCE(snatchedAt, ?) ELSE NULL END WHERE id = ?',
          [
            Tools.boolToInt(item.isSnatched.value == true),
            favouriteFlag,
            Tools.boolToInt(item.isSnatched.value == true),
            DateTime.now().millisecondsSinceEpoch,
            itemID,
          ],
        );
      } else if (mode == BooruUpdateMode.urlUpdate) {
        await db?.rawUpdate(
          'UPDATE BooruItem SET thumbnailURL = ?,sampleURL = ?,fileURL = ? WHERE id = ?',
          [
            item.thumbnailURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.sampleURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.fileURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            itemID,
          ],
        );
      } else {
        exist++;
      }
      await Future.delayed(const Duration(milliseconds: 1));
    }
    await deleteUntracked();

    return {'saved': saved, 'exist': exist};
  }

  /// Gets a BooruItem id from the database based on a fileurl
  Future<String?> getItemID(String postURL) async {
    List? result;
    result = await db?.rawQuery('SELECT id FROM BooruItem WHERE postURL = ?', [postURL]);

    if (result != null && result.isNotEmpty) {
      return result.first['id'].toString();
    } else {
      return null;
    }
  }

  Future<List<String>> getItemIDs(List<String> postURLs) async {
    final List<String> ids = List.generate(postURLs.length, (index) => '');
    // 1.0: in chunks - SQLite before 3.32 (Android before 11) takes at most
    // 999 values in one statement, and a bigger selection threw.
    const int chunkSize = 500;
    for (int start = 0; start < postURLs.length; start += chunkSize) {
      final List<String> chunk = postURLs.sublist(start, min(postURLs.length, start + chunkSize));
      final List? result = await db?.rawQuery(
        "SELECT id, postURL FROM BooruItem WHERE postURL IN (${List.generate(chunk.length, (_) => '?').join(',')})",
        chunk,
      );

      if (result != null && result.isNotEmpty) {
        for (final Map<String, dynamic> item in result) {
          final int postIndex = postURLs.indexOf(item['postURL']);
          if (postIndex != -1) {
            ids[postIndex] = item['id'].toString();
          }
        }
      }
    }
    return ids;
  }

  Future<List<BooruItem>> getSankakuItems({
    String search = '',
    bool idol = false,
  }) async {
    if (search.isNotEmpty) {
      final items = await searchDB(
        search,
        '0',
        '1000000',
        customConditions: ["bi.postURL like '%${idol ? "idol" : "chan"}.sankakucomplex%'"],
      );
      for (final item in items) {
        item.isSnatched.value = false;
      }
      return items;
    }

    final List? result = await db?.rawQuery(
      'SELECT BooruItem.id as ItemID, thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite '
      'FROM BooruItem '
      "WHERE postURL like '%${idol ? "idol" : "chan"}.sankakucomplex%' "
      'ORDER BY BooruItem.id DESC;',
    );
    final List<BooruItem> items = [];
    if (result != null && result.isNotEmpty) {
      for (int i = 0; i < result.length; i++) {
        final currentItem = result[i];
        if (currentItem != null && currentItem.isNotEmpty) {
          final BooruItem bItem = BooruItem.fromDBRow(currentItem, []);
          items.add(bItem);
        }
      }
    }
    return items;
  }

  Future<List<BooruItem>> searchDB(
    String searchTagsString,
    String offset,
    String limit, {
    String? order,
    List<String> customConditions = const [],
    bool isDownloads = false,
    int? collectionId,
  }) async {
    final db = this.db;
    if (db == null) return [];

    // --- 1. PARSE PARAMETERS ---
    // Clean input tags and separate special commands
    final List<String> rawTags = searchTagsString.trim().split(' ').where((t) => t.isNotEmpty).toList();
    final List<String> andTags = [];
    final List<String> orTags = [];
    final List<String> excludeTags = [];
    String siteQuery = '';
    String siteTerm = '';
    bool isRandomOrder = false;
    bool isReverseOrder = false;

    for (final tag in rawTags) {
      final lowerTag = tag.toLowerCase();
      if (lowerTag.startsWith('site:') || lowerTag.startsWith('-site:')) {
        final isExclude = lowerTag.startsWith('-site:');
        final term = tag.replaceAll(RegExp('^-?site:', caseSensitive: false), '');
        // 1.0: the term is bound, not written into the SQL (a quote broke the
        // query, and any SQL typed here ran).
        siteQuery = "(bi.postURL ${isExclude ? 'NOT' : ''} LIKE ? OR bi.fileURL ${isExclude ? 'NOT' : ''} LIKE ?) ";
        siteTerm = term;
      } else if (lowerTag == 'sort:random') {
        isRandomOrder = true;
      } else if (lowerTag == 'sort:reverse') {
        isReverseOrder = true;
      } else {
        // Replace booru wildcard '*' with SQLite wildcard '%'
        final String sqlTag = tag.replaceAll('*', '%');

        if (sqlTag.startsWith('-')) {
          excludeTags.add(sqlTag.substring(1));
        } else if (sqlTag.startsWith('~')) {
          orTags.add(sqlTag.substring(1));
        } else {
          andTags.add(sqlTag);
        }
      }
    }

    // --- 2. BUILD MAIN QUERY ---
    final StringBuffer sql = StringBuffer(
      'SELECT bi.id as dbid, bi.thumbnailURL, bi.sampleURL, bi.fileURL, bi.postURL, bi.mediaType, bi.isSnatched, bi.isFavourite '
      'FROM BooruItem AS bi ',
    );
    final List<String> whereClauses = [];
    final List<dynamic> args = [];

    // Only join if we need to filter by included tags
    final bool hasIncludedTags = andTags.isNotEmpty || orTags.isNotEmpty;

    if (hasIncludedTags) {
      sql.write('JOIN ImageTag AS it ON bi.id = it.booruItemID ');
      sql.write('JOIN Tag AS t ON it.tagID = t.id ');
    }

    // A. Base Filter
    whereClauses.add(_baseTrackFilter(isDownloads: isDownloads, collectionId: collectionId));

    // B. Site Filter
    if (siteQuery.isNotEmpty) {
      whereClauses.add(siteQuery);
      args.addAll(['%$siteTerm%', '%$siteTerm%']);
    }

    // C. Custom Conditions
    if (customConditions.isNotEmpty) {
      whereClauses.add('(${customConditions.join(' AND ')})');
    }

    // D. Exclusions
    if (excludeTags.isNotEmpty) {
      final List<String> excludeConditions = [];
      for (final ex in excludeTags) {
        excludeConditions.add('t_ex.name LIKE ?');
        args.add(ex);
      }
      final excludeSql = excludeConditions.join(' OR ');

      whereClauses.add('''
        bi.id NOT IN (
          SELECT it_ex.booruItemID 
          FROM ImageTag it_ex 
          JOIN Tag t_ex ON it_ex.tagID = t_ex.id 
          WHERE $excludeSql
        )
      ''');
    }

    // E. Inclusions
    if (hasIncludedTags) {
      final List<String> allSearchTags = [...andTags, ...orTags];
      final List<String> likeConditions = [];

      for (final tag in allSearchTags) {
        likeConditions.add('t.name LIKE ?');
        args.add(tag);
      }
      whereClauses.add('(${likeConditions.join(' OR ')})');
    }

    // Apply WHERE
    if (whereClauses.isNotEmpty) {
      sql.write('WHERE ${whereClauses.join(' AND ')} ');
    }

    // --- GROUPING & INTERSECTION LOGIC (AND / OR) ---
    if (hasIncludedTags) {
      sql.write('GROUP BY bi.id ');

      final List<String> havingClauses = [];

      // MUST satisfy EVERY individual AND tag
      if (andTags.isNotEmpty) {
        for (final andTag in andTags) {
          havingClauses.add('MAX(CASE WHEN t.name LIKE ? THEN 1 ELSE 0 END) = 1');
          args.add(andTag);
        }
      }

      // MUST satisfy AT LEAST ONE of the OR tags
      if (orTags.isNotEmpty) {
        final List<String> orConditions = [];
        for (final orTag in orTags) {
          orConditions.add('t.name LIKE ?');
          args.add(orTag);
        }
        havingClauses.add('MAX(CASE WHEN ${orConditions.join(' OR ')} THEN 1 ELSE 0 END) = 1');
      }

      if (havingClauses.isNotEmpty) {
        sql.write('HAVING ${havingClauses.join(' AND ')} ');
      }
    }

    // Ordering & Pagination
    final String direction = order ?? (isReverseOrder ? 'ASC' : null) ?? 'DESC';
    // Downloads: newest SNATCH first. The id is insertion order, and a row
    // favourited or collected months ago keeps that old id when it is later
    // snatched, which put fresh downloads hundreds of rows down the list.
    String orderByClause = (isDownloads && collectionId == null)
        ? 'COALESCE(bi.snatchedAt, 0) $direction, bi.id $direction'
        : 'bi.id $direction';
    if (isRandomOrder) orderByClause = 'RANDOM()';
    sql.write('ORDER BY $orderByClause LIMIT ? OFFSET ?');
    args.add(limit);
    args.add(offset);

    // --- 3. EXECUTE MAIN SEARCH ---
    final List<Map<String, dynamic>> results = await db.rawQuery(sql.toString(), args);

    if (results.isEmpty) return [];

    // --- 4. FETCH TAGS ---
    final itemIDs = results.map((r) => r['dbid'] as int).toList();
    final tagPlaceholders = List.filled(itemIDs.length, '?').join(',');
    final tagsResult = await db.rawQuery(
      'SELECT it.booruItemID, t.name '
      'FROM Tag AS t '
      'INNER JOIN ImageTag AS it ON t.id = it.tagID '
      'WHERE it.booruItemID IN ($tagPlaceholders)',
      itemIDs,
    );

    // --- 5. MAP RESULTS ---
    final Map<int, List<String>> tagsMap = {};
    for (final row in tagsResult) {
      final id = row['booruItemID']! as int;
      final tagName = row['name'].toString();
      if (!tagsMap.containsKey(id)) tagsMap[id] = [];
      tagsMap[id]!.add(tagName);
    }

    // Construct final objects using BooruItem.fromDBRow
    return results.map((row) {
      final id = row['dbid'] as int;
      final itemTags = tagsMap[id] ?? [];
      return BooruItem.fromDBRow(row, itemTags);
    }).toList();
  }

  // Picks the base "tracked" WHERE clause for searchDB / searchDBCount:
  // collection membership when a collection is being browsed (collectionId
  // == -1 means "all collections"), otherwise the snatched/favourite filter.
  // The id is an app-controlled integer, so it's safe to inline.
  String _baseTrackFilter({required bool isDownloads, int? collectionId}) {
    if (collectionId != null) {
      if (collectionId == -1) {
        return 'bi.id IN (SELECT booruItemID FROM CollectionItem)';
      }
      return 'bi.id IN (SELECT booruItemID FROM CollectionItem WHERE collectionId = $collectionId)';
    }
    return isDownloads ? 'bi.isSnatched = 1' : 'bi.isFavourite = 1';
  }

  Future<int> searchDBCount(
    String searchTagsString, {
    List<String> customConditions = const [],
    bool isDownloads = false,
    int? collectionId,
  }) async {
    final db = this.db;
    if (db == null) return 0;

    // --- 1. PARSE PARAMETERS ---
    final List<String> rawTags = searchTagsString.trim().split(' ').where((t) => t.isNotEmpty).toList();
    final List<String> andTags = [];
    final List<String> orTags = [];
    final List<String> excludeTags = [];
    String siteQuery = '';
    String siteTerm = '';

    for (final tag in rawTags) {
      final lowerTag = tag.toLowerCase();

      if (lowerTag.startsWith('site:') || lowerTag.startsWith('-site:')) {
        final isExclude = lowerTag.startsWith('-site:');
        final term = tag.replaceAll(RegExp('^-?site:', caseSensitive: false), '');
        siteQuery = "(bi.postURL ${isExclude ? 'NOT' : ''} LIKE ? OR bi.fileURL ${isExclude ? 'NOT' : ''} LIKE ?)";
        siteTerm = term;
      } else if (lowerTag == 'sort:random' || lowerTag == 'sort:reverse') {
        // do nothing
      } else {
        // Replace booru wildcard '*' with SQLite wildcard '%'
        final String sqlTag = tag.replaceAll('*', '%');

        if (sqlTag.startsWith('-')) {
          excludeTags.add(sqlTag.substring(1));
        } else if (sqlTag.startsWith('~')) {
          orTags.add(sqlTag.substring(1));
        } else {
          andTags.add(sqlTag);
        }
      }
    }

    // --- 2. BUILD COUNT QUERY ---
    final StringBuffer sql = StringBuffer('SELECT COUNT(*) as count FROM BooruItem AS bi ');
    final List<String> whereClauses = [];
    final List<dynamic> args = [];

    // Join tables ONLY if filtering by included tags
    final bool hasIncludedTags = andTags.isNotEmpty || orTags.isNotEmpty;

    if (hasIncludedTags) {
      sql.write('JOIN ImageTag AS it ON bi.id = it.booruItemID ');
      sql.write('JOIN Tag AS t ON it.tagID = t.id ');
    }

    // --- 3. APPLY FILTERS ---

    // A. Base Filter
    whereClauses.add(_baseTrackFilter(isDownloads: isDownloads, collectionId: collectionId));

    // B. Site Filter
    if (siteQuery.isNotEmpty) {
      whereClauses.add(siteQuery);
      args.addAll(['%$siteTerm%', '%$siteTerm%']);
    }

    // C. Custom Conditions
    if (customConditions.isNotEmpty) {
      whereClauses.add('(${customConditions.join(' AND ')})');
    }

    // D. Exclusions
    if (excludeTags.isNotEmpty) {
      final List<String> excludeConditions = [];
      for (final ex in excludeTags) {
        excludeConditions.add('t_ex.name LIKE ?');
        args.add(ex);
      }
      final excludeSql = excludeConditions.join(' OR ');

      whereClauses.add('''
        bi.id NOT IN (
          SELECT it_ex.booruItemID 
          FROM ImageTag it_ex 
          JOIN Tag t_ex ON it_ex.tagID = t_ex.id 
          WHERE $excludeSql
        )
      ''');
    }

    // E. Inclusions
    if (hasIncludedTags) {
      final List<String> allSearchTags = [...andTags, ...orTags];
      final List<String> likeConditions = [];

      for (final tag in allSearchTags) {
        likeConditions.add('t.name LIKE ?');
        args.add(tag);
      }
      whereClauses.add('(${likeConditions.join(' OR ')})');
    }

    // Apply WHERE
    if (whereClauses.isNotEmpty) {
      sql.write('WHERE ${whereClauses.join(' AND ')} ');
    }

    // --- 4. INTERSECTION LOGIC ---
    if (hasIncludedTags) {
      sql.write('GROUP BY bi.id ');

      final List<String> havingClauses = [];

      // MUST satisfy EVERY individual AND tag
      if (andTags.isNotEmpty) {
        for (final andTag in andTags) {
          havingClauses.add('MAX(CASE WHEN t.name LIKE ? THEN 1 ELSE 0 END) = 1');
          args.add(andTag);
        }
      }

      // MUST satisfy AT LEAST ONE of the OR tags
      if (orTags.isNotEmpty) {
        final List<String> orConditions = [];
        for (final orTag in orTags) {
          orConditions.add('t.name LIKE ?');
          args.add(orTag);
        }
        havingClauses.add('MAX(CASE WHEN ${orConditions.join(' OR ')} THEN 1 ELSE 0 END) = 1');
      }

      if (havingClauses.isNotEmpty) {
        sql.write('HAVING ${havingClauses.join(' AND ')} ');
      }

      final fullSql = 'SELECT COUNT(*) as total FROM ($sql)';
      final result = await db.rawQuery(fullSql, args);
      return result.first['total'] as int? ?? 0;
    } else {
      final result = await db.rawQuery(sql.toString(), args);
      return result.first['count'] as int? ?? 0;
    }
  }

  Future<int> getFavouritesCount() async {
    List? result;
    result = await db?.rawQuery('SELECT COUNT(*) as count FROM BooruItem WHERE isFavourite = 1');

    if (result != null) {
      return result.first['count'];
    } else {
      return 0;
    }
  }

  Future<int> getSnatchedCount() async {
    List? result;
    result = await db?.rawQuery('SELECT COUNT(*) as count FROM BooruItem WHERE isSnatched = 1');

    if (result != null) {
      return result.first['count'];
    } else {
      return 0;
    }
  }

  Future<void> clearSnatched() async {
    await db?.rawUpdate('UPDATE BooruItem SET isSnatched = 0');
    unawaited(deleteUntracked());
  }

  Future<void> clearFavourites() async {
    await db?.rawUpdate('UPDATE BooruItem SET isFavourite = 0');
    unawaited(deleteUntracked());
  }

  ///////
  /// Doujin migration helpers

  /// Raw SELECT for the doujin migration planner; empty when the DB is off.
  Future<List<Map<String, Object?>>> rawRows(String sql) async => (await db?.rawQuery(sql)) ?? const [];

  Future<void> clearFavouriteFlag(List<int> itemIds) async {
    if (itemIds.isEmpty) return;
    // Chunked so huge favourite migrations don't overrun the SQL length cap.
    for (int i = 0; i < itemIds.length; i += 500) {
      final chunk = itemIds.sublist(i, i + 500 > itemIds.length ? itemIds.length : i + 500);
      await db?.rawUpdate('UPDATE BooruItem SET isFavourite = 0 WHERE id IN (${chunk.join(',')})');
    }
  }

  /// Return a list of boolean for isSnatched and isFavourite
  Future<List<bool>> getTrackedValues(BooruItem item) async {
    final List<bool> values = [false, false];
    List? result;

    // DateTime startTime = DateTime.now();
    if (item.fileURL.contains('sankakucomplex.com') ||
        item.fileURL.contains('rule34.xxx') ||
        item.fileURL.contains('paheal.net')) {
      // compare by post url, not file url (for example: r34xxx changes urls based on country)
      result = await db?.rawQuery('SELECT isFavourite, isSnatched FROM BooruItem WHERE postURL = ?', [item.postURL]);
    } else {
      result = await db?.rawQuery('SELECT isFavourite, isSnatched FROM BooruItem WHERE fileURL = ?', [item.fileURL]);
    }
    // print("getTrackedValues: ${DateTime.now().difference(startTime).inMilliseconds}ms"); // performance test
    if (result != null && result.isNotEmpty) {
      values[0] = Tools.intToBool(result.first['isSnatched']);
      values[1] = Tools.intToBool(result.first['isFavourite']);
    }
    return values;
  }

  /// Deletes booruItems which are no longer favourited or snatched
  /// Drops the snatched flag from rows whose file is gone from disk (the
  /// downloads reconciler's explicit "forget" action). Rows that are neither
  /// favourited nor collected are then removed by [deleteUntracked]. Returns
  /// how many rows were changed.
  Future<int> clearSnatchedFlags(List<String> postURLs) async {
    if (postURLs.isEmpty || db == null) return 0;
    int changed = 0;
    const int chunkSize = 500;
    for (int i = 0; i < postURLs.length; i += chunkSize) {
      final chunk = postURLs.sublist(i, min(postURLs.length, i + chunkSize));
      final placeholders = List.filled(chunk.length, '?').join(',');
      changed += await db!.rawUpdate(
        'UPDATE BooruItem SET isSnatched = 0, snatchedAt = NULL WHERE postURL IN ($placeholders)',
        chunk,
      );
    }
    await deleteUntracked();
    return changed;
  }

  Future<bool> deleteUntracked() async {
    // Keep items that are favourited, snatched, OR held by a collection.
    final result = await db?.rawQuery(
      'SELECT id FROM BooruItem '
      'WHERE (isFavourite = 0 OR isFavourite IS NULL) '
      'AND (isSnatched = 0 OR isSnatched IS NULL) '
      'AND id NOT IN (SELECT booruItemID FROM CollectionItem)',
    );
    if (result != null && result.isNotEmpty) {
      await deleteItem(result.map((r) => r['id'].toString()).toList());
    }
    return true;
  }

  /// Deletes a BooruItem and its tags from the database
  Future<void> deleteItem(List<String> itemIDs) async {
    Logger.Inst().log(
      'DBHandler deleting ${itemIDs.length} items',
      'DBHandler',
      'deleteItem',
      LogTypes.booruHandlerInfo,
    );
    const int chunkSize = 1000;
    for (int i = 0; i < (itemIDs.length / chunkSize).ceil(); i++) {
      final chunk = itemIDs.sublist(i * chunkSize, min(itemIDs.length, (i + 1) * chunkSize));
      final batch = db?.batch();
      for (final id in chunk) {
        batch?.rawDelete('DELETE FROM BooruItem WHERE id = ?', [id]);
        batch?.rawDelete('DELETE FROM ImageTag WHERE booruItemID = ?', [id]);
      }
      await batch?.commit(noResult: true);
    }
  }
}
