import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/tabs/ui/doujin_mini_tab_manager.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

/// 1.0 M2 (tabs): the doujin mini tab manager.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  SearchTab doujinTab(String id, String title) {
    final SearchTab tab = SearchTab(nhentai, null, 'id:$id');
    final BooruItem item = BooruItem(
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
    tempDir = Directory.systemTemp.createTempSync('doujin_mini_tab_manager');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.visitedTabsHistory.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.visitedTabsHistory.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('mini tab manager', () {
    Future<void> pumpMini(WidgetTester tester) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            navigatorKey: NavigationHandler.instance.navigatorKey,
            home: const Scaffold(body: DoujinMiniTabManager()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a tap on a tab is a visit, recorded like a tap in the full manager', (tester) async {
      SettingsHandler.instance.booruList.add(nhentai);
      final SearchTab first = doujinTab('1001', 'First Book');
      final SearchTab second = doujinTab('1002', 'Second Book');
      SearchHandler.instance.tabs.addAll([first, second]);
      SearchHandler.instance.changeTabIndex(0);

      await pumpMini(tester);
      await tester.tap(find.byKey(ValueKey('mini-tab-${second.id}')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(SearchHandler.instance.currentTab, second);
      expect(SearchHandler.instance.visitedTabsHistory.map((v) => v.tabId), contains(second.id));
    });
  });
}
