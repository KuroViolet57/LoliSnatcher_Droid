part of '../database_handler.dart';

/// The tables and indexes store.db must have; run on every open (dbConnect).
extension DBSchema on DBHandler {
  Future<bool> updateTable() async {
    // 1.0: the CREATE TABLE IF NOT EXISTS statements go in one batch: one
    // platform call at every start instead of one each (test/db_schema_test
    // checks the schema is still exactly r89's).
    final Batch? ddl = db?.batch();
    ddl?.execute(
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
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS Tag ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT '
      'tagType TEXT '
      'updatedAt INTEGER '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS ImageTag ( '
      'tagID INTEGER, '
      'booruItemID INTEGER '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS SearchHistory ( '
      'id INTEGER PRIMARY KEY, '
      'booruType TEXT, '
      'booruName TEXT, '
      'searchText TEXT, '
      'isFavourite INTEGER, '
      'timestamp TEXT DEFAULT CURRENT_TIMESTAMP '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS TabRestore ( '
      'id INTEGER PRIMARY KEY, '
      'restore TEXT '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS PinnedTag ( '
      'id INTEGER PRIMARY KEY, '
      'tagName TEXT NOT NULL, '
      'booruType TEXT, '
      'booruName TEXT, '
      'pinnedAt INTEGER NOT NULL, '
      'sortOrder INTEGER DEFAULT 0, '
      'label TEXT, '
      'title TEXT '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS SavedSearch ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT, '
      'payload TEXT NOT NULL, '
      'createdAt INTEGER NOT NULL '
      ')',
    );
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS SeenPost ( '
      'postKey TEXT PRIMARY KEY, '
      'viewedAt INTEGER NOT NULL '
      ')',
    );
    // Viewing history: full serialized items so the History feed can render
    // thumbnails and reopen posts without re-fetching. SeenPost stays the
    // lightweight key set for grid dimming.
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS ViewedPost ( '
      'postKey TEXT PRIMARY KEY, '
      'itemJson TEXT NOT NULL, '
      'viewedAt INTEGER NOT NULL '
      ')',
    );
    ddl?.execute(
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
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS TagSignal ( '
      'name TEXT PRIMARY KEY, '
      'score REAL NOT NULL, '
      'updatedAt INTEGER NOT NULL '
      ')',
    );
    // r33: the recommender's training log — one row per interaction that
    // teaches the model (RecommenderHandler), with the item's feature hashes
    // at the time, so the model can be rebuilt from the log alone. Never
    // leaves the device.
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS Interaction ( '
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'world TEXT NOT NULL, '
      'itemKey TEXT NOT NULL, '
      'host TEXT NOT NULL, '
      'kind TEXT NOT NULL, '
      'value REAL NOT NULL, '
      'at INTEGER NOT NULL, '
      'features TEXT NOT NULL '
      ')',
    );
    // The names behind the feature hashes, so "what was learned" reads back
    // as tags and artists rather than numbers.
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS RecommenderFeature ( '
      'world TEXT NOT NULL, '
      'hash INTEGER NOT NULL, '
      'name TEXT NOT NULL, '
      'PRIMARY KEY (world, hash) '
      ')',
    );
    // r34: an item's vector from the downloaded encoder, per model, so an
    // item is read once. Never leaves the device.
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS ItemEmbedding ( '
      'itemKey TEXT NOT NULL, '
      'model TEXT NOT NULL, '
      'dim INTEGER NOT NULL, '
      'vector BLOB NOT NULL, '
      'at INTEGER NOT NULL, '
      'PRIMARY KEY (itemKey, model) '
      ')',
    );
    // Cross-booru tag alias cache: how <sourceTag> is spelled on <booruKey>
    // (e.g. burnice_white -> burnice_white_(zenless_zone_zero) on gelbooru).
    // Resolved on demand against each booru's tag-autocomplete API. An empty
    // targetTag records a confirmed miss so it isn't retried constantly.
    ddl?.execute(
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
    ddl?.execute(
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
    ddl?.execute(
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
    ddl?.execute(
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
    ddl?.execute(
      'CREATE TABLE IF NOT EXISTS Collection ( '
      'id INTEGER PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'createdAt INTEGER NOT NULL, '
      'sortOrder INTEGER DEFAULT 0 '
      ')',
    );
    ddl?.execute(
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
    ddl?.execute(
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
    ddl?.execute(
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
    await ddl?.commit(noResult: true);
    // r50: a pin's own name.
    try {
      if (!await columnExists('PinnedTag', 'title')) {
        await db?.execute('ALTER TABLE PinnedTag ADD COLUMN title TEXT;');
      }
    } catch (_) {}
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
    // 1.0: one batch, one platform call (see updateTable).
    final Batch? indexes = db?.batch();
    // postURL: de-dup / favourite lookup, hit per fetched item and DB write.
    indexes?.execute('CREATE INDEX IF NOT EXISTS BooruItem_postURL_index ON BooruItem (postURL);');
    // Tag.name: colour/type resolution, suggestions, id lookup.
    indexes?.execute('CREATE INDEX IF NOT EXISTS Tag_name_index ON Tag (name);');
    // PinnedTag.tagName: pin scoping / follow lookups.
    indexes?.execute('CREATE INDEX IF NOT EXISTS PinnedTag_tagName_index ON PinnedTag (tagName);');
    // Recency ordering for the History feed and the seen/viewed trims.
    indexes?.execute('CREATE INDEX IF NOT EXISTS ViewedPost_viewedAt_index ON ViewedPost (viewedAt);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS SeenPost_viewedAt_index ON SeenPost (viewedAt);');
    // The recommender replays and prunes its log per world, newest first.
    indexes?.execute('CREATE INDEX IF NOT EXISTS Interaction_world_at_index ON Interaction (world, at);');
    // Tag browser: every query is "this booru, optionally this type, ordered
    // by count" — without this it degrades into a full scan of a table that
    // can hold a site's entire tag database.
    indexes?.execute(
      'CREATE INDEX IF NOT EXISTS BooruTag_browse_index ON BooruTag (booruKey, tagType, count DESC);',
    );
    // Tag builder: "this source, this namespace, most used first".
    indexes?.execute(
      'CREATE INDEX IF NOT EXISTS BooruTag_ns_index ON BooruTag (booruKey, namespace, count DESC);',
    );
    // kemono's creator index: name search, and the Artists page's sorts.
    indexes?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_name_index ON KemonoCreator (name COLLATE NOCASE);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_updated_index ON KemonoCreator (updated DESC);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS KemonoCreator_favorited_index ON KemonoCreator (favorited DESC);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_name_index ON PawchiveCreator (name COLLATE NOCASE);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_updated_index ON PawchiveCreator (updated DESC);');
    indexes?.execute('CREATE INDEX IF NOT EXISTS PawchiveCreator_favorited_index ON PawchiveCreator (favorited DESC);');
    await indexes?.commit(noResult: true);
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
}
