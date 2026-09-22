import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';

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

  group('CJK titles', () {
    // Most of the catalogue on these sites has a Japanese or Chinese title.
    // A word split on those yields nothing at all, which used to make every
    // CJK-titled work look unrelated to every other.
    test('a Japanese title produces tokens instead of nothing', () {
      expect(DoujinRecommendationEngine.titleTokens('ケイちゃんといちゃいちゃする本'), isNotEmpty);
      expect(DoujinRecommendationEngine.titleTokens('想被狂挠脚底痒'), isNotEmpty);
    });

    test('two Japanese titles about the same thing score as similar', () {
      final tokens = DoujinRecommendationEngine.titleTokens('ケイちゃんといちゃいちゃする本');
      expect(
        DoujinRecommendationEngine.titleSimilarity(tokens, 'ヒナちゃんといちゃいちゃする本'),
        greaterThan(0.4),
      );
      expect(
        DoujinRecommendationEngine.titleSimilarity(tokens, '全然関係ない題名'),
        lessThan(0.2),
      );
    });

    test('a mixed title keeps both its words and its kana', () {
      final tokens = DoujinRecommendationEngine.titleTokens('Gravity ケイちゃん');
      expect(tokens, contains('gravity'));
      expect(tokens.any((t) => t.contains('ケ')), isTrue);
    });

    test('a single stray ideograph is not a token on its own', () {
      // One character says nothing and would match half the catalogue.
      expect(DoujinRecommendationEngine.titleTokens('本'), isEmpty);
    });
  });

  group('Related is never empty when anything is close', () {
    /// Tags as the handlers really build them: bare names carrying a type.
    /// A `namespace:name` string here would be fiction, and fiction in a
    /// fixture is how the prefix-matching bug survived a green suite.
    BooruItem make(String title, List<String> tags, String url) => BooruItem(
      fileURL: url,
      sampleURL: url,
      thumbnailURL: url,
      tagsList: [
        for (final t in tags)
          if (t.startsWith('artist:'))
            Tag(t.substring(7), tagType: TagType.artist)
          else if (t.startsWith('parody:'))
            Tag(t.substring(7), tagType: TagType.copyright)
          else
            Tag(t),
      ],
      postURL: url,
    )..description = title;

    test('a work with no second version still gets its series and artist mates', () {
      final source = make('Hidden Emotions', ['artist:wakahi', 'parody:original'], 'u/0');
      final candidates = [
        make('Something Else Entirely', ['artist:wakahi'], 'u/1'),
        make('Another Original Thing', ['parody:original'], 'u/2'),
        make('Nothing In Common', ['artist:someone', 'parody:other'], 'u/3'),
      ];

      final related = DoujinRecommendationEngine.related(source, candidates);

      expect(related, isNotEmpty);
      expect(related.map((e) => e.postURL), isNot(contains('u/3')));
    });

    test('same-work entries still come first, and are never dropped', () {
      final source = make('Kei-chan to Ichaicha Suru Hon', ['artist:remora'], 'u/0');
      final candidates = [
        make('Some Other Book', ['artist:remora'], 'u/filler'),
        make('Kei-chan to Ichaicha Suru Hon 2', ['artist:remora'], 'u/same'),
      ];

      final related = DoujinRecommendationEngine.related(source, candidates);

      expect(related.first.postURL, 'u/same');
    });

    test('a candidate sharing nothing at all is filler, not Related', () {
      final source = make('Hidden Emotions', ['artist:wakahi'], 'u/0');
      final candidates = [make('Unrelated Book', ['artist:nobody'], 'u/1')];

      expect(DoujinRecommendationEngine.related(source, candidates), isEmpty);
    });
  });

  test('namespaces survive where they matter and are dropped where they do not', () {
    // A real trap: tagsOf normalises `parody:x` to `x` for the blacklist, so
    // anything asking "is this a series tag?" has to read the raw tags.
    final item = BooruItem(
      fileURL: 'u',
      sampleURL: 'u',
      thumbnailURL: 'u',
      tagsList: [Tag('parody:Blue Archive'), Tag('big breasts')],
      postURL: 'u',
    );

    expect(DoujinRecommendationEngine.tagsOf(item), contains('blue_archive'));
    expect(DoujinRecommendationEngine.namespacedTagsOf(item), contains('parody:blue_archive'));
    expect(DoujinRecommendationEngine.namespacedTagsOf(item), contains('big_breasts'));
  });

  group('relatedness reads the tag TYPE, not a name prefix', () {
    // Regression: tag names are bare now, so `fullString.startsWith('artist:')`
    // matches nothing. That scored every candidate at zero and emptied Related
    // across all five sources — with no error anywhere, which is what made it
    // slip through until a live walk caught it.
    BooruItem make(String title, List<Tag> tags, String url) => BooruItem(
      fileURL: url,
      sampleURL: url,
      thumbnailURL: url,
      tagsList: tags,
      postURL: url,
    )..description = title;

    test('a shared artist counts, with bare names', () {
      final source = make('One Book', [Tag('wakahi_chan', tagType: TagType.artist)], 'u/0');
      final candidate = make('Another Book', [Tag('wakahi_chan', tagType: TagType.artist)], 'u/1');

      expect(DoujinRecommendationEngine.relatedness(source, candidate), greaterThan(0.3));
    });

    test('a shared series counts, with bare names', () {
      final source = make('One', [Tag('blue_archive', tagType: TagType.copyright)], 'u/0');
      final candidate = make('Two', [Tag('blue_archive', tagType: TagType.copyright)], 'u/1');

      expect(DoujinRecommendationEngine.relatedness(source, candidate), greaterThan(0.4));
    });

    test('the same name under a different type is not a match', () {
      // `original` as a series and `original` as a general tag are not the
      // same thing, and pretending otherwise would fill Related with noise.
      final source = make('One', [Tag('original', tagType: TagType.copyright)], 'u/0');
      final candidate = make('Two', [Tag('original')], 'u/1');

      expect(DoujinRecommendationEngine.relatedness(source, candidate), 0);
    });

    test('Related is not empty for a book that shares only its artist', () {
      final source = make('Hidden Emotions', [Tag('wakahi_chan', tagType: TagType.artist)], 'u/0');
      final candidates = [
        make('Something Else', [Tag('wakahi_chan', tagType: TagType.artist)], 'u/1'),
        make('Unrelated', [Tag('someone_else', tagType: TagType.artist)], 'u/2'),
      ];

      final related = DoujinRecommendationEngine.related(source, candidates);
      expect(related.map((e) => e.postURL), ['u/1']);
    });
  });
}
