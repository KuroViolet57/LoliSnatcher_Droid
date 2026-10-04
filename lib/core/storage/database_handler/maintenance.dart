part of '../database_handler.dart';

/// Repairs of old rows run at start and the delayed tag cleanup.
extension DBMaintenance on DBHandler {
  //

  Future<void> fixBooruItems(ValueChanged<String>? onStatusUpdate) async {
    try {
      await convertGelbooruServers(
        'img2',
        'video-cdn4',
        onStatusUpdate,
      ); // latest change i4->2, v3->4, ~early-mid December 25
      await fixR34XXXPostUrls(onStatusUpdate);
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        s: s,
        'DBHandler',
        'fixBooruItems',
        LogTypes.exception,
      );
    }
  }

  Future<void> convertGelbooruServers(
    String newImgServer,
    String newVidServer,
    ValueChanged<String>? onStatusUpdate,
  ) async {
    final List<String> conditions = [];
    for (final server in [
      {'img': newImgServer},
      {'video-cdn': newVidServer},
    ]) {
      for (final type in ['fileURL', 'sampleURL', 'thumbnailURL']) {
        conditions.add(
          "($type LIKE '%${server.keys.first}%.gelbooru.com%' AND $type NOT LIKE '%${server.values.first}.gelbooru.com%')",
        );
      }
    }

    // gelbooru moves images (imgN) and videos (cdnN) to new servers from time to time?
    final List<Map<String, dynamic>> items =
        await db?.rawQuery(
          'SELECT id, fileURL, sampleURL, thumbnailURL FROM BooruItem WHERE '
          "(${conditions.join(' OR ')} " // migrate to other servers
          "OR fileURL LIKE 'https://%//%' OR sampleURL LIKE 'https://%//%' OR thumbnailURL LIKE 'https://%//%') " // fix multiple slashes (except https://)
          "AND postURL LIKE '%gelbooru.com%';",
        ) ??
        [];

    const int chunkSize = 1000;
    for (int i = 0; i < (items.length / chunkSize).ceil(); i++) {
      final batch = db?.batch();
      final chunk = items.sublist(i * chunkSize, min(items.length, (i + 1) * chunkSize));
      onStatusUpdate?.call('Gelbooru: ${i * chunkSize}/${items.length}');
      for (final Map<String, dynamic> item in chunk) {
        final String newFileURL = item['fileURL']
            .toString()
            .replaceAllMapped(RegExp(r'img(\d+).gelbooru.com'), (m) => '$newImgServer.gelbooru.com')
            .replaceAllMapped(RegExp(r'video-cdn(\d+).gelbooru.com'), (m) => '$newVidServer.gelbooru.com')
            .replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/');
        final String newSampleURL = item['sampleURL']
            .toString()
            .replaceAllMapped(RegExp(r'img(\d+).gelbooru.com'), (m) => '$newImgServer.gelbooru.com')
            .replaceAllMapped(RegExp(r'video-cdn(\d+).gelbooru.com'), (m) => '$newVidServer.gelbooru.com')
            .replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/');
        final String newThumbnailURL = item['thumbnailURL']
            .toString()
            .replaceAllMapped(RegExp(r'img(\d+).gelbooru.com'), (m) => '$newImgServer.gelbooru.com')
            .replaceAllMapped(RegExp(r'video-cdn(\d+).gelbooru.com'), (m) => '$newVidServer.gelbooru.com')
            .replaceFirstMapped(RegExp('(?<!https?:)//'), (m) => '/');
        batch?.rawUpdate(
          'UPDATE BooruItem SET fileURL = ?, sampleURL = ?, thumbnailURL = ? WHERE id = ?;',
          [newFileURL, newSampleURL, newThumbnailURL, item['id']],
        );
      }
      await batch?.commit(noResult: true);
    }
  }

  Future<void> fixR34XXXPostUrls(ValueChanged<String>? onStatusUpdate) async {
    // 2.4.4+4203 introduced a bug where postURL was changed to api.rule34.xxx, this fixes those entries back to just rule34.xxx

    final List<Map<String, dynamic>> items =
        await db?.rawQuery(
          "SELECT id, postURL FROM BooruItem WHERE postURL LIKE '%api.rule34.xxx%';",
        ) ??
        [];

    const int chunkSize = 1000;
    for (int i = 0; i < (items.length / chunkSize).ceil(); i++) {
      final batch = db?.batch();
      final chunk = items.sublist(i * chunkSize, min(items.length, (i + 1) * chunkSize));
      onStatusUpdate?.call('R34XXX: ${i * chunkSize}/${items.length}');
      for (final Map<String, dynamic> item in chunk) {
        final String newPostURL = item['postURL'].toString().replaceAll('api.rule34.xxx', 'rule34.xxx');
        batch?.rawUpdate(
          'UPDATE BooruItem SET postURL = ? WHERE id = ?;',
          [newPostURL, item['id']],
        );
      }
      await batch?.commit(noResult: true);
    }
  }

  /// Scans for empty tags and direct duplicates, then deletes them.
  Future<void> tagsCleanup() async {
    if (db == null) return;

    try {
      final emptyTags = await db?.rawQuery("SELECT id FROM Tag WHERE trim(name) = '' OR name IS NULL") ?? [];

      if (emptyTags.isNotEmpty) {
        Logger.Inst().log(
          '[TagCleanup] Found ${emptyTags.length} empty tags. Removing...',
          'DBHandler',
          'tagsCleanup',
          LogTypes.booruHandlerInfo,
        );

        await db?.transaction((txn) async {
          final ids = emptyTags.map((e) => e['id']! as int).toList();
          // 1.0: in chunks (at most 999 values in one statement on older Android).
          for (int start = 0; start < ids.length; start += 500) {
            final chunk = ids.sublist(start, min(ids.length, start + 500));
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawDelete('DELETE FROM ImageTag WHERE tagID IN ($placeholders)', chunk);
            await txn.rawDelete('DELETE FROM Tag WHERE id IN ($placeholders)', chunk);
          }
        });
      }

      //

      final duplicateGroups =
          await db?.rawQuery('''
        SELECT name as cleanName, COUNT(*) as count 
        FROM Tag 
        GROUP BY name 
        HAVING count > 1
      ''') ??
          [];

      if (duplicateGroups.isEmpty) return;

      Logger.Inst().log(
        '[TagCleanup] Found ${duplicateGroups.length} duplicate tag groups.',
        'DBHandler',
        'tagsCleanup',
        LogTypes.booruHandlerInfo,
      );

      for (final g in duplicateGroups) {
        final String cleanName = g['cleanName'].toString();

        final variants =
            await db?.rawQuery('SELECT id, name FROM Tag WHERE name = ? ORDER BY id ASC', [cleanName]) ?? [];

        if (variants.length < 2) continue;

        int winnerId = -1;
        int maxUsage = -1;

        for (final v in variants) {
          final int id = v['id']! as int;
          final int count =
              Sqflite.firstIntValue(await db?.rawQuery('SELECT COUNT(*) FROM ImageTag WHERE tagID = ?', [id]) ?? []) ??
              0;

          if (count > maxUsage) {
            maxUsage = count;
            winnerId = id;
          }
        }

        await db?.transaction((txn) async {
          for (final v in variants) {
            final int id = v['id']! as int;
            if (id == winnerId) continue;
            await txn.rawUpdate(
              '''
              UPDATE ImageTag 
              SET tagID = ? 
              WHERE tagID = ? 
              AND booruItemID NOT IN (
                SELECT booruItemID FROM ImageTag WHERE tagID = ?
              )
            ''',
              [winnerId, id, winnerId],
            );
            await txn.rawDelete('DELETE FROM ImageTag WHERE tagID = ?', [id]);
            await txn.rawDelete('DELETE FROM Tag WHERE id = ?', [id]);
          }
        });
        if (kDebugMode) {
          Logger.Inst().log(
            '[TagCleanup] Removed duplicate tags for "$cleanName".',
            'DBHandler',
            'tagsCleanup',
            LogTypes.booruHandlerInfo,
          );
        }
      }

      Logger.Inst().log(
        '[TagCleanup] Done.',
        'DBHandler',
        'tagsCleanup',
        LogTypes.booruHandlerInfo,
      );
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        s: s,
        'DBHandler',
        'deduplicateTags',
        LogTypes.exception,
      );
    }
  }
}
