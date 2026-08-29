import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/doujin_item_menu.dart';

/// Round 2, item 4: the doujin item context menu is a CENTERED popup with a
/// fixed ordering and no "Open detail page" entry; "Open in new tab" honours
/// the doujin tab-placement setting.
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
  )..description = 'Menu Test Doujin $id';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_menu_test');
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

  Future<SearchTab> pumpMenu(WidgetTester tester) async {
    final booru = nhentaiBooru();
    final tab = SearchTab(booru, null, 'test');
    final item = doujinItem('1001');
    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filterFetched();
    SearchHandler.instance.tabs.add(tab);
    SearchHandler.instance.changeTabIndex(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDoujinItemMenu(context, tab: tab, index: 0),
                child: const Text('open menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open menu'));
    await tester.pump(const Duration(milliseconds: 400));
    return tab;
  }

  testWidgets('menu is a centered Dialog with the fixed ordering and no "Open detail page"', (tester) async {
    await pumpMenu(tester);

    // It's a dialog, not a bottom sheet.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    const orderedKeys = [
      'doujin-menu-new-tab',
      'doujin-menu-preview',
      'doujin-menu-read',
      'doujin-menu-group',
      'doujin-menu-favourite',
      'doujin-menu-bookmark',
      'doujin-menu-save',
      'doujin-menu-copy',
    ];
    double lastTop = -1;
    for (final key in orderedKeys) {
      final finder = find.byKey(Key(key));
      expect(finder, findsOneWidget, reason: key);
      final double top = tester.getTopLeft(finder).dy;
      expect(top, greaterThan(lastTop), reason: '$key must come after the previous entry');
      lastTop = top;
    }

    expect(find.text('Open detail page'), findsNothing);
    expect(find.text('Open in new tab'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Read now'), findsOneWidget);
  });

  testWidgets('"Open in new tab" respects the doujin tab-placement setting', (tester) async {
    // placement 'next': the new tab must land right AFTER the current one,
    // not at the end of the list.
    SourceSettingsHandler.instance.updateGlobal((s) => s.tabPlacement = 'next');

    final tab = await pumpMenu(tester);
    // a second tab AFTER the current one, so end != next
    SearchHandler.instance.tabs.add(SearchTab(nhentaiBooru(), null, 'other'));

    await tester.tap(find.byKey(const Key('doujin-menu-new-tab')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(SearchHandler.instance.tabs.length, 3);
    // index 0 = origin tab, index 1 = the new id: tab (next), index 2 = 'other'
    expect(SearchHandler.instance.tabs[0], tab);
    expect(SearchHandler.instance.tabs[1].tags.trim(), 'id:1001');
    expect(SearchHandler.instance.tabs[2].tags.trim(), 'other');
  });

  testWidgets('Favourite goes through the doujin store', (tester) async {
    final tab = await pumpMenu(tester);
    final item = tab.booruHandler.filteredFetched[0];
    expect(DoujinDataHandler.instance.isFavourite(item), isFalse);

    await tester.tap(find.byKey(const Key('doujin-menu-favourite')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(DoujinDataHandler.instance.isFavourite(item), isTrue);
    expect(item.isFavourite.value, isTrue);
  });
}
