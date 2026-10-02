import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The booru families' tag indexes, parsed against pages captured from the
/// live sites on 2026-09-06, and the exact requests each builder page sends.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tagindex');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    TagIndexSource.resetForTests();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('gelbooru family', () {
    const index = GelbooruTagIndex();

    test('rule34.xxx: 20 rows a page, most-used first, typed from the class', () {
      final body = fixture('rule34xxx_tags_list.html');
      final rows = GelbooruTagIndex.parseHtmlList(body);
      expect(rows.length, 20);
      expect(rows.first.name, 'female');
      expect(rows.first.tagType, TagType.none);
      expect(rows.first.count, greaterThan(10000000));
      final counts = rows.map((r) => r.count).toList();
      expect(counts, [...counts]..sort((a, b) => b.compareTo(a)), reason: 'count-descending');
      expect(rows.where((r) => r.tagType == TagType.meta), isNotEmpty);
      expect(GelbooruTagIndex.rowsOnPage(body), 20);
    });

    test('gelbooru.com: count after the link, 50 rows, alias rows and the empty first row dropped', () {
      final body = fixture('gelbooru_tags_list.html');
      expect(GelbooruTagIndex.rowsOnPage(body), 50);
      final rows = GelbooruTagIndex.parseHtmlList(body);
      expect(rows, isNotEmpty);
      expect(rows.map((r) => r.name), isNot(contains('')));
      expect(rows.map((r) => r.name), isNot(contains('1firl')), reason: 'deprecated alias');
      final girl = rows.firstWhere((r) => r.name == '1girl');
      expect(girl.tagType, TagType.none);
      expect(girl.count, greaterThan(9000000));
      expect(rows.firstWhere((r) => r.name == 'highres').tagType, TagType.meta);
      expect(rows.length, lessThan(50));
    });

    test('realbooru: models are artists', () {
      final rows = GelbooruTagIndex.parseHtmlList(fixture('realbooru_tags_list.html'));
      expect(rows.length, 50);
      expect(rows.where((r) => r.tagType == TagType.artist), isNotEmpty);
    });

    test('the walk steps pid by the rows a host renders', () {
      final rule34 = b('r34', BooruType.Gelbooru, 'https://rule34.xxx');
      final tbib = b('tbib', BooruType.GelbooruAlike, 'https://tbib.org');
      expect(index.listPageUrl(rule34, 3), 'https://rule34.xxx/index.php?page=tags&s=list&sort=desc&order_by=index_count&pid=60');
      expect(index.listPageUrl(tbib, 3), 'https://tbib.org/index.php?page=tags&s=list&sort=desc&order_by=index_count&pid=150');
      expect(index.lastPage(rule34, const []), isFalse, reason: 'junk rows are dropped, so a short page proves nothing');
    });

    test('the builder walks one shared list; five chips read it by type', () {
      final ns = index.catalogNamespaces(b('r34', BooruType.Gelbooru, 'https://rule34.xxx'));
      expect(ns.map((n) => n.key), ['artist', 'character', 'copyright', 'meta', 'tag']);
      expect(ns.every((n) => n.byType), isTrue);
      expect(index.walksByCategory, isFalse);
      expect(index.catalogPagesPerPull, 100);
    });
  });

  group('danbooru family', () {
    const index = DanbooruTagIndex();
    final booru = b('danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us');

    test('one category a page, a thousand rows, most-used first', () {
      expect(
        index.categoryQuery(TagType.artist, 0),
        'limit=1000&page=1&search[category]=1&search[order]=count&search[hide_empty]=yes',
      );
      expect(
        index.categoryQuery(TagType.none, 4),
        'limit=1000&page=5&search[category]=0&search[order]=count&search[hide_empty]=yes',
      );
      expect(index.catalogNamespaces(booru).map((n) => n.key), ['artist', 'character', 'copyright', 'meta', 'tag']);
      expect(index.catalogNamespaces(booru).map((n) => n.maxShards).toSet(), {null}, reason: 'r50: a booru pull runs to the end of the index');
      expect(index.walksByCategory, isTrue);
      expect(index.pageSizeFor(booru), 1000);
    });

    test('rows are typed through the handler numbering, resolved once', () {
      final rows = DanbooruTagIndex.parseRows(
        booru,
        '[{"name":"Hatsune_Miku","category":4,"post_count":12},{"name":"","category":1}]',
      );
      expect(rows.length, 1);
      expect(rows.single.name, 'hatsune_miku');
      expect(rows.single.tagType, TagType.character);
      expect(identical(TagIndexSource.typeMapFor(booru), TagIndexSource.typeMapFor(booru)), isTrue);
    });
  });

  group('e621', () {
    const index = E621TagIndex();
    final booru = b('e621', BooruType.e621, 'https://e621.net');

    test('artists page: category 1, 320 a page, species and meta offered', () {
      final rows = E621TagIndex.parseRows(booru, fixture('e621_tags_artist.json'));
      expect(rows.length, 5);
      expect(rows.first.name, 'conditional_dnp');
      expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
      expect(E621TagIndex.parseRows(booru, '{"tags":[]}'), isEmpty);
      expect(
        index.categoryQuery(TagType.species, 1),
        'limit=320&page=2&search[category]=5&search[order]=count&search[hide_empty]=true',
      );
      expect(
        index.catalogNamespaces(booru).map((n) => n.key),
        ['artist', 'contributor', 'character', 'copyright', 'species', 'meta', 'lore', 'tag'],
      );
      expect(index.catalogDelay, greaterThanOrEqualTo(const Duration(seconds: 1)));
    });
  });

  group('philomena', () {
    const index = PhilomenaTagIndex();
    final booru = b('derpi', BooruType.Philomena, 'https://derpibooru.org');

    test('artists are origin tags named artist:…, stored underscored and typed artist', () {
      final rows = PhilomenaTagIndex.parseRows(fixture('derpibooru_tags_artist.json'));
      expect(rows.length, 5);
      expect(rows.every((r) => r.name.startsWith('artist:')), isTrue);
      expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
      expect(rows.every((r) => !r.name.contains(' ')), isTrue);
      expect(rows.map((r) => r.name), contains('artist:cold-blooded-twilight'));
    });

    test('characters keep their spaces as underscores; origin is meta; general is untyped', () {
      final chars = PhilomenaTagIndex.parseRows(fixture('derpibooru_tags_character.json'));
      expect(chars.first.name, 'twilight_sparkle');
      expect(chars.first.tagType, TagType.character);
      final origin = PhilomenaTagIndex.parseRows(fixture('derpibooru_tags_origin.json'));
      expect(origin.first.name, 'screencap');
      expect(origin.first.tagType, TagType.meta);
      expect(PhilomenaTagIndex.typeOf('female', null), TagType.none);
    });

    test('one query per chip, fifty a page', () {
      expect(index.categoryQuery(TagType.artist, 0), 'q=artist%3A*&per_page=50&page=1&sf=images&sd=desc');
      expect(index.categoryQuery(TagType.character, 2), 'q=category%3Acharacter&per_page=50&page=3&sf=images&sd=desc');
      expect(index.categoryQuery(TagType.none, 0), 'q=*&per_page=50&page=1&sf=images&sd=desc');
      expect(index.catalogNamespaces(booru).map((n) => n.key), ['artist', 'character', 'copyright', 'species', 'tag']);
    });
  });

  group('moebooru', () {
    const index = MoebooruTagIndex();
    final booru = b('yandere', BooruType.Moebooru, 'https://yande.re');

    test('tag.json by type, 500 a page', () {
      final rows = MoebooruTagIndex.parseRows(booru, fixture('yandere_tag_artist.json'));
      expect(rows.length, 5);
      expect(rows.first.name, 'kantoku');
      expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
      expect(rows.first.count, greaterThan(1000));
      expect(index.categoryQuery(TagType.character, 0), 'limit=500&order=count&type=4&page=1');
      expect(index.catalogNamespaces(booru).map((n) => n.key), ['artist', 'character', 'copyright', 'tag']);
    });
  });

  group('sankaku', () {
    const index = SankakuTagIndex();
    final booru = b('sankaku', BooruType.Sankaku, 'https://chan.sankakucomplex.com');

    test('the canonical tagName, post_count, a thousand a page on the API host', () {
      final rows = SankakuTagIndex.parseRows(booru, fixture('sankaku_tags_artist.json'));
      expect(rows.length, 3);
      expect(rows.first.name, 'artist_request');
      expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
      expect(rows.first.count, greaterThan(100000));
      expect(index.categoryQuery(TagType.meta, 0), 'limit=1000&order=count&type=8&page=1');
      expect(index.catalogNamespaces(booru).map((n) => n.key), ['artist', 'character', 'copyright', 'meta', 'tag']);
    });
  });

  test('forBooru covers the six families and nothing else', () {
    expect(TagIndexSource.forBooru(b('r', BooruType.Realbooru, 'https://realbooru.com')), isA<GelbooruTagIndex>());
    expect(TagIndexSource.forBooru(b('m', BooruType.Moebooru, 'https://konachan.com')), isA<MoebooruTagIndex>());
    expect(TagIndexSource.forBooru(b('s', BooruType.Sankaku, 'https://chan.sankakucomplex.com')), isA<SankakuTagIndex>());
    expect(TagIndexSource.forBooru(b('i', BooruType.IdolSankaku, 'https://idol.sankakucomplex.com')), isNull);
    expect(TagIndexSource.forBooru(b('sh', BooruType.Shimmie, 'https://rule34hentai.net')), isNull);
  });
}
