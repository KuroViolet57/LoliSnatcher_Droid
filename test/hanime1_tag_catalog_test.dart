import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/hanime1_handler.dart';
import 'package:lolisnatcher/src/boorus/hanime1_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/hanime_dictionary.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// hanime1.me's Tag builder: the site enumerates its whole vocabulary in its
/// search form (240 tags in seven groups, nine genres), and the app already
/// carries it translated in [HanimeDictionary]. So the chips list it without
/// a request — a "pull" is instant — and every picked term is one the
/// handler's grammar already accepts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru booru = Booru('hanime1', BooruType.Hanime1, '', 'https://hanime1.me', '');
  Hanime1Handler handler() => Hanime1Handler(booru, 20);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('hanime1cat');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the dictionary knows its groups', () {
    test('every tag belongs to one of the seven site groups, and the groups add up to the whole list', () {
      expect(HanimeGroup.values, hasLength(7));
      int total = 0;
      for (final HanimeGroup g in HanimeGroup.values) {
        final tags = HanimeDictionary.byGroup(g);
        expect(tags, isNotEmpty, reason: g.name);
        expect(tags.every((t) => t.group == g), isTrue, reason: g.name);
        total += tags.length;
      }
      expect(total, HanimeDictionary.tags.length);
      expect(HanimeDictionary.tags, hasLength(240));
    });

    test("the groups are the form's seven, in the form's order, with the attributes typed meta", () {
      expect(HanimeGroup.values.map((g) => g.key), [
        'attribute',
        'relationship',
        'archetype',
        'appearance',
        'setting',
        'story',
        'act',
      ]);
      expect(HanimeDictionary.fromEn('uncensored')!.group, HanimeGroup.attribute);
      expect(HanimeDictionary.fromEn('creampie')!.group, HanimeGroup.act);
      expect(HanimeDictionary.byGroup(HanimeGroup.attribute).every((t) => t.type == TagType.meta), isTrue);
    });
  });

  group('the catalog', () {
    test('offers one chip per group plus genres, each a single instant shard', () {
      final TagCatalogSource catalog = handler().tagCatalog!;
      expect(catalog, isA<Hanime1TagCatalog>());
      expect(catalog.namespaces.map((n) => n.key), [
        'attribute',
        'relationship',
        'archetype',
        'appearance',
        'setting',
        'story',
        'act',
        'genre',
      ]);
      expect(catalog.namespaces.every((n) => n.shards == 1), isTrue);
      expect(catalog.namespaces.every((n) => n.label.isNotEmpty), isTrue);
      expect(catalog.sharedShards, isFalse);
      expect(catalog.shardDelay, Duration.zero, reason: 'nothing is fetched');
    });

    test('a group shard is the dictionary group, filed under the group and typed as the dictionary says', () async {
      final catalog = handler().tagCatalog!;
      final List<BooruTagEntry> acts = (await catalog.shardAt('act', 0))!;
      expect(acts.map((e) => e.name), contains('creampie'));
      expect(acts.every((e) => e.namespace == 'act'), isTrue);
      expect(acts, hasLength(HanimeDictionary.byGroup(HanimeGroup.act).length));
      final List<BooruTagEntry> attributes = (await catalog.shardAt('attribute', 0))!;
      expect(attributes.every((e) => e.tagType == TagType.meta), isTrue);
      expect(attributes.map((e) => e.name), contains('uncensored'));
      expect(attributes.every((e) => e.sourceId != null && e.sourceId!.isNotEmpty), isTrue, reason: 'the site string travels with the row');
    });

    test('the genre shard lists the nine genres under genre', () async {
      final catalog = handler().tagCatalog!;
      final List<BooruTagEntry> genres = (await catalog.shardAt('genre', 0))!;
      expect(genres.map((e) => e.name), containsAll(['hentai', '3dcg', 'mmd', 'cosplay']));
      expect(genres, hasLength(HanimeDictionary.genres.length));
      expect(genres.every((e) => e.namespace == 'genre' && e.tagType == TagType.meta), isTrue);
    });

    test('there is no second shard and no unknown namespace', () async {
      final catalog = handler().tagCatalog!;
      expect(await catalog.shardAt('act', 1), isNull);
      expect(await catalog.shardAt('genre', 1), isNull);
      expect(await catalog.shardAt('artist', 0), isNull);
      expect(await catalog.shardAt('', 0), isNull);
    });

    test('every term a chip inserts is one the search grammar routes to the site', () async {
      final h = handler();
      final catalog = h.tagCatalog!;
      for (final ns in catalog.namespaces) {
        for (final BooruTagEntry e in (await catalog.shardAt(ns.key, 0))!) {
          final String term = catalog.searchTerm(e);
          final String url = h.makeURL(term);
          if (ns.key == 'genre') {
            expect(term, startsWith('genre:'));
            expect(url, contains('genre=${Uri.encodeQueryComponent(HanimeDictionary.genres[e.name]!)}'), reason: term);
          } else {
            expect(term, e.name, reason: 'tags insert bare');
            expect(url, contains('tags%5B%5D=${Uri.encodeQueryComponent(e.sourceId!)}'), reason: term);
            expect(url, isNot(contains('query=${Uri.encodeQueryComponent(e.name)}')), reason: '$term must not fall through to free text');
          }
        }
      }
    });
  });

  group('suggestions while typing', () {
    test('a prefix match comes before a substring match, in either language', () async {
      final h = handler();
      // Dictionary order is short_hair, hair_bun, pubic_hair, armpit_hair,
      // hairjob, hair_pulling; the prefix matches must come first.
      final hair = (await h.getTagSuggestions('hair')).getOrElse((_) => []).map((s) => s.tag).toList();
      expect(hair.take(3), unorderedEquals(['hair_bun', 'hairjob', 'hair_pulling']));
      expect(hair.skip(3), unorderedEquals(['short_hair', 'pubic_hair', 'armpit_hair']));
      final tags = (await h.getTagSuggestions('crea')).getOrElse((_) => []).map((s) => s.tag).toList();
      expect(tags.first, 'creampie');
      final zh = (await h.getTagSuggestions('無碼')).getOrElse((_) => []).map((s) => s.tag).toList();
      expect(zh, contains('uncensored'));
      final genre = (await h.getTagSuggestions('mmd')).getOrElse((_) => []).map((s) => s.tag).toList();
      expect(genre, contains('genre:mmd'));
    });

    test('genre: keeps its metatag autocomplete while the Genres chip has never been pulled (review)', () async {
      // With the database off the store answers nothing; the catalog must then
      // step aside (null) so the editor falls back to the genre metatag's list.
      final h = handler();
      expect(await TagCatalogSource.suggestFromCatalog(h, booru, 'genre:m'), isNull);
      expect(await TagCatalogSource.suggestFromCatalog(h, booru, 'artist:x'), isNull, reason: 'not a catalog namespace');
    });
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

    test('once the Genres chip was pulled, typed genre: is answered from the snapshot', () async {
      if (!dbReady) return;
      final h = handler();
      final catalog = h.tagCatalog!;
      await BooruTagStore.record(booru, (await catalog.shardAt('genre', 0))!);
      final rows = await TagCatalogSource.suggestFromCatalog(h, booru, 'genre:m');
      expect(rows, isNotNull);
      expect(rows!.map((s) => s.tag), containsAll(['genre:mmd', 'genre:motion_anime']));
      expect(await TagCatalogSource.suggestFromCatalog(h, booru, 'genre:zzz'), isNull, reason: 'no match: step aside again');
    });
  });

  group('what a chip can insert, the grammar must accept (review)', () {
    test("a long-pressed chip's -term is dropped with a warning, not sent as free text", () {
      final h = handler();
      final String url = h.makeURL('-creampie schoolgirl');
      expect(url, contains('tags%5B%5D=${Uri.encodeQueryComponent('JK')}'));
      expect(url, isNot(contains('%E5%85%A7%E5%B0%84')), reason: 'the negated tag is not sent as a positive filter either');
      expect(url, contains('query=&'), reason: 'nothing leaks into the free-text query');
      final String genre = h.makeURL('-genre:mmd');
      expect(genre, isNot(contains('genre=')));
      expect(genre, contains('query=&'));
    });
  });
}
