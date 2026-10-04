part of '../database_handler.dart';

/// The kemono.cr / pawchive.pw creator indexes.
extension DBKemonoCreators on DBHandler {
  Future<void> upsertKemonoCreators(List<List<Object?>> rows, int seenAt, {String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null || rows.isEmpty) return;
    final String t = DBHandler.creatorTable(table);
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.rawInsert(
          'INSERT OR REPLACE INTO $t(service, id, name, indexed, updated, favorited, seenAt) VALUES(?,?,?,?,?,?,?)',
          [...row, seenAt],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> pruneKemonoCreators({required int seenBefore, String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null) return 0;
    return db.rawDelete('DELETE FROM ${DBHandler.creatorTable(table)} WHERE seenAt < ?', [seenBefore]);
  }

  Future<int> countKemonoCreators({String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM ${DBHandler.creatorTable(table)}');
    return int.tryParse(rows.first['c']?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, Object?>>> findKemonoCreatorsByName(String name, {int limit = 5, String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null || name.isEmpty) return const [];
    return db.rawQuery(
      'SELECT service, id, name, indexed, updated, favorited FROM ${DBHandler.creatorTable(table)} '
      'WHERE name = ? COLLATE NOCASE ORDER BY favorited DESC LIMIT ?',
      [name, limit],
    );
  }
}
