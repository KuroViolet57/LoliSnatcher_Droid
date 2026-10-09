import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/doujin/nhentai/nhentai_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_list_card.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_build.dart';

/// r63: the list card a doujin feed can use instead of the grid cards - cover
/// on the left, then the title, the tags, and what the gallery is: kind,
/// language, pages. The title and the tag block scroll sideways, because both
/// are longer than the card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem doujin() => BooruItem(
    fileURL: 'https://images.invalid/1.png',
    sampleURL: 'https://images.invalid/1.png',
    thumbnailURL: 'https://thumbs.invalid/1.png',
    tagsList: [
      Tag('english'),
      Tag('doujinshi'),
      for (int i = 0; i < 14; i++) Tag('tag number $i'),
    ],
    postURL: 'https://nhentai.net/g/1001/',
    serverId: '1001',
  )
    ..description =
        '[Some Very Long Circle Name] A Title So Long That It Cannot Possibly Fit Across The Card At Once\nOriginal'
    ..uploaderName = 'someuploader'
    ..fileCountHint.value = 56;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_list_card');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinCoverAspects.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<BooruItem> pumpCard(WidgetTester tester, {double coverWidth = DoujinListCard.defaultCoverWidth}) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    final BooruItem item = doujin();
    handler.fetched.add(item);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: DoujinListCard(
              index: 0,
              item: item,
              handler: handler,
              scrollController: AutoScrollController(),
              coverWidth: coverWidth,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return item;
  }

  testWidgets('the card says what the gallery is: title, kind, language, pages', (tester) async {
    await pumpCard(tester);

    expect(
      find.textContaining('A Title So Long That It Cannot Possibly Fit', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Doujinshi'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('56P'), findsOneWidget);
    expect(find.text('someuploader'), findsOneWidget);
  });

  testWidgets('the tags sit in rows that scroll sideways', (tester) async {
    await pumpCard(tester);

    expect(find.text('tag number 0'), findsOneWidget);
    final double before = tester.getTopLeft(find.text('tag number 0')).dx;

    await tester.drag(find.byKey(const ValueKey('doujin-list-card-tags')), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('tag number 0')).dx,
      lessThan(before - 50),
      reason: 'the tag block must scroll horizontally',
    );
  });

  testWidgets('the title scrolls sideways too, so a long one can be read', (tester) async {
    await pumpCard(tester);

    final Finder title = find.byKey(const ValueKey('doujin-list-card-title'));
    final double before = tester.getTopLeft(find.textContaining('A Title So Long')).dx;

    await tester.drag(title, const Offset(-150, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.textContaining('A Title So Long')).dx,
      lessThan(before - 50),
      reason: 'the title must scroll horizontally',
    );
  });

  /// 2026-10-09, "it takes quite a long time to load, and it's very laggy":
  /// every row used to build every tag chip, including the dozens to the right
  /// of the card that nobody sees until they scroll the tag block. A row now
  /// builds what can be on screen and the rest the moment a finger touches
  /// the tag block - before the drag moves anything.
  Future<void> pumpManyTags(WidgetTester tester, int count) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    final BooruItem item = doujin()..tagsList = [for (int i = 0; i < count; i++) Tag('tag number $i')];
    handler.fetched.add(item);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: DoujinListCard(
              index: 0,
              item: item,
              handler: handler,
              scrollController: AutoScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a row builds only the tags that can be on screen', (tester) async {
    await pumpManyTags(tester, 120);

    final int built = find.textContaining('tag number ').evaluate().length;
    expect(built, lessThan(60), reason: 'the 120 chips must not all be built for a row nobody has touched');
    // The first chip of each of the three rows is there.
    expect(find.text('tag number 0'), findsOneWidget);
    expect(find.text('tag number 40'), findsOneWidget);
    expect(find.text('tag number 80'), findsOneWidget);
  });

  testWidgets('touching the tag block builds the rest, and the last tag can be reached', (tester) async {
    await pumpManyTags(tester, 120);
    expect(find.text('tag number 39'), findsNothing);

    final Finder block = find.byKey(const ValueKey('doujin-list-card-tags'));
    await tester.drag(block, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('tag number 39'), findsOneWidget);
    expect(find.text('tag number 119'), findsOneWidget);

    // Drag to the far end: the last chip of the widest row (the third: its
    // tags have the longest names) comes fully into view.
    for (int i = 0; i < 20; i++) {
      await tester.drag(block, const Offset(-400, 0));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final Rect blockRect = tester.getRect(block);
    final Rect last = tester.getRect(find.text('tag number 119'));
    expect(last.right, lessThanOrEqualTo(blockRect.right + 0.5));
    expect(last.left, greaterThanOrEqualTo(blockRect.left - 0.5));
  });

  testWidgets('a row with few tags builds them all, as before', (tester) async {
    await pumpManyTags(tester, 9);
    for (int i = 0; i < 9; i++) {
      expect(find.text('tag number $i'), findsOneWidget);
    }
  });

  test('the card style is a per-source setting, grid by default', () {
    final Booru booru = nhentaiBooru();
    expect(SourceSettingsHandler.instance.feedCardStyle(booru), 'grid');

    SourceSettingsHandler.instance.settingsFor(booru).feedCardStyle = 'list';
    expect(SourceSettingsHandler.instance.feedCardStyle(booru), 'list');
  });

  /// r69: the per-source Cover display choice applies to list cards too, and
  /// the cover column has its own width.
  group('cover display on the list card (r69)', () {
    final Finder column = find.byKey(const ValueKey('doujin-list-card-cover'));

    testWidgets('crop, the default, fills the column at the default width', (tester) async {
      await pumpCard(tester);
      expect(tester.widget<ThumbnailBuild>(find.byType(ThumbnailBuild)).fit, BoxFit.cover);
      expect(tester.getSize(column).width, DoujinListCard.defaultCoverWidth);
    });

    testWidgets('fit letterboxes the whole cover inside the column', (tester) async {
      SourceSettingsHandler.instance.settingsFor(nhentaiBooru()).coverDisplay = 'fit';
      await pumpCard(tester);
      expect(tester.widget<ThumbnailBuild>(find.byType(ThumbnailBuild)).fit, BoxFit.contain);
      expect(tester.getSize(column).width, DoujinListCard.defaultCoverWidth);
    });

    testWidgets('the cover width setting is the column width', (tester) async {
      await pumpCard(tester, coverWidth: 160);
      expect(tester.getSize(column).width, 160);
      expect(tester.getSize(find.byKey(const ValueKey('doujin-list-card-row'))).height, DoujinListCard.defaultHeight);
    });

    testWidgets('adapt gives the column the shape of the cover, the width setting as the cap', (tester) async {
      SourceSettingsHandler.instance.settingsFor(nhentaiBooru()).coverDisplay = 'adapt';
      // Nothing decoded yet: the provisional cover shape, capped.
      final BooruItem item = await pumpCard(tester);
      expect(tester.getSize(column).width, DoujinListCard.defaultCoverWidth);

      // A tall cover (1:2) at the 176 row: 88 wide, whole, nothing cropped.
      DoujinCoverAspects.instance.record(item.displayThumbnailURL, 300, 600);
      await tester.pump();
      expect(tester.getSize(column).width, closeTo(88, 0.5));
      expect(tester.widget<ThumbnailBuild>(find.byType(ThumbnailBuild)).fit, BoxFit.contain);

      // A square cover would want 176: the cap wins and the overflow is cropped.
      DoujinCoverAspects.instance.record(item.displayThumbnailURL, 500, 500);
      await tester.pump();
      expect(tester.getSize(column).width, DoujinListCard.defaultCoverWidth);
      expect(tester.widget<ThumbnailBuild>(find.byType(ThumbnailBuild)).fit, BoxFit.cover);
    });
  });
}
