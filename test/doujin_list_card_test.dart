import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/doujin_list_card.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

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
