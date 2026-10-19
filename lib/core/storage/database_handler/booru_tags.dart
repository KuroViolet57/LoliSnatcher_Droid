part of '../database_handler.dart';

/// The tag builder's snapshot (BooruTag), your corrections (BooruTagOverride) and the cross-booru alias cache.
extension DBBooruTags on DBHandler {
  //
  // Cross-booru tag alias cache
  //

  /// null = not cached; '' = cached miss (tag confirmed absent on that booru).
  Future<String?> getTagAlias(String sourceTag, String booruKey) async {
    final List? rows = await db?.rawQuery(
      'SELECT targetTag, updatedAt FROM TagAliasCache WHERE sourceTag = ? AND booruKey = ?',
      [sourceTag.toLowerCase(), booruKey],
    );
    if (rows == null || rows.isEmpty) return null;
    final int updatedAt = (rows.first['updatedAt'] as int?) ?? 0;
    final String target = rows.first['targetTag'].toString();
    // Re-resolve misses after a day; successful mappings are kept for a
    // month. Misses are deliberately short-lived: a "miss" can also be a
    // request that failed, and a week of remembering that is a week of a
    // booru silently refusing to translate anything.
    final int ttlDays = target.isEmpty ? 1 : 30;
    if (DateTime.now().millisecondsSinceEpoch - updatedAt > ttlDays * Duration.millisecondsPerDay) {
      return null;
    }
    return target;
  }

  /// Drops cached "this tag does not exist here" rows on startup.
  ///
  /// Those rows were also written when a suggestion lookup FAILED (a 403, a
  /// CAPTCHA, a rate-limit), which made cross-booru translation stay dead for
  /// a week after a single bad moment. The resolver no longer stores a
  /// negative it did not actually observe, but databases in the wild still
  /// carry the old ones — and a miss costs one cheap request to re-derive, so
  /// clearing them every launch is the safe side to err on.
  Future<void> purgeTagAliasMisses() async {
    try {
      await db?.rawDelete("DELETE FROM TagAliasCache WHERE targetTag = ''");
    } catch (_) {}
  }

  Future<void> setTagAlias(String sourceTag, String booruKey, String targetTag) async {
    await db?.rawInsert(
      'INSERT OR REPLACE INTO TagAliasCache(sourceTag, booruKey, targetTag, updatedAt) VALUES(?,?,?,?)',
      [sourceTag.toLowerCase(), booruKey, targetTag, DateTime.now().millisecondsSinceEpoch],
    );
  }

  //
  // Per-booru tag snapshot + corrections
  //

  Future<void> upsertBooruTags(String booruKey, List<BooruTagEntry> entries) async {
    final db = this.db;
    if (db == null || entries.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    // One transaction for the whole page: a snapshot pull writes 100 rows at
    // a time and each autocommit would otherwise be its own fsync.
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in entries) {
        final String source = e.origin == TagTypeOrigin.inferred ? 'import' : 'api';
        final int stamp = e.updatedAt == 0 ? now : e.updatedAt;
        batch.rawInsert(
          'INSERT OR REPLACE INTO BooruTag(booruKey, namespace, name, tagType, count, source, updatedAt, sourceId) VALUES(?,?,?,?,?,?,?,?)',
          [booruKey, e.namespace, e.name, e.tagType.name, e.count, source, stamp, e.sourceId],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, Object?>>> getBooruTagsByNames(String booruKey, List<String> names) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty || names.isEmpty) return const [];
    // 1.0: in chunks (at most 999 values in one statement on older Android).
    const int chunkSize = 500;
    final List<Map<String, Object?>> rows = [];
    for (int start = 0; start < names.length; start += chunkSize) {
      final List<String> chunk = names.sublist(start, min(names.length, start + chunkSize));
      final String placeholders = List.filled(chunk.length, '?').join(',');
      rows.addAll(
        await db.rawQuery(
          'SELECT name, namespace, tagType, count, source, updatedAt, sourceId FROM BooruTag '
          'WHERE booruKey = ? AND name IN ($placeholders)',
          [booruKey, ...chunk],
        ),
      );
    }
    return rows;
  }

  /// The site's own id for one (namespace, name), when the snapshot holds it.
  Future<String?> getBooruTagSourceId(String booruKey, String namespace, String name) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty || name.isEmpty) return null;
    final rows = await db.rawQuery(
      'SELECT sourceId FROM BooruTag WHERE booruKey = ? AND namespace = ? AND name = ? LIMIT 1',
      [booruKey, namespace, name],
    );
    if (rows.isEmpty) return null;
    final String id = rows.first['sourceId']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }

  /// Rows per namespace for one source — what the tag builder's chips show.
  Future<Map<String, int>> countBooruTagsByNamespace(String booruKey) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty) return const {};
    final rows = await db.rawQuery(
      'SELECT namespace, COUNT(*) AS c FROM BooruTag WHERE booruKey = ? GROUP BY namespace',
      [booruKey],
    );
    return {
      for (final row in rows) row['namespace']?.toString() ?? '': int.tryParse(row['c']?.toString() ?? '') ?? 0,
    };
  }

  /// Rows per type among the namespace-less rows â€” the tag builder's badges
  /// on a classic booru, whose snapshot keeps the site's category in tagType.
  Future<Map<String, int>> countBooruTagsByType(String booruKey) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty) return const {};
    final rows = await db.rawQuery(
      "SELECT tagType, COUNT(*) AS c FROM BooruTag WHERE booruKey = ? AND namespace = '' GROUP BY tagType",
      [booruKey],
    );
    return {
      for (final row in rows) row['tagType']?.toString() ?? '': int.tryParse(row['c']?.toString() ?? '') ?? 0,
    };
  }

  Future<void> deleteBooruTags(String booruKey, {String? namespace, String? tagType}) async {
    final List<Object?> args = [booruKey];
    String where = 'booruKey = ?';
    if (namespace != null) {
      where += ' AND namespace = ?';
      args.add(namespace);
    }
    if (tagType != null) {
      where += ' AND tagType = ?';
      args.add(tagType);
    }
    await db?.rawDelete('DELETE FROM BooruTag WHERE $where', args);
  }

  Future<List<Map<String, Object?>>> getBooruTagOverrides({String? booruKey}) async {
    final db = this.db;
    if (db == null) return const [];
    if (booruKey == null) {
      return db.rawQuery('SELECT booruKey, name, tagType, source, updatedAt FROM BooruTagOverride');
    }
    return db.rawQuery(
      'SELECT booruKey, name, tagType, source, updatedAt FROM BooruTagOverride WHERE booruKey = ?',
      [booruKey],
    );
  }

  Future<void> setBooruTagOverride(String booruKey, String name, String tagType, String source) async {
    await db?.rawInsert(
      'INSERT OR REPLACE INTO BooruTagOverride(booruKey, name, tagType, source, updatedAt) VALUES(?,?,?,?,?)',
      [booruKey, name, tagType, source, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> deleteBooruTagOverride(String booruKey, String name) async {
    await db?.rawDelete('DELETE FROM BooruTagOverride WHERE booruKey = ? AND name = ?', [booruKey, name]);
  }

  Future<void> deleteBooruTagOverrides(String? booruKey) async {
    if (booruKey == null) {
      await db?.rawDelete('DELETE FROM BooruTagOverride');
    } else {
      await db?.rawDelete('DELETE FROM BooruTagOverride WHERE booruKey = ?', [booruKey]);
    }
  }
}
