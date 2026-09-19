import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin_foryou_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r33: the doujin For You — a virtual doujin source that asks the
/// configured doujin sites for what the history and the learner point at,
/// and hands each card to its own source for everything else.
class _FakeSource extends BooruHandler {
  _FakeSource(super.booru, super.limit);

  final List<String> queries = [];
  final List<BooruItem> loaded = [];

  /// How many rows a query answers (by substring); 6 otherwise.
  final Map<String, int> answers = {};

  /// How long a query takes (by substring).
  final Map<String, Duration> delays = {};

  int _inFlight = 0;

  /// A real handler's search is not re-entrant; this one notices.
  bool reentered = false;

  String get host => Uri.parse(booru.baseURL!).host;

  @override
  bool get hasReader => true;

  /// Like the real base class: a new query empties [fetched], a page appends
  /// to it, and the whole list comes back.
  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (_inFlight > 0) reentered = true;
    _inFlight++;
    try {
      queries.add(tags);
      final Duration? delay = delays.entries.where((e) => tags.contains(e.key)).map((e) => e.value).firstOrNull;
      if (delay != null) await Future<void>.delayed(delay);
      if (prevTags != tags) fetched.value = [];
      prevTags = tags;
      final int count = answers.entries.where((e) => tags.contains(e.key)).map((e) => e.value).firstOrNull ?? 6;
      final int stamp = tags.hashCode.abs() % 1000;
      fetched.addAll([
        for (int i = 0; i < count; i++)
          BooruItem(
            fileURL: 'https://$host/g/$stamp-$pageNum-$i/',
            sampleURL: '',
            thumbnailURL: '',
            tagsList: [
              Tag('genshin_impact', tagType: TagType.copyright),
              Tag('artist_${i % 3}', tagType: TagType.artist),
              Tag('big_breasts'),
            ],
            postURL: 'https://$host/g/$stamp-$pageNum-$i/',
            description: 'Book $stamp-$pageNum-$i',
          ),
      ]);
      return fetched;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    loaded.add(item);
    return (item: item, failed: false, error: null);
  }

  @override
  String? relatedVersionsQuery(BooruItem item) => 'related:${item.serverId ?? 'x'}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru ehentai = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  final Booru hitomi = Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', '');
  final Map<String, _FakeSource> fakes = {};

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_foryou');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false
      ..aiRecommendations = false
      ..booruList.clear()
      ..booruList.addAll([gelbooru, nhentai, ehentai, hitomi]);
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    RecommenderHandler.register();
    fakes.clear();
    DoujinForYouHandler.sourceHandlerFactory = (Booru b, int limit) => fakes[b.baseURL!] ??= _FakeSource(b, limit);
  });

  tearDown(() {
    DoujinForYouHandler.sourceHandlerFactory = null;
    RecommenderHandler.unregister();
    DoujinDataHandler.instance.resetForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  DoujinEntry read(String id, List<String> tags, {String host = 'nhentai.net'}) => DoujinEntry(
    postURL: 'https://$host/g/$id/',
    serverId: id,
    thumbnailURL: '',
    title: 'Book $id',
    booruHost: host,
    addedAt: 1,
    tags: tags,
    pages: 30,
  );

  group('the virtual source', () {
    test('is a doujin source of its own kind, offered nowhere a real source is picked', () {
      expect(BooruType.ForYouDoujin.isForYouDoujin, isTrue);
      expect(BooruType.dropDownValues, isNot(contains(BooruType.ForYouDoujin)));
      expect(BooruType.detectable, isNot(contains(BooruType.ForYouDoujin)));
      expect(BooruType.saveable, isNot(contains(BooruType.ForYouDoujin)));
      final Booru b = SettingsHandler.instance.ensureForYouDoujinBooru();
      expect(b.type, BooruType.ForYouDoujin);
      expect(SettingsHandler.instance.ensureForYouDoujinBooru(), same(b), reason: 'added once');
      expect(DoujinDataHandler.isDoujinBooru(b), isTrue, reason: 'the whole doujin system treats it as doujin');
      final BooruHandler h = BooruHandlerFactory().getBooruHandler([b], 20).booruHandler;
      expect(h, isA<DoujinForYouHandler>());
      expect(h.hasReader, isTrue);
    });

    test('fans out over the doujin sources only, and says so when there is nothing to go on', () async {
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      final List result = await h.search('', null) as List;
      expect(result, isEmpty);
      expect(h.sources.map((b) => b.name), ['nhentai', 'eh', 'hitomi']);
      expect(h.errorString, contains('read'));
      expect(h.locked, isTrue);
    });

    test('a doujin booru, but not a doujin source: the pickers and stores that list sources leave it out (review)', () {
      final Booru virtual = SettingsHandler.instance.ensureForYouDoujinBooru();
      expect(DoujinDataHandler.isDoujinBooru(virtual), isTrue);
      expect(DoujinDataHandler.isDoujinSource(virtual), isFalse);
      expect(DoujinDataHandler.isDoujinSource(nhentai), isTrue);
      expect(DoujinDataHandler.isDoujinSource(gelbooru), isFalse);
      expect(DoujinDataHandler.doujinSources().map((b) => b.name), ['nhentai', 'eh', 'hitomi']);
    });

    test('a source added after the feed was opened is asked from the next page on (review)', () async {
      SettingsHandler.instance.booruList
        ..clear()
        ..add(gelbooru);
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      await h.search('seed:parody:x', null);
      expect(h.sources, isEmpty);
      expect(h.errorString, contains('Add at least one doujin source'));
      SettingsHandler.instance.booruList.add(nhentai);
      h.locked = false;
      final List<BooruItem> page = List<BooruItem>.from(await h.search('seed:parody:x', null) as List);
      expect(h.sources.map((b) => b.name), ['nhentai']);
      expect(page, isNotEmpty);
      expect(h.errorString, isEmpty);
    });

    test("each card is filtered by its own source's blacklist, not the virtual source's empty one (review)", () {
      SourceSettingsHandler.instance.addBlacklistTag(nhentai, 'netorare');
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      BooruItem card(String host) => BooruItem(
        fileURL: 'https://$host/g/1/',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: [Tag('netorare')],
        postURL: 'https://$host/g/1/',
      );
      h.fetched.addAll([card('nhentai.net'), card('hitomi.la')]);
      h.filterFetched();
      expect(h.filteredFetched.map((i) => Uri.parse(i.postURL).host), ['hitomi.la']);
    });
  });

  group('the feed', () {
    test("history mode: each remembered gallery asks its parody, character, artist and act tags, in the sites' own grammar", () async {
      DoujinDataHandler.instance.history.addAll([
        read('1', ['parody:genshin_impact', 'character:hu_tao', 'artist:wakahi', 'female:big_breasts', 'female:nakadashi', 'language:english']),
        read('2', ['parody:blue_archive', 'character:hina', 'artist:momoko', 'female:stockings', 'language:english']),
      ]);
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      final List<BooruItem> page = List<BooruItem>.from(await h.search('', null) as List);
      expect(page, isNotEmpty);
      expect(h.errorString, isEmpty);
      final List<String> asked = [for (final f in fakes.values) ...f.queries];
      expect(asked, isNotEmpty);
      expect(asked.any((q) => q.contains('parody:genshin_impact') || q.contains('parody:blue_archive')), isTrue);
      expect(asked.any((q) => q.contains('character:')), isTrue);
      expect(asked.every((q) => !q.contains('language:') || q.contains('language:english')), isTrue);
      // Nothing that was already read comes back, and nothing twice.
      expect(page.map((i) => i.postURL), isNot(contains('https://nhentai.net/g/1/')));
      expect(page.map((i) => i.postURL).toSet().length, page.length);
      // Sources rotate: more than one site answered the first page.
      expect(page.map((i) => Uri.parse(i.postURL).host).toSet().length, greaterThan(1));
      // The act tags are asked, not only the names (review: three facets per
      // gallery used to be character, parody, artist — never an act).
      expect(asked.any((q) => q.contains('female:')), isTrue, reason: asked.join(' | '));
    });

    test('a source that answered a short page and then a long one loses nothing of the long one (review)', () async {
      SettingsHandler.instance.booruList
        ..clear()
        ..add(nhentai);
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      await h.search('seed:parody:short', null);
      final _FakeSource fake = fakes['https://nhentai.net']!;
      fake.answers['parody:long'] = 10;
      fake.answers['parody:short'] = 4;
      // Two seeds rotate: page 1 asks one, page 2 the other.
      final DoujinForYouHandler h2 = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      final List<BooruItem> page1 = List<BooruItem>.from(await h2.search('seed:parody:short seed:parody:long', null) as List);
      final List<BooruItem> page2 = List<BooruItem>.from(await h2.search('seed:parody:short seed:parody:long', null) as List);
      expect(page2.length, 14, reason: '4 + 10, whichever order the seeds were asked in (page 1 had ${page1.length})');
      expect(h2.lastRequests.map((r) => r.got).toList(), anyOf(equals([10]), equals([4])), reason: 'the second page kept the whole answer');
    });

    test('a source that answers late keeps its lane: the next question waits instead of re-entering the handler (review)', () async {
      SettingsHandler.instance.booruList
        ..clear()
        ..add(nhentai);
      DoujinForYouHandler.searchTimeout = const Duration(milliseconds: 40);
      addTearDown(() => DoujinForYouHandler.searchTimeout = DoujinForYouHandler.defaultSearchTimeout);
      final _FakeSource fake = fakes['https://nhentai.net'] = _FakeSource(nhentai, 20);
      fake.delays['parody:slow'] = const Duration(milliseconds: 120);
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      final List<BooruItem> page1 = List<BooruItem>.from(await h.search('seed:parody:slow seed:parody:quick', null) as List);
      final List<BooruItem> page2 = List<BooruItem>.from(await h.search('seed:parody:slow seed:parody:quick', null) as List);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fake.reentered, isFalse, reason: 'the second query waited for the first to finish, timeout or not');
      expect(fake.queries, hasLength(2));
      // The quick query answered its own items, never the slow one's.
      final List<BooruItem> quick = page1.isEmpty ? page2 : page1;
      expect(quick, isNotEmpty);
      expect(quick.every((i) => i.postURL.contains('${'parody:quick'.hashCode.abs() % 1000}-')), isTrue);
    });

    test('the dominant reading language constrains the sites that understand it', () async {
      DoujinDataHandler.instance.history.addAll([
        read('1', ['parody:a', 'language:english']),
        read('2', ['parody:b', 'language:english']),
        read('3', ['parody:c', 'language:english']),
        read('4', ['parody:d', 'language:japanese']),
      ]);
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      await h.search('', null);
      expect(h.language, 'english');
      for (final _FakeSource f in fakes.values) {
        for (final String q in f.queries) {
          if (DoujinForYouHandler.understandsLanguage(f.booru)) {
            expect(q, endsWith('language:english'), reason: '${f.booru.name}: $q');
          } else {
            expect(q, isNot(contains('language:')), reason: '${f.booru.name}: $q');
          }
        }
      }
      expect(DoujinForYouHandler.dominantLanguage([read('1', ['language:english']), read('2', ['language:japanese'])]), '', reason: 'no majority');
    });

    test('seed mode: every source is asked the seed, exclusions travel as a filter', () async {
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      final List<BooruItem> page = List<BooruItem>.from(await h.search('seed:parody:genshin_impact -female:netorare', null) as List);
      expect(page, isNotEmpty);
      final List<String> asked = [for (final f in fakes.values) ...f.queries];
      expect(asked, isNotEmpty);
      expect(asked.every((q) => q.startsWith('parody:genshin_impact') && q.contains('-female:netorare')), isTrue, reason: asked.join(' | '));
      expect(h.seeds, ['parody:genshin_impact']);
      // A plain namespaced term seeds too.
      final DoujinForYouHandler h2 = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      await h2.search('artist:wakahi', null);
      expect(h2.seeds, ['artist:wakahi']);
    });

    test('a card belongs to its own source: loading, related versions and page thumbnails go there', () async {
      final DoujinForYouHandler h = DoujinForYouHandler(SettingsHandler.instance.ensureForYouDoujinBooru(), 20);
      await h.search('seed:parody:x', null);
      final BooruItem card = h.fetched.firstWhere((i) => i.postURL.contains('e-hentai.org'));
      final BooruHandler source = h.handlerForItem(card);
      expect(source, same(fakes['https://e-hentai.org']));
      expect(source.booru.type, BooruType.EHentai);
      await h.loadItem(item: card);
      expect(fakes['https://e-hentai.org']!.loaded, contains(card));
      expect(h.relatedVersionsQuery(card), startsWith('related:'));
      expect(h.handlerForItem(BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://unknown.example/g/1')), same(h), reason: 'no source for an unknown host: itself');
    });
  });

  group('facets', () {
    test('a remembered gallery yields character, parody, artist and act facets, rotating with the page', () {
      final DoujinEntry e = read('1', ['parody:genshin_impact', 'character:hu_tao', 'character:yanfei', 'artist:wakahi', 'female:big_breasts', 'female:nakadashi', 'male:shota', 'language:english']);
      final List<SuggestionFacet> f0 = DoujinForYouHandler.facetsForEntry(e, seed: 0);
      expect(f0.map((f) => f.query), containsAll(['character:hu_tao', 'parody:genshin_impact', 'artist:wakahi']));
      expect(f0.where((f) => f.kind == SuggestionFacetKind.act).map((f) => f.query), containsAll(['female:big_breasts', 'female:nakadashi']));
      expect(f0.map((f) => f.query), isNot(contains('language:english')), reason: 'language is a constraint, not a facet');
      expect(f0.firstWhere((f) => f.kind == SuggestionFacetKind.artist).quota, lessThanOrEqualTo(3), reason: 'the artist is one tap away already');
      final List<SuggestionFacet> f1 = DoujinForYouHandler.facetsForEntry(e, seed: 1);
      expect(f1.map((f) => f.query), contains('character:yanfei'));
      expect(DoujinForYouHandler.facetsForEntry(read('2', const []), seed: 0), isEmpty);
    });
  });
}
