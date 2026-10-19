import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/doujin/nhentai/nhentai_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_card_build.dart';

/// Per-surface doujin card rendering (round 2, item 2):
/// - strips: cover + language badge + TITLE below, no tag chips;
/// - main feed: cover + language badge + tag strip below, no title.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem doujinItem() => BooruItem(
    fileURL: 'https://images.invalid/1.png',
    sampleURL: 'https://images.invalid/1.png',
    thumbnailURL: 'https://thumbs.invalid/1.png',
    tagsList: [Tag('big breasts'), Tag('vanilla'), Tag('english')],
    postURL: 'https://nhentai.net/g/1001/',
    serverId: '1001',
  )..description = '[Artist] My Great Doujin Title\nOriginal title line';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_card_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host(Widget card) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 148, height: 220, child: card)),
    ),
  );

  testWidgets('strip card shows the title and NO tag chips', (tester) async {
    final handler = NHentaiHandler(nhentaiBooru(), 20);
    final item = doujinItem();
    handler.fetched.add(item);
    await tester.pumpWidget(
      host(
        ThumbnailCardBuild(
          index: 0,
          item: item,
          handler: handler,
          scrollController: AutoScrollController(),
          selectable: false,
          stripMode: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('[Artist] My Great Doujin Title'), findsOneWidget);
    // No tag chips and no +N button in strip mode.
    expect(find.text('big breasts'), findsNothing);
    expect(find.text('vanilla'), findsNothing);
    expect(find.textContaining('+'), findsNothing);
    // Language badge still on the cover.
    expect(find.text('EN'), findsOneWidget);
  });

  // 2026-10-09: the user asked for the title on grid cards too ("in the
  // grid, the doujins have no title"). It sits between the cover and the tag
  // strip, and Source settings -> Grid -> Titles on grid cards turns it off.
  Future<void> pumpFeedCard(WidgetTester tester) async {
    final handler = NHentaiHandler(nhentaiBooru(), 20);
    final item = doujinItem();
    handler.fetched.add(item);
    await tester.pumpWidget(
      host(
        ThumbnailCardBuild(
          index: 0,
          item: item,
          handler: handler,
          scrollController: AutoScrollController(),
          selectable: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('feed card shows the title above the tag strip', (tester) async {
    await pumpFeedCard(tester);

    expect(find.text('[Artist] My Great Doujin Title'), findsOneWidget);
    expect(find.text('big breasts'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('[Artist] My Great Doujin Title')).dy,
      lessThan(tester.getTopLeft(find.text('big breasts')).dy),
      reason: 'the title sits under the cover, above the tags',
    );
    expect(find.text('EN'), findsOneWidget);
  });

  testWidgets('the title on feed cards is a per-source setting, on by default', (tester) async {
    final Booru booru = nhentaiBooru();
    expect(SourceSettingsHandler.instance.gridTitle(booru), isTrue);
    SourceSettingsHandler.instance.settingsFor(booru).gridTitle = false;

    await pumpFeedCard(tester);

    expect(find.text('[Artist] My Great Doujin Title'), findsNothing);
    expect(find.text('big breasts'), findsOneWidget);
  });

  test('the title switch survives a save and a backup (toJson/fromJson)', () {
    final SourceSettings s = SourceSettings(gridTitle: false);
    expect(SourceSettings.fromJson(s.toJson()).gridTitle, isFalse);
    expect(SourceSettings.fromJson(const {}).gridTitle, isNull);
  });

  testWidgets('with titles and tags both off the feed card is the plain cover', (tester) async {
    final Booru booru = nhentaiBooru();
    SourceSettingsHandler.instance.settingsFor(booru)
      ..gridTitle = false
      ..gridTagStrip = false;
    final handler = NHentaiHandler(nhentaiBooru(), 20);
    final item = doujinItem();
    handler.fetched.add(item);
    await tester.pumpWidget(
      host(
        ThumbnailCardBuild(
          index: 0,
          item: item,
          handler: handler,
          scrollController: AutoScrollController(),
          selectable: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('[Artist] My Great Doujin Title'), findsNothing);
    expect(find.text('big breasts'), findsNothing);
  });
}
