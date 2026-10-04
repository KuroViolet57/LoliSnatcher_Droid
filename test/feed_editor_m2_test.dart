import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:rich_text_controller/rich_text_controller.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/settings/hand_side.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/empty_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/floating_preview_handler.dart';
import 'package:lolisnatcher/features/feed/logic/query_editor_core.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/feed/ui/main_appbar.dart';
import 'package:lolisnatcher/features/feed/ui/search/main_search_query_editor_page.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_card_build.dart';

/// Tag lookups answer only when the test says so, to replay a slow answer
/// for older text arriving after the answer for newer text.
class _SlowTagsDb extends DBHandler {
  final Map<String, Completer<List<String>>> pending = {};

  @override
  Future<List<String>> getTags(String queryStr, int limit) => (pending[queryStr] = Completer<List<String>>()).future;

  @override
  Future<List<({String searchText, String booruName})>> getSearchHistoryByInputWithBooru(String queryStr, int limit) async => [];
}

/// 1.0 M2 (feed): the search window, its history card, the top bar, the
/// doujin preview window and the thumbnail's item reload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DBHandler realDb;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru hdoujin = Booru('hdoujin', BooruType.HDoujin, '', 'https://hdoujin.org', '');

  SearchHandler sh() => SearchHandler.instance;

  SearchTab loaded(Booru booru, String query) {
    final SearchTab tab = SearchTab(booru, null, query);
    tab.booruHandler.fetched.add(
      BooruItem(fileURL: 'https://img.invalid/$query.jpg', sampleURL: '', thumbnailURL: '', tagsList: [Tag(query)], postURL: '${booru.baseURL}/$query'),
    );
    tab.booruHandler.filterFetched();
    return tab;
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
    FloatingPreviewHandler.register();
    tempDir = Directory.systemTemp.createTempSync('feed_editor_m2');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    realDb = SettingsHandler.instance.dbHandler;
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.index.value = 0;
    SearchHandler.instance.searchTextController.text = '';
    SettingsHandler.instance.booruList.clear();
  });

  tearDown(() {
    SettingsHandler.instance.dbHandler = realDb;
    SettingsHandler.instance.handSide.value = HandSide.defaultValue;
    SettingsHandler.instance.dbEnabled = true;
    FloatingPreviewHandler.instance.closeAll();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.index.value = 0;
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget app(Widget home) => TranslationProvider(
    child: MaterialApp(
      navigatorKey: NavigationHandler.instance.navigatorKey,
      home: home,
    ),
  );

  test('query editor: an answer for older text does not replace the answer for newer text', () async {
    final _SlowTagsDb db = _SlowTagsDb();
    SettingsHandler.instance.dbHandler = db;
    // A source with no tag API and no metatags: suggestions come from the tag store.
    final QueryEditorController editor = QueryEditorController(
      onUpdate: () {},
      booru: Booru('plain', null, '', 'https://plain.invalid', ''),
    )..initialize();

    editor.suggestionTextController.text = 'a';
    await editor.runSearch();
    await Future<void>.delayed(Duration.zero);
    expect(db.pending.keys, contains('a'));

    editor.suggestionTextController.text = 'ab';
    await editor.runSearch();
    await Future<void>.delayed(Duration.zero);
    expect(db.pending.keys, contains('ab'));

    db.pending['ab']!.complete(['ab_tag']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    db.pending['a']!.complete(['a_tag']);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(editor.suggestedTags.map((t) => t.tag).toList(), ['ab_tag']);
    editor.dispose();
  });

  group('the search window', () {
    Future<void> openEditor(WidgetTester tester, _SlowTagsDb db) async {
      SettingsHandler.instance.dbHandler = db;
      SettingsHandler.instance.dbEnabled = false;
      SettingsHandler.instance.booruList.add(gelbooru);
      // The tab's source has no tag API: suggestions come from the tag store.
      sh().tabs.add(SearchTab(gelbooru, null, '', customHandler: EmptyHandler(gelbooru, 20)));
      sh().index.value = 0;
      await tester.pumpWidget(app(const MainSearchQueryEditorPage(autoFocus: false)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Finder suggestionField() => find.byWidgetPredicate((w) => w is TextField && w.controller is RichTextController);

    testWidgets('closing it while a suggestion lookup waits does not touch the closed page', (tester) async {
      final _SlowTagsDb db = _SlowTagsDb();
      await openEditor(tester, db);
      await tester.enterText(suggestionField(), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      // Back within the 400 ms the window waits before it looks up suggestions.
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(db.pending, isEmpty, reason: 'the lookup of a closed window should not start');
    });

    testWidgets('closing it while the lookup runs does not touch the closed page', (tester) async {
      final _SlowTagsDb db = _SlowTagsDb();
      await openEditor(tester, db);
      await tester.enterText(suggestionField(), 'a');
      await tester.pump(const Duration(milliseconds: 500));
      expect(db.pending.keys, contains('a'));
      await tester.pumpWidget(app(const SizedBox()));
      db.pending['a']!.complete(['a_tag']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an answer for older text does not replace the answer for newer text', (tester) async {
      final _SlowTagsDb db = _SlowTagsDb();
      await openEditor(tester, db);
      await tester.enterText(suggestionField(), 'a');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(suggestionField(), 'ab');
      await tester.pump(const Duration(milliseconds: 500));
      expect(db.pending.keys, containsAll(['a', 'ab']));
      db.pending['ab']!.complete(['abbey']);
      await tester.pump(const Duration(milliseconds: 50));
      db.pending['a']!.complete(['apple']);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('abbey', findRichText: true), findsWidgets);
      expect(find.textContaining('apple', findRichText: true), findsNothing);
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  testWidgets('history card: an entry whose source is gone does not open a tab on an unknown source', (tester) async {
    SettingsHandler.instance.dbEnabled = true;
    SettingsHandler.instance.booruList.add(nhentai);
    sh().tabs.add(loaded(nhentai, 'current'));
    sh().index.value = 0;
    // A doujin search made on a source that has since been removed.
    DoujinDataHandler.instance.addSearchHistory('glasses', Booru('gone', BooruType.NHentai, '', 'https://gone.example', ''));

    await tester.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: HistoryBlock()))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('glasses'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Open in new tab'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(sh().tabs, hasLength(1));
    expect(sh().tabs.where((t) => t.selectedBooru.value.type == null), isEmpty);
    // The sheet stays open over the notice: close it, let the notice run out.
    NavigationHandler.instance.navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Open in new tab'), findsNothing, reason: 'the sheet is closed');
    DoujinDataHandler.instance.resetForTests();
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('top bar: changing the hand side moves the menu button at once', (tester) async {
    SettingsHandler.instance.booruList.add(gelbooru);
    sh().tabs.add(loaded(gelbooru, 'cats'));
    sh().index.value = 0;
    SettingsHandler.instance.handSide.value = HandSide.left;
    await tester.pumpWidget(app(const Scaffold(body: CustomScrollView(slivers: [MainAppBar()]))));
    await tester.pump();
    final double width = tester.getSize(find.byType(CustomScrollView)).width;
    expect(tester.getCenter(find.byIcon(Symbols.menu_rounded)).dx, lessThan(width / 2));

    SettingsHandler.instance.handSide.value = HandSide.right;
    // The change reaches the bar's listeners, then the next frame builds it.
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(find.byIcon(Symbols.menu_rounded)).dx, greaterThan(width / 2));
  });

}
