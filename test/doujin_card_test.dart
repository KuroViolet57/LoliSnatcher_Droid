import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

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

  testWidgets('feed card shows the tag strip and NO title', (tester) async {
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
    expect(find.text('big breasts'), findsOneWidget);
    expect(find.text('vanilla'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
  });
}
