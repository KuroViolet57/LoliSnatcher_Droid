import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/board_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/board_query.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r73: the board feed - a virtual booru that asks the board's sources for
/// the must-have tags plus the tags derived from the description and the
/// reference image, keeps only posts that really carry the must-have tags,
/// and ranks by how close each post reads to the description.
class _FakeSource extends BooruHandler {
  _FakeSource(super.booru, super.limit);
  final List<String> queries = [];

  /// Rows answered per query substring; each row is its tag list.
  Map<String, List<List<String>>> answers = {};

  String get host => Uri.parse(booru.baseURL!).host;

  @override
  String validateTags(String tags) => tags;

  int _inFlight = 0;

  /// A real handler's search is not re-entrant; this one notices.
  bool reentered = false;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (_inFlight > 0) reentered = true;
    _inFlight++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    queries.add(tags);
    if (prevTags != tags) fetched.value = [];
    prevTags = tags;
    final List<List<String>> rows = answers.entries.where((e) => tags.contains(e.key)).map((e) => e.value).firstOrNull ?? const [];
    _inFlight--;
    fetched.addAll([
      for (int i = 0; i < rows.length; i++)
        BooruItem(
          fileURL: 'https://$host/f/${tags.hashCode.abs()}-$pageNum-$i.jpg',
          sampleURL: '',
          thumbnailURL: '',
          tagsList: rows[i].map(Tag.new).toList(),
          postURL: 'https://$host/p/${tags.hashCode.abs()}-$pageNum-$i',
          serverId: '${tags.hashCode.abs() % 1000}$pageNum$i',
        ),
    ]);
    return fetched;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Map<String, _FakeSource> fakes = {};
  Booru b(String name) => Booru(name, BooruType.Gelbooru, '', 'https://$name.example', '');
  final Booru boardBooru = Booru('Boards', BooruType.Board, '', '', '');

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('board_handler');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    await BoardsHandler.instance.resetForTests();
    BoardsHandler.instance.directoryOverride = SettingsHandler.instance.path;
    BoardQueryBuilder.resetForTests();
    BoardHandler.resetForTests();
    fakes.clear();
    BoardHandler.sourceFactory = (Booru booru, int limit) {
      final _FakeSource f = fakes.putIfAbsent(booru.name ?? '', () => _FakeSource(booru, limit));
      return (handler: f, startingPage: 0);
    };
    BoardHandler.allSources = () => [b('one'), b('two')];
    // The alias resolver: 'animated' is 'video' on source two; 'nope' a confirmed miss everywhere (null).
    BoardHandler.resolveTag = (String tag, Booru booru) async {
      if (tag == 'nope') return null;
      if (tag == 'animated' && booru.name == 'two') return 'video';
      return tag;
    };
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => const [];
    BoardQueryBuilder.siteSuggest = (handler, String word) async => const [];
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async => const [];
  });
  tearDown(() async {
    BoardHandler.resetForTests();
    BoardQueryBuilder.resetForTests();
    await BoardsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Board> board({String description = '', List<String> must = const [], List<String> exclude = const [], List<String> sources = const [], String imageUrl = ''}) =>
      BoardsHandler.instance.save(Board(id: BoardsHandler.instance.newId(), name: 'test', description: description, mustTags: must, excludeTags: exclude, sourceNames: sources, imageUrl: imageUrl));

  test('the factory hands a Boards tab to the board handler; the type is a feed, not a saveable source', () {
    final r = BooruHandlerFactory().getBooruHandler([boardBooru], 20);
    expect(r.booruHandler, isA<BoardHandler>());
    expect(BooruType.Board.isRecommendationFeed, isTrue);
    expect(BooruType.saveable, isNot(contains(BooruType.Board)));
    expect(BooruType.detectable, isNot(contains(BooruType.Board)));
    expect(BoardHandler.boardIdOf('board:abc'), 'abc');
    expect(BoardHandler.boardIdOf('abc'), isNull);
  });

  test('an unknown board id is an error, not an empty feed', () async {
    final BoardHandler h = BoardHandler(boardBooru, 20);
    final List items = await h.search('board:missing', null) as List;
    expect(items, isEmpty);
    expect(h.errorString, contains('board'));
    expect(h.locked, isTrue);
  });

  test('must-have tags are asked for in the site\'s own spelling and enforced on the answers; a site that lacks the tag is skipped', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'beach' ? [entry('beach')] : const [];
    final Board bd = await board(description: 'beach', must: ['animated'], sources: ['one', 'two']);
    final BoardHandler h = BoardHandler(boardBooru, 20);
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'animated': [['animated', 'beach'], ['beach', 'solo']]};
    fakes['two'] = _FakeSource(b('two'), 20)..answers = {'video': [['video', 'beach']]};
    final List<BooruItem> items = List<BooruItem>.from(await h.search('board:${bd.id}', null) as List);
    expect(fakes['one']!.queries.first, 'animated beach');
    expect(fakes['two']!.queries.first, 'video beach', reason: 'the must-have tag in the site\'s spelling, then the derived tag');
    expect(items.map((i) => i.tagsList.map((t) => t.fullString).join(' ')), containsAll(['animated beach', 'video beach']));
    expect(items.map((i) => i.tagsList.map((t) => t.fullString).join(' ')), isNot(contains('beach solo')), reason: 'the site answered a post without the must-have tag');
    // A must-have tag no site knows: nothing is asked, the feed says why.
    final Board none = await board(description: 'beach', must: ['nope'], sources: ['one']);
    final BoardHandler h2 = BoardHandler(boardBooru, 20);
    fakes['one']!.queries.clear();
    final List r2 = await h2.search('board:${none.id}', null) as List;
    expect(r2, isEmpty);
    expect(fakes['one']!.queries, isEmpty);
    expect(h2.skippedSources, ['one']);
    expect(h2.errorString, contains('nope'));
  });

  test('excluded tags drop posts; the description alone still asks derived tags; pages rotate the derived tags and deepen', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => switch (query) {
      'beach' => [entry('beach')],
      'sunset' => [entry('sunset')],
      _ => const [],
    };
    final Board bd = await board(description: 'beach sunset', exclude: ['male'], sources: ['one']);
    fakes['one'] = _FakeSource(b('one'), 20)
      ..answers = {
        'beach': [['beach', 'male'], ['beach', 'girl']],
        'sunset': [['sunset', 'sky']],
      };
    final BoardHandler h = BoardHandler(boardBooru, 20);
    final List<BooruItem> page1 = List<BooruItem>.from(await h.search('board:${bd.id}', null) as List);
    expect(page1.map((i) => i.tagsList.first.fullString), isNot(contains('male')));
    expect(page1, isNotEmpty);
    expect(h.derivedTags.map((t) => t.tag), containsAll(['beach', 'sunset']));
    final List<BooruItem> page2 = List<BooruItem>.from(await h.search('board:${bd.id}', null) as List);
    expect(page2.length, greaterThanOrEqualTo(page1.length));
    expect(fakes['one']!.queries.toSet().length, greaterThan(1), reason: 'the second page asks a different derived tag or a deeper page');
  });

  test('ranking: the encoder puts posts that read like the description first; the reference image\'s exact match is pinned on top', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'beach' ? [entry('beach')] : const [];
    // Exact matches go to the site that owns the id, by host.
    final Booru gel = Booru('one', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    BoardHandler.allSources = () => [gel];
    final Board bd = await board(description: 'beach', sources: ['one'], imageUrl: 'https://x/ref.jpg');
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async => [
      ReverseMatch(site: 'gelbooru', postId: '42', similarity: 95, tags: const ['sakamata_chloe']),
    ];
    fakes['one'] = _FakeSource(gel, 20)
      ..answers = {
        'id:42': [['sakamata_chloe', 'beach', 'exact']],
        'sakamata_chloe': [['sakamata_chloe', 'city']],
        'beach': [['beach', 'far'], ['beach', 'near']],
      };
    // A toy encoder: "near" reads like the description, "far" does not.
    BoardHandler.embedText = (String text) async => Float32List.fromList([1, 0]);
    BoardHandler.embedItems = (List<BooruItem> items, BooruHandler handler) async => [
      for (final BooruItem i in items) Float32List.fromList(i.tagsList.any((t) => t.fullString == 'near') ? [1, 0] : [0, 1]),
    ];
    final BoardHandler h = BoardHandler(boardBooru, 20);
    // One derived tag per source per page: the match's character first, the description's tag on the next page.
    await h.search('board:${bd.id}', null);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('board:${bd.id}', null) as List);
    final List<String> firstTags = items.map((i) => i.tagsList.map((t) => t.fullString).join(' ')).toList();
    expect(firstTags.first, 'sakamata_chloe beach exact', reason: 'the exact match comes first');
    expect(firstTags, containsAll(['beach near', 'beach far']));
    expect(firstTags.indexOf('beach near'), lessThan(firstTags.indexOf('beach far')), reason: 'the encoder ranks within the page');
    expect(h.derivedTags.first.tag, 'sakamata_chloe', reason: 'the match\'s character leads the derived tags');
    expect(fakes['one']!.queries, contains('id:42'));
    expect(fakes['one']!.reentered, isFalse, reason: 'the exact match and the derived query must not overlap on one source');
  });

  test('image matches are cached on the board: the same image asks nothing twice, a new image asks again, a failure is not cached', () async {
    int calls = 0;
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async {
      calls++;
      return [ReverseMatch(site: 'gelbooru', postId: '7', similarity: 90, tags: const ['x'])];
    };
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'id:7': [['x', 'seven']], 'x': [['x']]};
    final Board bd = await board(sources: ['one'], imageUrl: 'https://x/a.jpg');
    await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
    expect(calls, 1);
    final Board stored = BoardsHandler.instance.byId(bd.id)!;
    expect(stored.matches!.single.postId, '7');
    expect(stored.matchedImage, 'url:https://x/a.jpg');
    expect(stored.matchedAt, isNotNull);
    await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
    expect(calls, 1, reason: 'the cache answered');
    await BoardsHandler.instance.save(stored.copyWith(imageUrl: 'https://x/b.jpg'));
    await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
    expect(calls, 2, reason: 'a new image asks again');
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async {
      calls++;
      throw Exception('SauceNAO: Daily Search Limit Exceeded');
    };
    await BoardsHandler.instance.save(BoardsHandler.instance.byId(bd.id)!.copyWith(imageUrl: 'https://x/c.jpg', clearMatches: true));
    final BoardHandler failing = BoardHandler(boardBooru, 20);
    await failing.search('board:${bd.id}', null);
    expect(calls, 3);
    expect(failing.imageError, contains('Daily Search Limit'));
    expect(BoardsHandler.instance.byId(bd.id)!.matches, isNull, reason: 'a failure is not cached');
  });

  test('exact matches are asked only on sites whose id: search is verified (danbooru, gelbooru, moebooru, e621), not sankaku', () async {
    final Booru sank = Booru('sank', BooruType.Sankaku, '', 'https://chan.sankakucomplex.com', '');
    final Booru gel = Booru('one', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    BoardHandler.allSources = () => [sank, gel];
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async => [
      const ReverseMatch(site: 'sankaku', postId: '5', similarity: 90),
      const ReverseMatch(site: 'gelbooru', postId: '6', similarity: 88),
    ];
    fakes['sank'] = _FakeSource(sank, 20);
    fakes['one'] = _FakeSource(gel, 20)..answers = {'id:6': [['six']]};
    final Board bd = await board(sources: ['sank', 'one'], imageUrl: 'https://x/a.jpg');
    await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
    expect(fakes['sank']!.queries.where((q) => q.startsWith('id:')), isEmpty);
    expect(fakes['one']!.queries, contains('id:6'));
  });

  test('exact matches go to the site that owns the id, by host, never to another site of the same engine; the other-site ids of a match count too', () async {
    final Booru gel = Booru('gel', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    final Booru r34 = Booru('r34', BooruType.Gelbooru, '', 'https://rule34.xxx', '');
    BoardHandler.allSources = () => [gel, r34];
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async => [
      const ReverseMatch(site: 'danbooru', postId: '1234', similarity: 93, alsoOn: {'gelbooru': '99'}),
    ];
    fakes['gel'] = _FakeSource(gel, 20)..answers = {'id:99': [['ninety_nine']]};
    fakes['r34'] = _FakeSource(r34, 20);
    final Board bd = await board(sources: ['gel', 'r34'], imageUrl: 'https://x/a.jpg');
    final List<BooruItem> items = List<BooruItem>.from(await BoardHandler(boardBooru, 20).search('board:${bd.id}', null) as List);
    expect(fakes['gel']!.queries, contains('id:99'), reason: 'the gelbooru id of the same picture');
    expect(fakes['r34']!.queries.where((q) => q.startsWith('id:')), isEmpty, reason: 'rule34.xxx is not gelbooru.com');
    expect(items.map((i) => i.tagsList.first.fullString), contains('ninety_nine'));
  });

  test('a restored board tab loads the store by itself (the Boards page was never opened)', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'beach' ? [entry('beach')] : const [];
    final Board bd = await board(description: 'beach', sources: ['one']);
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'beach': [['beach']]};
    // A fresh process: nothing in memory, the file on disk.
    final String dir = BoardsHandler.instance.directoryOverride!;
    await BoardsHandler.instance.resetForTests();
    BoardsHandler.instance.directoryOverride = dir;
    expect(BoardsHandler.instance.isLoaded, isFalse);
    final BoardHandler h = BoardHandler(boardBooru, 20);
    final List items = await h.search('board:${bd.id}', null) as List;
    expect(h.errorString, isEmpty);
    expect(items, isNotEmpty);
  });

  test('two searches at once (a tab switch during the first load) share one init and one page', () async {
    int matcherCalls = 0;
    BoardHandler.imageMatcher = (Board board, List<Booru> sources) async {
      matcherCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return const [];
    };
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'beach' ? [entry('beach')] : const [];
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'beach': [['beach', 'a'], ['beach', 'b']]};
    final Board bd = await board(description: 'beach', sources: ['one'], imageUrl: 'https://x/a.jpg');
    final BoardHandler h = BoardHandler(boardBooru, 20);
    final List<dynamic> both = await Future.wait([h.search('board:${bd.id}', null), h.search('board:${bd.id}', null)]);
    expect(matcherCalls, 1);
    expect(fakes['one']!.queries, ['beach'], reason: 'one page, asked once');
    expect((both[0] as List).length, 2);
    expect((both[1] as List).length, 2);
    expect(h.errorString, isEmpty);
    expect(h.locked, isFalse);
  });

  test('no sources chosen means every eligible source; nothing left after two empty rounds locks the feed without an error', () async {
    final Board bd = await board(description: 'zzzz', sources: const []);
    fakes['one'] = _FakeSource(b('one'), 20);
    fakes['two'] = _FakeSource(b('two'), 20);
    final BoardHandler h = BoardHandler(boardBooru, 20);
    final List r = await h.search('board:${bd.id}', null) as List;
    expect(r, isEmpty);
    expect(h.sources.map((s) => s.name), ['one', 'two']);
    expect(h.locked, isTrue);
    expect(h.errorString, contains('nothing'), reason: 'a description no site understands says so');
  });

  group('r74: tags from the picture', () {
    late int taggerCalls;
    setUp(() {
      taggerCalls = 0;
      BoardHandler.pixelModelId = () => 'wd';
      BoardHandler.pixelTagger = (Board board) async {
        taggerCalls++;
        return [(tag: 'sakamata_chloe', weight: 4.0), (tag: 'cat_ears', weight: 2.7)];
      };
    });

    test('the tagger\'s tags seed the queries, strongest first, and are cached on the board with the image and the model', () async {
      final Board bd = await board(imageUrl: 'https://x.example/ref.jpg', sources: ['one', 'two']);
      fakes['one'] = _FakeSource(b('one'), 20)..answers = {'sakamata_chloe': [['sakamata_chloe', 'cat_ears']]};
      fakes['two'] = _FakeSource(b('two'), 20)..answers = {'cat_ears': [['cat_ears', 'beach']]};
      final BoardHandler h = BoardHandler(boardBooru, 20);
      final List<BooruItem> items = List<BooruItem>.from(await h.search('board:${bd.id}', null) as List);
      expect(items, isNotEmpty);
      expect(h.derivedTags.map((t) => t.tag).toList(), ['sakamata_chloe', 'cat_ears']);
      expect([...fakes['one']!.queries, ...fakes['two']!.queries], containsAll(['sakamata_chloe', 'cat_ears']));
      expect(taggerCalls, 1);
      final Board stored = BoardsHandler.instance.byId(bd.id)!;
      expect(stored.pixelTags?.map((t) => t.tag).toList(), ['sakamata_chloe', 'cat_ears']);
      expect(stored.pixelImage, '${stored.imageKey}@wd');
      expect(stored.hasFreshPixelTags('wd'), isTrue);
      expect(stored.hasFreshPixelTags('other-model'), isFalse);
      // A second open: the cache answers, the tagger is not run again.
      final BoardHandler again = BoardHandler(boardBooru, 20);
      await again.search('board:${bd.id}', null);
      expect(taggerCalls, 1);
      expect(again.derivedTags.map((t) => t.tag).toList(), ['sakamata_chloe', 'cat_ears']);
      // A new image, then a new model: tagged again.
      await BoardsHandler.instance.save(stored.copyWith(imageUrl: 'https://x.example/other.jpg'));
      await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
      expect(taggerCalls, 2);
      BoardHandler.pixelModelId = () => 'wd-2';
      await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
      expect(taggerCalls, 3);
      // Refreshing the image matches forgets the pixel tags too.
      final Board cleared = BoardsHandler.instance.byId(bd.id)!.copyWith(clearMatches: true);
      expect(cleared.pixelTags, isNull);
      expect(cleared.pixelImage, '');
    });

    test('a tagger failure leaves the feed on the description and caches nothing; no tagger = nothing asked', () async {
      BoardHandler.pixelTagger = (Board board) async {
        taggerCalls++;
        throw StateError('boom');
      };
      BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'beach' ? [entry('beach')] : const [];
      final Board bd = await board(description: 'beach', imageUrl: 'https://x.example/ref.jpg', sources: ['one']);
      fakes['one'] = _FakeSource(b('one'), 20)..answers = {'beach': [['beach', 'solo']]};
      final BoardHandler h = BoardHandler(boardBooru, 20);
      final List items = await h.search('board:${bd.id}', null) as List;
      expect(items, hasLength(1));
      expect(taggerCalls, 1);
      expect(BoardsHandler.instance.byId(bd.id)!.pixelTags, isNull);
      BoardHandler.pixelModelId = () => '';
      await BoardHandler(boardBooru, 20).search('board:${bd.id}', null);
      expect(taggerCalls, 1, reason: 'no tagger downloaded: not asked');
    });

    test('seedsFrom: a character weighs like a SauceNAO name, general tags by confidence, ten at most', () {
      final TaggerResult r = TaggerResult(
        general: [for (int i = 0; i < 12; i++) (tag: 'g$i', confidence: 0.9 - i * 0.05, character: false)],
        characters: const [(tag: 'hatsune_miku', confidence: 0.95, character: true)],
        rating: 'general',
        ratingConfidence: 0.8,
      );
      final List<WeightedTag> seeds = BoardHandler.seedsFrom(r);
      expect(seeds.first, (tag: 'hatsune_miku', weight: 4.0));
      expect(seeds, hasLength(11));
      expect(seeds[1].tag, 'g0');
      expect(seeds[1].weight, closeTo(2.7, 1e-9));
    });
  });
}

BooruTagEntry entry(String name) => BooruTagEntry(name: name, tagType: TagType.none);
