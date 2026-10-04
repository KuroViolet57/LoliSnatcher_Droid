import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sqflite/sqflite.dart';

import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_tag.dart';
import 'package:lolisnatcher/models/collection_info.dart';
import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/models/history_item.dart';
import 'package:lolisnatcher/models/pinned_tag.dart';
import 'package:lolisnatcher/features/tags/logic/pinned_tag_visibility.dart';
import 'package:lolisnatcher/models/saved_search.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/rewards.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
part 'database_handler/schema.dart';
part 'database_handler/maintenance.dart';
part 'database_handler/booru_items.dart';
part 'database_handler/tags.dart';
part 'database_handler/collections.dart';
part 'database_handler/recommender_log.dart';
part 'database_handler/vectors.dart';
part 'database_handler/booru_tags.dart';
part 'database_handler/kemono_creators.dart';
part 'database_handler/history.dart';
part 'database_handler/pins_reader.dart';

///////////////////////////////////////////////////////////////
/// WARNING:
/// On desktop releases you need to add sqlite3.dll for windows and have sqlite3 installed for linux
/// https://www.sqlite.org/download.html
/// https://archlinux.org/packages/core/x86_64/sqlite/
/// https://pub.dev/packages/sqflite_common_ffi
///////////////////////////////////////////////////////////////

enum BooruUpdateMode { local, urlUpdate, sync }

class DBHandler {
  DBHandler();
  Database? db;

  Future<void> closeDb() async {
    await db?.close();
    db = null;
  }

  /// Connects to the database file and create the database if the tables dont exist
  Future<bool> dbConnect(
    String path, {
    ValueChanged<String>? onStatusUpdate,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      db = await openDatabase(
        '${path}store.db',
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          try {
            await db.rawQuery('PRAGMA journal_mode=WAL;');
          } catch (e, s) {
            Logger.Inst().log(
              e.toString(),
              'DBHandler',
              'dbConnect',
              LogTypes.exception,
              s: s,
            );
          }
        },
      );
    } else if (Platform.isWindows || Platform.isLinux) {
      db = await databaseFactory.openDatabase('${path}store.db');
    }
    await updateTable();
    await createCriticalIndexes();
    // r81: the vectors in a database of their own.
    await openVectors(path);
    await purgeTagAliasMisses();
    await fixBooruItems(onStatusUpdate);
    await deleteUntracked();
    return true;
  }

  //
  // Behaviour signals (local "For You" recommender)
  //

  /// Half-life of an interest signal: after this many days without
  /// reinforcement a tag's score halves. Keeps the profile tracking current
  /// taste instead of everything ever clicked.
  static const double tagSignalHalfLifeDays = 30;

  static double decayedTagScore(double score, int updatedAtMs) {
    final double days = (DateTime.now().millisecondsSinceEpoch - updatedAtMs) / Duration.millisecondsPerDay;
    if (days <= 0) return score;
    return score * pow(0.5, days / tagSignalHalfLifeDays);
  }

  //
  // r34: item embeddings. r81: in a database of their own (vectors.db).
  //

  /// r81: the vectors the text and looks models work out for posts live in
  /// vectors.db beside store.db: it may grow to the space set for it
  /// (Settings → Recommendations → Models) and is an item of its own in a
  /// backup. Null until [openVectors]; the calls below then use [db], where
  /// they lived before r81 (tests open only that one).
  Database? vectorsDb;

  static const String vectorsFileName = 'vectors.db';

  /// r81: the vectors are kept within their space every this many writes.
  static const int defaultPruneEvery = 200;
  static int pruneEvery = defaultPruneEvery;

  /// Test seam: the space in bytes, instead of the setting.
  static int? spaceOverrideBytes;
  int _putsSincePrune = 0;

  /// A vector read this long after it was written (or last counted as
  /// used) counts as used again: a write for every read would be too many.
  static const Duration touchAfter = Duration(days: 1);

  /// What a row takes besides its vector, key and model name (an estimate).
  static const int rowOverhead = 24;

  static const String _rowBytes = 'LENGTH(vector) + LENGTH(itemKey) + LENGTH(model) + $rowOverhead';

  static Future<void> createVectorTable(Database db, {String schema = 'main'}) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $schema.ItemEmbedding ( '
      'itemKey TEXT NOT NULL, '
      'model TEXT NOT NULL, '
      'dim INTEGER NOT NULL, '
      'vector BLOB NOT NULL, '
      'at INTEGER NOT NULL, '
      'PRIMARY KEY (itemKey, model) '
      ')',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS $schema.ItemEmbedding_at ON ItemEmbedding(at)');
  }

  static int _settingBytes() {
    try {
      return SettingsHandler.instance.vectorSpaceMb * 1048576;
    } catch (_) {
      return 250 * 1048576;
    }
  }

  Future<List<Map<String, Object?>>> queryBooruTags({
    required String booruKey,
    String? nameLike,
    String? tagType,
    String? namespace,
    int limit = 60,
    int offset = 0,
  }) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty) return const [];
    final List<Object?> args = [booruKey];
    final StringBuffer where = StringBuffer('booruKey = ?');
    if (tagType != null) {
      where.write(' AND tagType = ?');
      args.add(tagType);
    }
    if (namespace != null) {
      where.write(' AND namespace = ?');
      args.add(namespace);
    }
    if (nameLike != null && nameLike.isNotEmpty) {
      where.write(' AND name LIKE ?');
      args.add('%$nameLike%');
    }
    args
      ..add(limit)
      ..add(offset);
    return db.rawQuery(
      'SELECT name, namespace, tagType, count, source, updatedAt, sourceId FROM BooruTag '
      'WHERE $where ORDER BY count DESC, name ASC LIMIT ? OFFSET ?',
      args,
    );
  }

  Future<int> countBooruTags(String booruKey, {String? tagType, String? namespace}) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty) return 0;
    final List<Object?> args = [booruKey];
    String where = 'booruKey = ?';
    if (tagType != null) {
      where += ' AND tagType = ?';
      args.add(tagType);
    }
    if (namespace != null) {
      where += ' AND namespace = ?';
      args.add(namespace);
    }
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM BooruTag WHERE $where', args);
    return int.tryParse(rows.first['c']?.toString() ?? '') ?? 0;
  }

  //
  // kemono creator index
  //

  /// Rows are `[service, id, name, indexed, updated, favorited]`.
  static const Set<String> _creatorTables = {'KemonoCreator', 'PawchiveCreator'};

  /// Only the two known creator tables: the name lands in SQL.
  static String creatorTable(String table) => _creatorTables.contains(table) ? table : 'KemonoCreator';

  static const Set<String> _kemonoSorts = {'favorited', 'updated', 'indexed', 'name'};

  Future<List<Map<String, Object?>>> queryKemonoCreators({
    String? nameLike,
    Set<String>? services,
    String orderBy = 'favorited',
    Set<String>? keys,
    int limit = 60,
    int offset = 0,
    String table = 'KemonoCreator',
  }) async {
    final db = this.db;
    if (db == null) return const [];
    final List<Object?> args = [];
    final List<String> where = [];
    if (nameLike != null && nameLike.isNotEmpty) {
      where.add('name LIKE ? COLLATE NOCASE');
      args.add('%$nameLike%');
    }
    if (services != null && services.isNotEmpty) {
      where.add('service IN (${List.filled(services.length, '?').join(',')})');
      args.addAll(services);
    }
    if (keys != null) {
      if (keys.isEmpty) return const [];
      where.add("(service || ':' || id) IN (${List.filled(keys.length, '?').join(',')})");
      args.addAll(keys);
    }
    final String order = switch (_kemonoSorts.contains(orderBy) ? orderBy : 'favorited') {
      'name' => 'name COLLATE NOCASE ASC',
      'updated' => 'updated DESC',
      'indexed' => 'indexed DESC',
      _ => 'favorited DESC',
    };
    args
      ..add(limit)
      ..add(offset);
    return db.rawQuery(
      'SELECT service, id, name, indexed, updated, favorited FROM ${creatorTable(table)} '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
      'ORDER BY $order, name COLLATE NOCASE ASC LIMIT ? OFFSET ?',
      args,
    );
  }

  Future<List<Map<String, Object?>>> getKemonoCreatorsByKeys(List<({String service, String id})> pairs, {String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null || pairs.isEmpty) return const [];
    final List<Map<String, Object?>> out = [];
    for (int i = 0; i < pairs.length; i += 400) {
      final slice = pairs.sublist(i, (i + 400).clamp(0, pairs.length));
      final rows = await db.rawQuery(
        'SELECT service, id, name, indexed, updated, favorited FROM ${creatorTable(table)} '
        "WHERE (service || ':' || id) IN (${List.filled(slice.length, '?').join(',')})",
        [for (final p in slice) '${p.service}:${p.id}'],
      );
      out.addAll(rows);
    }
    return out;
  }

  /// Get a list of tags from the database based on an input
  Future<List<String>> getTags(String queryStr, int limit) async {
    final List<String> tags = [];
    final result = await db?.rawQuery('SELECT DISTINCT name FROM Tag WHERE lower(name) LIKE (?) LIMIT $limit', [
      '${queryStr.toLowerCase()}%',
    ]);
    if (result != null && result.isNotEmpty) {
      for (int i = 0; i < result.length; i++) {
        tags.add(result[i]['name'].toString());
      }
    }
    return tags;
  }

  /// functions related to tab backup logic:
  Future<void> addTabRestore(String restore) async {
    final result = await db?.rawQuery('SELECT id FROM TabRestore ORDER BY id DESC LIMIT 1');
    if (result != null && result.isNotEmpty) {
      // replace existing entry
      await db?.rawUpdate('UPDATE TabRestore SET restore = ? WHERE id = ?;', [restore, result[0]['id'].toString()]);
    } else {
      // or add new if no entries
      await db?.rawInsert('INSERT INTO TabRestore(restore) VALUES(?);', [restore]);
    }

    // clear all then add a new one
    // await clearTabRestore();
    // await db?.rawInsert("INSERT INTO TabRestore(restore) VALUES(?);", [restore]);
    return;
  }

  Future<void> clearTabRestore() async {
    await db?.rawDelete('DELETE FROM TabRestore WHERE id IS NOT NULL;'); // remove previous items
    return;
  }
  ///////

  /// Remove duplicates and add every new search to history table
  Future<void> updateSearchHistory(String searchText, String? booruType, String? booruName) async {
    // trim extra spaces
    searchText = searchText.trim();

    // remove non-favourite duplicates of new entry
    const String notFavouriteQuery = "(isFavourite != '1' OR isFavourite is null)";
    await db?.rawDelete(
      'DELETE FROM SearchHistory WHERE searchText=? AND booruType=? AND booruName=? AND $notFavouriteQuery;',
      [searchText, booruType, booruName],
    );

    final favouriteDuplicates = await db?.rawQuery(
      "SELECT * FROM SearchHistory WHERE searchText=? AND booruType=? AND booruName=? AND isFavourite == '1';",
      [searchText, booruType, booruName],
    );
    if (favouriteDuplicates == null || favouriteDuplicates.isEmpty) {
      // insert new entry only if it wasn't favourited before
      await db?.rawInsert('INSERT INTO SearchHistory(searchText, booruType, booruName) VALUES(?,?,?)', [
        searchText,
        booruType,
        booruName,
      ]);
    } else {
      // otherwise update the last seartch time
      await db?.rawUpdate(
        "UPDATE SearchHistory SET timestamp = CURRENT_TIMESTAMP WHERE searchText=? AND booruType=? AND booruName=? AND isFavourite == '1';",
        [searchText, booruType, booruName],
      );
    }

    // remove everything except last X entries (ignores favourited)
    await db?.rawDelete(
      'DELETE FROM SearchHistory WHERE $notFavouriteQuery AND id NOT IN (SELECT id FROM SearchHistory WHERE $notFavouriteQuery ORDER BY id DESC LIMIT ${Constants.historyLimit});',
    );
  }

  /// Like [getSearchHistoryByInput], but keeps each row's booru name so the
  /// caller can drop rows belonging to another domain (doujin searches
  /// recorded before they got their own store).
  Future<List<({String searchText, String booruName})>> getSearchHistoryByInputWithBooru(
    String queryStr,
    int limit,
  ) async {
    final out = <({String searchText, String booruName})>[];
    final result = await db?.rawQuery(
      'SELECT DISTINCT searchText, booruName FROM SearchHistory WHERE lower(searchText) LIKE (?) LIMIT $limit',
      ['${queryStr.toLowerCase()}%'],
    );
    if (result != null) {
      for (final row in result) {
        out.add((searchText: row['searchText'].toString(), booruName: row['booruName']?.toString() ?? ''));
      }
    }
    return out;
  }

  ///////
  /// Seen posts (already-viewed dimming)

  // Cap so the table can't grow unbounded; trims oldest beyond this on insert.
  static const int _seenPostLimit = 100000;

  ///////
  /// Viewing history (full items, newest first — powers the History feed)

  // Cap so the table can't grow unbounded; trims oldest beyond this on insert.
  static const int _viewedPostLimit = 5000;

  // History rows use their own (de)serializer — BooruItem.fromMap is lossy
  // (drops rating/score/sources and stringifies Tag maps into garbage).
  static String serializeHistoryItem(BooruItem item) => jsonEncode({
    'postURL': item.postURL,
    'fileURL': item.fileURL,
    'sampleURL': item.sampleURL,
    'thumbnailURL': item.thumbnailURL,
    'tags': [for (final t in item.tagsList) t.fullString],
    'fileExt': item.fileExt,
    'serverId': item.serverId,
    'rating': item.rating,
    'score': item.score,
    'md5String': item.md5String,
    'sources': item.sources,
    'postDate': item.postDate,
    'postDateFormat': item.postDateFormat,
    'fileWidth': item.fileWidth,
    'fileHeight': item.fileHeight,
  });

  static BooruItem? deserializeHistoryItem(String jsonStr) {
    try {
      final Map<String, dynamic> j = jsonDecode(jsonStr);
      return BooruItem(
        fileURL: j['fileURL']?.toString() ?? '',
        sampleURL: j['sampleURL']?.toString() ?? '',
        thumbnailURL: j['thumbnailURL']?.toString() ?? '',
        postURL: j['postURL']?.toString() ?? '',
        tagsList: [for (final t in (j['tags'] as List? ?? [])) Tag(t.toString())],
        fileExt: j['fileExt']?.toString(),
        serverId: j['serverId']?.toString(),
        rating: j['rating']?.toString(),
        score: j['score']?.toString(),
        md5String: j['md5String']?.toString(),
        sources: (j['sources'] as List?)?.map((e) => e.toString()).toList(),
        postDate: j['postDate']?.toString(),
        postDateFormat: j['postDateFormat']?.toString(),
        fileWidth: double.tryParse(j['fileWidth']?.toString() ?? ''),
        fileHeight: double.tryParse(j['fileHeight']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  ///////
  /// Doujin reader progress

  Future<Map<String, Object?>?> getReaderProgress(String galleryKey) async {
    final List<Map<String, Object?>>? result = await db?.rawQuery(
      'SELECT page, totalPages, updatedAt FROM ReaderProgress WHERE galleryKey = ?',
      [galleryKey],
    );
    return (result?.isNotEmpty ?? false) ? result!.first : null;
  }

  /// Return a list of lists of boolean for isSnatched and isFavourite, attempt to make a bulk fetcher
  Future<List<List<bool>>> getMultipleTrackedValues(List<BooruItem> items) async {
    final List<List<bool>> values = [];

    // compare by post url, not file url (for example: r34xxx changes urls based on country)
    // TODO merge them by type? i.e. - (postURL in [] OR fileURL in [])
    bool byPostURL(BooruItem item) =>
        item.fileURL.contains('sankakucomplex.com') ||
        item.fileURL.contains('rule34.xxx') ||
        item.fileURL.contains('paheal.net');

    // 1.0: in chunks - at most 999 values in one statement on older Android,
    // and an OR chain at most 1000 deep.
    const int chunkSize = 500;
    final List<Map<String, dynamic>> result = [];
    for (int start = 0; start < items.length; start += chunkSize) {
      final List<String> queryParts = [];
      final List<String> queryArgs = [];
      for (final BooruItem item in items.sublist(start, min(items.length, start + chunkSize))) {
        if (byPostURL(item)) {
          queryParts.add('postURL = ?');
          queryArgs.add(item.postURL);
        } else {
          queryParts.add('fileURL = ?');
          queryArgs.add(item.fileURL);
        }
      }

      // DateTime startTime = DateTime.now();
      final List<Map<String, Object?>>? rows = await db?.rawQuery(
        "SELECT fileURL, postURL, isFavourite, isSnatched FROM BooruItem WHERE ${queryParts.join(' OR ')};",
        queryArgs,
      );
      // print("Query took ${DateTime.now().difference(startTime).inMilliseconds}ms"); // performance test
      if (rows == null) return values;
      result.addAll(rows);
    }

    for (final BooruItem item in items) {
      // 1.0: the row with the same post address first, as before; a row
      // looked up by its file and stored with another post address (http,
      // an older address format) no longer reads as not favourited and not
      // downloaded.
      final res = result.firstWhere(
        (el) => el['postURL'].toString() == item.postURL,
        orElse: () => byPostURL(item)
            ? {'isSnatched': 0, 'isFavourite': 0}
            : result.firstWhere(
                (el) => el['fileURL'].toString() == item.fileURL,
                orElse: () => {'isSnatched': 0, 'isFavourite': 0},
              ),
      );
      values.add([Tools.intToBool(res['isSnatched']), Tools.intToBool(res['isFavourite'])]);
    }
    return values;
  }
}
