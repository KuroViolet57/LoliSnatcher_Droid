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

/// 2026-10-10, build 149 (user, F42): "the card on the list has a fixed size
/// that I can configure ... it should be the same in every entry". In List
/// view every row - the card and its cover column - is the same size whatever
/// shape each cover has, in Crop, Fit and Adapt alike. Adapt used to narrow
/// the column to each cover, so the rows looked uneven.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  /// A tall, a square and a wide cover, plus one that has not decoded yet.
  const List<(int, int)?> coverSizes = [(300, 600), (500, 500), (900, 500), null];

  BooruItem doujin(int i) => BooruItem(
    fileURL: 'https://images.invalid/$i.png',
    sampleURL: 'https://images.invalid/$i.png',
    thumbnailURL: 'https://thumbs.invalid/$i.png',
    tagsList: [Tag('english'), for (int t = 0; t < 3 + i * 9; t++) Tag('tag $i $t')],
    postURL: 'https://nhentai.net/g/${1000 + i}/',
    serverId: '${1000 + i}',
  )..description = 'Gallery $i';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_list_rows_equal');
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

  Future<void> pumpRows(WidgetTester tester, {required double height, required double coverWidth}) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    final List<BooruItem> items = [for (int i = 0; i < coverSizes.length; i++) doujin(i)];
    handler.fetched.addAll(items);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              // A plain column: each card sizes itself, nothing forces it.
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++)
                    DoujinListCard(
                      index: i,
                      item: items[i],
                      handler: handler,
                      scrollController: AutoScrollController(),
                      height: height,
                      coverWidth: coverWidth,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < items.length; i++) {
      final (int, int)? size = coverSizes[i];
      if (size != null) DoujinCoverAspects.instance.record(items[i].displayThumbnailURL, size.$1, size.$2);
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  final Finder rows = find.byKey(const ValueKey('doujin-list-card-row'));
  final Finder covers = find.byKey(const ValueKey('doujin-list-card-cover'));

  for (final String mode in ['crop', 'fit', 'adapt']) {
    testWidgets('$mode: every row and every cover column is the same size', (tester) async {
      SourceSettingsHandler.instance.settingsFor(nhentaiBooru()).coverDisplay = mode;
      await pumpRows(tester, height: 184, coverWidth: 140);

      expect(rows, findsNWidgets(coverSizes.length));
      for (final Element row in rows.evaluate()) {
        expect(tester.getSize(find.byElementPredicate((e) => e == row)).height, 184, reason: '$mode row');
      }
      expect(covers, findsNWidgets(coverSizes.length));
      for (int i = 0; i < coverSizes.length; i++) {
        expect(tester.getSize(covers.at(i)), const Size(140, 184), reason: '$mode cover ${coverSizes[i]}');
      }
    });
  }
}
