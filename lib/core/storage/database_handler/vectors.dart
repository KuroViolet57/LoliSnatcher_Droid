part of '../database_handler.dart';

/// The vectors database (vectors.db): text and looks embeddings, its space limit and pruning.
extension DBVectors on DBHandler {
  /// Where the vector calls go.
  Database? get vectorDatabase => vectorsDb ?? db;

  /// Opens vectors.db in [dir] (with a trailing separator). The vectors
  /// store.db holds move there first: on the first start of r81, and after
  /// a whole restore of an older backup, whose store.db still holds them.
  Future<void> openVectors(String dir) async {
    final String file = '$dir${DBHandler.vectorsFileName}';
    try {
      await _moveVectorsOut(file);
    } catch (e, s) {
      Logger.Inst().log('vectors could not move out of store.db: $e', 'DBHandler', 'openVectors', LogTypes.exception, s: s);
    }
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        vectorsDb = await openDatabase(
          file,
          version: 1,
          singleInstance: false,
          onConfigure: (Database d) async {
            try {
              await d.rawQuery('PRAGMA journal_mode=WAL;');
            } catch (_) {}
          },
        );
      } else {
        vectorsDb = await databaseFactory.openDatabase(file);
      }
      await DBHandler.createVectorTable(vectorsDb!);
    } catch (e, s) {
      Logger.Inst().log('the vectors database could not be opened ($e); vectors stay in store.db', 'DBHandler', 'openVectors', LogTypes.exception, s: s);
      vectorsDb = null;
    }
  }

  Future<void> _moveVectorsOut(String file) async {
    final Database? main = db;
    if (main == null) return;
    final List<Map<String, Object?>> table = await main.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ItemEmbedding'");
    if (table.isEmpty) return;
    final int count = (await main.rawQuery('SELECT COUNT(*) AS n FROM ItemEmbedding')).first['n'] as int? ?? 0;
    if (count == 0) return;
    await main.execute('ATTACH DATABASE ? AS v', [file]);
    try {
      await DBHandler.createVectorTable(main, schema: 'v');
      await main.transaction((Transaction txn) async {
        // A vector already in vectors.db stays as it is.
        await txn.execute(
          'INSERT OR IGNORE INTO v.ItemEmbedding(itemKey, model, dim, vector, at) SELECT itemKey, model, dim, vector, at FROM main.ItemEmbedding',
        );
        await txn.execute('DELETE FROM main.ItemEmbedding');
      });
    } finally {
      await main.execute('DETACH DATABASE v');
    }
    Logger.Inst().log('vectors: $count moved from store.db to ${DBHandler.vectorsFileName}', 'DBHandler', 'openVectors', LogTypes.booruHandlerInfo);
  }

  Future<void> closeVectors() async {
    final Database? v = vectorsDb;
    vectorsDb = null;
    await v?.close();
  }

  Future<void> putEmbeddings(String model, Map<String, Float32List> vectors) async {
    final Database? db = vectorDatabase;
    if (db == null || vectors.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final entry in vectors.entries) {
      final Float32List v = entry.value;
      batch.rawInsert(
        'INSERT OR REPLACE INTO ItemEmbedding(itemKey, model, dim, vector, at) VALUES(?,?,?,?,?)',
        [entry.key, model, v.length, Uint8List.fromList(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes)), now],
      );
    }
    await batch.commit(noResult: true);
    // r81: kept within their space here, whoever writes them.
    _putsSincePrune += vectors.length;
    if (_putsSincePrune >= DBHandler.pruneEvery) {
      _putsSincePrune = 0;
      await pruneEmbeddings();
    }
  }

  /// r81: a vector read here counts as used (at most once a [touchAfter]),
  /// so the ones For You and boards keep reading are the last to go.
  Future<Map<String, Float32List>> getEmbeddings(String model, List<String> keys) async {
    final Database? db = vectorDatabase;
    if (keys.isEmpty || db == null) return const {};
    final Map<String, Float32List> out = {};
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int stale = now - DBHandler.touchAfter.inMilliseconds;
    for (int start = 0; start < keys.length; start += 400) {
      final List<String> chunk = keys.sublist(start, (start + 400).clamp(0, keys.length));
      final List rows = await db.rawQuery(
        'SELECT itemKey, dim, vector, at FROM ItemEmbedding WHERE model = ? AND itemKey IN (${List.filled(chunk.length, '?').join(',')})',
        [model, ...chunk],
      );
      final List<String> used = [];
      for (final r in rows) {
        final dynamic blob = r['vector'];
        final int dim = (r['dim'] as int?) ?? 0;
        if (blob is! List<int> || dim <= 0 || blob.length != dim * 4) continue;
        // A copy of its own: the driver's bytes need not be 4-byte aligned.
        final Uint8List bytes = Uint8List.fromList(blob);
        final String key = r['itemKey'].toString();
        out[key] = Float32List.view(bytes.buffer, 0, dim);
        if (((r['at'] as int?) ?? 0) < stale) used.add(key);
      }
      if (used.isNotEmpty) {
        try {
          await db.rawUpdate(
            'UPDATE ItemEmbedding SET at = ? WHERE model = ? AND itemKey IN (${List.filled(used.length, '?').join(',')})',
            [now, model, ...used],
          );
        } catch (_) {
          // A read never fails for want of marking the vectors used.
        }
      }
    }
    return out;
  }

  Future<void> clearEmbeddings(String model) async {
    if (model.isEmpty) return;
    await vectorDatabase?.rawDelete('DELETE FROM ItemEmbedding WHERE model = ?', [model]);
  }

  Future<int> countEmbeddings(String model) async {
    final List? rows = await vectorDatabase?.rawQuery('SELECT COUNT(*) AS n FROM ItemEmbedding WHERE model = ?', [model]);
    return (rows?.firstOrNull?['n'] as int?) ?? 0;
  }

  /// r81: what the vectors take, in bytes (their rows, estimated).
  Future<int> vectorBytes() async {
    final List? rows = await vectorDatabase?.rawQuery('SELECT COALESCE(SUM(${DBHandler._rowBytes}), 0) AS b FROM ItemEmbedding');
    return (rows?.firstOrNull?['b'] as int?) ?? 0;
  }

  /// r81: [vectorBytes] told apart: the looks model's rows are named
  /// `look:<model>`, the text model's by the model alone.
  Future<({int text, int looks})> vectorUsage() async {
    final List? rows = await vectorDatabase?.rawQuery('SELECT model, COALESCE(SUM(${DBHandler._rowBytes}), 0) AS b FROM ItemEmbedding GROUP BY model');
    int text = 0;
    int looks = 0;
    for (final r in rows ?? const []) {
      final int b = (r['b'] as int?) ?? 0;
      if (r['model'].toString().startsWith('look:')) {
        looks += b;
      } else {
        text += b;
      }
    }
    return (text: text, looks: looks);
  }

  /// The vectors' file on disk, with its journal.
  Future<int> vectorFileBytes(String dir) async {
    int total = 0;
    for (final String suffix in ['', '-wal']) {
      final File f = File('$dir${DBHandler.vectorsFileName}$suffix');
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  /// r81: keeps the vectors within [maxBytes] (the setting when not given):
  /// the least recently used go first, down to 90% so it does not run again
  /// at the next write. Returns how many went.
  Future<int> pruneEmbeddings({int? maxBytes}) async {
    final Database? db = vectorDatabase;
    if (db == null) return 0;
    final int limit = maxBytes ?? DBHandler.spaceOverrideBytes ?? DBHandler._settingBytes();
    int bytes = await vectorBytes();
    if (bytes <= limit) return 0;
    final int target = (limit * 0.9).floor();
    int dropped = 0;
    for (int round = 0; round < 8 && bytes > target; round++) {
      final int count = (await db.rawQuery('SELECT COUNT(*) AS n FROM ItemEmbedding')).first['n'] as int? ?? 0;
      if (count == 0) break;
      final int drop = ((bytes - target) / (bytes / count)).ceil().clamp(1, count);
      dropped += await db.rawDelete('DELETE FROM ItemEmbedding WHERE rowid IN (SELECT rowid FROM ItemEmbedding ORDER BY at ASC LIMIT ?)', [drop]);
      bytes = await vectorBytes();
    }
    if (dropped > 0) {
      Logger.Inst().log('vectors: $dropped least used removed to stay within ${(limit / 1048576).toStringAsFixed(0)} MB', 'DBHandler', 'pruneEmbeddings', LogTypes.booruHandlerInfo);
    }
    return dropped;
  }

  /// r81: gives the room of removed vectors back to the phone.
  Future<void> compactVectors() async {
    final Database? v = vectorsDb;
    if (v == null) return;
    await v.execute('VACUUM');
    try {
      await v.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }
}
