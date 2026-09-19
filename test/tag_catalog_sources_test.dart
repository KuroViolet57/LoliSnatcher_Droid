import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/rule34video_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/tikporn_handler.dart';
import 'package:lolisnatcher/src/boorus/tikporn_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/civitai_handler.dart';
import 'package:lolisnatcher/src/boorus/civitai_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';

/// The tag builder's catalogs, parsed against pages and dumps captured from
/// the live sites on 2026-09-02, and the capability each handler declares.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  /// A plausible base URL per type, so the factory builds a real handler.
  String defaultUrlFor(BooruType type) => switch (type) {
    BooruType.EHentai => 'https://e-hentai.org',
    BooruType.HDoujin => 'https://hdoujin.org',
    BooruType.NiyaNiya => 'https://niyaniya.moe',
    BooruType.TikPorn => 'https://tik.porn',
    BooruType.Kusowanka => 'https://kusowanka.com',
    BooruType.Civitai => 'https://civitai.com',
    BooruType.Hitomi => 'https://hitomi.la',
    BooruType.NHentai => 'https://nhentai.net',
    BooruType.AsmHentai => 'https://asmhentai.com',
    BooruType.HentaiPaw => 'https://hentaipaw.com',
    BooruType.EaHentai => 'https://eahentai.com',
    BooruType.Faccina => 'https://hentalk.pw',
    BooruType.Kemono => 'https://kemono.cr',
    BooruType.Pawchive => 'https://pawchive.pw',
    BooruType.FurAffinity => 'https://www.furaffinity.net',
    BooruType.Hanime1 => 'https://hanime1.me',
    BooruType.Rule34Video => 'https://rule34video.com',
    BooruType.Gelbooru => 'https://gelbooru.com',
    BooruType.GelbooruAlike => 'https://rule34.xxx',
    BooruType.Realbooru => 'https://realbooru.com',
    BooruType.Danbooru => 'https://danbooru.donmai.us',
    BooruType.e621 => 'https://e621.net',
    BooruType.Philomena => 'https://derpibooru.org',
    BooruType.Moebooru => 'https://yande.re',
    BooruType.Sankaku => 'https://chan.sankakucomplex.com',
    BooruType.IdolSankaku => 'https://idol.sankakucomplex.com',
    _ => 'https://example.com',
  };

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('catalog');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('rule34video', () {
    test('tags, artists and categories are offered; tags insert bare, the rest prefixed', () {
      final catalog = Rule34VideoHandler(b('r34v', BooruType.Rule34Video, 'https://rule34video.com'), 24).tagCatalog!;
      expect(catalog.namespaces.map((n) => n.key), ['tag', 'artist', 'category']);
      expect(catalog.namespaces.map((n) => n.maxShards), [40, 50, 35], reason: 'pull caps: 74 / 299 / 68 fragments');
      expect(catalog.sharedShards, isFalse);
      expect(catalog.shardDelay, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
      expect(catalog.searchTerm(const BooruTagEntry(name: 'x', tagType: TagType.none, namespace: 'tag')), 'x');
      expect(catalog.searchTerm(const BooruTagEntry(name: 'x', tagType: TagType.artist, namespace: 'artist')), 'artist:x');
    });
  });

  group('the entry carries its namespace', () {
    test('round-trips through JSON and defaults to none', () {
      const e = BooruTagEntry(name: 'ahegao', namespace: 'female', tagType: TagType.none, count: 3);
      final back = BooruTagEntry.fromJson(e.toJson());
      expect(back.namespace, 'female');
      expect(back.count, 3);
      expect(BooruTagEntry.fromJson({'n': 'x', 't': 'artist'}).namespace, '');
      expect(const BooruTagEntry(name: 'x', tagType: TagType.none).toJson().containsKey('ns'), isFalse);
    });
  });

  group('niyaniya', () {
    test('the dump is bucketed by namespace code and searched qualified', () {
      final rows = SchaleTagCatalog.parseTags(jsonDecode(fixture('schale_tags.json')));
      expect(rows.map((e) => e.namespace).toSet(), containsAll(['tag', 'artist', 'circle', 'male', 'female', 'mixed']));
      final artist = rows.firstWhere((e) => e.namespace == 'artist');
      expect(artist.tagType, TagType.artist);
      expect(artist.name, isNot(contains(' ')));
      final catalog = SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20).tagCatalog as SchaleTagCatalog;
      expect(catalog.searchTerm(artist), 'artist:${artist.name}');
      final plain = rows.firstWhere((e) => e.namespace == 'tag');
      expect(catalog.searchTerm(plain), plain.name);
    });

    test('only enumerable AND searchable namespaces are offered', () {
      final catalog = SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20).tagCatalog;
      final keys = catalog.namespaces.map((n) => n.key).toList();
      expect(keys, ['artist', 'circle', 'female', 'male', 'mixed', 'tag']);
      expect(keys, isNot(contains('character')));
      expect(catalog.sharedShards, isTrue);
      expect(catalog.sharedShardCount, 3);
      expect(catalog.shardDelay, greaterThanOrEqualTo(const Duration(seconds: 3)), reason: 'rate limit 5 per window');
    });
  });

  group('hitomi', () {
    test('a tags shard yields plain, female and male rows with counts', () {
      final rows = HitomiTagCatalog.parseIndex(fixture('hitomi_alltags_a.html'));
      expect(rows.where((e) => e.namespace == 'tag'), isNotEmpty);
      expect(rows.where((e) => e.namespace == 'female'), isNotEmpty);
      expect(rows.where((e) => e.namespace == 'male'), isNotEmpty);
      final abortion = rows.firstWhere((e) => e.name == 'abortion' && e.namespace == 'female');
      expect(abortion.count, greaterThan(0));
      expect(abortion.name, 'abortion', reason: 'the ♀ label and the female: prefix are not part of the name');
      expect(rows.every((e) => !e.name.contains('%')), isTrue, reason: 'slugs are decoded');
    });

    test('an artists shard files under artist', () {
      final rows = HitomiTagCatalog.parseIndex(fixture('hitomi_allartists_a.html'));
      expect(rows, isNotEmpty);
      expect(rows.every((e) => e.namespace == 'artist' && e.tagType == TagType.artist), isTrue);
    });

    test('every term the catalog inserts is one hitomi can route', () {
      final catalog = HitomiHandler(b('h', BooruType.Hitomi, 'https://hitomi.la'), 20).tagCatalog;
      for (final e in HitomiTagCatalog.parseIndex(fixture('hitomi_alltags_a.html'))) {
        expect(HitomiHandler.nozomiTargetFor(catalog.searchTerm(e)), isNotNull, reason: catalog.searchTerm(e));
      }
      expect(catalog.searchTerm(const BooruTagEntry(name: 'ahegao', namespace: 'female', tagType: TagType.none)), 'female:ahegao');
      expect(catalog.searchTerm(const BooruTagEntry(name: 'ahegao', namespace: 'male', tagType: TagType.none)), 'male:ahegao');
    });

    test('languages come from language_support.js, types are fixed', () {
      final langs = HitomiTagCatalog.parseLanguages('var bitnumber_language = {"42":"korean","8":"english","21":"portuguese"};');
      expect(langs.map((e) => e.name), ['english', 'korean', 'portuguese']);
      final catalog = HitomiHandler(b('h', BooruType.Hitomi, 'https://hitomi.la'), 20).tagCatalog;
      expect(catalog.namespaceFor('language')!.shards, 1);
      expect(catalog.namespaceFor('artist')!.shards, 27);
      expect(HitomiTagCatalog.shardKeys.length, 27);
    });
  });

  group('asmhentai', () {
    test('an index page yields namespace, name and count', () {
      final rows = AsmHentaiTagCatalog.parseIndex(fixture('asmhentai_tags_index.html'));
      expect(rows.length, greaterThan(20));
      final big = rows.firstWhere((e) => e.name == 'big_breasts');
      expect(big.namespace, 'tag');
      expect(big.count, greaterThan(100000));
    });

    test('one namespaced term routes to the taxonomy page; mixed queries text-search', () {
      final h = AsmHentaiHandler(b('a', BooruType.AsmHentai, 'https://asmhentai.com'), 20)..pageNum = 2;
      expect(h.makeURL('artist:foo_bar'), 'https://asmhentai.com/artist/foo-bar/?page=2');
      expect(h.makeURL('tag:big_breasts'), 'https://asmhentai.com/tag/big-breasts/?page=2');
      expect(h.makeURL('artist:foo glasses'), 'https://asmhentai.com/search/?q=foo+glasses&page=2');
      expect(h.makeURL('glasses'), 'https://asmhentai.com/search/?q=glasses&page=2');
      expect(AsmHentaiHandler.taxonomyPath('bogus:x'), isNull);
    });

    test('a page past the end ends the walk', () {
      expect(AsmHentaiTagCatalog.parseIndex('<html><body><div class="tags"></div></body></html>'), isEmpty);
    });
  });

  group('nhentai', () {
    test('rows bucket by type and insert the way suggestions do', () {
      final rows = NHentaiTagCatalog.fromRows([
        {'id': 1, 'name': 'big breasts', 'type': 'tag', 'count': 10},
        {'id': 2, 'name': 'Shindol', 'type': 'artist', 'count': 5},
        {'id': 3, 'name': 'touhou project', 'type': 'parody', 'count': 7},
      ]);
      expect(rows.map((e) => e.namespace), ['tag', 'artist', 'parody']);
      final catalog = NHentaiHandler(b('n', BooruType.NHentai, 'https://nhentai.net'), 20).tagCatalog;
      expect(catalog.searchTerm(rows[0]), 'big_breasts');
      expect(catalog.searchTerm(rows[1]), 'artist:shindol');
      expect(rows[2].tagType, TagType.copyright);
    });

    test('a full answer expands the prefix; a short one does not', () {
      expect(NHentaiTagCatalog.shouldExpand(500, 500), isTrue);
      expect(NHentaiTagCatalog.shouldExpand(499, 500), isFalse);
      expect(NHentaiTagCatalog.expand('a').length, NHentaiTagCatalog.alphabet.length + 1);
      expect(NHentaiTagCatalog.expand('a').first, 'aa');
      expect(NHentaiTagCatalog.expand('a').last, 'a ');
    });
  });

  group('hentaipaw', () {
    test('an index page yields id-keyed rows with no counts', () {
      final rows = HentaiPawTagCatalog.parseIndex(fixture('hentaipaw_tags_index.html'), plural: 'tags');
      expect(rows.length, 30);
      expect(rows.every((e) => e.namespace == 'tag' && e.sourceId != null && e.count == 0), isTrue);
      final first = rows.first;
      expect(first.sourceId, '14390');
      expect(first.name, '🟢', reason: 'the name is the title attribute, as the site spells it');
      expect(rows.any((e) => e.name == '요구르트썬더'), isTrue);
      expect(HentaiPawTagCatalog.parseIndex(fixture('hentaipaw_tags_index.html'), plural: 'artists'), isEmpty);
    });

    test('the page count comes from the last-page arrow', () {
      expect(HentaiPawTagCatalog.lastPageFrom(fixture('hentaipaw_tags_index.html')), 138);
      expect(HentaiPawTagCatalog.lastPageFrom('<html><body><main></main></body></html>'), isNull);
    });

    test('a page with no entries ends the walk; the term is always qualified', () {
      expect(HentaiPawTagCatalog.parseIndex('<html><body><div class="tag-container"></div></body></html>'), isEmpty);
      final catalog = HentaiPawHandler(b('p', BooruType.HentaiPaw, 'https://hentaipaw.com'), 20).tagCatalog;
      expect(catalog.searchTerm(const BooruTagEntry(name: 'x', namespace: 'tag', tagType: TagType.none, sourceId: '1')), 'tag:x');
      expect(catalog.namespaceFor('tag')!.maxShards, HentaiPawTagCatalog.pagesPerPull);
    });

    test('the id survives the JSON snapshot form', () {
      const e = BooruTagEntry(name: 'x', namespace: 'tag', tagType: TagType.none, sourceId: '14390');
      expect(BooruTagEntry.fromJson(e.toJson()).sourceId, '14390');
      expect(const BooruTagEntry(name: 'x', tagType: TagType.none).toJson().containsKey('i'), isFalse);
    });
  });

  group('the sweep (r31): sources that turned out to enumerate after all', () {
    test('tikporn: the two fixed lists the handler already loads', () async {
      final h = TikPornHandler(b('t', BooruType.TikPorn, 'https://tik.porn'), 20);
      final catalog = h.tagCatalog! as TikPornTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), ['tag', 'action']);
      expect(catalog.namespaces.every((n) => n.shards == 1), isTrue);
      // A tag is inserted bare — the handler recognises a known tag word and
      // opens its feed, which is better than a free-text search; an act must
      // say so or it would be read as a tag first.
      expect(catalog.searchTerm(const BooruTagEntry(name: 'teen', tagType: TagType.none, namespace: 'tag')), 'teen');
      expect(catalog.searchTerm(const BooruTagEntry(name: '69', tagType: TagType.none, namespace: 'action')), 'action:69');
    });

    test('kusowanka: five browse indexes, slugs, a capped walk that knows its last page', () {
      final h = KusowankaHandler(b('k', BooruType.Kusowanka, 'https://kusowanka.com'), 20);
      final catalog = h.tagCatalog! as KusowankaTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), ['tag', 'artist', 'character', 'parody', 'metadata']);
      expect(catalog.namespaces.every((n) => n.maxShards == KusowankaTagCatalog.pagesPerPull), isTrue, reason: 'the lists run to thousands of pages');
      expect(catalog.indexUrl('artist', 0), 'https://kusowanka.com/artists/');
      expect(catalog.indexUrl('artist', 3), 'https://kusowanka.com/artists/?page=4');
      expect(catalog.indexUrl('metadata', 0), 'https://kusowanka.com/metadatas/');
      expect(
        catalog.searchTerm(const BooruTagEntry(name: "'o'ne", tagType: TagType.artist, namespace: 'artist', sourceId: 'o-ne')),
        'artist:o-ne',
        reason: 'the slug routes, even when the name it shows is punctuated',
      );

      final String page = fixture('kusowanka_artists.html');
      final rows = KusowankaTagCatalog.parseIndex(page, 'artist');
      expect(rows, isNotEmpty);
      expect(rows.every((e) => e.namespace == 'artist' && e.tagType == TagType.artist), isTrue);
      expect(rows.map((e) => e.name), isNot(contains('popular')), reason: 'the Popular link is not a tag');
      expect(rows.map((e) => e.sourceId).toSet().length, rows.length, reason: 'each entry links several times');
      // The list must read like a tag list, not like URL slugs: the site
      // shows `'o'ne` where the link says `o-ne`.
      expect(rows.map((e) => e.name), contains("'o'ne"));
      expect(rows.firstWhere((e) => e.name == "'o'ne").sourceId, 'o-ne');
      expect(KusowankaTagCatalog.lastPageOf(page, 'artists'), greaterThan(100));
      expect(KusowankaTagCatalog.lastPageOf('<html></html>', 'artists'), isNull);
      // Every row round-trips: the handler routes `artist:<slug>` to that page.
      expect(h.makeURL(catalog.searchTerm(rows.first)), 'https://kusowanka.com/artist/${rows.first.sourceId}/');
      // Every row, not just the first: a name the slug cannot be derived from
      // would route to the wrong page.
      for (final row in rows) {
        expect(h.makeURL(catalog.searchTerm(row)), 'https://kusowanka.com/artist/${row.sourceId}/', reason: row.name);
      }
    });

    test('civitai: the public tag list, walked until a page comes back empty', () {
      final h = CivitaiHandler(b('c', BooruType.Civitai, 'https://civitai.com'), 20);
      final catalog = h.tagCatalog! as CivitaiTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), ['tag']);
      expect(catalog.pageUrl(0), 'https://civitai.com/api/v1/tags?limit=100&page=1');
      expect(catalog.pageUrl(4), 'https://civitai.com/api/v1/tags?limit=100&page=5');
      final rows = CivitaiTagCatalog.parseTags(jsonDecode(fixture('civitai_tags.json')));
      expect(rows, hasLength(greaterThan(50)));
      expect(rows.every((e) => e.namespace == 'tag'), isTrue);
      expect(rows.map((e) => e.name), contains('game_character'), reason: 'names are underscored like everywhere else');
      expect(rows.every((e) => !e.name.contains(' ')), isTrue);
      // The empty page is the end marker, since the site's own metadata lies.
      expect(CivitaiTagCatalog.parseTags(const {'items': []}), isEmpty);
      expect(catalog.searchTerm(rows.first), rows.first.name, reason: 'the site has no namespaces');
      // The API answers most-used first and the picker sorts by count, so the
      // order has to survive as a rank or page 10 interleaves with page 1.
      expect(rows.first.count, greaterThan(rows.last.count));
      final later = CivitaiTagCatalog.parseTags(jsonDecode(fixture('civitai_tags.json')), rankFrom: 500);
      expect(later.first.count, lessThan(rows.last.count), reason: 'a later page ranks below an earlier one');
    });

    test("hdoujin reads its own network, not niyaniya's own", () {
      final catalog = SchaleHandler(b('hd', BooruType.HDoujin, 'https://hdoujin.org'), 20).tagCatalog as SchaleTagCatalog;
      expect(catalog.shardUrl(0), 'https://api.hdoujin.org/books/tags');
      expect(catalog.shardUrl(1), 'https://api.hdoujin.org/books/tags?namespace=1');
      final niya = SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20).tagCatalog as SchaleTagCatalog;
      expect(niya.shardUrl(0), 'https://api.schale.network/books/tags');
    });
  });

  group('every source has a decided answer', () {
    // A source with no tag builder must say why, here. Adding a BooruType
    // without deciding fails this test; a source silently LOSING its catalog
    // fails it too, which is how r30 shipped e-hentai without one.
    const Map<BooruType, String> noCatalog = {
      // r70: eahentai's index pages and hentalk's page data (`tagList`) are
      // catalogs now - see eahentai_tag_catalog.dart, faccina_tag_catalog.dart.
      BooruType.RedGifs: 'suggestions only, no index endpoint',
      BooruType.XXXTik: 'search answers prefixes; there is no full list',
      BooruType.XXXFollow: 'search answers prefixes; there is no full list',
      BooruType.Nozomi: 'static per-tag index files; the site lists no tags',
      BooruType.Hydrus: "the user's own local instance; its tag search needs a query",
      BooruType.InkBunny: 'the keyword endpoint answers prefixes, not a list',
      BooruType.IdolSankaku: 'not probed yet: iapi.sankakucomplex.com/tag/index.json (r32)',
      BooruType.Shimmie: 'not probed yet: instance-specific; paheal has an autocomplete route (r32)',
      BooruType.Szurubooru: "not probed yet: /api/tags is paged, but the instance is the user's (r32)",
      BooruType.GelbooruV1: 'not probed yet: gelbooru 0.1 has no dapi (r32)',
      BooruType.R34Hentai: 'not probed yet: Cloudflare-fronted from here (r32)',
      BooruType.R34US: 'not probed yet: the alphabetic page looks script-driven (r32)',
      BooruType.AGNPH: 'not probed yet: /gallery/tags/ answers but carries no tag table (r32)',
      BooruType.BooruOnRails: 'not probed yet: /api/v3/search/tags (r32)',
      BooruType.Rainbooru: "its tag endpoint points at another site's vocabulary",
      BooruType.NyanPals: 'no tag endpoint',
      BooruType.WildCritters: 'no tag endpoint',
      BooruType.World: 'the tag route answers prefixes only',
      BooruType.Rule34Dev: 'an aggregator: its suggestions come from four other sites',
      BooruType.WebView: 'a browser tab, not a source',
    };

    test('a source either offers a tag builder or says why not', () {
      final List<String> undecided = [];
      final List<String> lost = [];
      // Some types map onto SEVERAL handler classes by URL (gelbooru's three,
      // shimmie's two), so the walk carries extra hosts — otherwise the branch
      // an excuse is written for is never the branch the test builds.
      const List<(BooruType, String)> extraHosts = [
        (BooruType.Shimmie, 'https://rule34.paheal.net'),
        (BooruType.Gelbooru, 'https://rule34.xxx'),
        (BooruType.Gelbooru, 'https://bakemono.app'),
      ];
      final List<(BooruType, String)> walk = [
        for (final BooruType type in BooruType.saveable)
          if (!type.isLocalDb && type != BooruType.Merge) (type, defaultUrlFor(type)),
        ...extraHosts,
      ];
      for (final (BooruType type, String url) in walk) {
        final Booru booru = b(type.name, type, url);
        final BooruHandler handler = BooruHandlerFactory().getBooruHandler([booru], null).booruHandler;
        final bool hasCatalog = handler.tagCatalog?.namespaces.isNotEmpty ?? false;
        final bool excused = noCatalog.containsKey(type);
        // bakemono is a gelbooru host whose profile switches the catalog off
        // deliberately; it is the one host-level exception.
        if (url.contains('bakemono.app')) continue;
        if (!hasCatalog && !excused) undecided.add('${type.name} ($url)');
        if (hasCatalog && excused) lost.add('${type.name} ($url)');
      }
      expect(undecided, isEmpty, reason: 'these sources have no tag builder and no reason on record');
      expect(lost, isEmpty, reason: 'these have a tag builder now — take them out of the list');
    });
  });

  group('capabilities', () {
    test('each source offers exactly what it can enumerate', () {
      List<String> keys(BooruHandler h) => h.tagCatalog?.namespaces.map((n) => n.key).toList() ?? const [];
      expect(keys(SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20)), ['artist', 'circle', 'female', 'male', 'mixed', 'tag']);
      expect(keys(HitomiHandler(b('h', BooruType.Hitomi, 'https://hitomi.la'), 20)), ['artist', 'circle', 'parody', 'character', 'female', 'male', 'tag', 'language', 'type']);
      expect(keys(AsmHentaiHandler(b('a', BooruType.AsmHentai, 'https://asmhentai.com'), 20)), ['artist', 'group', 'parody', 'character', 'tag']);
      expect(keys(NHentaiHandler(b('n', BooruType.NHentai, 'https://nhentai.net'), 20)), ['parody', 'character', 'artist', 'group', 'tag']);
      expect(keys(HentaiPawHandler(b('p', BooruType.HentaiPaw, 'https://hentaipaw.com'), 20)), ['artist', 'group', 'parody', 'character', 'tag']);
      expect(FaccinaHandler(b('f', BooruType.Faccina, 'https://hentalk.pw'), 20).tagCatalog, isNotNull, reason: 'r70: the page data lists every tag');
      expect(EaHentaiHandler(b('e', BooruType.EaHentai, 'https://eahentai.com'), 20).tagCatalog, isNotNull, reason: 'r70: the index pages');
      expect(
        keys(EHentaiHandler(b('eh', BooruType.EHentai, 'https://e-hentai.org'), 25)),
        ['artist', 'character', 'parody', 'group', 'female', 'male', 'mixed', 'cosplayer', 'language', 'other'],
      );
      expect(keys(TikPornHandler(b('t', BooruType.TikPorn, 'https://tik.porn'), 20)), ['tag', 'action']);
      expect(keys(KusowankaHandler(b('k', BooruType.Kusowanka, 'https://kusowanka.com'), 20)), ['tag', 'artist', 'character', 'parody', 'metadata']);
      expect(keys(CivitaiHandler(b('c', BooruType.Civitai, 'https://civitai.com'), 20)), ['tag']);
    });
  });
}
