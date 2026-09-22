import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/services/db_parts.dart';

/// A backup target in memory, standing in for a folder or a Drive snapshot.
class _Memory implements BackupTarget {
  final Map<String, Uint8List> files = {};

  @override
  String get label => 'memory';

  @override
  Future<Set<String>> names() async => files.keys.toSet();

  @override
  Future<void> write(String name, List<int> bytes) async => files[name] = Uint8List.fromList(bytes);

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<void> writeFile(String name, File file) async => files[name] = await file.readAsBytes();

  @override
  Future<bool> readToFile(String name, File to) async {
    final Uint8List? b = files[name];
    if (b == null) return false;
    await to.parent.create(recursive: true);
    await to.writeAsBytes(b, flush: true);
    return true;
  }
}

/// r80: backup and restore choose what they carry - any mix of the app's
/// files, the recommender's learning included, and the database whole or in
/// parts - so a second device can be made to recommend like the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String config;
  late List<String> calls;
  late BackupHooks hooks;

  String p(String name) => '$config$name';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('backup_plan');
    config = '${tempDir.path}${Platform.pathSeparator}config${Platform.pathSeparator}';
    Directory(config).createSync(recursive: true);
    calls = [];
    hooks = BackupHooks(
      sourcesJson: () => '[{"name":"rule34xxx"}]',
      restoreSources: (String json) async => calls.add('sources $json'),
      tagTypesJson: () => '[{"name":"tag_a"}]',
      restoreTagTypes: (String json) async => calls.add('tag types $json'),
      reloadStores: () => calls.add('reload stores'),
      stopRecommenderWrites: () => calls.add('recommender stops writing'),
      checkpointDatabase: () async => calls.add('checkpoint'),
      closeDatabase: () async => calls.add('close database'),
      rearmDoujinMigration: () => calls.add('rearm migration'),
      boardPicturesDir: () => '${config}boards${Platform.pathSeparator}',
      liveDatabase: () => null,
    );
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the items', () {
    test('every item has a name and says what it holds', () {
      for (final BackupItem i in BackupItem.values) {
        expect(BackupItems.labelOf(i), isNotEmpty, reason: i.name);
        expect(BackupItems.describe(i).length, greaterThan(15), reason: i.name);
      }
      expect(BackupItem.values, contains(BackupItem.recommender));
    });

    test('the file names of a backup tell which items it holds - old backups included', () {
      expect(
        BackupItems.itemsIn(['settings.json', 'boorus.json', 'store.db', 'doujinData.json', 'tags.json']),
        {BackupItem.settings, BackupItem.sources, BackupItem.database, BackupItem.doujinLibrary, BackupItem.tagTypes},
      );
      expect(
        BackupItems.itemsIn(['recommender.booru.bin', 'board-picture.b1.jpg', 'something else.txt']),
        {BackupItem.recommender, BackupItem.boardPictures},
      );
    });
  });

  group('back up', () {
    test('only the ticked items are written, the recommender folder and board pictures file by file', () async {
      File(p('settings.json')).writeAsStringSync('{"a":1}');
      File(p('doujinData.json')).writeAsStringSync('{"d":1}');
      File(p('boards.json')).writeAsStringSync('[]');
      Directory(p('recommender')).createSync();
      File(p('recommender${Platform.pathSeparator}booru.bin')).writeAsBytesSync([1, 2, 3]);
      File(p('recommender${Platform.pathSeparator}booru.look-taste.json')).writeAsStringSync('{"t":1}');
      Directory(p('boards')).createSync();
      File(p('boards${Platform.pathSeparator}b1.jpg')).writeAsBytesSync([9, 9]);
      final _Memory target = _Memory();
      final BackupResult r = await BackupRunner(configDir: config, hooks: hooks).backup(
        {BackupItem.settings, BackupItem.recommender, BackupItem.boardPictures, BackupItem.sources},
        target,
      );
      expect(r.failures, isEmpty);
      expect(target.files.keys.toSet(), {
        'settings.json',
        'boorus.json',
        'recommender.booru.bin',
        'recommender.booru.look-taste.json',
        'board-picture.b1.jpg',
      });
      expect(target.files['recommender.booru.bin'], [1, 2, 3]);
      expect(utf8.decode(target.files['boorus.json']!), '[{"name":"rule34xxx"}]');
    });

    test('the database is written out of its journal before it is copied', () async {
      File(p('store.db')).writeAsBytesSync([1]);
      final _Memory target = _Memory();
      await BackupRunner(configDir: config, hooks: hooks).backup({BackupItem.database}, target);
      expect(calls.first, 'checkpoint');
      expect(target.files.keys, ['store.db']);
    });

    test('an item with nothing on this device yet is skipped, not a failure', () async {
      final _Memory target = _Memory();
      final BackupResult r = await BackupRunner(configDir: config, hooks: hooks).backup({BackupItem.bookmarks, BackupItem.recommender}, target);
      expect(r.failures, isEmpty);
      expect(target.files, isEmpty);
    });
  });

  group('restore', () {
    test('only the ticked items come back, each into its place', () async {
      final _Memory target = _Memory()
        ..files['settings.json'] = Uint8List.fromList(utf8.encode('{"restored":true}'))
        ..files['doujinData.json'] = Uint8List.fromList(utf8.encode('{"doujin":true}'))
        ..files['recommender.booru.bin'] = Uint8List.fromList([7, 7])
        ..files['recommender.deferred.json'] = Uint8List.fromList(utf8.encode('[]'))
        ..files['board-picture.b2.png'] = Uint8List.fromList([5]);
      File(p('settings.json')).writeAsStringSync('{"mine":true}');
      final BackupResult r = await BackupRunner(configDir: config, hooks: hooks).restore(
        {BackupItem.doujinLibrary, BackupItem.recommender, BackupItem.boardPictures},
        target,
      );
      expect(r.failures, isEmpty);
      expect(File(p('settings.json')).readAsStringSync(), '{"mine":true}', reason: 'not ticked');
      expect(File(p('doujinData.json')).readAsStringSync(), '{"doujin":true}');
      expect(File(p('recommender${Platform.pathSeparator}booru.bin')).readAsBytesSync(), [7, 7]);
      expect(File(p('recommender${Platform.pathSeparator}deferred.json')).existsSync(), isTrue);
      expect(File(p('boards${Platform.pathSeparator}b2.png')).readAsBytesSync(), [5]);
      expect(calls, containsAllInOrder(['recommender stops writing']), reason: 'its memory must not write over the restored files');
      expect(calls, contains('reload stores'));
      expect(r.needsRestart, isTrue);
    });

    test('sources and tag types go through their own loaders', () async {
      final _Memory target = _Memory()
        ..files['boorus.json'] = Uint8List.fromList(utf8.encode('[x]'))
        ..files['tags.json'] = Uint8List.fromList(utf8.encode('[t]'));
      await BackupRunner(configDir: config, hooks: hooks).restore({BackupItem.sources, BackupItem.tagTypes}, target);
      expect(calls, containsAll(['sources [x]', 'tag types [t]']));
    });

    test('an item missing from the backup is reported, the rest still restore', () async {
      final _Memory target = _Memory()..files['bookmarks.json'] = Uint8List.fromList(utf8.encode('{}'));
      final BackupResult r = await BackupRunner(configDir: config, hooks: hooks).restore({BackupItem.bookmarks, BackupItem.settings}, target);
      expect(r.failures, [contains(BackupItems.labelOf(BackupItem.settings))]);
      expect(File(p('bookmarks.json')).existsSync(), isTrue);
    });

    test('the whole database: closed, journal files removed, replaced, doujin migration re-armed', () async {
      File(p('store.db')).writeAsBytesSync([1]);
      File(p('store.db-wal')).writeAsBytesSync([2]);
      File(p('store.db-shm')).writeAsBytesSync([3]);
      final _Memory target = _Memory()..files['store.db'] = Uint8List.fromList([8, 8, 8]);
      final BackupResult r = await BackupRunner(configDir: config, hooks: hooks).restore({BackupItem.database}, target);
      expect(r.failures, isEmpty);
      expect(File(p('store.db')).readAsBytesSync(), [8, 8, 8]);
      expect(File(p('store.db-wal')).existsSync(), isFalse);
      expect(File(p('store.db-shm')).existsSync(), isFalse);
      expect(calls, containsAllInOrder(['close database', 'rearm migration']));
      expect(r.needsRestart, isTrue);
    });
  });

  group('restoring parts of the database', () {
    bool dbReady = false;
    Database? live;

    setUp(() async {
      dbReady = false;
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        SettingsHandler.register();
        SettingsHandler.instance.path = config;
        dbReady = true;
      } catch (e) {
        // ignore: avoid_print
        print('sqlite unavailable on this test host: $e');
      }
    });

    tearDown(() async {
      await live?.close();
      live = null;
    });

    /// A database with the app's schema, at [path] (or in memory).
    Future<Database> schemaDb(String path) async {
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(path);
      await db.updateTable();
      return db.db!;
    }

    Future<File> backupDbWith(void Function(Batch b) rows) async {
      final String path = '${tempDir.path}${Platform.pathSeparator}backup.db';
      final Database b = await schemaDb(path);
      final Batch batch = b.batch();
      rows(batch);
      await batch.commit(noResult: true);
      await b.close();
      return File(path);
    }

    test('pulled tags and the vector cache merge in; the log, favourites and history stay as they were', () async {
      if (!dbReady) return;
      final File backup = await backupDbWith((Batch b) {
        b.rawInsert("INSERT INTO BooruTag(booruKey, namespace, name, tagType, count, source, updatedAt) VALUES('rule34.xxx', '', 'from_backup', 'general', 5, 'pull', 1)");
        b.rawInsert("INSERT INTO ItemEmbedding(itemKey, model, dim, vector, at) VALUES('post/1', 'look:s0', 2, x'00000000', 1)");
        b.rawInsert("INSERT INTO Interaction(world, itemKey, host, kind, value, at, features) VALUES('booru', 'post/9', 'h', 'favourite', 0, 1, '')");
      });
      live = await schemaDb(inMemoryDatabasePath);
      await live!.rawInsert("INSERT INTO BooruTag(booruKey, namespace, name, tagType, count, source, updatedAt) VALUES('rule34.xxx', '', 'mine', 'general', 1, 'pull', 1)");
      await live!.rawInsert("INSERT INTO Interaction(world, itemKey, host, kind, value, at, features) VALUES('booru', 'post/mine', 'h', 'favourite', 0, 1, '')");
      await DbParts.restore(backup, {DbPart.pulledTags, DbPart.vectorCache}, live!);
      final List<String> tags = [for (final Map<String, Object?> r in await live!.rawQuery('SELECT name FROM BooruTag ORDER BY name')) r['name']! as String];
      expect(tags, ['from_backup', 'mine'], reason: 'merged, nothing of mine lost');
      expect((await live!.rawQuery('SELECT itemKey FROM ItemEmbedding')).single['itemKey'], 'post/1');
      expect((await live!.rawQuery('SELECT itemKey FROM Interaction')).single['itemKey'], 'post/mine', reason: 'the log was not ticked');
    });

    test("the recommendation log replaces this device's log, so it matches the restored learning", () async {
      if (!dbReady) return;
      final File backup = await backupDbWith((Batch b) {
        b.rawInsert("INSERT INTO Interaction(world, itemKey, host, kind, value, at, features) VALUES('booru', 'post/9', 'h', 'favourite', 0, 1, '')");
        b.rawInsert("INSERT INTO TagSignal(name, score, updatedAt) VALUES('fox', 3.0, 1)");
      });
      live = await schemaDb(inMemoryDatabasePath);
      await live!.rawInsert("INSERT INTO Interaction(world, itemKey, host, kind, value, at, features) VALUES('booru', 'post/mine', 'h', 'view', 0, 1, '')");
      await DbParts.restore(backup, {DbPart.recommenderLog}, live!);
      expect([for (final r in await live!.rawQuery('SELECT itemKey FROM Interaction')) r['itemKey']], ['post/9']);
      expect((await live!.rawQuery('SELECT name FROM TagSignal')).single['name'], 'fox', reason: 'For You interests come along');
    });

    test('a backup made before a table existed is not an error', () async {
      if (!dbReady) return;
      final String path = '${tempDir.path}${Platform.pathSeparator}old.db';
      final Database old = await databaseFactory.openDatabase(path);
      await old.execute('CREATE TABLE Unrelated(x INTEGER)');
      await old.close();
      live = await schemaDb(inMemoryDatabasePath);
      final List<String> skipped = await DbParts.restore(File(path), DbPart.values.toSet(), live!);
      expect(skipped, isNotEmpty, reason: 'the missing tables are named, not thrown');
    });
  });
}
