import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// r80: parts of the database a restore can take on their own, instead of
/// replacing the whole file (favourites, history, collections and all).
enum DbPart {
  /// Tag lists pulled from the sources, your corrections to them, and the
  /// cross-source tag spellings.
  pulledTags,

  /// What the recommender learned from: every reaction (the log it can rebuild
  /// itself from), the names behind its features, and For You's interests.
  recommenderLog,

  /// The text and picture vectors already computed for posts.
  vectorCache,
}

class DbParts {
  const DbParts._();

  /// The tables each part is.
  static const Map<DbPart, List<String>> tables = {
    DbPart.pulledTags: ['BooruTag', 'BooruTagOverride', 'TagAliasCache'],
    DbPart.recommenderLog: ['Interaction', 'RecommenderFeature', 'TagSignal'],
    DbPart.vectorCache: ['ItemEmbedding'],
  };

  /// The log replaces this device's own, so it matches the restored learning
  /// (two logs mixed would count reactions twice when the model is rebuilt).
  /// Tags and vectors are merged in: nothing already here is lost.
  static bool replaces(DbPart part) => part == DbPart.recommenderLog;

  static String labelOf(DbPart part) {
    switch (part) {
      case DbPart.pulledTags:
        return 'Pulled tags';
      case DbPart.recommenderLog:
        return 'Recommendation log and For You interests';
      case DbPart.vectorCache:
        return 'Vector cache';
    }
  }

  static String describe(DbPart part) {
    switch (part) {
      case DbPart.pulledTags:
        return "The sources' tag lists, your corrections and tag spellings - added to what is here.";
      case DbPart.recommenderLog:
        return "Every reaction the recommender learned from and For You's interests - replaces this device's.";
      case DbPart.vectorCache:
        return 'From a backup made before build 111, whose database still held the vectors - added to what is here. Newer backups carry them as the item "Vector cache".';
    }
  }

  /// Copies [parts] from the database file [backup] into [live], column by
  /// column where both have them (a backup from an older version may lack
  /// some). Returns the tables the backup does not have.
  ///
  /// r81: the vector cache goes into [vectors], the database the vectors
  /// have of their own (into [live] when there is none).
  static Future<List<String>> restore(File backup, Set<DbPart> parts, Database live, {Database? vectors}) async {
    final List<String> skipped = [];
    for (final DbPart part in DbPart.values) {
      if (!parts.contains(part)) continue;
      final Database into = part == DbPart.vectorCache && vectors != null ? vectors : live;
      skipped.addAll(await _copy(backup, into, tables[part]!, replace: replaces(part)));
    }
    return skipped;
  }

  /// r81: a backup's vectors.db added to the open vectors' database.
  static Future<List<String>> mergeVectors(File backup, Database live) => _copy(backup, live, tables[DbPart.vectorCache]!, replace: false);

  static Future<List<String>> _copy(File backup, Database into, List<String> tables, {required bool replace}) async {
    final List<String> skipped = [];
    await into.execute('ATTACH DATABASE ? AS bk', [backup.path]);
    try {
      for (final String table in tables) {
        final List<String> theirs = await _columns(into, 'bk', table);
        if (theirs.isEmpty) {
          skipped.add(table);
          continue;
        }
        final List<String> ours = await _columns(into, 'main', table);
        final List<String> both = theirs.where(ours.contains).toList();
        if (both.isEmpty) {
          skipped.add(table);
          continue;
        }
        final String cols = both.map((String c) => '"$c"').join(', ');
        await into.transaction((Transaction txn) async {
          if (replace) await txn.execute('DELETE FROM main."$table"');
          await txn.execute('INSERT OR REPLACE INTO main."$table" ($cols) SELECT $cols FROM bk."$table"');
        });
      }
    } finally {
      await into.execute('DETACH DATABASE bk');
    }
    return skipped;
  }

  static Future<List<String>> _columns(Database db, String schema, String table) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('PRAGMA $schema.table_info("$table")');
    return [for (final Map<String, Object?> r in rows) r['name']! as String];
  }
}
