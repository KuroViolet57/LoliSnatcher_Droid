part of '../database_handler.dart';

/// Booru collections (Collection, CollectionItem).
extension DBCollections on DBHandler {
  //
  // Collections / albums
  //

  Future<int?> createCollection(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db?.rawInsert(
      'INSERT INTO Collection(name, createdAt, sortOrder) VALUES(?,?,?)',
      [trimmed, now, now],
    );
  }

  Future<void> renameCollection(int id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await db?.rawUpdate('UPDATE Collection SET name = ? WHERE id = ?', [trimmed, id]);
  }

  Future<void> deleteCollection(int id) async {
    await db?.rawDelete('DELETE FROM CollectionItem WHERE collectionId = ?', [id]);
    await db?.rawDelete('DELETE FROM Collection WHERE id = ?', [id]);
    // Any BooruItems that were only kept because of this collection get swept.
    await deleteUntracked();
  }

  /// Returns each collection with its item count and a cover thumbnail
  /// (the most-recently-added item's thumbnail).
  Future<List<CollectionInfo>> getCollections() async {
    final List? rows = await db?.rawQuery('''
      SELECT c.id AS id, c.name AS name, c.createdAt AS createdAt,
             COUNT(ci.booruItemID) AS itemCount,
             (SELECT bi.thumbnailURL FROM CollectionItem ci2
                JOIN BooruItem bi ON bi.id = ci2.booruItemID
                WHERE ci2.collectionId = c.id
                ORDER BY ci2.addedAt DESC LIMIT 1) AS cover
      FROM Collection c
      LEFT JOIN CollectionItem ci ON ci.collectionId = c.id
      GROUP BY c.id
      ORDER BY c.sortOrder DESC
    ''');
    if (rows == null) return [];
    return rows
        .map(
          (r) => CollectionInfo(
            id: r['id'] as int,
            name: r['name']?.toString() ?? '',
            itemCount: (r['itemCount'] as int?) ?? 0,
            coverThumbnailURL: r['cover']?.toString(),
            createdAt: (r['createdAt'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Inserts each item into the shared BooruItem table if missing (without
  /// touching its favourite/snatched flags) and links it to [collectionId].
  /// Returns how many were newly added to the collection.
  Future<int> addItemsToCollection(int collectionId, List<BooruItem> items) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    int added = 0;
    for (final BooruItem item in items) {
      String? itemID = await getItemID(item.postURL);
      // Same domain rule as the other two BooruItem writers: a doujin row
      // never carries a favourite flag or its tags into store.db. Callers
      // split by domain before getting here, so this is a guard rail rather
      // than a live path — but it is one careless caller away from mattering.
      final bool isDoujin = DoujinDataHandler.isDoujinItem(item);
      if (itemID == null || itemID.isEmpty) {
        final result = await db?.rawInsert(
          'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite) VALUES(?,?,?,?,?,?,?)',
          [
            item.thumbnailURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.sampleURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.fileURL.replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/'),
            item.postURL,
            item.mediaType.value.toJson(),
            Tools.boolToInt(item.isSnatched.value == true),
            Tools.boolToInt(!isDoujin && item.isFavourite.value == true),
          ],
        );
        itemID = result?.toString();
        if (!isDoujin) {
          await updateTags(item.tagsList.map((t) => t.fullString).toList(), itemID);
        }
      }
      if (itemID == null || itemID.isEmpty) continue;
      final int count = Sqflite.firstIntValue(
            await db!.rawQuery(
              'SELECT COUNT(*) FROM CollectionItem WHERE collectionId = ? AND booruItemID = ?',
              [collectionId, itemID],
            ),
          ) ??
          0;
      if (count == 0) {
        await db?.rawInsert(
          'INSERT INTO CollectionItem(collectionId, booruItemID, addedAt) VALUES(?,?,?)',
          [collectionId, int.parse(itemID), now],
        );
        added++;
      }
    }
    return added;
  }

  Future<void> removeItemsFromCollection(int collectionId, List<String> postURLs) async {
    for (final String postURL in postURLs) {
      final String? itemID = await getItemID(postURL);
      if (itemID == null || itemID.isEmpty) continue;
      await db?.rawDelete(
        'DELETE FROM CollectionItem WHERE collectionId = ? AND booruItemID = ?',
        [collectionId, itemID],
      );
    }
    await deleteUntracked();
  }

  /// Set of collection ids that already contain the given post.
  Future<Set<int>> getCollectionsForItem(String postURL) async {
    final String? itemID = await getItemID(postURL);
    if (itemID == null || itemID.isEmpty) return {};
    final List? rows = await db?.rawQuery(
      'SELECT collectionId FROM CollectionItem WHERE booruItemID = ?',
      [itemID],
    );
    if (rows == null) return {};
    return rows.map((r) => r['collectionId'] as int).toSet();
  }

  Future<void> removeCollectionItem(int collectionId, int booruItemId) async {
    await db?.rawDelete(
      'DELETE FROM CollectionItem WHERE collectionId = ? AND booruItemID = ?',
      [collectionId, booruItemId],
    );
  }
}
