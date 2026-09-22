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
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/preview/flow_tab_carousel.dart';
import 'package:lolisnatcher/src/widgets/preview/tab_pill.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// r38: the tab cards run both ways and show covers; the tab pill reaches
/// them from anywhere in a feed; the tab manager's doujin rows can ask for
/// a big cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  SearchTab searchTab(String query, {String thumb = ''}) {
    final SearchTab tab = SearchTab(gelbooru, null, query);
    tab.booruHandler.fetched.add(
      BooruItem(fileURL: 'https://img.invalid/$query.jpg', sampleURL: '', thumbnailURL: thumb, tagsList: [Tag(query)], postURL: 'https://gelbooru.com/$query'),
    );
    tab.booruHandler.filterFetched();
    return tab;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tab_cards');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  void select(int index) {
    SearchHandler.instance.index.value = index;
    SearchHandler.instance.tabId.value = SearchHandler.instance.tabs[index].id;
  }

  testWidgets('the cards run both ways: every tab has one, the active one leads the view, the earlier ones are a scroll away', (tester) async {
    for (int i = 0; i < 5; i++) {
      SearchHandler.instance.tabs.add(searchTab('q$i'));
    }
    select(3);
    // A phone's width: on the wide test surface the whole strip nearly fits
    // and the jump to the active card is clamped away.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: Scaffold(body: FlowTabCarousel()))));
    await tester.pump(const Duration(milliseconds: 300));
    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 6, reason: 'five tabs and the add card');
    expect(list.itemExtentBuilder, isNotNull, reason: 'fixed widths: a far tab is found by arithmetic, not by building every card before it');
    expect(find.byKey(const ValueKey('flow-card-3')), findsOneWidget, reason: 'the active card leads');
    expect(find.byKey(const ValueKey('flow-card-4')), findsOneWidget);
    expect(list.controller!.offset, closeTo(3 * 190, 1), reason: 'the view starts at the active card: three 180-pixel cards and their gaps before it');
    await tester.drag(find.byType(ListView), const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('flow-card-0')), findsOneWidget, reason: 'the earlier tabs are reachable');
    expect(find.byKey(const ValueKey('flow-card-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('flow-card-1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(SearchHandler.instance.currentIndex, 1);
  });

  testWidgets('thousands of tabs: showing a far tab builds a handful of cards, not every card before it (r39: r38 built them all, each starting a favicon request)', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (int i = 0; i < 1500; i++) {
      SearchHandler.instance.tabs.add(SearchTab(gelbooru, null, 'q$i'));
    }
    select(1400);
    FlowTabCarousel.cardsBuilt = 0;
    await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: Scaffold(body: FlowTabCarousel()))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('flow-card-1400')), findsOneWidget);
    expect(FlowTabCarousel.cardsBuilt, lessThan(40), reason: 'only the cards near the first view and near the active one');
    select(20);
    FlowTabCarousel.cardsBuilt = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('flow-card-20')), findsOneWidget);
    expect(FlowTabCarousel.cardsBuilt, lessThan(40), reason: 'and so does a switch back');
  });

  testWidgets('a doujin tab shows its cover on its card, a search tab its first thumbnail', (tester) async {
    SettingsHandler.instance.booruList.add(nhentai);
    final SearchTab doujin = SearchTab(nhentai, null, 'id:1001', doujinPostURL: 'https://nhentai.net/g/1001/', doujinTitle: 'A Book', doujinThumb: 'https://thumbs.invalid/1001.png');
    SearchHandler.instance.tabs.addAll([doujin, searchTab('q1', thumb: 'https://thumbs.invalid/q1.png')]);
    select(0);
    expect(FlowTabCarousel.coverUrlOf(doujin), 'https://thumbs.invalid/1001.png');
    expect(FlowTabCarousel.coverUrlOf(SearchHandler.instance.tabs[1]), 'https://thumbs.invalid/q1.png');
    expect(FlowTabCarousel.coverUrlOf(searchTab('bare')), isNull);
    await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: Scaffold(body: FlowTabCarousel()))));
    await tester.pump(const Duration(milliseconds: 300));
    bool showsCover(String url) => find.byWidgetPredicate((w) => w is Image && w.image is CustomNetworkImage && (w.image as CustomNetworkImage).url == url).evaluate().isNotEmpty;
    expect(showsCover('https://thumbs.invalid/1001.png'), isTrue);
    // The cards keep to the current tab's section (r40): the search tab's card is with the booru tabs.
    expect(showsCover('https://thumbs.invalid/q1.png'), isFalse);
    select(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(showsCover('https://thumbs.invalid/q1.png'), isTrue);
  });

  testWidgets('the tab pill says where you are, opens the strip on a tap, and switches tabs on a swipe', (tester) async {
    for (int i = 0; i < 3; i++) {
      SearchHandler.instance.tabs.add(searchTab('q$i'));
    }
    select(1);
    await tester.pumpWidget(
      TranslationProvider(
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [Positioned(bottom: 20, left: 12, child: TabPill())])),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FlowTabCarousel), findsOneWidget, reason: 'the strip, in a sheet');
    await tester.tap(find.byKey(const ValueKey('flow-card-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(SearchHandler.instance.currentIndex, 2);
    expect(find.byType(FlowTabCarousel), findsNothing, reason: 'picking a card closes the sheet');
    await tester.fling(find.byKey(const ValueKey('tab-pill')), const Offset(180, 0), 1200);
    await tester.pump(const Duration(milliseconds: 300));
    expect(SearchHandler.instance.currentIndex, 1, reason: 'a swipe to the right goes back one tab');
    await tester.fling(find.byKey(const ValueKey('tab-pill')), const Offset(-180, 0), 1200);
    await tester.pump(const Duration(milliseconds: 300));
    expect(SearchHandler.instance.currentIndex, 2);
  });

  testWidgets('the tab manager: a doujin row is taller and leads with its cover, inside its own height (r39: r38 overflowed the fixed row)', (tester) async {
    SettingsHandler.instance.booruList.add(nhentai);
    final SearchTab doujin = SearchTab(nhentai, null, 'id:1001', doujinPostURL: 'https://nhentai.net/g/1001/', doujinTitle: 'A Book', doujinThumb: 'https://thumbs.invalid/1001.png');
    expect(TabManagerItem.extentFor(doujin), greaterThan(TabManagerItem.extentFor(searchTab('q'))));
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: TabManagerItem.extentFor(doujin), child: TabManagerItem(tab: doujin, onCloseTap: () {})),
                SizedBox(height: TabManagerItem.extentFor(searchTab('q')), child: TabManagerItem(tab: searchTab('q2'), onCloseTap: () {})),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byWidgetPredicate((w) => w is SizedBox && w.height == TabManagerItem.doujinCoverHeight), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  test('showing a doujin tab again is not a new open; a page pushed from a card always is (r39)', () {
    DoujinDetailPage.resetOpensForTests();
    expect(DoujinDetailPage.claimOpen('t1', 'https://nhentai.net/g/1/', asTab: true), isTrue);
    expect(DoujinDetailPage.claimOpen('t1', 'https://nhentai.net/g/1/', asTab: true), isFalse, reason: 'switching back to the tab');
    expect(DoujinDetailPage.claimOpen('t2', 'https://nhentai.net/g/1/', asTab: true), isTrue, reason: 'another tab');
    expect(DoujinDetailPage.claimOpen('t1', 'https://nhentai.net/g/1/', asTab: false), isTrue);
    expect(DoujinDetailPage.claimOpen('t1', 'https://nhentai.net/g/1/', asTab: false), isTrue);
  });

  testWidgets('an empty, disabled settings button is a gap, not a blank card (r39)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [SettingsButton(name: '', enabled: false)]))));
    expect(tester.getSize(find.byType(SettingsButton)).height, lessThanOrEqualTo(12));
  });

  group('r40: the tab pill and the tab cards keep to the section you are in', () {
    SearchTab doujinSearch(String query) => SearchTab(nhentai, null, query);

    Widget pillApp(Widget child) => TranslationProvider(
      child: MaterialApp(home: Scaffold(body: Stack(children: [child]))),
    );

    testWidgets('from a doujin tab, the pill counts and swipes through the doujin tabs only', (tester) async {
      SettingsHandler.instance.booruList.add(nhentai);
      SearchHandler.instance.tabs.addAll([searchTab('q0'), doujinSearch('d0'), searchTab('q1'), doujinSearch('d1'), searchTab('q2')]);
      select(1);
      await tester.pumpWidget(pillApp(const Positioned(bottom: 20, left: 12, child: TabPill())));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1/2'), findsOneWidget, reason: 'two doujin tabs, not all five tabs');
      await tester.fling(find.byKey(const ValueKey('tab-pill')), const Offset(-180, 0), 1200);
      await tester.pump(const Duration(milliseconds: 300));
      expect(SearchHandler.instance.currentIndex, 3, reason: 'the next doujin tab, past the booru tab between them');
      expect(find.text('2/2'), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('tab-pill')), const Offset(-180, 0), 1200);
      await tester.pump(const Duration(milliseconds: 300));
      expect(SearchHandler.instance.currentIndex, 3, reason: 'the last doujin tab stays: the booru tab after it is another section');
      select(2);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2/3'), findsOneWidget, reason: 'a booru tab counts the booru tabs');
    });

    testWidgets('the tab cards of a doujin tab are the doujin tabs, and a card still opens its own tab', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SettingsHandler.instance.booruList.add(nhentai);
      SearchHandler.instance.tabs.addAll([searchTab('q0'), doujinSearch('d0'), searchTab('q1'), doujinSearch('d1')]);
      select(3);
      await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: Scaffold(body: FlowTabCarousel()))));
      await tester.pump(const Duration(milliseconds: 300));
      final ListView list = tester.widget<ListView>(find.byType(ListView));
      expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 3, reason: 'two doujin tabs and the add card');
      expect(find.byKey(const ValueKey('flow-card-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-card-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-card-0')), findsNothing);
      expect(find.byKey(const ValueKey('flow-card-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('flow-card-1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(SearchHandler.instance.currentIndex, 1);
    });

    testWidgets('the pill moves: hold, drag, and it stays where it was left', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SearchHandler.instance.tabs.addAll([searchTab('q0'), searchTab('q1')]);
      select(0);
      Widget app() => pillApp(const Positioned.fill(child: TabPillHost(bottomInset: 120, alignLeft: true)));
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      final Offset before = tester.getTopLeft(find.byKey(const ValueKey('tab-pill')));
      expect(before.dx, 12, reason: 'the default place');
      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tab-pill'))));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(150, -300));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      final Offset after = tester.getTopLeft(find.byKey(const ValueKey('tab-pill')));
      expect(after.dx, closeTo(before.dx + 150, 1));
      expect(after.dy, closeTo(before.dy - 300, 1));
      expect(find.byType(TabManagerPage), findsNothing, reason: 'a drag moves the pill; only a hold without one opens the tab manager');
      expect(find.text('1/2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      final Offset again = tester.getTopLeft(find.byKey(const ValueKey('tab-pill')));
      expect(again.dx, closeTo(after.dx, 1), reason: 'a new feed puts it back where it was left');
      expect(again.dy, closeTo(after.dy, 1));
    });
  });

}
