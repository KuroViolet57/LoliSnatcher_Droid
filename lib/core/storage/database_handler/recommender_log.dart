part of '../database_handler.dart';

/// What the recommender learns from: tag signals, interactions, feature names.
extension DBRecommenderLog on DBHandler {
  /// Adds [deltas] to the interest scores of their tags, applying decay to
  /// the previously stored score first.
  Future<void> addTagSignals(Map<String, double> deltas) async {
    final db = this.db;
    if (db == null || deltas.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final entry in deltas.entries) {
      final String name = entry.key.trim().toLowerCase();
      if (name.isEmpty) continue;
      final List rows = await db.rawQuery('SELECT score, updatedAt FROM TagSignal WHERE name = ?', [name]);
      double base = 0;
      if (rows.isNotEmpty) {
        base = DBHandler.decayedTagScore(
          (rows.first['score'] as num?)?.toDouble() ?? 0,
          (rows.first['updatedAt'] as int?) ?? now,
        );
      }
      batch.rawInsert(
        'INSERT OR REPLACE INTO TagSignal(name, score, updatedAt) VALUES(?,?,?)',
        [name, base + entry.value, now],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Top interest tags by decayed score.
  Future<List<MapEntry<String, double>>> getTagSignals({int limit = 100}) async {
    final List? rows = await db?.rawQuery(
      'SELECT name, score, updatedAt FROM TagSignal ORDER BY score DESC LIMIT ?',
      // over-fetch: decay can reorder rows relative to raw score
      [limit * 3],
    );
    if (rows == null) return [];
    final List<MapEntry<String, double>> out = rows
        .map(
          (r) => MapEntry(
            r['name'].toString(),
            DBHandler.decayedTagScore((r['score'] as num?)?.toDouble() ?? 0, (r['updatedAt'] as int?) ?? 0),
          ),
        )
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out.take(limit).toList();
  }

  Future<void> deleteTagSignal(String name) async {
    await db?.rawDelete('DELETE FROM TagSignal WHERE name = ?', [name.trim().toLowerCase()]);
  }

  Future<void> clearTagSignals() async {
    await db?.rawDelete('DELETE FROM TagSignal');
  }

  // ── recommender log (r33) ──

  /// One interaction that teaches the recommender; [features] are the item's
  /// feature hashes at the time.
  Future<void> addInteraction({
    required String world,
    required String itemKey,
    required String host,
    required String kind,
    required double value,
    required List<int> features,
  }) async {
    await db?.rawInsert(
      'INSERT INTO Interaction(world, itemKey, host, kind, value, at, features) VALUES(?,?,?,?,?,?,?)',
      [world, itemKey, host, kind, value, DateTime.now().millisecondsSinceEpoch, features.join(',')],
    );
  }

  Future<int> countInteractions(String world) async {
    final List? rows = await db?.rawQuery('SELECT COUNT(*) AS n FROM Interaction WHERE world = ?', [world]);
    if (rows == null || rows.isEmpty) return 0;
    return (rows.first['n'] as int?) ?? 0;
  }

  /// The newest [limit] interactions of [world], newest first.
  Future<List<InteractionRow>> recentInteractions(String world, {int limit = 20000}) async {
    final List? rows = await db?.rawQuery(
      'SELECT id, world, itemKey, host, kind, value, at, features FROM Interaction WHERE world = ? ORDER BY at DESC, id DESC LIMIT ?',
      [world, limit],
    );
    if (rows == null) return const [];
    return [
      for (final r in rows)
        InteractionRow(
          id: (r['id'] as int?) ?? 0,
          world: r['world'].toString(),
          itemKey: r['itemKey'].toString(),
          host: r['host'].toString(),
          kind: InteractionKind.fromName(r['kind'].toString()),
          value: (r['value'] as num?)?.toDouble() ?? 0,
          at: (r['at'] as int?) ?? 0,
          features: [
            for (final part in r['features'].toString().split(','))
              if (int.tryParse(part) case final int h) h,
          ],
        ),
    ];
  }

  /// Keeps the newest [keep] interactions of every world.
  Future<void> pruneInteractions({int keep = 20000}) async {
    final List? worlds = await db?.rawQuery('SELECT DISTINCT world FROM Interaction');
    if (worlds == null) return;
    for (final w in worlds) {
      final String world = w['world'].toString();
      await db?.rawDelete(
        'DELETE FROM Interaction WHERE world = ? AND id NOT IN '
        '(SELECT id FROM Interaction WHERE world = ? ORDER BY at DESC, id DESC LIMIT ?)',
        [world, world, keep],
      );
    }
  }

  Future<void> clearInteractions(String world) async {
    await db?.rawDelete('DELETE FROM Interaction WHERE world = ?', [world]);
  }

  Future<void> addFeatureNames(String world, Map<int, String> names) async {
    final db = this.db;
    if (db == null || names.isEmpty) return;
    final batch = db.batch();
    for (final entry in names.entries) {
      batch.rawInsert('INSERT OR IGNORE INTO RecommenderFeature(world, hash, name) VALUES(?,?,?)', [world, entry.key, entry.value]);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, String>> featureNames(String world, List<int> hashes) async {
    if (hashes.isEmpty) return const {};
    final Map<int, String> out = {};
    // Chunked: SQLite caps the number of bound variables.
    for (int start = 0; start < hashes.length; start += 500) {
      final List<int> chunk = hashes.sublist(start, (start + 500).clamp(0, hashes.length));
      final List? rows = await db?.rawQuery(
        'SELECT hash, name FROM RecommenderFeature WHERE world = ? AND hash IN (${List.filled(chunk.length, '?').join(',')})',
        [world, ...chunk],
      );
      for (final r in rows ?? const []) {
        out[(r['hash'] as int?) ?? -1] = r['name'].toString();
      }
    }
    return out;
  }

  Future<void> clearFeatureNames(String world) async {
    await db?.rawDelete('DELETE FROM RecommenderFeature WHERE world = ?', [world]);
  }

  /// The item keys of every logged interaction of [kind] in [world]
  /// (r34: what was marked "Not interested").
  Future<List<String>> interactionKeys(String world, String kind) async {
    final List? rows = await db?.rawQuery('SELECT DISTINCT itemKey FROM Interaction WHERE world = ? AND kind = ?', [world, kind]);
    return [for (final r in rows ?? const []) r['itemKey'].toString()];
  }
}
