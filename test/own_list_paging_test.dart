import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/hidden_by_filters.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/waterfall_error_buttons.dart';

/// A source whose pages are given: each search adds the next page, and past
/// the last one it reports the end.
class _PagedHandler extends BooruHandler {
  _PagedHandler(super.booru, super.limit, this.pages);

  final List<List<BooruItem>> pages;
  final List<int> pagesAsked = [];

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    pagesAsked.add(pageNum);
    final int at = pagesAsked.length - 1;
    if (at >= pages.length) {
      locked = true;
      return fetched;
    }
    fetched.addAll(pages[at]);
    filterFetched();
    return fetched;
  }

  @override
  Future<void> searchCount(String input) async {}
}

/// r85: a page whose posts are all hidden (or, in Downloads, whose files are
/// all gone) no longer ends the list. Your own lists cost no network, so the
/// next page is read at once - up to ten per load; a site's feed waits for
/// the banner's tap, which now reads the NEXT page instead of the same one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  int serial = 0;

  BooruItem post({bool hidden = false}) {
    final int id = ++serial;
    return BooruItem(
      fileURL: 'https://img.example.org/$id.png',
      sampleURL: 'https://img.example.org/$id.png',
      thumbnailURL: 'https://img.example.org/$id-thumb.png',
      tagsList: [Tag(hidden ? 'gore' : 'solo')],
      postURL: 'https://example.org/posts/$id',
      serverId: '$id',
    );
  }

  List<BooruItem> hiddenPage() => [for (int i = 0; i < 20; i++) post(hidden: true)];

  _PagedHandler open(BooruType type, List<List<BooruItem>> pages) {
    final Booru booru = Booru(type.name, type, '', 'https://example.org', '');
    final _PagedHandler handler = _PagedHandler(booru, 20, pages);
    final SearchHandler search = SearchHandler.instance;
    search.tabs.add(SearchTab(booru, null, '', customHandler: handler));
    search.index.value = 0;
    search.isLastPage.value = false;
    search.errorString.value = '';
    search.isLoading.value = false;
    search.pageNum.value = handler.pageNum;
    return handler;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('own_list_paging_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance
      ..filterHated = true
      ..hiddenTags.add('gore');
    SettingsHandler.instance.invalidateBlacklistCache();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.filterHated = false;
    SettingsHandler.instance.hiddenTags.clear();
    SettingsHandler.instance.invalidateBlacklistCache();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('your own list reads on past pages that show nothing, until something shows', () async {
    final _PagedHandler h = open(BooruType.Downloads, [
      hiddenPage(),
      [], // a Downloads page whose files are all gone adds nothing
      [post(), post(), post()],
      [post()],
    ]);
    await SearchHandler.instance.runSearch();
    expect(h.pagesAsked, [1, 2, 3]);
    expect(h.filteredFetched.length, 3);
    expect(SearchHandler.instance.pageNum.value, 3);
    expect(SearchHandler.instance.isLastPage.value, isFalse);
  });

  test('…but at most ten pages per load', () async {
    final _PagedHandler h = open(BooruType.Favourites, [for (int i = 0; i < 12; i++) hiddenPage()]);
    await SearchHandler.instance.runSearch();
    expect(h.pagesAsked.length, SearchHandler.ownListPagesPerLoad);
    expect(SearchHandler.ownListPagesPerLoad, 10);
  });

  test('…and it stops at the end of the list', () async {
    final _PagedHandler h = open(BooruType.History, [hiddenPage()]);
    await SearchHandler.instance.runSearch();
    expect(h.pagesAsked, [1, 2]);
    expect(SearchHandler.instance.isLastPage.value, isTrue);
  });

  test("a site's feed reads one page per load, as before", () async {
    final _PagedHandler h = open(BooruType.Gelbooru, [hiddenPage(), [post()]]);
    await SearchHandler.instance.runSearch();
    expect(h.pagesAsked, [1]);
    expect(h.filteredFetched, isEmpty);
  });

  test('Downloads ends where the database runs out of rows, not where the files do', () {
    expect(DownloadsHandler.reachedEnd(rows: 20, limit: 20), isFalse);
    expect(DownloadsHandler.reachedEnd(rows: 19, limit: 20), isTrue);
    expect(DownloadsHandler.reachedEnd(rows: 0, limit: 20), isTrue);
  });

  test('the empty Downloads note counts every download looked for, and stays at the end of the list', () {
    int n = DownloadsHandler.checkedWithoutFile(before: 0, pageNum: 0, rows: 20, present: 0, listedBefore: 0);
    expect(n, 20);
    n = DownloadsHandler.checkedWithoutFile(before: n, pageNum: 1, rows: 20, present: 0, listedBefore: 0);
    expect(n, 40);
    n = DownloadsHandler.checkedWithoutFile(before: n, pageNum: 2, rows: 0, present: 0, listedBefore: 0);
    expect(n, 40, reason: 'the empty page at the end keeps the note');
    expect(DownloadsHandler.checkedWithoutFile(before: n, pageNum: 3, rows: 20, present: 1, listedBefore: 0), 0);
    expect(DownloadsHandler.checkedWithoutFile(before: n, pageNum: 3, rows: 20, present: 0, listedBefore: 5), 0);
    expect(
      DownloadsHandler.checkedWithoutFile(before: 40, pageNum: 0, rows: 0, present: 0, listedBefore: 0),
      0,
      reason: 'a new search starts over',
    );
  });

  testWidgets('the banner says the page is hidden, and its tap reads the next page', (tester) async {
    final _PagedHandler h = open(BooruType.Gelbooru, [
      [post(hidden: true), post(hidden: true)],
      [post()],
    ]);
    await tester.runAsync(() => SearchHandler.instance.runSearch());
    await tester.pump(const Duration(milliseconds: 300));
    SearchHandler.instance.isLoading.value = false;
    expect(h.pagesAsked, [1]);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: const Scaffold(
            body: WaterfallErrorButtons(animation: AlwaysStoppedAnimation<double>(1), showSearchBar: false),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(HiddenByFilters.title(2)), findsOneWidget);
    expect(find.textContaining('2 with hidden tags'), findsOneWidget);

    await tester.tap(find.text(HiddenByFilters.title(2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.pagesAsked, [1, 2], reason: 'the next page, not the same one again');
    expect(h.filteredFetched.length, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
