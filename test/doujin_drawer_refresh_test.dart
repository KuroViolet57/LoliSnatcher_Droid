import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/drawer_refresh.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/drawer_quick_access.dart';

/// Round 3, item 5: drawer content was snapshotted at tab creation and then
/// drifted — deleted favourites kept their old count, fresh pins never showed
/// up, and only a brand-new tab displayed current values. The drawers now
/// re-read on a shared refresh signal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem doujinItem(String id) => BooruItem(
    fileURL: 'https://images.invalid/$id.png',
    sampleURL: 'https://images.invalid/$id.png',
    thumbnailURL: 'https://thumbs.invalid/$id.png',
    tagsList: [Tag('vanilla')],
    postURL: 'https://nhentai.net/g/$id/',
    serverId: id,
  )..description = 'Doujin $id';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_drawer_refresh_test');
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

  test('every doujin store write raises the shared drawer refresh signal', () {
    final int before = DrawerRefresh.tick.value;

    DoujinDataHandler.instance.toggleFavourite(doujinItem('1001'), nhentaiBooru());
    expect(DrawerRefresh.tick.value, greaterThan(before));

    final int afterFav = DrawerRefresh.tick.value;
    DoujinDataHandler.instance.addPin('vanilla', nhentaiBooru());
    expect(DrawerRefresh.tick.value, greaterThan(afterFav));
  });

  testWidgets('drawer counts follow the store instead of a stale snapshot', (tester) async {
    final booru = nhentaiBooru();
    SettingsHandler.instance.booruList.add(booru);
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'vanilla'));
    SearchHandler.instance.changeTabIndex(0);

    final store = DoujinDataHandler.instance;
    store.toggleFavourite(doujinItem('1001'), booru);
    store.toggleFavourite(doujinItem('1002'), booru);
    expect(store.favourites.length, 2);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: Scaffold(body: DrawerQuickAccess(toggleDrawer: () {})),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2'), findsWidgets);

    // The user's repro: delete the favourites elsewhere while the drawer is
    // alive. Before the fix the row kept saying "2" until a NEW tab was made.
    store.toggleFavourite(doujinItem('1001'), booru);
    store.toggleFavourite(doujinItem('1002'), booru);
    expect(store.favourites, isEmpty);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2'), findsNothing);

    SettingsHandler.instance.booruList.clear();
  });

  testWidgets('a freshly pinned tag appears without recreating the tab', (tester) async {
    final booru = nhentaiBooru();
    SettingsHandler.instance.booruList.add(booru);
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'vanilla'));
    SearchHandler.instance.changeTabIndex(0);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: Scaffold(body: DrawerQuickAccess(toggleDrawer: () {})),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ponytail'), findsNothing);

    DoujinDataHandler.instance.addPin('ponytail', booru);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ponytail'), findsOneWidget);

    SettingsHandler.instance.booruList.clear();
  });
}
