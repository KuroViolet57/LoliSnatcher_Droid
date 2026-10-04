import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';

/// 1.0 M2 (feed): the tab list keeps its current tab, its groups and its
/// tabs through moves, removals, merges, replaces, restores and page jumps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru danbooru = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru hdoujin = Booru('hdoujin', BooruType.HDoujin, '', 'https://hdoujin.org', '');

  SearchHandler sh() => SearchHandler.instance;

  /// A tab with one post already loaded, so switching to it starts no search.
  SearchTab loaded(String query, {Booru? booru}) {
    final SearchTab tab = SearchTab(booru ?? gelbooru, null, query);
    tab.booruHandler.fetched.add(
      BooruItem(fileURL: 'https://img.invalid/$query.jpg', sampleURL: '', thumbnailURL: '', tagsList: [Tag(query)], postURL: 'https://gelbooru.com/$query'),
    );
    tab.booruHandler.filterFetched();
    return tab;
  }

  void select(int index) {
    sh().index.value = index;
    sh().tabId.value = sh().tabs[index].id;
  }

  /// A doujin detail tab in backup form: restoring it seeds its item, so it
  /// does not start a network search when it becomes current.
  Map<String, dynamic> doujinBackup(String id, {bool selected = false}) => TabBackup(
    tags: 'id:$id',
    booru: 'hdoujin',
    doujinPostURL: 'https://hdoujin.org/g/$id/k$id',
    doujinTitle: 'Book $id',
    selected: selected,
  ).toJson();

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: const SizedBox(),
        ),
      ),
    );
  }

  /// Lets a search started by the code under test run out (the network is
  /// mocked to fail) so no timer outlives the test.
  Future<void> settle(WidgetTester tester) async {
    if (sh().tabs.isNotEmpty) {
      sh().currentBooruHandler.locked = true;
      sh().isLastPage.value = true;
    }
    await tester.pump(const Duration(seconds: 1));
  }

  // The first Logger.Inst() installs the app's error handlers. Here, before
  // any test, it cannot replace the test binding's handler in the middle of one.
  setUpAll(Logger.Inst);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('feed_tabs_m2');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.index.value = 0;
    SettingsHandler.instance.booruList.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.index.value = 0;
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('moveTab keeps the current tab current', () {
    test('an earlier tab moved onto the current position: the current tab moves back one', () {
      final a = loaded('a'), b = loaded('b'), c = loaded('c');
      sh().tabs.addAll([a, b, c]);
      select(2);
      sh().moveTab(0, 2);
      expect(sh().tabs, [b, c, a]);
      expect(sh().currentTab, same(c));
      expect(sh().currentIndex, 1);
      expect(sh().currentTabId, c.id);
    });

    test('an earlier tab dragged just below the current one', () {
      final a = loaded('a'), b = loaded('b'), c = loaded('c');
      sh().tabs.addAll([a, b, c]);
      select(1);
      sh().moveTab(0, 1);
      expect(sh().tabs, [b, a, c]);
      expect(sh().currentTab, same(b));
      expect(sh().currentIndex, 0);
    });

    test('a later tab moved onto the current position pushes the current tab on (unchanged)', () {
      final a = loaded('a'), b = loaded('b'), c = loaded('c');
      sh().tabs.addAll([a, b, c]);
      select(0);
      sh().moveTab(2, 0);
      expect(sh().tabs, [c, a, b]);
      expect(sh().currentTab, same(a));
      expect(sh().currentIndex, 1);
    });
  });

  group('removeTabs', () {
    testWidgets('removing tabs after the current one tells the tab list listeners', (tester) async {
      await pumpApp(tester);
      final a = loaded('a'), b = loaded('b'), c = loaded('c'), d = loaded('d');
      sh().tabs.addAll([a, b, c, d]);
      select(0);
      int notified = 0;
      void listener() => notified++;
      sh().tabs.addListener(listener);
      sh().removeTabs([c, d]);
      sh().tabs.removeListener(listener);
      expect(sh().tabs, [a, b]);
      expect(notified, greaterThan(0), reason: 'the tab pill, the carousel and the tab count listen to the list');
      expect(sh().currentTab, same(a));
    });

    testWidgets('removing every tab leaves one default tab instead of throwing', (tester) async {
      await pumpApp(tester);
      SettingsHandler.instance.booruList.add(gelbooru);
      final a = loaded('a'), b = loaded('b');
      sh().tabs.addAll([a, b]);
      select(1);
      sh().removeTabs([a, b]);
      expect(sh().tabs, hasLength(1));
      expect(sh().currentTab.selectedBooru.value.name, 'gelbooru');
      expect(sh().currentTab.tags, SettingsHandler.instance.defTags);
      await settle(tester);
    });
  });

  group('mergeTabs (LoliSync merge)', () {
    testWidgets('adds the tabs this device does not have, and only those', (tester) async {
      await pumpApp(tester);
      SettingsHandler.instance.booruList.addAll([gelbooru, danbooru]);
      final cats = loaded('cats');
      final fish = SearchTab(gelbooru, [danbooru], 'fish');
      // Merge sources all switched off: an empty list, not null.
      final eels = SearchTab(gelbooru, const [], 'eels');
      sh().tabs.addAll([cats, fish, eels]);
      select(0);
      final String incoming = jsonEncode([
        TabBackup(tags: 'cats', booru: 'gelbooru').toJson(),
        TabBackup(tags: 'dogs', booru: 'gelbooru').toJson(),
        TabBackup(tags: 'fish', booru: 'gelbooru', secondaryBoorus: ['danbooru']).toJson(),
        TabBackup(tags: 'birds', booru: 'gelbooru', secondaryBoorus: ['danbooru']).toJson(),
        TabBackup(tags: 'eels', booru: 'gelbooru').toJson(),
        TabBackup(tags: 'gone', booru: 'not on this device').toJson(),
      ]);
      sh().mergeTabs(incoming);
      expect(sh().tabs.map((t) => t.tags).toList(), ['cats', 'fish', 'eels', 'dogs', 'birds']);
      expect(sh().currentTab, same(cats));
    });
  });

}
