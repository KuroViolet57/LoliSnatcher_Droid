import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/catalog_suggestions.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_tag_catalog.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/eahentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r70 parity sweep, the tag side: every doujin source gets a Tag builder and
/// autocomplete. eahentai and hentalk had no builder at all; hitomi,
/// asmhentai, hentaipaw and hentalk had lists but no autocomplete; e-hentai
/// had neither although its API suggests tags.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru of(BooruType type, String url) => Booru(type.name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('parity_catalogs');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    EaHentaiSessionHandler.instance.resetForTests();
    EHentaiSessionHandler.instance.resetForTests();
    EaHentaiHandler.forgetFailedLoginsForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('eahentai tag builder', () {
    EaHentaiHandler handler() => EaHentaiHandler(of(BooruType.EaHentai, 'https://eahentai.com'), 42);

    test('the handler offers the four index families and autocomplete', () {
      final h = handler();
      expect(h.tagCatalog, isA<EaHentaiTagCatalog>());
      expect(h.tagCatalog!.namespaces.map((n) => n.key), ['artist', 'character', 'parody', 'tag']);
      expect(h.tagCatalog!.namespaces.every((n) => n.shards == EaHentaiTagCatalog.shardsPerNamespace), isTrue, reason: '# and A-Z, one page a shard');
      expect(EaHentaiTagCatalog.shardPosition(0), (letter: 0, page: 1));
      expect(EaHentaiTagCatalog.shardPosition(EaHentaiTagCatalog.pagesPerLetter * 2 + 1), (letter: 2, page: 2));
      expect(h.hasTagSuggestions, isTrue);
    });

    test('shard URLs follow the site: a letter, then its pages', () {
      expect(EaHentaiTagCatalog.shardUrl('artist', 2), 'https://eahentai.com/artists?q=B');
      expect(EaHentaiTagCatalog.shardUrl('artist', 2, page: 3), 'https://eahentai.com/artists?q=B&p=3');
      expect(EaHentaiTagCatalog.shardUrl('character', 0), 'https://eahentai.com/characters?q=%23');
      expect(EaHentaiTagCatalog.shardUrl('parody', 26), 'https://eahentai.com/parodies?q=Z');
      expect(EaHentaiTagCatalog.shardUrl('tag', 1), 'https://eahentai.com/tags?q=A');
    });

    test('an artists page gives 100 named, counted artists', () {
      final List<BooruTagEntry> rows = EaHentaiTagCatalog.parseIndex('artist', fixture('eahentai_artists_b.html'));
      expect(rows, hasLength(100));
      final BooruTagEntry kaiman = rows.firstWhere((e) => e.name == 'b_kaiman');
      expect(kaiman.namespace, 'artist');
      expect(kaiman.count, 7);
      expect(kaiman.tagType, TagType.artist);
      expect(rows.every((e) => !e.name.contains(' ') && !e.name.contains('%')), isTrue);
    });

    test('characters and parodies parse the same way; tags come from their search links', () {
      final characters = EaHentaiTagCatalog.parseIndex('character', fixture('eahentai_characters_b.html'));
      expect(characters, isNotEmpty);
      expect(characters.first.namespace, 'character');
      expect(characters.first.tagType, TagType.character);
      final parodies = EaHentaiTagCatalog.parseIndex('parody', fixture('eahentai_parodies_b.html'));
      expect(parodies, isNotEmpty);
      expect(parodies.first.tagType, TagType.copyright);
      final tags = EaHentaiTagCatalog.parseIndex('tag', fixture('eahentai_tags_b.html'));
      expect(tags.length, greaterThan(30));
      expect(tags.map((e) => e.name), contains('bald'));
      expect(tags.every((e) => e.namespace == 'tag'), isTrue);
    });

    test('a shard is one page of one letter; past the end of a letter its shards cost no request', () async {
      final h = handler();
      final List<String> asked = [];
      h.fetcher = (url, {postJson}) async {
        asked.add(url);
        if (url.endsWith('&p=2')) return (status: 404, body: '', finalUrl: url);
        if (url.contains('/tags?')) return (status: 200, body: fixture('eahentai_tags_b.html'), finalUrl: url);
        return (status: 200, body: fixture('eahentai_artists_b.html'), finalUrl: url);
      };
      const int b = EaHentaiTagCatalog.pagesPerLetter * 2;
      expect(await h.tagCatalog!.shardAt('artist', b), hasLength(100));
      expect(await h.tagCatalog!.shardAt('artist', b + 1), isEmpty, reason: 'page 2 is a 404: the letter ended');
      expect(await h.tagCatalog!.shardAt('artist', b + 2), isEmpty);
      expect(await h.tagCatalog!.shardAt('artist', b + EaHentaiTagCatalog.pagesPerLetter - 1), isEmpty);
      expect(asked, ['https://eahentai.com/artists?q=B', 'https://eahentai.com/artists?q=B&p=2'], reason: 'the rest of the letter is answered from memory');

      asked.clear();
      expect(await h.tagCatalog!.shardAt('tag', b), isNotEmpty);
      expect(await h.tagCatalog!.shardAt('tag', b + 1), isEmpty);
      expect(asked, ['https://eahentai.com/tags?q=B'], reason: 'one page a letter for tags');
      expect(await h.tagCatalog!.shardAt('artist', EaHentaiTagCatalog.shardsPerNamespace), isNull);
    });

    test('a picked row is a term the search understands', () {
      final TagCatalogSource c = handler().tagCatalog!;
      expect(c.searchTerm(const BooruTagEntry(name: 'b_kaiman', namespace: 'artist', tagType: TagType.artist)), 'artist:b_kaiman');
      expect(c.searchTerm(const BooruTagEntry(name: 'bald', namespace: 'tag', tagType: TagType.none)), 'bald');
    });
  });

  group('hentalk tag builder', () {
    FaccinaHandler handler() => FaccinaHandler(of(BooruType.Faccina, 'https://hentalk.pw'), 24);

    test('the handler offers every namespace of the site in one pull, and autocomplete', () {
      final h = handler();
      expect(h.tagCatalog, isA<FaccinaTagCatalog>());
      final TagCatalogSource c = h.tagCatalog!;
      expect(c.sharedShards, isTrue);
      expect(c.sharedShardCount, 1);
      expect(c.namespaces.map((n) => n.key), containsAll(['artist', 'circle', 'parody', 'magazine', 'publisher', 'event', 'tag']));
      expect(h.hasTagSuggestions, isTrue);
      expect(h.tagNamespaceSections.map((s) => s.$1), contains('event'));
    });

    test('devalue: objects and lists hold indexes into one flat array; a negative index is a hole', () {
      final dynamic root = FaccinaTagCatalog.devalue([
        {'a': 1, 'b': 2},
        'x',
        [3, 4, -1],
        5,
        {'n': 1},
      ]);
      expect(root, {
        'a': 'x',
        'b': [
          5,
          {'n': 'x'},
          null,
        ],
      });
    });

    test('the page data lists 4,427 typed rows', () {
      final List<BooruTagEntry> rows = FaccinaTagCatalog.parseTagList(fixture('hentalk_data.json'));
      expect(rows.length, greaterThan(4000));
      final Map<String, int> perNamespace = {};
      for (final e in rows) {
        perNamespace[e.namespace] = (perNamespace[e.namespace] ?? 0) + 1;
      }
      expect(perNamespace['artist'], greaterThan(2000));
      expect(perNamespace['tag'], greaterThan(300));
      expect(perNamespace['event'], greaterThan(50));
      expect(perNamespace['magazine'], greaterThan(800), reason: '944 on the site, fewer once spellings merge');
      expect(rows.firstWhere((e) => e.name == '1-gou').namespace, 'artist');
      expect(rows.firstWhere((e) => e.namespace == 'tag').tagType, TagType.none);
      expect(rows.firstWhere((e) => e.namespace == 'magazine').tagType, TagType.meta);
    });

    test('one shard, from the site data URL, through the seam', () async {
      final h = handler();
      final FaccinaTagCatalog c = h.tagCatalog! as FaccinaTagCatalog;
      final List<String> asked = [];
      c.fetcher = (url) async {
        asked.add(url);
        return (status: 200, body: fixture('hentalk_data.json'));
      };
      final rows = await c.shardAt('', 0);
      expect(rows!.length, greaterThan(4000));
      expect(asked, ['https://hentalk.pw/__data.json']);
      expect(await c.shardAt('', 1), isNull);
      expect(c.searchTerm(const BooruTagEntry(name: 'beauty_mark', namespace: 'tag', tagType: TagType.none)), 'tag:beauty_mark');
    });

    test('an answer without the list is empty, not an exception', () {
      expect(FaccinaTagCatalog.parseTagList('{"type":"data","nodes":[]}'), isEmpty);
      expect(FaccinaTagCatalog.parseTagList(jsonEncode({'nodes': [{'type': 'data', 'data': [{'x': 1}, 2]}]})), isEmpty);
    });
  });

  group('autocomplete from the local lists', () {
    test('hitomi, asmhentai, hentaipaw and hentalk now suggest while typing', () {
      expect(HitomiHandler(of(BooruType.Hitomi, 'https://hitomi.la'), 20).hasTagSuggestions, isTrue);
      expect(AsmHentaiHandler(of(BooruType.AsmHentai, 'https://asmhentai.com'), 20).hasTagSuggestions, isTrue);
      expect(HentaiPawHandler(of(BooruType.HentaiPaw, 'https://hentaipaw.com'), 20).hasTagSuggestions, isTrue);
      expect(FaccinaHandler(of(BooruType.Faccina, 'https://hentalk.pw'), 24).hasTagSuggestions, isTrue);
    });

    test("rows become suggestions in the catalog's own search terms", () {
      final HitomiHandler h = HitomiHandler(of(BooruType.Hitomi, 'https://hitomi.la'), 20);
      expect(CatalogSuggestions.splitInput('tag:beauty mark'), (namespace: 'tag', query: 'beauty_mark'));
      expect(CatalogSuggestions.splitInput('glasses'), (namespace: null, query: 'glasses'));
      expect(CatalogSuggestions.splitInput('-artist:x'), (namespace: 'artist', query: 'x'));
      final List<TagSuggestion> out = CatalogSuggestions.suggestionsFrom(h.tagCatalog!, [
        const BooruTagEntry(name: 'glasses', namespace: 'tag', tagType: TagType.none, count: 3),
        const BooruTagEntry(name: 'santa', namespace: 'artist', tagType: TagType.artist, count: 9),
      ]);
      expect(out.map((s) => s.tag), ['tag:glasses', 'artist:santa'], reason: 'hitomi wants every term typed');
      expect(out.last.count, 9);
      expect(out.last.type, TagType.artist);
    });
  });

  group("e-hentai's own suggestions", () {
    Booru eh() => of(BooruType.EHentai, 'https://e-hentai.org');

    test('the tagsuggest answer becomes typed terms', () {
      final List<TagSuggestion> out = EHentaiHandler.parseTagSuggest(jsonDecode(fixture('ehentai_api_tagsuggest.json')));
      expect(out.map((s) => s.tag), containsAll(['female:big_breasts', 'artist:big_bomber', 'parody:the_big_bang_theory']));
      expect(out.firstWhere((s) => s.tag == 'artist:big_bomber').type, TagType.artist);
      expect(out.firstWhere((s) => s.tag == 'parody:the_big_bang_theory').type, TagType.copyright);
      expect(EHentaiHandler.parseTagSuggest({'tags': []}), isEmpty, reason: 'no match answers an empty array');
      expect(EHentaiHandler.parseTagSuggest('<html>'), isEmpty);
    });

    test('the handler asks the API once per input, typed as the site types', () async {
      final h = EHentaiHandler(eh(), 25);
      expect(h.hasTagSuggestions, isTrue);
      final List<String?> bodies = [];
      h.fetcher = (url, {postJson}) async {
        bodies.add(postJson);
        return (status: 200, body: fixture('ehentai_api_tagsuggest.json'), finalUrl: url);
      };
      final result = await h.getTagSuggestions('big_b');
      expect(result.isRight(), isTrue);
      expect(result.getOrElse((_) => const []).length, 10);
      expect(bodies.single, contains('"tagsuggest"'));
      expect(bodies.single, contains('"big b"'), reason: 'underscores are spaces on the site');
      await h.getTagSuggestions('big b');
      expect(bodies.last, contains('"big b"'), reason: 'the whole input, not its last word (review)');
    });
  });
}
