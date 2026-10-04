import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/empty_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/feed/ui/waterfall_view.dart';

/// Counts the page fetches and answers them only when the test says so.
class _SlowPagesHandler extends EmptyHandler {
  _SlowPagesHandler(super.booru, super.limit);

  final List<Completer<void>> fetches = [];

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) {
    final Completer<void> fetch = Completer<void>();
    fetches.add(fetch);
    return fetch.future;
  }
}

/// 1.0 M2 (feed): the feed view itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  SearchHandler sh() => SearchHandler.instance;

  setUpAll(Logger.Inst);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('feed_view_m2');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    sh().tabs.clear();
    sh().index.value = 0;
    SettingsHandler.instance.booruList.clear();
  });

  tearDown(() {
    sh().tabs.clear();
    sh().index.value = 0;
    sh().isLastPage.value = false;
    sh().errorString.value = '';
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a first page that does not fill the screen loads one next page, not one per rebuild', (tester) async {
    // Tall enough that one row of posts leaves the screen unfilled.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SettingsHandler.instance.booruList.add(gelbooru);
    final _SlowPagesHandler handler = _SlowPagesHandler(gelbooru, 20);
    handler.fetched.add(
      BooruItem(fileURL: 'https://img.invalid/1.jpg', sampleURL: '', thumbnailURL: '', tagsList: [Tag('cats')], postURL: 'https://gelbooru.com/1'),
    );
    handler.filterFetched();
    final SearchTab tab = SearchTab(gelbooru, null, 'cats', customHandler: handler);
    sh().tabs.add(tab);
    sh().index.value = 0;
    sh().tabId.value = tab.id;
    sh().isLoading.value = false;
    sh().isLastPage.value = false;
    sh().errorString.value = '';

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          navigatorObservers: [NavigationHandler.instance.routeObserver],
          home: const Scaffold(body: WaterfallView()),
        ),
      ),
    );
    await tester.pump();
    // The feed rebuilds again within the 500 ms the first rebuild waits.
    sh().isLoading.value = true;
    await tester.pump();
    sh().isLoading.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(handler.fetches, hasLength(1), reason: 'one page at a time');

    // Let it run out: the source has no more pages.
    handler.locked = true;
    sh().isLastPage.value = true;
    for (final Completer<void> fetch in handler.fetches) {
      if (!fetch.isCompleted) fetch.complete();
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
