import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/foryou_handler.dart';
import 'package:lolisnatcher/src/boorus/suggestion_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The Suggested strip and the Recommended feed both ignored every filter put
/// on them: the strip's videos/GIFs toggle changed nothing, and a feed asked
/// for animated content came back with animated and still images mixed.
///
/// Neither surface reads the tag string it is given. The strip passes the
/// placeholder 'suggestions' as its tag and builds queries from the source
/// POST; For You treats plain tags as seeds that steer rather than constrain.
/// So the filter was assembled into a string nothing ever looked at.
///
/// FALSIFIER for each test below: a sub-query that goes out without the filter
/// attached is a result set that can contain the thing being filtered out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('sugg_filter');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final booru = Booru('r34', BooruType.Gelbooru, '', 'https://rule34.xxx', '');

  BooruItem sourceItem() => BooruItem(
    fileURL: 'https://cdn.invalid/a.webm',
    sampleURL: 'https://cdn.invalid/a.webm',
    thumbnailURL: 'https://cdn.invalid/a.jpg',
    tagsList: [Tag('artist_name'), Tag('character_name'), Tag('animated')],
    postURL: 'https://rule34.xxx/index.php?page=post&s=view&id=1',
    serverId: '1',
  );

  group('the strip videos/GIFs toggle reaches the query', () {
    SuggestionHandler handlerWith(String filter) => SuggestionHandler(
      booru,
      30,
      sourceItem: sourceItem(),
      extraFilter: filter,
    );

    test('the filter is appended to a facet query', () {
      expect(handlerWith('animated|video').withFilter('artist_name'), 'artist_name animated|video');
    });

    test('with the toggle off the query is untouched', () {
      // Off must mean off — a stray token would change what the strip returns.
      expect(handlerWith('').withFilter('artist_name'), 'artist_name');
      expect(handlerWith('   ').withFilter('artist_name'), 'artist_name');
    });

    test('a multi-term facet keeps all of its terms', () {
      // The style facets are two-term ("3d mating_press"); dropping one would
      // silently widen the strip.
      expect(
        handlerWith('video').withFilter('3d mating_press'),
        '3d mating_press video',
      );
    });

    test('an empty facet query becomes just the filter', () {
      expect(handlerWith('video').withFilter(''), 'video');
    });

    test('the default is no filter, so nothing changes for anyone not using it', () {
      final plain = SuggestionHandler(booru, 30, sourceItem: sourceItem());
      expect(plain.withFilter('artist_name'), 'artist_name');
    });
  });

  group('the Recommended feed can actually be constrained', () {
    ForYouHandler forYou() => ForYouHandler(
      Booru('For You', BooruType.ForYou, '', '', ''),
      20,
    );

    test('an exclusion is a filter, not a seed', () {
      // -tag was already skipped as a seed, and then dropped entirely, so it
      // constrained nothing at all.
      expect(ForYouHandler.parseFilter('cats -animated'), '-animated');
    });

    test('filter: requires a tag on every result', () {
      expect(ForYouHandler.parseFilter('cats filter:animated'), 'animated');
    });

    test('an OR filter survives for boorus that support it', () {
      expect(ForYouHandler.parseFilter('filter:animated|video'), 'animated|video');
    });

    test('plain tags stay seeds — steering is not filtering', () {
      // Deliberate: searching `girl` aims the feed rather than requiring it.
      // Changing that would break steering, which is a separate feature.
      expect(ForYouHandler.parseFilter('girl cats'), isEmpty);
      expect(ForYouHandler.parseFilter('seed:girl'), isEmpty);
    });

    test('several filters combine', () {
      expect(
        ForYouHandler.parseFilter('seed:cat filter:animated -loli extra'),
        contains('animated'),
      );
      expect(ForYouHandler.parseFilter('seed:cat filter:animated -loli'), contains('-loli'));
    });

    test('a bare prefix with nothing after it is ignored', () {
      expect(ForYouHandler.parseFilter('filter:'), isEmpty);
      expect(ForYouHandler.parseFilter('-'), isEmpty);
    });

    test('the filter is appended to a sub-query', () {
      final h = forYou()..extraFilter = 'animated';
      expect(h.withFilter('hatsune_miku'), 'hatsune_miku animated');
    });

    test('with no filter the sub-query is untouched', () {
      expect(forYou().withFilter('hatsune_miku'), 'hatsune_miku');
    });
  });
}
