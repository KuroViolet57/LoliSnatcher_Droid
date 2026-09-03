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
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The tag builder's catalogs, parsed against pages and dumps captured from
/// the live sites on 2026-09-02, and the capability each handler declares.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

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

  group('capabilities', () {
    test('each source offers exactly what it can enumerate', () {
      List<String> keys(BooruHandler h) => h.tagCatalog?.namespaces.map((n) => n.key).toList() ?? const [];
      expect(keys(SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20)), ['artist', 'circle', 'female', 'male', 'mixed', 'tag']);
      expect(keys(HitomiHandler(b('h', BooruType.Hitomi, 'https://hitomi.la'), 20)), ['artist', 'circle', 'parody', 'character', 'female', 'male', 'tag', 'language', 'type']);
      expect(keys(AsmHentaiHandler(b('a', BooruType.AsmHentai, 'https://asmhentai.com'), 20)), ['artist', 'group', 'parody', 'character', 'tag']);
      expect(keys(NHentaiHandler(b('n', BooruType.NHentai, 'https://nhentai.net'), 20)), ['parody', 'character', 'artist', 'group', 'tag']);
      expect(keys(HentaiPawHandler(b('p', BooruType.HentaiPaw, 'https://hentaipaw.com'), 20)), ['artist', 'group', 'parody', 'character', 'tag']);
      expect(FaccinaHandler(b('f', BooruType.Faccina, 'https://hentalk.pw'), 20).tagCatalog, isNull);
      expect(EaHentaiHandler(b('e', BooruType.EaHentai, 'https://eahentai.com'), 20).tagCatalog, isNull);
    });
  });
}
