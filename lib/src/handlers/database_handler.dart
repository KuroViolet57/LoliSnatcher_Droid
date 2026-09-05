import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sqflite/sqflite.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/collection_info.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/history_item.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/data/saved_search.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

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
    await purgeTagAliasMisses();
    await fixBooruItems(onStatusUpdate);
    await deleteUntracked();
    return true;
  }

  Future<bool> updateTable() async {
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS BooruItem '
      '(id INTEGER PRIMARY KEY, '
      'thumbnailURL TEXT, '
      'sampleURL TEXT, '
      'fileURL TEXT, '
      'postURL TEXT, '
      'mediaType TEXT, '
      'isSnatched INTEGER, '
      'isFavourite INTEGER '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS Tag ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT '
      'tagType TEXT '
      'updatedAt INTEGER '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS ImageTag ( '
      'tagID INTEGER, '
      'booruItemID INTEGER '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS SearchHistory ( '
      'id INTEGER PRIMARY KEY, '
      'booruType TEXT, '
      'booruName TEXT, '
      'searchText TEXT, '
      'isFavourite INTEGER, '
      'timestamp TEXT DEFAULT CURRENT_TIMESTAMP '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS TabRestore ( '
      'id INTEGER PRIMARY KEY, '
      'restore TEXT '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS PinnedTag ( '
      'id INTEGER PRIMARY KEY, '
      'tagName TEXT NOT NULL, '
      'booruType TEXT, '
      'booruName TEXT, '
      'pinnedAt INTEGER NOT NULL, '
      'sortOrder INTEGER DEFAULT 0, '
      'label TEXT '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS SavedSearch ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT, '
      'payload TEXT NOT NULL, '
      'createdAt INTEGER NOT NULL '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS SeenPost ( '
      'postKey TEXT PRIMARY KEY, '
      'viewedAt INTEGER NOT NULL '
      ')',
    );
    // Viewing history: full serialized items so the History feed can render
    // thumbnails and reopen posts without re-fetching. SeenPost stays the
    // lightweight key set for grid dimming.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS ViewedPost ( '
      'postKey TEXT PRIMARY KEY, '
      'itemJson TEXT NOT NULL, '
      'viewedAt INTEGER NOT NULL '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS TabVisitHistory ( '
      'id INTEGER PRIMARY KEY, '
      'tabId TEXT, '
      'tags TEXT, '
      'booruName TEXT, '
      'booruType TEXT, '
      'visitedAt INTEGER NOT NULL '
      ')',
    );
    // Behaviour signals for the local "For You" recommender: one row per tag
    // with an accumulated, time-decayed interest score. Written by
    // InterestsHandler; never leaves the device.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS TagSignal ( '
      'name TEXT PRIMARY KEY, '
      'score REAL NOT NULL, '
      'updatedAt INTEGER NOT NULL '
      ')',
    );
    // Cross-booru tag alias cache: how <sourceTag> is spelled on <booruKey>
    // (e.g. burnice_white -> burnice_white_(zenless_zone_zero) on gelbooru).
    // Resolved on demand against each booru's tag-autocomplete API. An empty
    // targetTag records a confirmed miss so it isn't retried constantly.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS TagAliasCache ( '
      'sourceTag TEXT NOT NULL, '
      'booruKey TEXT NOT NULL, '
      'targetTag TEXT NOT NULL, '
      'updatedAt INTEGER NOT NULL, '
      'PRIMARY KEY (sourceTag, booruKey) '
      ')',
    );
    // Per-booru tag snapshot: what a given SITE says its own tags are. The
    // global Tag table stores one type per tag string for the whole app,
    // which breaks down the moment two boorus disagree about the same string
    // — so per-site truth lives here instead of overloading that column.
    // `source`: 'api' (the site told us) | 'import' (a snapshot file).
    // `namespace`: the site's own grouping (artist/circle/female/…), part of
    // the key because a doujin site can file one name under two namespaces
    // (hitomi: female:ahegao and male:ahegao). '' for booru snapshots.
    // `sourceId`: the site's own id for the tag where its pages are keyed by
    // id rather than name (hentaipaw: `/tags/14390`). Null elsewhere.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS BooruTag ( '
      'booruKey TEXT NOT NULL, '
      "namespace TEXT NOT NULL DEFAULT '', "
      'name TEXT NOT NULL, '
      'tagType TEXT NOT NULL, '
      'count INTEGER NOT NULL DEFAULT 0, '
      "source TEXT NOT NULL DEFAULT 'api', "
      'updatedAt INTEGER NOT NULL, '
      'sourceId TEXT, '
      'PRIMARY KEY (booruKey, namespace, name) '
      ')',
    );
    // Your hand-made corrections, and — by existing at all — the permanent
    // exclusion list: a pair in here is never re-typed automatically again.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS BooruTagOverride ( '
      'booruKey TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'tagType TEXT NOT NULL, '
      "source TEXT NOT NULL DEFAULT 'manual', "
      'updatedAt INTEGER NOT NULL, '
      'PRIMARY KEY (booruKey, name) '
      ')',
    );
    // Doujin reading positions, keyed on "host|galleryId" (see
    // ReaderHandler.progressKey) so the key survives booru renames.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS ReaderProgress ( '
      'galleryKey TEXT NOT NULL PRIMARY KEY, '
      'page INTEGER NOT NULL, '
      'totalPages INTEGER NOT NULL, '
      'updatedAt INTEGER NOT NULL '
      ')',
    );
    // Collections / albums: named groups of posts. Membership is a join onto
    // the shared BooruItem table so in-collection tag search reuses the same
    // index; the items are protected from deleteUntracked below.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS Collection ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'createdAt INTEGER NOT NULL, '
      'sortOrder INTEGER DEFAULT 0 '
      ')',
    );
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS CollectionItem ( '
      'collectionId INTEGER NOT NULL, '
      'booruItemID INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL, '
      'PRIMARY KEY (collectionId, booruItemID) '
      ')',
    );
    // kemono's creator index (see KemonoCreatorStore): every creator the
    // site lists, so names, the Artists page and suggestions come from the
    // phone. `seenAt` marks the refresh that last listed a row; rows a later
    // refresh no longer lists are pruned by it.
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS KemonoCreator ( '
      'service TEXT NOT NULL, '
      'id TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'indexed INTEGER NOT NULL DEFAULT 0, '
      'updated INTEGER NOT NULL DEFAULT 0, '
      'favorited INTEGER NOT NULL DEFAULT 0, '
      'seenAt INTEGER NOT NULL, '
      'PRIMARY KEY (service, id) '
      ')',
    );
    // pawchive's index: same shape, its own table (same creator ids, another site).
    await db?.execute(
      'CREATE TABLE IF NOT EXISTS PawchiveCreator ( '
      'service TEXT NOT NULL, '
      'id TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'indexed INTEGER NOT NULL DEFAULT 0, '
      'updated INTEGER NOT NULL DEFAULT 0, '
      'favorited INTEGER NOT NULL DEFAULT 0, '
      'seenAt INTEGER NOT NULL, '
      'PRIMARY KEY (service, id) '
      ')',
    );
    try {
      if (!await columnExists('SearchHistory', 'isFavourite')) {
        await db?.execute('ALTER TABLE SearchHistory ADD COLUMN isFavourite INTEGER;');
      }
      if (!await columnExists('Tag', 'tagType')) {
        await db?.execute('ALTER TABLE Tag ADD COLUMN tagType TEXT;');
      }
      if (!await columnExists('Tag', 'updatedAt')) {
        await db?.execute('ALTER TABLE Tag ADD COLUMN updatedAt INTEGER;');
      }
      // When a row was snatched. Downloads list by this, newest first: the
      // row id is NOT the download order (a post favourited or collected
      // earlier keeps its old id), which buried fresh downloads deep in the
      // list. Null on rows snatched before this column existed.
      if (!await columnExists('BooruItem', 'snatchedAt')) {
        await db?.execute('ALTER TABLE BooruItem ADD COLUMN snatchedAt INTEGER;');
      }
      // BooruTag gained a namespace column IN ITS PRIMARY KEY; SQLite cannot
      // alter a key, so the table is rebuilt once. Existing rows keep every
      // value with an empty namespace.
      if (await tableExists('BooruTag') && !await columnExists('BooruTag', 'namespace')) {
        await db?.transaction((txn) async {
          await txn.execute('ALTER TABLE BooruTag RENAME TO BooruTag_old');
          await txn.execute(
            'CREATE TABLE BooruTag ( '
            'booruKey TEXT NOT NULL, '
            "namespace TEXT NOT NULL DEFAULT '', "
            'name TEXT NOT NULL, '
            'tagType TEXT NOT NULL, '
            'count INTEGER NOT NULL DEFAULT 0, '
            "source TEXT NOT NULL DEFAULT 'api', "
            'updatedAt INTEGER NOT NULL, '
            'PRIMARY KEY (booruKey, namespace, name) '
            ')',
          );
          await txn.execute(
            'INSERT OR IGNORE INTO BooruTag(booruKey, namespace, name, tagType, count, source, updatedAt) '
            "SELECT booruKey, '', name, tagType, count, source, updatedAt FROM BooruTag_old",
          );
          await txn.execute('DROP TABLE BooruTag_old');
        });
      }
      if (await tableExists('BooruTag') && !await columnExists('BooruTag', 'sourceId')) {
        await db?.execute('ALTER TABLE BooruTag ADD COLUMN sourceId TEXT;');
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Error updating table',
        'DBHandler',
        'updateTable',
        LogTypes.exception,
        s: s,
      );
    }
    return true;
  }

  Future<bool> tableExists(String tableName) async {
    final List<Map<String, Object?>>? result = await db?.rawQuery(
      "SELECT COUNT(*) AS count FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return result != null && result.isNotEmpty && (result[0]['count'] ?? 0) == 1;
  }

  Future<bool> columnExists(String tableName, String columnName) async {
    final List<Map<String, Object?>>? result = await db?.rawQuery(
      "SELECT COUNT(*) AS count FROM pragma_table_info('$tableName') WHERE name='$columnName'",
    );
    if (result != null && result.isNotEmpty) {
      if ((result[0]['count'] ?? 0) == 1) {
        return true;
      }
    }
    return false;
  }

  Future<bool> createIndexes() async {
    await db?.execute('CREATE INDEX IF NOT EXISTS ImageTag_tagID_index ON ImageTag (tagID);');
    await db?.execute('CREATE INDEX IF NOT EXISTS ImageTag_booruItemID_index ON ImageTag (booruItemID);');
    return true;
  }

  // Small, always-worth-it indexes on hot lookup columns — created on every
  // DB open regardless of the (heavy) ImageTag index toggle. Each of these
  // columns was previously scanned linearly on very common queries.
  Future<void> createCriticalIndexes() async {
    // postURL: de-dup / favourite lookup, hit per fetched item and DB write.
    await db?.execute('CREATE INDEX IF NOT EXISTS BooruItem_postURL_index ON BooruItem (postURL);');
    // Tag.name: colour/type resolution, suggestions, id lookup.
    await db?.execute('CREATE INDEX IF NOT EXISTS Tag_name_index ON Tag (name);');
    // PinnedTag.tagName: pin scoping / follow lookups.
    await db?.execute('CREATE INDEX IF NOT EXISTS PinnedTag_tagName_index ON PinnedTag (tagName);');
    // Recency ordering for the History feed and the seen/viewed trims.
    await db?.execute('CREATE INDEX IF NOT EXISTS ViewedPost_viewedAt_index ON ViewedPost (viewedAt);');
    await db?.execute('CREATE INDEX IF NOT EXISTS SeenPost_viewedAt_index ON SeenPost (viewedAt);');
    // Tag browser: every query is "this booru, optionally this type, ordered
    // by count" — without this it degrades into a full scan of a table that
    // can hold a site's entire tag database.
    await db?.execute(
      'CREATE INDEX IF NOT EXISTS BooruTag_browse_index ON BooruTag (booruKey, tagType, count DESC);',
    );
    // Tag builder: "this source, this namespace, most used first".
    await db?.execute(
      'CREATE INDEX IF NOT EXISTS BooruTag_ns_index ON BooruTag (booruKey, namespace, count DESC);',
    );
    // kemono's creator index: name search, and the Artists page's sorts.
    await db?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_name_index ON KemonoCreator (name COLLATE NOCASE);');
    await db?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_updated_index ON KemonoCreator (updated DESC);');
    await db?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_favorited_index ON KemonoCreator (favorited DESC);');
    await db?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_name_index ON PawchiveCreator (name COLLATE NOCASE);');
    await db?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_updated_index ON PawchiveCreator (updated DESC);');
    await db?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_favorited_index ON PawchiveCreator (favorited DESC);');
  }

  Future<bool> dropIndexes() async {
    await db?.execute('DROP INDEX IF EXISTS ImageTag_tagID_index;');
    await db?.execute('DROP INDEX IF EXISTS ImageTag_booruItemID_index;');
    await db?.execute('DROP INDEX IF EXISTS BooruItem_isSnatched_index;');
    await db?.execute('DROP INDEX IF EXISTS BooruItem_isFavourite_index;');
    await db?.execute('DROP INDEX IF EXISTS BooruItem_fileURL_index;');
    await db?.execute('DROP INDEX IF EXISTS BooruItem_id_index;');
    await db?.execute('DROP INDEX IF EXISTS BooruItem_fileURL_isFavourite_isSnatched_index;');
    await db?.execute('DROP INDEX IF EXISTS Tag_name_index;');
    await db?.execute('DROP INDEX IF EXISTS Tag_id_index;');
    return true;
  }

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
    final List? result = await db?.rawQuery(
      "SELECT id, postURL FROM BooruItem WHERE postURL IN (${List.generate(postURLs.length, (_) => '?').join(',')})",
      postURLs,
    );

    final List<String> ids = List.generate(postURLs.length, (index) => '');
    if (result != null && result.isNotEmpty) {
      for (final Map<String, dynamic> item in result) {
        final int postIndex = postURLs.indexOf(item['postURL']);
        if (postIndex != -1) {
          ids[postIndex] = item['id'].toString();
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
    bool isRandomOrder = false;
    bool isReverseOrder = false;

    for (final tag in rawTags) {
      final lowerTag = tag.toLowerCase();
      if (lowerTag.startsWith('site:') || lowerTag.startsWith('-site:')) {
        final isExclude = lowerTag.startsWith('-site:');
        final term = tag.replaceAll(RegExp('^-?site:', caseSensitive: false), '');
        siteQuery =
            "(bi.postURL ${isExclude ? 'NOT' : ''} LIKE '%$term%' OR bi.fileURL ${isExclude ? 'NOT' : ''} LIKE '%$term%') ";
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
    if (siteQuery.isNotEmpty) whereClauses.add(siteQuery);

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
        base = decayedTagScore(
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
            decayedTagScore((r['score'] as num?)?.toDouble() ?? 0, (r['updatedAt'] as int?) ?? 0),
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

  Future<List<Map<String, Object?>>> getBooruTagsByNames(String booruKey, List<String> names) async {
    final db = this.db;
    if (db == null || booruKey.isEmpty || names.isEmpty) return const [];
    final String placeholders = List.filled(names.length, '?').join(',');
    return db.rawQuery(
      'SELECT name, namespace, tagType, count, source, updatedAt, sourceId FROM BooruTag '
      'WHERE booruKey = ? AND name IN ($placeholders)',
      [booruKey, ...names],
    );
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

  Future<void> deleteBooruTags(String booruKey, {String? namespace}) async {
    if (namespace == null) {
      await db?.rawDelete('DELETE FROM BooruTag WHERE booruKey = ?', [booruKey]);
    } else {
      await db?.rawDelete('DELETE FROM BooruTag WHERE booruKey = ? AND namespace = ?', [booruKey, namespace]);
    }
  }

  //
  // kemono creator index
  //

  /// Rows are `[service, id, name, indexed, updated, favorited]`.
  static const Set<String> _creatorTables = {'KemonoCreator', 'PawchiveCreator'};

  /// Only the two known creator tables: the name lands in SQL.
  static String creatorTable(String table) => _creatorTables.contains(table) ? table : 'KemonoCreator';

  Future<void> upsertKemonoCreators(List<List<Object?>> rows, int seenAt, {String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null || rows.isEmpty) return;
    final String t = creatorTable(table);
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
    return db.rawDelete('DELETE FROM ${creatorTable(table)} WHERE seenAt < ?', [seenBefore]);
  }

  Future<int> countKemonoCreators({String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM ${creatorTable(table)}');
    return int.tryParse(rows.first['c']?.toString() ?? '') ?? 0;
  }

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

  Future<List<Map<String, Object?>>> findKemonoCreatorsByName(String name, {int limit = 5, String table = 'KemonoCreator'}) async {
    final db = this.db;
    if (db == null || name.isEmpty) return const [];
    return db.rawQuery(
      'SELECT service, id, name, indexed, updated, favorited FROM ${creatorTable(table)} '
      'WHERE name = ? COLLATE NOCASE ORDER BY favorited DESC LIMIT ?',
      [name, limit],
    );
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

  Future<List<Tag>> getAllTags() async {
    final List? result = await db?.rawQuery('SELECT name, tagType, updatedAt FROM Tag');
    final List<Tag> tags = [];
    if (result != null && result.isNotEmpty) {
      for (int i = 0; i < result.length; i++) {
        final currentItem = result[i];
        if (currentItem != null && currentItem.isNotEmpty) {
          tags.add(Tag.fromJson(currentItem));
        }
      }
    }
    return tags;
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

    for (final tag in rawTags) {
      final lowerTag = tag.toLowerCase();

      if (lowerTag.startsWith('site:') || lowerTag.startsWith('-site:')) {
        final isExclude = lowerTag.startsWith('-site:');
        final term = tag.replaceAll(RegExp('^-?site:', caseSensitive: false), '');
        siteQuery =
            "(bi.postURL ${isExclude ? 'NOT' : ''} LIKE '%$term%' OR bi.fileURL ${isExclude ? 'NOT' : ''} LIKE '%$term%')";
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
    if (siteQuery.isNotEmpty) whereClauses.add(siteQuery);

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

  /// Adds tags for a BooruItem to the database
  Future<void> updateTags(List<String> tags, String? itemID) async {
    if (itemID == null) {
      return;
    }
    String? id = '';
    // TODO rewrite using batch
    for (final tag in tags) {
      id = await getTagID(tag);
      if (id.isEmpty) {
        final result = await db?.rawInsert('INSERT INTO Tag(name) VALUES(?)', [tag]);
        id = result?.toString();
      }
      await db?.rawInsert('INSERT INTO ImageTag(tagID, booruItemID) VALUES(?,?)', [id, itemID]);
    }
  }

  /// Adds tags for a BooruItem to the database
  Future<void> updateTagsFromObjects(List<Tag> tags) async {
    String? id = '';
    // TODO rewrite using batch
    for (final tag in tags) {
      id = await getTagID(tag.fullString);
      if (id.isEmpty) {
        final result = await db?.rawInsert('INSERT INTO Tag(name, tagType, updatedAt) VALUES(?,?,?)', [
          tag.fullString,
          tag.tagType.name,
          tag.updatedAt,
        ]);
        id = result?.toString();
      } else {
        await db?.rawUpdate('UPDATE Tag SET tagType = ?,updatedAt = ? WHERE id = ?', [
          tag.tagType.name,
          tag.updatedAt,
          id,
        ]);
      }
    }
    return;
  }

  /// Gets a tag id from the database
  Future<String> getTagID(String tagName) async {
    // TODO rewrite using batch
    final result = await db?.rawQuery('SELECT id FROM Tag WHERE name IN (?)', [tagName]);
    if (result != null && result.isNotEmpty) {
      return result.first['id'].toString();
    } else {
      return '';
    }
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

  /// Get tags sorted by usage count (how many items they're attached to)
  /// If [queryStr] is provided, filters tags that start with the query
  /// Returns a list of maps with 'name' and 'count' keys
  Future<List<({String name, int count})>> getTagsByUsageCount(String? queryStr, int limit) async {
    final List<({String name, int count})> tags = [];

    String query;
    List<Object?> args;

    if (queryStr != null && queryStr.isNotEmpty) {
      query = '''
        SELECT t.name, COUNT(it.booruItemID) as count
        FROM Tag t
        LEFT JOIN ImageTag it ON t.id = it.tagID
        WHERE lower(t.name) LIKE (?)
        GROUP BY t.id
        ORDER BY count DESC
        LIMIT ?
      ''';
      args = ['${queryStr.toLowerCase()}%', limit];
    } else {
      query = '''
        SELECT t.name, COUNT(it.booruItemID) as count
        FROM Tag t
        LEFT JOIN ImageTag it ON t.id = it.tagID
        GROUP BY t.id
        ORDER BY count DESC
        LIMIT ?
      ''';
      args = [limit];
    }

    final result = await db?.rawQuery(query, args);
    if (result != null && result.isNotEmpty) {
      for (final row in result) {
        final name = row['name']?.toString() ?? '';
        final count = row['count'] as int? ?? 0;
        if (name.isNotEmpty) {
          tags.add((name: name, count: count));
        }
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

  ///////
  /// Seen posts (already-viewed dimming)

  // Cap so the table can't grow unbounded; trims oldest beyond this on insert.
  static const int _seenPostLimit = 100000;

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
      '(SELECT postKey FROM SeenPost ORDER BY viewedAt DESC LIMIT $_seenPostLimit)',
    );
  }

  Future<void> clearSeenPosts() async {
    await db?.rawDelete('DELETE FROM SeenPost');
  }

  ///////
  /// Viewing history (full items, newest first — powers the History feed)

  // Cap so the table can't grow unbounded; trims oldest beyond this on insert.
  static const int _viewedPostLimit = 5000;

  Future<void> addViewedPost(String postKey, String itemJson) async {
    if (postKey.isEmpty || itemJson.isEmpty) return;
    // INSERT OR REPLACE so a re-view bumps the entry back to the top.
    await db?.rawInsert(
      'INSERT OR REPLACE INTO ViewedPost(postKey, itemJson, viewedAt) VALUES(?, ?, ?)',
      [postKey, itemJson, DateTime.now().millisecondsSinceEpoch],
    );
    await db?.rawDelete(
      'DELETE FROM ViewedPost WHERE postKey NOT IN '
      '(SELECT postKey FROM ViewedPost ORDER BY viewedAt DESC LIMIT $_viewedPostLimit)',
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

  Future<List<BooruItem>> getViewedPosts(String filter, int offset, int limit) async {
    final (String where, List<String> args) = _viewedPostFilter(filter);
    final rows = await db?.rawQuery(
      'SELECT itemJson FROM ViewedPost $where ORDER BY viewedAt DESC LIMIT $limit OFFSET $offset',
      args,
    );
    if (rows == null || rows.isEmpty) return [];
    final List<BooruItem> items = [];
    for (final row in rows) {
      final BooruItem? item = deserializeHistoryItem(row['itemJson']!.toString());
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

  Future<void> removeCollectionItem(int collectionId, int booruItemId) async {
    await db?.rawDelete(
      'DELETE FROM CollectionItem WHERE collectionId = ? AND booruItemID = ?',
      [collectionId, booruItemId],
    );
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

  Future<void> updateReaderProgress(String galleryKey, int page, int totalPages, int updatedAt) async {
    await db?.rawInsert(
      'INSERT OR REPLACE INTO ReaderProgress (galleryKey, page, totalPages, updatedAt) VALUES (?, ?, ?, ?)',
      [galleryKey, page, totalPages, updatedAt],
    );
  }

  ///////
  /// Pinned Tags methods

  /// Add a pinned tag (global or booru-specific)
  Future<int?> addPinnedTag(
    String tagName, {
    String? booruType,
    String? booruName,
    List<String> labels = const [],
  }) async {
    // Check if already pinned with same scope
    final existing = await db?.rawQuery(
      'SELECT id FROM PinnedTag WHERE tagName = ? AND (booruName IS ? OR (booruName = ? AND booruType = ?))',
      [tagName, booruName, booruName, booruType],
    );
    if (existing != null && existing.isNotEmpty) {
      return null; // Already pinned
    }

    final pinnedAt = DateTime.now().millisecondsSinceEpoch;
    final labelsString = labels.isNotEmpty ? labels.join(',') : null;
    final result = await db?.rawInsert(
      'INSERT INTO PinnedTag(tagName, booruType, booruName, pinnedAt, sortOrder, label) VALUES(?, ?, ?, ?, ?, ?)',
      [tagName, booruType, booruName, pinnedAt, 0, labelsString],
    );
    return result;
  }

  /// Remove a pinned tag by id
  Future<void> removePinnedTag(int id) async {
    await db?.rawDelete('DELETE FROM PinnedTag WHERE id = ?', [id]);
  }

  /// Remove a pinned tag by tagName and scope
  Future<void> removePinnedTagByName(String tagName, {String? booruType, String? booruName}) async {
    if (booruName == null) {
      await db?.rawDelete('DELETE FROM PinnedTag WHERE tagName = ? AND booruName IS NULL', [tagName]);
    } else {
      await db?.rawDelete(
        'DELETE FROM PinnedTag WHERE tagName = ? AND booruName = ? AND booruType = ?',
        [tagName, booruName, booruType],
      );
    }
  }

  /// Get all pinned tags (both global and booru-specific for the given booru)
  Future<List<PinnedTag>> getPinnedTags({String? booruType, String? booruName}) async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      'SELECT * FROM PinnedTag WHERE booruName IS NULL OR (booruName = ? AND booruType = ?) ORDER BY sortOrder ASC, pinnedAt DESC',
      [booruName, booruType],
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    return result.map(PinnedTag.fromMap).toList();
  }

  /// Get all pinned tags (regardless of booru)
  Future<List<PinnedTag>> getAllPinnedTags() async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      'SELECT * FROM PinnedTag ORDER BY sortOrder ASC, pinnedAt DESC',
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    return result.map(PinnedTag.fromMap).toList();
  }

  /// Check if a tag is pinned (either globally or for specific booru)
  Future<PinnedTag?> getPinnedTag(String tagName, {String? booruType, String? booruName}) async {
    // First check for booru-specific pin
    if (booruName != null) {
      final booruSpecific = await db?.rawQuery(
        'SELECT * FROM PinnedTag WHERE tagName = ? AND booruName = ? AND booruType = ?',
        [tagName, booruName, booruType],
      );
      if (booruSpecific != null && booruSpecific.isNotEmpty) {
        return PinnedTag.fromMap(booruSpecific.first);
      }
    }

    // Then check for global pin
    final global = await db?.rawQuery(
      'SELECT * FROM PinnedTag WHERE tagName = ? AND booruName IS NULL',
      [tagName],
    );
    if (global != null && global.isNotEmpty) {
      return PinnedTag.fromMap(global.first);
    }

    return null;
  }

  /// Update sort order for pinned tags
  Future<void> updatePinnedTagOrder(int id, int sortOrder) async {
    await db?.rawUpdate('UPDATE PinnedTag SET sortOrder = ? WHERE id = ?', [sortOrder, id]);
  }

  /// Batch update sort order for multiple pinned tags
  Future<void> updatePinnedTagsOrder(List<PinnedTag> tags) async {
    final batch = db?.batch();
    for (int i = 0; i < tags.length; i++) {
      batch?.rawUpdate('UPDATE PinnedTag SET sortOrder = ? WHERE id = ?', [i, tags[i].id]);
    }
    await batch?.commit(noResult: true);
  }

  /// Update labels for a pinned tag (stored as comma-separated string)
  Future<void> updatePinnedTagLabels(int id, List<String> labels) async {
    final labelsString = labels.join(',');
    await db?.rawUpdate('UPDATE PinnedTag SET label = ? WHERE id = ?', [labelsString, id]);
  }

  /// Get all unique labels from pinned tags (parses comma-separated labels)
  Future<List<String>> getPinnedTagLabels({String? booruType, String? booruName}) async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      "SELECT DISTINCT label FROM PinnedTag WHERE label IS NOT NULL AND label != '' AND (booruName IS NULL OR (booruName = ? AND booruType = ?))",
      [booruName, booruType],
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    // Parse comma-separated labels and collect unique ones
    final Set<String> uniqueLabels = {};
    for (final row in result) {
      final labelString = row['label'] as String;
      final labels = labelString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      uniqueLabels.addAll(labels);
    }

    final labelsList = uniqueLabels.toList()..sort();
    return labelsList;
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

  /// Return a list of lists of boolean for isSnatched and isFavourite, attempt to make a bulk fetcher
  Future<List<List<bool>>> getMultipleTrackedValues(List<BooruItem> items) async {
    final List<List<bool>> values = [];

    final List<String> queryParts = [];
    final List<String> queryArgs = [];
    for (final BooruItem item in items) {
      if (item.fileURL.contains('sankakucomplex.com') ||
          item.fileURL.contains('rule34.xxx') ||
          item.fileURL.contains('paheal.net')) {
        // compare by post url, not file url (for example: r34xxx changes urls based on country)
        // TODO merge them by type? i.e. - (postURL in [] OR fileURL in [])
        queryParts.add('postURL = ?');
        queryArgs.add(item.postURL);
      } else {
        queryParts.add('fileURL = ?');
        queryArgs.add(item.fileURL);
      }
    }

    // DateTime startTime = DateTime.now();
    final List? result = await db?.rawQuery(
      "SELECT fileURL, postURL, isFavourite, isSnatched FROM BooruItem WHERE ${queryParts.join(' OR ')};",
      queryArgs,
    );
    // print("Query took ${DateTime.now().difference(startTime).inMilliseconds}ms"); // performance test

    if (result != null) {
      for (final BooruItem item in items) {
        final res = result.firstWhere(
          (el) => el['postURL'].toString() == item.postURL,
          orElse: () => {'isSnatched': 0, 'isFavourite': 0},
        );
        values.add([Tools.intToBool(res['isSnatched']), Tools.intToBool(res['isFavourite'])]);
      }
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
          final placeholders = List.filled(ids.length, '?').join(',');
          await txn.rawDelete('DELETE FROM ImageTag WHERE tagID IN ($placeholders)', ids);
          await txn.rawDelete('DELETE FROM Tag WHERE id IN ($placeholders)', ids);
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
