import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/doujin/ui/library/doujin_favourites_page.dart';
import 'package:lolisnatcher/features/doujin/ui/library/doujin_library_pages.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/recommender_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/rewards.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/doujin/asmhentai/asmhentai_handler.dart';
import 'package:lolisnatcher/sources/doujin/ehentai/ehentai_query.dart';
import 'package:lolisnatcher/sources/doujin/hitomi/hitomi_handler.dart';
import 'package:lolisnatcher/sources/doujin/nhentai/nhentai_handler.dart';

/// Hears what the favourite path tells the recommender.
class _RecordingRecommender extends RecommenderHandler {
  final List<(String, InteractionKind)> events = [];

  @override
  Future<void> onEvent(BooruItem item, InteractionKind kind, {double value = 0, BooruHandler? handler, Map<String, String>? namespaces}) async {
    events.add((item.postURL, kind));
  }
}

/// 1.0 M2: the doujin library screens open tabs other code then has to read -
/// a followed artist as a query every source understands, a bookmark on its
/// own source with its gallery key, and the account favourites feed only where
/// the source has one. A favourite swiped away leaves like any unfavourite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru({String key = ''}) => Booru.withKey('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '', key, '');
  Booru ehentaiBooru() => Booru('e-hentai', BooruType.EHentai, '', 'https://e-hentai.org', '');
  Booru asmhentaiBooru({String key = ''}) =>
      Booru.withKey('asmhentai', BooruType.AsmHentai, '', 'https://asmhentai.com', '', key, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_library_pages_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: page,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Tapping opens a tab and starts its search; the page is torn down and the
  /// tab dropped so nothing it started outlives the test body.
  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('a followed artist opens as artist:<tag>, the form every source translates', (tester) async {
    final Booru booru = nhentaiBooru();
    SettingsHandler.instance.booruList.add(booru);
    DoujinDataHandler.instance.toggleFollow('some_artist', booru);

    await pumpPage(tester, DoujinFollowedPage(booru: booru));
    await tester.tap(find.text('some artist'));
    await tester.pump(const Duration(milliseconds: 100));

    final SearchTab tab = SearchHandler.instance.tabs.last;
    // The tab's search is running; let it settle before anything can fail.
    await closePage(tester);

    expect(tab.tags, 'artist:some_artist');
    // What the sources make of it: nhentai's and e-hentai's quoted names with
    // spaces; hitomi's artist index; asmhentai's taxonomy page. The quoted
    // form (artist:"some_artist") came out as artist:""some artist"" on
    // nhentai and kept the underscores on e-hentai.
    expect(NHentaiHandler(booru, 20).makeURL(tab.tags), contains(Uri.encodeQueryComponent('artist:"some artist"')));
    expect(EHentaiQuery.parse(tab.tags).terms, [r'artist:"some artist"$']);
    expect(HitomiHandler.nozomiTargetFor(tab.tags)?.tag, 'some artist');
    expect(AsmHentaiHandler.taxonomyPath(tab.tags), '/artist/some-artist/');
  });

  testWidgets('a bookmark opens on its own source, with the gallery key, from any drawer source', (tester) async {
    final Booru drawer = nhentaiBooru();
    final Booru eh = ehentaiBooru();
    SettingsHandler.instance.booruList.addAll([drawer, eh]);
    final BooruItem gallery = BooruItem(
      fileURL: 'https://images.invalid/123.png',
      sampleURL: 'https://images.invalid/123.png',
      thumbnailURL: '',
      tagsList: [Tag('vanilla')],
      postURL: 'https://e-hentai.org/g/123/abcdef0123/',
      serverId: '123',
    )..description = 'Bookmarked Gallery';
    DoujinDataHandler.instance.toggleBookmark(gallery, eh);

    await pumpPage(tester, DoujinFavouritesPage(booru: drawer));
    await tester.tap(find.text('Bookmarked Gallery'));
    await tester.pump(const Duration(milliseconds: 100));

    final SearchTab tab = SearchHandler.instance.tabs.last;
    expect(tab.selectedBooru.value.baseURL, 'https://e-hentai.org');
    expect(tab.tags, 'id:123/abcdef0123');

    await closePage(tester);
  });

  testWidgets('swiping a favourite away is an unfavourite: the recommender hears it, loaded cards lose the heart', (tester) async {
    final Booru booru = nhentaiBooru();
    SettingsHandler.instance.booruList.add(booru);
    BooruItem gallery() => BooruItem(
      fileURL: 'https://images.invalid/177013.png',
      sampleURL: 'https://images.invalid/177013.png',
      thumbnailURL: '',
      tagsList: [Tag('vanilla')],
      postURL: 'https://nhentai.net/g/177013/',
      serverId: '177013',
    )..description = 'Favourite Gallery';
    DoujinDataHandler.instance.toggleFavourite(gallery(), booru);
    // The same gallery's card, already loaded in an open tab.
    final SearchTab tab = SearchTab(booru, null, 'vanilla');
    final BooruItem card = gallery()..isFavourite.value = true;
    tab.booruHandler.fetched.add(card);
    SearchHandler.instance.tabs.add(tab);
    final _RecordingRecommender recommender = _RecordingRecommender();
    GetIt.instance.registerSingleton<RecommenderHandler>(recommender);
    addTearDown(RecommenderHandler.unregister);

    await pumpPage(tester, const DoujinFavouritesListPage());
    await tester.drag(find.text('Favourite Gallery'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Favourite Gallery'), findsNothing);
    expect(DoujinDataHandler.instance.favourites, isEmpty);
    // The swipe used to drop the store entry and nothing else: no account
    // sync, no unfavourite for the recommender, the loaded card still hearted.
    expect(recommender.events, [('https://nhentai.net/g/177013/', InteractionKind.unfavourite)]);
    expect(card.isFavourite.value, isFalse);

    await closePage(tester);
  });

  testWidgets('Account favourites is offered only where the source reads favorites:me', (tester) async {
    ListTile accountRow() =>
        tester.widget<ListTile>(find.ancestor(of: find.text('Account favourites'), matching: find.byType(ListTile)));

    // asmhentai's key field holds the login password; the source has no
    // favourites feed and would search the words "favorites me".
    await pumpPage(tester, DoujinFavouritesPage(booru: asmhentaiBooru(key: 'password')));
    expect(accountRow().enabled, isFalse);

    // A fresh app each time: MaterialApp builds its home route once.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpPage(tester, DoujinFavouritesPage(booru: nhentaiBooru(key: 'api-key')));
    expect(accountRow().enabled, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpPage(tester, DoujinFavouritesPage(booru: nhentaiBooru()));
    expect(accountRow().enabled, isFalse);

    await closePage(tester);
  });
}
