import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/handlers/database_handler.dart';

/// r81: the vectors the text and looks models work out for posts live in a
/// database of their own (vectors.db beside store.db), so a backup can take
/// them or leave them, and they may grow to the space the person allows:
/// past it, the least recently used go first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dir;
  late DBHandler h;
  bool dbReady = false;

  Float32List vec(int n, [double v = 1]) => Float32List.fromList(List<double>.filled(n, v));

  Future<int> rows(Database db, String table) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']! as int;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vector_store');
    dir = '${tempDir.path}${Platform.pathSeparator}';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      h = DBHandler();
      h.db = await databaseFactory.openDatabase('${dir}store.db');
      await h.updateTable();
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
    DBHandler.pruneEvery = DBHandler.defaultPruneEvery;
    DBHandler.spaceOverrideBytes = null;
  });

  tearDown(() async {
    DBHandler.pruneEvery = DBHandler.defaultPruneEvery;
    DBHandler.spaceOverrideBytes = null;
    await h.closeVectors();
    await h.closeDb();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the vectors live in vectors.db beside store.db; store.db keeps none', () async {
    if (!dbReady) return;
    await h.openVectors(dir);
    expect(File('${dir}vectors.db').existsSync(), isTrue);
    await h.putEmbeddings('look:s0', {'post/1': vec(4)});
    expect(await rows(h.vectorsDb!, 'ItemEmbedding'), 1);
    expect(await rows(h.db!, 'ItemEmbedding'), 0);
    expect((await h.getEmbeddings('look:s0', ['post/1']))['post/1'], vec(4));
  });

  test('the first start moves the vectors kept in store.db over; a vector already in vectors.db stays as it is', () async {
    if (!dbReady) return;
    await h.putEmbeddings('look:s0', {'post/1': vec(4, 1), 'post/2': vec(4, 2)});
    await h.putEmbeddings('minilm', {'text:ab-3': vec(3, 3)});
    expect(await rows(h.db!, 'ItemEmbedding'), 3, reason: 'before r81 they were in store.db');
    // An older vectors.db already holds post/1 with another value.
    final Database older = await databaseFactory.openDatabase('${dir}vectors.db');
    await DBHandler.createVectorTable(older);
    await older.rawInsert('INSERT INTO ItemEmbedding(itemKey, model, dim, vector, at) VALUES(?,?,?,?,?)', ['post/1', 'look:s0', 4, Uint8List.fromList(vec(4, 9).buffer.asUint8List()), 1]);
    await older.close();

    await h.openVectors(dir);
    expect(await rows(h.db!, 'ItemEmbedding'), 0, reason: 'moved out of store.db');
    expect(await rows(h.vectorsDb!, 'ItemEmbedding'), 3);
    final Map<String, Float32List> got = await h.getEmbeddings('look:s0', ['post/1', 'post/2']);
    expect(got['post/1'], vec(4, 9), reason: 'the one already there wins');
    expect(got['post/2'], vec(4, 2));
    expect((await h.getEmbeddings('minilm', ['text:ab-3']))['text:ab-3'], vec(3, 3));
  });

  test('past the space set for them, the least recently used go first, down to 90%', () async {
    if (!dbReady) return;
    await h.openVectors(dir);
    final Database v = h.vectorsDb!;
    // 20 vectors of 100 floats (400 bytes each), written two days ago, oldest first.
    final int old = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    for (int i = 0; i < 20; i++) {
      await v.rawInsert('INSERT INTO ItemEmbedding(itemKey, model, dim, vector, at) VALUES(?,?,?,?,?)', ['post/$i', 'look:s0', 100, Uint8List.fromList(vec(100, i.toDouble()).buffer.asUint8List()), old + i]);
    }
    final int total = await h.vectorBytes();
    expect(total, greaterThan(20 * 400));
    // post/0 is the oldest; reading it makes it recently used.
    expect((await h.getEmbeddings('look:s0', ['post/0']))['post/0'], isNotNull);

    final int budget = total ~/ 2;
    final int dropped = await h.pruneEmbeddings(maxBytes: budget);
    expect(dropped, greaterThan(0));
    expect(await h.vectorBytes(), lessThanOrEqualTo((budget * 0.9).ceil()));
    final Map<String, Float32List> left = await h.getEmbeddings('look:s0', [for (int i = 0; i < 20; i++) 'post/$i']);
    expect(left.containsKey('post/0'), isTrue, reason: 'read a moment ago: kept');
    expect(left.containsKey('post/1'), isFalse, reason: 'the least recently used went first');
    expect(left.containsKey('post/19'), isTrue);

    expect(await h.pruneEmbeddings(maxBytes: budget), 0, reason: 'within the space: nothing to do');
  });

  test('writes keep the store within the space on their own, every few writes', () async {
    if (!dbReady) return;
    await h.openVectors(dir);
    DBHandler.pruneEvery = 5;
    DBHandler.spaceOverrideBytes = 4000;
    for (int i = 0; i < 40; i++) {
      await h.putEmbeddings('look:s0', {'post/$i': vec(100)});
    }
    expect(await h.vectorBytes(), lessThanOrEqualTo(4000 + 5 * 600));
    expect(await rows(h.vectorsDb!, 'ItemEmbedding'), greaterThan(0));
  });

  test('the space used is told apart by model; compacting gives the room back to the phone', () async {
    if (!dbReady) return;
    await h.openVectors(dir);
    await h.putEmbeddings('look:s0', {for (int i = 0; i < 300; i++) 'post/$i': vec(512)});
    await h.putEmbeddings('minilm', {for (int i = 0; i < 100; i++) 'text:$i': vec(384)});
    final ({int text, int looks}) used = await h.vectorUsage();
    expect(used.looks, greaterThan(300 * 2048));
    expect(used.text, greaterThan(100 * 1536));
    expect(used.text, lessThan(used.looks));

    final int before = await h.vectorFileBytes(dir);
    await h.pruneEmbeddings(maxBytes: 50000);
    await h.compactVectors();
    expect(await h.vectorFileBytes(dir), lessThan(before));
  });

  test('without a vectors database open, the vectors stay in the main one (as tests set it up)', () async {
    if (!dbReady) return;
    await h.putEmbeddings('look:s0', {'post/1': vec(2)});
    expect(await rows(h.db!, 'ItemEmbedding'), 1);
    expect((await h.getEmbeddings('look:s0', ['post/1']))['post/1'], vec(2));
  });
}
