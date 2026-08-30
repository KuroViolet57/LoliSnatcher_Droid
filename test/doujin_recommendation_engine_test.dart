import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';

/// Round 4: Related and Recommended have to exist on EVERY doujin source,
/// including the ones whose sites publish nothing of the kind. This engine
/// derives both from what every source already has — the title and the tags —
/// so it works the same everywhere.
void main() {
  BooruItem gallery(String id, String title, List<String> tags) => BooruItem(
    fileURL: 'https://img.example/$id.png',
    sampleURL: 'https://img.example/$id.png',
    thumbnailURL: 'https://thumb.example/$id.png',
    tagsList: [for (final t in tags) Tag(t)],
    postURL: 'https://example.org/g/$id/',
    serverId: id,
  )..description = title;

  group('title handling', () {
    test('the work title survives circle prefixes, qualifiers and chapter numbers', () {
      expect(
        DoujinRecommendationEngine.baseTitle('[Asakawa (Hayaku)] Gravity Drawn to You Episode 2'),
        'Gravity Drawn to You',
      );
      expect(DoujinRecommendationEngine.baseTitle('Some Work Ch. 3'), 'Some Work');
      expect(DoujinRecommendationEngine.baseTitle('Some Work [English]'), 'Some Work');
      expect(DoujinRecommendationEngine.baseTitle('Some Work'), 'Some Work');
    });

    test('boilerplate words do not count as title similarity', () {
      // Two unrelated works sharing only "english"/"digital" must not match.
      final double sim = DoujinRecommendationEngine.titleSimilarity(
        DoujinRecommendationEngine.titleTokens('Alpha Story [English] [Digital]'),
        'Beta Chronicle [English] [Digital]',
      );
      expect(sim, 0);
    });

    test('a real shared title scores high', () {
      final double sim = DoujinRecommendationEngine.titleSimilarity(
        DoujinRecommendationEngine.titleTokens('Gravity Drawn to You Episode 1'),
        'Gravity Drawn to You Episode 2',
      );
      expect(sim, greaterThan(0.8));
    });
  });

  group('Related — other chapters and versions of the same work', () {
    test('picks up sibling instalments and language versions, not strangers', () {
      final source = gallery('1', '[Circle] Gravity Drawn to You Episode 1', ['romance']);
      final related = DoujinRecommendationEngine.related(source, [
        gallery('2', '[Circle] Gravity Drawn to You Episode 2', ['romance']),
        gallery('3', '[Circle] Gravity Drawn to You Episode 3 [English]', ['romance']),
        gallery('4', 'Completely Different Work', ['romance']),
      ]);

      expect(related.map((e) => e.serverId), ['2', '3']);
    });

    test('never returns the source gallery itself', () {
      final source = gallery('1', 'Gravity Drawn to You', ['romance']);
      final related = DoujinRecommendationEngine.related(source, [source]);
      expect(related, isEmpty);
    });
  });

  group('Recommended — tag overlap and title, with artists kept a minority', () {
    test('ranks by shared tags', () {
      final source = gallery('1', 'Source Work', ['vanilla', 'glasses', 'romance']);
      final ranked = DoujinRecommendationEngine.rank(
        source,
        [
          gallery('2', 'Barely Related', ['ntr']),
          gallery('3', 'Very Close', ['vanilla', 'glasses', 'romance']),
          gallery('4', 'Somewhat Close', ['vanilla', 'glasses']),
        ],
        count: 3,
      );

      expect(ranked.map((e) => e.serverId).toList(), ['3', '4', '2']);
    });

    test('other versions of the same work are left to Related', () {
      final source = gallery('1', 'Gravity Episode 1', ['vanilla']);
      final ranked = DoujinRecommendationEngine.rank(
        source,
        [
          gallery('2', 'Gravity Episode 2', ['vanilla']),
          gallery('3', 'Unrelated Story', ['vanilla']),
        ],
        count: 5,
      );
      expect(ranked.map((e) => e.serverId), ['3']);
    });

    test('same-artist results are capped rather than allowed to take over', () {
      final source = gallery('1', 'Source', ['vanilla', 'artist:someone']);
      // Ten same-artist candidates, all a perfect tag match.
      final candidates = [
        for (int i = 2; i <= 11; i++) gallery('$i', 'Work $i', ['vanilla', 'artist:someone']),
        gallery('99', 'Other Author Work', ['vanilla']),
      ];

      final ranked = DoujinRecommendationEngine.rank(
        source,
        candidates,
        count: 6,
        sourceArtist: 'someone',
      );

      final int sameArtist = ranked
          .where((e) => e.tagsList.any((t) => t.fullString == 'artist:someone'))
          .length;
      expect(sameArtist, lessThanOrEqualTo(DoujinRecommendationEngine.artistCap(6)));
      // ...and the non-artist match still gets a place.
      expect(ranked.map((e) => e.serverId), contains('99'));
    });

    test('duplicates are dropped and the count is respected', () {
      final source = gallery('1', 'Source', ['vanilla']);
      final dupe = gallery('2', 'Dupe', ['vanilla']);
      final ranked = DoujinRecommendationEngine.rank(
        source,
        [dupe, dupe, gallery('3', 'Third', ['vanilla'])],
        count: 2,
      );
      expect(ranked.length, 2);
      expect(ranked.map((e) => e.serverId).toSet().length, 2);
    });

    test('a source with no tags still ranks by title instead of crashing', () {
      final source = gallery('1', 'Gravity Drawn', const []);
      final ranked = DoujinRecommendationEngine.rank(
        source,
        [gallery('2', 'Totally Other', const []), gallery('3', 'Gravity Pulled', const [])],
        count: 2,
      );
      expect(ranked.first.serverId, '3');
    });
  });
}
