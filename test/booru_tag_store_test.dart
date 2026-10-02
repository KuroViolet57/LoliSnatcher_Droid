import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// A catalog that only lists namespaces, for the badge counts.
class _Catalog extends TagCatalogSource {
  _Catalog(this.namespaces);

  @override
  final List<TagCatalogNamespace> namespaces;

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async => null;
}

/// Where a tag-builder namespace's rows live: under the site's own namespace
/// for doujin sources, by TYPE among the namespace-less rows for classic
/// boorus — and the two never read each other's rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru booru = Booru('r34', BooruType.GelbooruAlike, '', 'https://rule34.xxx', '');
  const artists = TagCatalogNamespace(key: 'artist', label: 'Artists', type: TagType.artist, byType: true);
  const general = TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none, byType: true);
  const doujinArtists = TagCatalogNamespace(key: 'artist', label: 'Artists', type: TagType.artist);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tagstore');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('filterFor: by type reads the empty namespace, by namespace ignores the type', () {
    expect(BooruTagStore.filterFor(artists), (namespace: '', type: TagType.artist));
    expect(BooruTagStore.filterFor(general), (namespace: '', type: TagType.none));
    expect(BooruTagStore.filterFor(doujinArtists), (namespace: 'artist', type: null));
  });

  group('against a database', () {
    late bool dbReady;

    setUp(() async {
      dbReady = false;
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = SettingsHandler.instance.dbHandler;
        db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await db.updateTable();
        await db.createCriticalIndexes();
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
    });

    test('type-keyed rows are browsed, counted and cleared apart from namespaced ones', () async {
      if (!dbReady) {
        markTestSkipped('sqlite3 native library not loadable here');
        return;
      }
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'kantoku', tagType: TagType.artist, count: 40),
        BooruTagEntry(name: 'ramchi', tagType: TagType.artist, count: 90),
        BooruTagEntry(name: 'female', tagType: TagType.none, count: 900),
        BooruTagEntry(name: 'kantoku', namespace: 'artist', tagType: TagType.artist, count: 5),
      ]);
      final rows = await BooruTagStore.browseNamespace(booru, artists);
      expect(rows.map((r) => r.name), ['ramchi', 'kantoku'], reason: 'most-used first, only the booru rows');
      expect(await BooruTagStore.countNamespace(booru, artists), 2);
      expect(await BooruTagStore.countNamespace(booru, general), 1);
      expect(await BooruTagStore.countNamespace(booru, doujinArtists), 1);
      expect((await BooruTagStore.browseNamespace(booru, artists, query: 'ram')).single.name, 'ramchi');

      await BooruTagStore.clearNamespace(booru, artists);
      expect(await BooruTagStore.countNamespace(booru, artists), 0);
      expect(await BooruTagStore.countNamespace(booru, general), 1, reason: 'other types stay');
      expect(await BooruTagStore.countNamespace(booru, doujinArtists), 1, reason: 'the namespaced row stays');
    });

    test('catalogCounts groups by type for booru chips and by namespace for the rest', () async {
      if (!dbReady) {
        markTestSkipped('sqlite3 native library not loadable here');
        return;
      }
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'a', tagType: TagType.artist),
        BooruTagEntry(name: 'b', tagType: TagType.artist),
        BooruTagEntry(name: 'c', tagType: TagType.none),
        BooruTagEntry(name: 'd', namespace: 'artist', tagType: TagType.artist),
      ]);
      expect(await BooruTagStore.catalogCounts(booru, _Catalog(const [artists, general])), {'artist': 2, 'tag': 1});
      expect(await BooruTagStore.catalogCounts(booru, _Catalog(const [doujinArtists])), {'artist': 1});
    });
  });
}
