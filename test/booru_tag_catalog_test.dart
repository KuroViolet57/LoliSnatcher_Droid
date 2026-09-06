import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/moebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/boorus/realbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/shimmie_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// A fake family: pages are made up, so the adapter's walk can be checked
/// without a network. The last real page is one row short.
class _FakeIndex extends TagIndexSource {
  _FakeIndex({this.byCategory = true, this.pages = 3, this.rowsPerPage = 4, this.maxPages = 10, this.emptyFirst = false});

  final bool byCategory;
  final int pages;
  final int rowsPerPage;
  final int maxPages;
  final bool emptyFirst;
  final List<(String, int)> asked = [];

  @override
  int get pageSize => rowsPerPage;

  @override
  int get maxIndexPages => maxPages;

  @override
  bool get walksByCategory => byCategory;

  @override
  int get catalogPagesPerPull => 2;

  @override
  Duration get catalogDelay => Duration.zero;

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(const [TagType.artist, TagType.none], maxShards: 2);

  List<BooruTagEntry> _page(String key, TagType type, int page) {
    asked.add((key, page));
    if (emptyFirst || page >= pages) return const [];
    final int n = page == pages - 1 ? rowsPerPage - 1 : rowsPerPage;
    return [for (int i = 0; i < n; i++) BooruTagEntry(name: '${type.name}_${page}_$i', tagType: type)];
  }

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) async => _page('', TagType.none, page);

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) async =>
      _page('', TagType.none, page);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) async =>
      _page(type.name, type, page);

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) async => const [];

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async => null;
}

/// The tag builder on classic boorus: which handlers offer one, what its
/// chips are, and how the adapter walks a family's index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('boorucatalog');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    TagIndexSource.resetForTests();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('which handlers offer a builder', () {
    List<String> keys(BooruHandler h) => h.tagCatalog?.namespaces.map((n) => n.key).toList() ?? const [];

    test('the six families', () {
      const five = ['artist', 'character', 'copyright', 'meta', 'tag'];
      expect(keys(GelbooruHandler(b('g', BooruType.Gelbooru, 'https://gelbooru.com'), 20)), five);
      expect(keys(GelbooruAlikesHandler(b('r', BooruType.GelbooruAlike, 'https://rule34.xxx'), 20)), five);
      expect(keys(RealbooruHandler(b('rb', BooruType.Realbooru, 'https://realbooru.com'), 20)), five);
      expect(keys(DanbooruHandler(b('d', BooruType.Danbooru, 'https://danbooru.donmai.us'), 20)), five);
      expect(
        keys(e621Handler(b('e', BooruType.e621, 'https://e621.net'), 20)),
        ['artist', 'character', 'copyright', 'species', 'meta', 'tag'],
      );
      expect(
        keys(PhilomenaHandler(b('p', BooruType.Philomena, 'https://derpibooru.org'), 20)),
        ['artist', 'character', 'copyright', 'species', 'tag'],
      );
      expect(keys(MoebooruHandler(b('m', BooruType.Moebooru, 'https://yande.re'), 20)), ['artist', 'character', 'copyright', 'tag']);
      expect(keys(SankakuHandler(b('s', BooruType.Sankaku, 'https://chan.sankakucomplex.com'), 20)), five);
    });

    test('and not the rest', () {
      expect(IdolSankakuHandler(b('i', BooruType.IdolSankaku, 'https://idol.sankakucomplex.com'), 20).tagCatalog, isNull);
      expect(GelbooruHandler(b('bake', BooruType.Gelbooru, 'https://bakemono.app'), 20).tagCatalog, isNull, reason: 'profile veto');
      expect(ShimmieHandler(b('sh', BooruType.Shimmie, 'https://rule34hentai.net'), 20).tagCatalog, isNull);
      expect(HydrusHandler(b('h', BooruType.Hydrus, 'http://localhost:45869'), 20).tagCatalog, isNull);
    });

    test('every booru chip reads by type; the walk shape and the term follow the family', () {
      final gel = GelbooruHandler(b('g', BooruType.Gelbooru, 'https://gelbooru.com'), 20).tagCatalog!;
      expect(gel.namespaces.every((n) => n.byType), isTrue);
      expect(gel.sharedShards, isTrue);
      expect(gel.maxShardsPerPull, 100);
      expect(gel.searchTerm(const BooruTagEntry(name: 'hatsune_miku', tagType: TagType.character)), 'hatsune_miku');

      final dan = DanbooruHandler(b('d', BooruType.Danbooru, 'https://danbooru.donmai.us'), 20).tagCatalog!;
      expect(dan.sharedShards, isFalse);
      expect(dan.namespaces.every((n) => n.maxShards == 5), isTrue);

      expect(
        e621Handler(b('e', BooruType.e621, 'https://e621.net'), 20).tagCatalog!.shardDelay,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      final derpi = PhilomenaHandler(b('p', BooruType.Philomena, 'https://derpibooru.org'), 20).tagCatalog!;
      expect(derpi.searchTerm(const BooruTagEntry(name: 'artist:foo_bar', tagType: TagType.artist)), 'artist:foo_bar');
    });
  });

  group('the walk', () {
    final booru = b('d', BooruType.Danbooru, 'https://danbooru.donmai.us');
    BooruHandler handler() => DanbooruHandler(booru, 20);

    test('a category shard asks that category and ends after a short page without another request', () async {
      final fake = _FakeIndex(pages: 3, rowsPerPage: 4);
      final catalog = BooruTagCatalog(handler(), fake);
      expect(catalog.sharedShards, isFalse);
      expect((await catalog.shardAt('artist', 0))!.length, 4);
      expect((await catalog.shardAt('artist', 1))!.length, 4);
      expect((await catalog.shardAt('artist', 2))!.length, 3, reason: 'short last page');
      expect(await catalog.shardAt('artist', 3), isNull);
      expect(fake.asked, [('artist', 0), ('artist', 1), ('artist', 2)], reason: 'shard 3 cost no request');
      expect((await catalog.shardAt('tag', 0))!.every((e) => e.tagType == TagType.none), isTrue);
    });

    test('the plain index walk is the shared one, capped by the family', () async {
      final fake = _FakeIndex(byCategory: false, pages: 5, rowsPerPage: 4, maxPages: 2);
      final catalog = BooruTagCatalog(handler(), fake);
      expect(catalog.sharedShards, isTrue);
      expect(catalog.maxShardsPerPull, 2);
      expect(await catalog.shardAt('', 0), isNotNull);
      expect(await catalog.shardAt('', 2), isNull, reason: 'past maxIndexPages');
      expect(fake.asked, [('', 0)]);
    });

    test('an empty first page is an error the picker can show, not a silent end', () async {
      final fake = _FakeIndex(emptyFirst: true);
      final catalog = BooruTagCatalog(handler(), fake);
      expect(() => catalog.shardAt('artist', 0), throwsA(isA<Exception>()));

      final later = _FakeIndex(pages: 1);
      final catalog2 = BooruTagCatalog(handler(), later);
      expect(await catalog2.shardAt('artist', 0), isNotNull);
      expect(await catalog2.shardAt('artist', 1), isNull, reason: 'the short page 0 was the end');
      expect(later.asked, [('artist', 0)]);
    });
  });
}
