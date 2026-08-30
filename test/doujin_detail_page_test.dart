import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';

/// Round 3, items 6 + 7: the detail page's strip sections put their
/// open-in-new-tab action in the section header instead of spending a whole
/// row on it, and the big-cover header is capped so the cover can't push
/// everything else off screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  /// A tab holding one fully-loaded doujin: tags present and the book already
  /// registered, so the page never reaches for the network.
  SearchTab loadedTab() {
    final booru = nhentaiBooru();
    final tab = SearchTab(booru, null, 'id:1001');
    final item = BooruItem(
      fileURL: 'https://images.invalid/1001.png',
      sampleURL: 'https://images.invalid/1001.png',
      thumbnailURL: 'https://thumbs.invalid/1001.png',
      tagsList: [Tag('vanilla'), Tag('glasses')],
      postURL: 'https://nhentai.net/g/1001/',
      serverId: '1001',
      fileWidth: 800,
      fileHeight: 1200,
    )..description = 'Cover Test Doujin';

    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filterFetched();
    ReaderHandler.instance.registerBook(item, [
      BooruItem(
        fileURL: 'https://images.invalid/1001-p1.png',
        sampleURL: 'https://images.invalid/1001-p1.png',
        thumbnailURL: 'https://thumbs.invalid/1001-p1.png',
        tagsList: const [],
        postURL: 'https://nhentai.net/g/1001/1/',
      ),
    ]);
    return tab;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_detail_page_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpDetail(WidgetTester tester, SearchTab tab) async {
    SearchHandler.instance.tabs.add(tab);
    SearchHandler.instance.changeTabIndex(0);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: NavigationHandler.instance.navigatorKey,
        home: DoujinDetailPage(tab: tab, index: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('strip sections carry their new-tab button in the HEADER, not a row of their own', (tester) async {
    await pumpDetail(tester, loadedTab());

    // The button lives in the section header, beside the chevron...
    final newTabButtons = find.byWidgetPredicate(
      (w) => w is IconButton && w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('strip-new-tab-'),
    );
    expect(newTabButtons, findsWidgets);

    // ...and the header row is the ExpansionTile's own trailing, so it costs
    // no extra vertical space: the button sits within the tile's header
    // height rather than under it.
    final ExpansionTile tile = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile)).first;
    expect(tile.trailing, isNotNull);
    expect(
      find.descendant(of: find.byType(ExpansionTile).first, matching: newTabButtons),
      findsOneWidget,
    );
  });

  testWidgets('big-cover header is capped to about half the viewport', (tester) async {
    SourceSettingsHandler.instance.updateGlobal((s) => s.detailLayout = 'cover');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpDetail(tester, loadedTab());

    final double viewportHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final Finder cover = find.byKey(const Key('doujin-big-cover'));
    expect(cover, findsOneWidget);

    final Size size = tester.getSize(cover);
    // Full width, but never more than ~55% of the screen tall — a portrait
    // cover used to run the whole viewport and push the title, actions and
    // tags below the fold.
    expect(size.height, lessThanOrEqualTo(viewportHeight * 0.55 + 1));
    expect(size.height, greaterThan(viewportHeight * 0.2));
  });
}
