import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru_item.dart';

/// store.db queries that take a list: favourites and downloads in bulk, the
/// feed's favourited/downloaded badges, the local search box.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;

  Database db() => SettingsHandler.instance.dbHandler.db!;

  /// One more bound value than this SQLite takes in one statement (999 on
  /// Android before 11, 32766 in newer builds).
  Future<int> overTheLimit() async {
    for (final Map<String, Object?> row in await db().rawQuery('PRAGMA compile_options')) {
      final String option = row.values.first.toString();
      if (option.startsWith('MAX_VARIABLE_NUMBER=')) return int.parse(option.substring('MAX_VARIABLE_NUMBER='.length)) + 1;
    }
    final String version = (await db().rawQuery('SELECT sqlite_version() AS v')).first['v'].toString();
    final List<int> parts = version.split('.').map(int.parse).toList();
    final bool modern = parts[0] > 3 || (parts[0] == 3 && parts[1] >= 32);
    return (modern ? 32766 : 999) + 1;
  }

  Future<void> insertItem({required String postURL, required String fileURL, int favourite = 0, int snatched = 0}) async {
    await db().rawInsert(
      'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite) VALUES(?,?,?,?,?,?,?)',
      ['', '', fileURL, postURL, 'image', snatched, favourite],
    );
  }

  BooruItem item({required String postURL, required String fileURL}) => BooruItem(
    fileURL: fileURL,
    sampleURL: fileURL,
    thumbnailURL: fileURL,
    tagsList: const [],
    postURL: postURL,
  );

  setUp(() async {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('db_bulk');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final handler = SettingsHandler.instance.dbHandler;
      handler.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await handler.updateTable();
      SettingsHandler.instance.dbEnabled = true;
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
  });

  tearDown(() async {
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('lists longer than SQLite takes in one statement', () {
    test('ids of more posts than one statement can bind (a big selection favourited at once)', () async {
      if (!dbReady) return;
      final int n = await overTheLimit();
      final List<String> urls = [for (int i = 0; i < n; i++) 'https://gelbooru.com/index.php?page=post&s=view&id=$i'];
      await insertItem(postURL: urls.first, fileURL: 'https://img.gelbooru.com/first.jpg', favourite: 1);
      await insertItem(postURL: urls.last, fileURL: 'https://img.gelbooru.com/last.jpg', favourite: 1);

      final List<String> ids = await SettingsHandler.instance.dbHandler.getItemIDs(urls);

      expect(ids, hasLength(n));
      expect(ids.first, isNotEmpty);
      expect(ids.last, isNotEmpty);
      expect(ids.where((String id) => id.isNotEmpty), hasLength(2));
    });

    test('the badges of more posts than one statement can bind', () async {
      if (!dbReady) return;
      final int n = await overTheLimit();
      await insertItem(postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1', fileURL: 'https://img.gelbooru.com/1.jpg', favourite: 1);
      final BooruItem favourited = item(postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1', fileURL: 'https://img.gelbooru.com/1.jpg');
      final BooruItem other = item(postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=2', fileURL: 'https://img.gelbooru.com/2.jpg');
      final List<BooruItem> items = [favourited, for (int i = 1; i < n - 1; i++) other, favourited];

      final List<List<bool>> values = await SettingsHandler.instance.dbHandler.getMultipleTrackedValues(items);

      expect(values, hasLength(n));
      expect(values.first, [false, true]);
      expect(values[1], [false, false]);
      expect(values.last, [false, true]);
    });

    test('pulled tags looked up by more names than one statement can bind', () async {
      if (!dbReady) return;
      final int n = await overTheLimit();
      await db().rawInsert(
        "INSERT INTO BooruTag(booruKey, namespace, name, tagType, count, source, updatedAt) VALUES('gelbooru.com', '', 'name_7', 'general', 5, 'pull', 1)",
      );
      final List<Map<String, Object?>> rows = await SettingsHandler.instance.dbHandler.getBooruTagsByNames('gelbooru.com', [
        for (int i = 0; i < n; i++) 'name_$i',
      ]);
      expect(rows.map((r) => r['name']), ['name_7']);
    });

    test('the tag cleanup removes more empty tags than one statement can bind', () async {
      if (!dbReady) return;
      final int n = await overTheLimit();
      final Batch batch = db().batch();
      for (int i = 0; i < n; i++) {
        batch.rawInsert("INSERT INTO Tag(name) VALUES('')");
      }
      batch.rawInsert("INSERT INTO Tag(name) VALUES('kept')");
      await batch.commit(noResult: true);

      await SettingsHandler.instance.dbHandler.tagsCleanup();

      expect([for (final r in await db().rawQuery('SELECT name FROM Tag')) r['name']], ['kept']);
    });
  });

  group('the feed badges', () {
    test('a favourite found by its file is shown as favourited even when its stored post address differs', () async {
      if (!dbReady) return;
      // Favourited years ago over http; the site now links its posts over https.
      await insertItem(
        postURL: 'http://gelbooru.com/index.php?page=post&s=view&id=5',
        fileURL: 'https://img.gelbooru.com/images/5.jpg',
        favourite: 1,
        snatched: 1,
      );
      final BooruItem fetched = item(postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=5', fileURL: 'https://img.gelbooru.com/images/5.jpg');

      expect(await SettingsHandler.instance.dbHandler.getMultipleTrackedValues([fetched]), [
        [true, true],
      ]);
      expect(await SettingsHandler.instance.dbHandler.getTrackedValues(fetched), [true, true], reason: 'the single lookup agrees');
    });

    test('the row with the same post address wins over another row with the same file (a mirror of the site)', () async {
      if (!dbReady) return;
      // Favourited on danbooru; the same file was downloaded from a mirror.
      await insertItem(postURL: 'https://safebooru.donmai.us/posts/7', fileURL: 'https://cdn.donmai.us/original/7.jpg', snatched: 1);
      await insertItem(postURL: 'https://danbooru.donmai.us/posts/7', fileURL: 'https://cdn.donmai.us/original/7.jpg', favourite: 1);
      final BooruItem onDanbooru = item(postURL: 'https://danbooru.donmai.us/posts/7', fileURL: 'https://cdn.donmai.us/original/7.jpg');
      final BooruItem onMirror = item(postURL: 'https://safebooru.donmai.us/posts/7', fileURL: 'https://cdn.donmai.us/original/7.jpg');
      expect(await SettingsHandler.instance.dbHandler.getMultipleTrackedValues([onDanbooru, onMirror]), [
        [false, true],
        [true, false],
      ]);
    });

    test('sites matched by post address still are (rule34.xxx changes its file hosts by country)', () async {
      if (!dbReady) return;
      await insertItem(postURL: 'https://rule34.xxx/index.php?page=post&s=view&id=9', fileURL: 'https://wimg.rule34.xxx/images/9.jpg', favourite: 1);
      final BooruItem fetched = item(postURL: 'https://rule34.xxx/index.php?page=post&s=view&id=9', fileURL: 'https://us.rule34.xxx/images/9.jpg');
      expect(await SettingsHandler.instance.dbHandler.getMultipleTrackedValues([fetched]), [
        [false, true],
      ]);
    });
  });

  group('the local search box', () {
    test('a site: term with a quote is a search, not broken SQL', () async {
      if (!dbReady) return;
      await insertItem(postURL: "https://example.com/o'neil/1", fileURL: "https://example.com/o'neil/1.jpg", favourite: 1);
      await insertItem(postURL: 'https://example.com/other/2', fileURL: 'https://example.com/2.jpg', favourite: 1);
      final handler = SettingsHandler.instance.dbHandler;

      final List<BooruItem> found = await handler.searchDB("site:o'neil", '0', '10');
      expect(found.map((i) => i.postURL), ["https://example.com/o'neil/1"]);
      expect(await handler.searchDBCount("site:o'neil"), 1);
      expect((await handler.searchDB("-site:o'neil", '0', '10')).map((i) => i.postURL), ['https://example.com/other/2']);
    });

    test('a site: term still matches part of the address, with other terms after it', () async {
      if (!dbReady) return;
      await insertItem(postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1', fileURL: 'https://img.gelbooru.com/1.jpg', favourite: 1);
      await insertItem(postURL: 'https://danbooru.donmai.us/posts/2', fileURL: 'https://cdn.donmai.us/2.jpg', favourite: 1);
      final handler = SettingsHandler.instance.dbHandler;
      expect((await handler.searchDB('site:donmai', '0', '10')).map((i) => i.postURL), ['https://danbooru.donmai.us/posts/2']);
      expect(await handler.searchDBCount('site:gelbooru sort:reverse'), 1);
    });
  });
}
