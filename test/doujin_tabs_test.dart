import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/tabs/doujin_mini_tab_manager.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_row.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

/// Round 2, item 6: doujin tabs — a tab can BE a doujin (cover + title in the
/// tab lists), and the mini tab manager sidebar works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  Booru gelbooruBooru() => Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  SearchTab doujinTab(String id, String title) {
    final tab = SearchTab(nhentaiBooru(), null, 'id:$id');
    final item = BooruItem(
      fileURL: 'https://images.invalid/$id.png',
      sampleURL: 'https://images.invalid/$id.png',
      thumbnailURL: 'https://thumbs.invalid/$id.png',
      tagsList: [Tag('vanilla')],
      postURL: 'https://nhentai.net/g/$id/',
      serverId: id,
    )..description = title;
    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filterFetched();
    return tab;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_tabs_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('doujin detail tab type (round 3, item 3)', () {
    test('a tab created with doujin identity IS a doujin detail tab; a plain search is not', () {
      final detail = SearchTab(
        nhentaiBooru(),
        null,
        'id:177013',
        doujinPostURL: 'https://nhentai.net/g/177013/',
        doujinTitle: 'Metamorphosis',
        doujinThumb: 'https://thumbs.invalid/177013.png',
      );
      expect(detail.isDoujinDetail, isTrue);

      final search = SearchTab(nhentaiBooru(), null, 'vanilla');
      expect(search.isDoujinDetail, isFalse);

      // Legacy tabs (id: search on a doujin source, no marker) still count.
      final legacy = SearchTab(nhentaiBooru(), null, 'id:123');
      expect(legacy.isDoujinDetail, isTrue);

      // id: on a NON-doujin source is just a search.
      final booruIdSearch = SearchTab(gelbooruBooru(), null, 'id:123');
      expect(booruIdSearch.isDoujinDetail, isFalse);
    });

    test('doujin identity serializes through TabBackup and restores as a detail tab', () {
      SettingsHandler.instance.booruList.add(nhentaiBooru());

      final backup = TabBackup(
        tags: 'id:177013',
        booru: 'nhentai',
        doujinPostURL: 'https://nhentai.net/g/177013/',
        doujinTitle: 'Metamorphosis',
        doujinThumb: 'https://thumbs.invalid/177013.png',
      );
      // Round-trip the exact bytes that go to disk.
      final restoredBackup = TabBackup.fromJson(backup.toJson());
      expect(restoredBackup!.doujinPostURL, 'https://nhentai.net/g/177013/');
      expect(restoredBackup.doujinTitle, 'Metamorphosis');
      expect(restoredBackup.doujinThumb, 'https://thumbs.invalid/177013.png');

      final SearchTab restored = SearchHandler.instance.parseTabFromBackup(restoredBackup);
      expect(restored.isDoujinDetail, isTrue);
      expect(restored.doujinPostURL, 'https://nhentai.net/g/177013/');
      expect(restored.doujinTitle, 'Metamorphosis');
      expect(restored.doujinThumb, 'https://thumbs.invalid/177013.png');

      // And generateBackupJson writes the marker for open tabs.
      SearchHandler.instance.tabs.add(restored);
      SearchHandler.instance.tabs.add(SearchTab(nhentaiBooru(), null, 'vanilla'));
      final String? dump = SearchHandler.instance.generateBackupJson();
      expect(dump, isNotNull);
      expect(dump, contains('"dp":"https://nhentai.net/g/177013/"'));

      SettingsHandler.instance.booruList.clear();
    });

    testWidgets('TabRow renders the PERSISTED cover/title before any fetch', (tester) async {
      final tab = SearchTab(
        nhentaiBooru(),
        null,
        'id:177013',
        doujinPostURL: 'https://nhentai.net/g/177013/',
        doujinTitle: 'Metamorphosis',
        doujinThumb: 'https://thumbs.invalid/177013.png',
      );
      // NO fetch — the tab was just restored.
      expect(tab.booruHandler.filteredFetched, isEmpty);

      await tester.pumpWidget(
        TranslationProvider(child: MaterialApp(home: Scaffold(body: TabRow(tab: tab)))),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Metamorphosis'), findsOneWidget);
      expect(find.textContaining('id:177013'), findsNothing);
    });
  });

  group('TabRow doujin rendering', () {
    testWidgets('a doujin tab shows the COVER + TITLE, not the id: query', (tester) async {
      final tab = doujinTab('1001', 'My Tab Doujin Title');
      expect(TabRow.isDoujinTab(tab), isTrue);

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(home: Scaffold(body: TabRow(tab: tab))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('My Tab Doujin Title'), findsOneWidget);
      expect(find.textContaining('id:1001'), findsNothing);
      // the 24x32 cover slot renders (errors into a ColoredBox for .invalid)
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 24 && w.height == 32),
        findsOneWidget,
      );
    });

    testWidgets('an ordinary doujin SEARCH tab keeps the query text', (tester) async {
      final tab = SearchTab(nhentaiBooru(), null, 'vanilla');
      expect(TabRow.isDoujinTab(tab), isFalse);

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(home: Scaffold(body: TabRow(tab: tab))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('vanilla'), findsOneWidget);
    });
  });

  group('tab manager three views', () {
    testWidgets('defaults by context and the toggle switches between doujins / boorus / all', (tester) async {
      SearchHandler.instance.tabs.add(SearchTab(gelbooruBooru(), null, 'landscape'));
      SearchHandler.instance.tabs.add(doujinTab('1001', 'Manager Doujin'));
      SearchHandler.instance.changeTabIndex(0); // booru context

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            navigatorKey: NavigationHandler.instance.navigatorKey,
            home: const TabManagerPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // booru context → boorus view: doujin tab hidden
      expect(find.textContaining('landscape'), findsWidgets);
      expect(find.textContaining('Manager Doujin'), findsNothing);

      await tester.tap(find.text('Doujins'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Manager Doujin'), findsOneWidget);
      expect(find.textContaining('landscape'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Manager Doujin'), findsOneWidget);
      expect(find.textContaining('landscape'), findsWidgets);
    });
  });

  group('mini tab manager', () {
    testWidgets('lists tabs, filters, and closes them', (tester) async {
      SearchHandler.instance.tabs.add(doujinTab('1001', 'Sidebar Doujin'));
      SearchHandler.instance.tabs.add(SearchTab(gelbooruBooru(), null, 'landscape'));
      SearchHandler.instance.changeTabIndex(0);

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            navigatorKey: NavigationHandler.instance.navigatorKey,
            home: const Scaffold(body: DoujinMiniTabManager()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // both tabs listed — the doujin one by TITLE
      expect(find.textContaining('Sidebar Doujin'), findsOneWidget);
      expect(find.textContaining('landscape'), findsOneWidget);

      // filter narrows the list
      await tester.enterText(find.byType(TextField), 'landscape');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Sidebar Doujin'), findsNothing);
      expect(find.textContaining('landscape'), findsWidgets);

      // close the remaining tab
      await tester.tap(find.byTooltip('Close tab'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(SearchHandler.instance.tabs.length, 1);
      expect(SearchHandler.instance.tabs.first.tags.trim(), 'id:1001');
    });
  });
}
