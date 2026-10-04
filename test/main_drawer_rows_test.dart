import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/app/drawers/main_drawer.dart';
import 'package:lolisnatcher/core/platform/local_auth_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

/// The lock handler asks the platform for biometrics on creation; tests have
/// no platform, so this one skips that.
class _NoLock extends LocalAuthHandler {
  @override
  Future<void> init() async {}
}

/// 1.0 M2 (tabs): the main drawer's rows follow the tab it is opened on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    if (!GetIt.instance.isRegistered<LocalAuthHandler>()) {
      GetIt.instance.registerSingleton<LocalAuthHandler>(_NoLock());
    }
    tempDir = Directory.systemTemp.createTempSync('main_drawer_rows');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    DoujinDataHandler.instance.resetForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('main drawer: the Favourites row follows a switch to a doujin tab', (tester) async {
    final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
    final Booru favourites = Booru('Favourites', BooruType.Favourites, '', '', '');
    SettingsHandler.instance.booruList.addAll([gelbooru, nhentai, favourites]);

    SearchTab withItem(Booru booru, String query) {
      final SearchTab tab = SearchTab(booru, null, query);
      tab.booruHandler.fetched.add(
        BooruItem(
          fileURL: 'https://img.invalid/$query.jpg',
          sampleURL: '',
          thumbnailURL: '',
          tagsList: [Tag(query)],
          postURL: 'https://${booru.name}.invalid/$query',
          serverId: '1',
        ),
      );
      tab.booruHandler.filterFetched();
      return tab;
    }

    SearchHandler.instance.tabs.addAll([withItem(gelbooru, 'landscape'), withItem(nhentai, 'id:1001')]);
    SearchHandler.instance.changeTabIndex(0);

    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // MobileHome passes a const MainDrawer: a tab switch does not rebuild it.
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: const Scaffold(body: MainDrawer()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Favourites'), findsOneWidget);

    SearchHandler.instance.changeTabIndex(1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(SearchHandler.instance.currentBooruHandler.hasReader, isTrue);
    expect(find.text('Favourites'), findsNothing, reason: 'hidden on doujin tabs (they have their own favourites)');
  });
}
