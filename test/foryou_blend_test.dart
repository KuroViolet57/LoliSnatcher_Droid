import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/foryou_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/recommender_handler.dart';

/// A site handler that notices being searched twice at once (its query,
/// page and results are shared, like the real base class).
class _Site extends BooruHandler {
  _Site(super.booru, super.limit);

  int _inFlight = 0;
  bool reentered = false;
  final List<String> queries = [];

  String get host => Uri.parse(booru.baseURL!).host;

  @override
  String validateTags(String tags) => tags;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (_inFlight > 0) reentered = true;
    _inFlight++;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      queries.add(tags);
      if (prevTags != tags) fetched.value = [];
      prevTags = tags;
      final String slug = tags.replaceAll(' ', '+');
      fetched.addAll([
        for (int i = 0; i < 2; i++)
          BooruItem(
            fileURL: 'https://img.$host/$slug-$pageNum-$i.jpg',
            sampleURL: '',
            thumbnailURL: '',
            tagsList: [Tag(tags.split(' ').first)],
            postURL: 'https://$host/p/$slug/$pageNum/$i',
          ),
      ]);
      return fetched;
    } finally {
      _inFlight--;
    }
  }
}

/// "Not interested" on every post of one query; nothing else of the learner.
class _Dismissing extends RecommenderHandler {
  _Dismissing(this.query);

  final String query;

  @override
  bool isDismissed(BooruItem item) => item.postURL.contains('/p/$query/');

  @override
  Future<void> onExposed(List<BooruItem> items, String surface, {BooruHandler? handler}) async {}
}

/// 1.0 (M2): the For You feed in its default mode (facets of recently viewed
/// posts) sent up to nine facet searches at once over two to four sources,
/// several through one source handler at the same time; and it never left
/// out what was marked "Not interested".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;
  final Map<String, _Site> sites = {};
  Booru b(String name) => Booru(name, BooruType.Gelbooru, '', 'https://$name.example', '');
  final Booru forYou = Booru('For You', BooruType.ForYou, '', '', '');

  BooruItem viewed(int n) => BooruItem(
    fileURL: 'https://img.one.example/viewed$n.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag('char_$n'), Tag('series_$n'), Tag('artist_$n'), Tag('act_${n}_thing')],
    postURL: 'https://one.example/p/viewed/$n',
  );

  setUp(() async {
    SettingsHandler.register();
    SearchHandler.register();
    InterestsHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('foryou_blend');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    SettingsHandler.instance.booruList.value = [b('one'), b('two')];
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
    for (int n = 0; n < 3; n++) {
      await TagHandler.instance.putTag(Tag('char_$n', tagType: TagType.character), dbEnabled: false);
      await TagHandler.instance.putTag(Tag('series_$n', tagType: TagType.copyright), dbEnabled: false);
      await TagHandler.instance.putTag(Tag('artist_$n', tagType: TagType.artist), dbEnabled: false);
      if (dbReady) {
        await SettingsHandler.instance.dbHandler.addViewedPost(viewed(n).postURL, DBHandler.serializeHistoryItem(viewed(n)));
      }
    }
    sites.clear();
    ForYouHandler.resetForTests();
    ForYouHandler.resolveTag = (String tag, Booru booru) async => tag;
    ForYouHandler.sourceFactory = (Booru booru, int limit) {
      final _Site s = sites.putIfAbsent(booru.name ?? '', () => _Site(booru, limit));
      return (handler: s, startingPage: 0);
    };
  });

  tearDown(() async {
    ForYouHandler.resetForTests();
    RecommenderHandler.unregister();
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('history mode: the facets that land on one source take turns; every source still answers', () async {
    if (!dbReady) return;
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('', null) as List);
    expect(sites.length, 2);
    final int asked = sites.values.fold(0, (int sum, s) => sum + s.queries.length);
    expect(asked, greaterThan(sites.length), reason: 'more facets than sources: some share a source');
    for (final _Site s in sites.values) {
      expect(s.reentered, isFalse, reason: '${s.booru.name} was searched twice at once');
      expect(s.queries, isNotEmpty);
    }
    expect(items, isNotEmpty);
    // Each facet's posts come back with it: every query asked shows up.
    final Set<String> shown = {for (final i in items) Uri.parse(i.postURL).pathSegments[1]};
    final Set<String> queried = {for (final s in sites.values) ...s.queries.map((q) => q.replaceAll(' ', '+'))};
    expect(shown, queried);
  });

  test('history mode leaves out what was marked "Not interested"', () async {
    if (!dbReady) return;
    RecommenderHandler.unregister();
    GetIt.instance.registerSingleton<RecommenderHandler>(_Dismissing('char_0'));
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('', null) as List);
    final Set<String> queried = {for (final s in sites.values) ...s.queries};
    expect(queried, contains('char_0'), reason: 'the dismissed posts were among the answers');
    expect(items, isNotEmpty);
    expect(items.where((i) => i.postURL.contains('/p/char_0/')), isEmpty);
  });
}
