import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r33: the rule every recommendation surface follows — what it shows goes
/// through the recommender's reranking and is reported as shown. One
/// guard reads the surfaces' sources for the two calls; the doujin
/// Recommended strip is exercised for real.
class _CountingRecommender extends RecommenderHandler {
  final List<({int count, String surface})> exposures = [];
  final Set<String> dismissed = {};
  double Function(BooruItem)? scorerToGive;

  @override
  Future<void> onExposed(List<BooruItem> items, String surface, {BooruHandler? handler}) async {
    exposures.add((count: items.length, surface: surface));
  }

  @override
  Future<double Function(BooruItem)?> scorer(RecommenderWorld world, {BooruHandler? handler, List<BooruItem>? items}) async => scorerToGive;

  @override
  bool isDismissed(BooruItem item) => dismissed.contains(item.postURL);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingRecommender counting;

  setUp(() {
    SettingsHandler.register();
    RecommenderHandler.unregister();
    counting = _CountingRecommender();
    GetIt.instance.registerSingleton<RecommenderHandler>(counting);
  });

  tearDown(RecommenderHandler.unregister);

  test('every surface that produces recommendations reranks through the recommender and reports what it showed', () {
    // r34: a surface also leaves out what the user said they are not
    // interested in (`withoutDismissed`).
    const Map<String, List<String>> surfaces = {
      'lib/src/boorus/foryou_handler.dart': ['RecommenderHandler.maybe?.rerank(', 'onExposed(', "'foryou'", 'withoutDismissed('],
      'lib/src/boorus/suggestion_handler.dart': ['RecommenderHandler.maybe?.rerank(', 'onExposed(', "'suggested'", 'withoutDismissed('],
      'lib/src/boorus/doujin_foryou_handler.dart': ['RecommenderHandler.maybe?.rerank(', 'onExposed(', "'foryou-doujin'", 'withoutDismissed('],
      'lib/src/boorus/doujin/doujin_recommendation_engine.dart': ['RecommenderHandler.maybe?.scorer(', 'onExposed(', "'doujin-recommend'", 'withoutDismissed('],
      // nhentai ranks its own raw rows rather than through the engine.
      'lib/src/boorus/nhentai_handler.dart': ['RecommenderHandler.maybe?.scorer(', 'onExposed(', 'DoujinRecommendationEngine.surface'],
    };
    for (final entry in surfaces.entries) {
      final String src = File(entry.key).readAsStringSync();
      for (final String needle in entry.value) {
        expect(src, contains(needle), reason: '${entry.key} must contain $needle');
      }
    }
    // The doujin Recommended strip: every source ranks through the personal
    // variant, never the bare engine (which would skip taste and exposures).
    final List<File> handlers = Directory('lib/src/boorus').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('_handler.dart')).toList();
    expect(handlers, isNotEmpty);
    for (final File f in handlers) {
      final String src = f.readAsStringSync();
      expect(src, isNot(contains('DoujinRecommendationEngine.rank(')), reason: '${f.path} must call rankPersonal, not rank');
    }
  });

  group('the doujin Recommended strip', () {
    BooruItem book(String id, List<String> tags, {String artist = 'a'}) => BooruItem(
      fileURL: 'https://nhentai.net/g/$id/',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: [for (final t in tags) Tag(t), Tag(artist, tagType: TagType.artist)],
      postURL: 'https://nhentai.net/g/$id/',
      description: 'Book $id',
    );

    test('with no scorer the similarity order stands, and the page is reported', () async {
      final BooruItem source = book('s', ['x', 'y', 'z']);
      final List<BooruItem> out = await DoujinRecommendationEngine.rankPersonal(
        source,
        [book('far', ['q']), book('near', ['x', 'y']), book('mid', ['x'])],
        count: 3,
      );
      expect(out.map((i) => i.serverId ?? i.postURL), ['https://nhentai.net/g/near/', 'https://nhentai.net/g/mid/', 'https://nhentai.net/g/far/']);
      expect(counting.exposures, [(count: 3, surface: 'doujin-recommend')]);
    });

    test('what the user is not interested in never comes back (r34)', () async {
      final BooruItem source = book('s', ['x', 'y', 'z']);
      final BooruItem gone = book('near', ['x', 'y']);
      counting.dismissed.add(gone.postURL);
      final List<BooruItem> out = await DoujinRecommendationEngine.rankPersonal(
        source,
        [book('far', ['q']), gone, book('mid', ['x'])],
        count: 3,
      );
      expect(out.map((i) => i.postURL), isNot(contains(gone.postURL)));
      expect(out, hasLength(2));
    });

    test('with a scorer, taste moves the order without drowning similarity', () async {
      final BooruItem source = book('s', ['x', 'y', 'z']);
      counting.scorerToGive = (BooruItem i) => i.postURL.contains('mid') ? 0.95 : 0.05;
      final List<BooruItem> out = await DoujinRecommendationEngine.rankPersonal(
        source,
        [book('far', ['q']), book('near', ['x', 'y']), book('mid', ['x'])],
        count: 3,
      );
      expect(out.first.postURL, contains('mid'), reason: 'liked and fairly similar wins');
      expect(out.last.postURL, contains('far'), reason: 'taste alone cannot lift something unrelated');
    });
  });
}
