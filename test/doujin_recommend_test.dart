import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 2, item 3: recommendation rebalance — same-artist results are a
/// capped minority, title similarity contributes to the score, and the count
/// setting supports an endless (0) mode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_recommend_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('artist minority cap', () {
    test('a flood of high-scoring same-artist rows cannot dominate a page', () {
      // 20 artist rows scoring HIGHER than 30 tag rows — pre-rebalance these
      // would fill the whole list.
      final pool = <(double, bool, dynamic)>[
        for (int i = 0; i < 20; i++) (0.9 - i * 0.001, true, 'artist-$i'),
        for (int i = 0; i < 30; i++) (0.5 - i * 0.001, false, 'tag-$i'),
      ];
      final (List out, _) = NHentaiHandler.takeWithArtistCap(pool, 30);
      expect(out.length, 30);
      final int artistRows = out.where((r) => r.toString().startsWith('artist-')).length;
      // cap = max(2, round(30 * 0.15)) = 5
      expect(artistRows, 5);
      // the best artist rows are the ones kept
      expect(out.contains('artist-0'), isTrue);
      expect(out.contains('artist-5'), isFalse);
    });

    test('over-cap artist rows are dropped, not queued for later pages', () {
      final pool = <(double, bool, dynamic)>[
        for (int i = 0; i < 20; i++) (0.9, true, 'artist-$i'),
        for (int i = 0; i < 5; i++) (0.5, false, 'tag-$i'),
      ];
      final (List out, List<(double, bool, dynamic)> keep) = NHentaiHandler.takeWithArtistCap(pool, 10);
      // 5 artist (cap = max(2, round(10*0.15)=2)... cap is 2 here) + 5 tag rows
      final int artistRows = out.where((r) => r.toString().startsWith('artist-')).length;
      expect(artistRows, 2);
      expect(out.where((r) => r.toString().startsWith('tag-')).length, 5);
      // nothing artist-flavoured left waiting to take over page 2
      expect(keep.where((e) => e.$2), isEmpty);
    });

    test('small pools still allow a couple of artist rows', () {
      final pool = <(double, bool, dynamic)>[
        (0.9, true, 'artist-0'),
        (0.8, true, 'artist-1'),
        (0.7, true, 'artist-2'),
      ];
      final (List out, _) = NHentaiHandler.takeWithArtistCap(pool, 5);
      expect(out, ['artist-0', 'artist-1']); // cap = max(2, round(0.75)) = 2
    });
  });

  group('title similarity', () {
    test('shared significant words score high, unrelated titles zero', () {
      final tokens = NHentaiHandler.titleTokensForTests('kanojo no okaa-san');
      expect(
        NHentaiHandler.titleSimilarity(tokens, 'Kanojo no Onee-san'),
        greaterThan(0),
      );
      expect(
        NHentaiHandler.titleSimilarity(tokens, 'Totally Different Work'),
        0,
      );
      // identical significant words = 1.0
      expect(
        NHentaiHandler.titleSimilarity(tokens, 'KANOJO no okaa-san (full color)'),
        1.0,
      );
    });

    test('short/stop words are ignored', () {
      expect(NHentaiHandler.titleTokensForTests('no ni wa a of'), isEmpty);
    });
  });

  group('count setting', () {
    final booru = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

    test('0 means endless and is not clamped up', () {
      SourceSettingsHandler.instance.update(booru, (s) => s.recommendedCount = 0);
      expect(SourceSettingsHandler.instance.recommendedCount(booru), 0);
    });

    test('normal values clamp to 5..100, default 30', () {
      expect(SourceSettingsHandler.instance.recommendedCount(booru), 30);
      SourceSettingsHandler.instance.update(booru, (s) => s.recommendedCount = 3);
      expect(SourceSettingsHandler.instance.recommendedCount(booru), 5);
      SourceSettingsHandler.instance.update(booru, (s) => s.recommendedCount = 500);
      expect(SourceSettingsHandler.instance.recommendedCount(booru), 100);
    });
  });
}
