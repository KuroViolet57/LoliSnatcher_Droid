import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/preview_quality.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';
import 'package:lolisnatcher/src/widgets/image/sprite_tile_image.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

/// A source whose pages learn their thumbnail late, the way e-hentai's do
/// (one strip per block of pages, read when a page of the block is shown).
class _LateThumbHandler extends BooruHandler {
  _LateThumbHandler(super.booru, super.limit);

  /// Page numbers asked for, in the order the tiles appeared.
  final List<int> asked = [];

  @override
  Future<void> ensurePageThumbnail(BooruItem page, {CancelToken? cancelToken}) async {
    asked.add(int.parse(page.serverId!.split('_p').last));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    page.transientThumbnailURL = 'https://strips.invalid/${page.serverId}.webp#xywh=0,0,200,277';
  }
}

/// r69: a source with a sharper detail cover than its listing thumbnail.
class _SharpCoverHandler extends BooruHandler {
  _SharpCoverHandler(super.booru, super.limit);

  int asked = 0;

  @override
  Future<BooruItem?> detailCoverImage(BooruItem item) async {
    asked++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return BooruItem(
      fileURL: 'https://pages.invalid/${item.serverId}-1.png',
      sampleURL: 'https://pages.invalid/${item.serverId}-1.png',
      thumbnailURL: 'https://pages.invalid/${item.serverId}-1.png',
      tagsList: const [],
      postURL: item.postURL,
      serverId: item.serverId,
      fileNameExtras: '${item.serverId}_0001',
    );
  }
}

/// Round 3, items 6 + 7: the detail page's strip sections put their
/// open-in-new-tab action in the section header instead of spending a whole
/// row on it, and the big-cover header is capped so the cover can't push
/// everything else off screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  /// A tab holding one fully-loaded doujin: tags present and the book already
  /// registered, so the page never reaches for the network.
  SearchTab loadedTab() {
    final booru = nhentaiBooru();
    final tab = SearchTab(booru, null, 'id:1001');
    final item = BooruItem(
      fileURL: 'https://images.invalid/1001.png',
      sampleURL: 'https://images.invalid/1001.png',
      thumbnailURL: 'https://thumbs.invalid/1001.png',
      tagsList: [Tag('vanilla'), Tag('glasses')],
      postURL: 'https://nhentai.net/g/1001/',
      serverId: '1001',
      fileWidth: 800,
      fileHeight: 1200,
    )..description = 'Cover Test Doujin';

    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filterFetched();
    ReaderHandler.instance.registerBook(item, [
      BooruItem(
        fileURL: 'https://images.invalid/1001-p1.png',
        sampleURL: 'https://images.invalid/1001-p1.png',
        thumbnailURL: 'https://thumbs.invalid/1001-p1.png',
        tagsList: const [],
        postURL: 'https://nhentai.net/g/1001/1/',
      ),
    ]);
    return tab;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_detail_page_test');
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

  Future<void> pumpDetail(WidgetTester tester, SearchTab tab) async {
    SearchHandler.instance.tabs.add(tab);
    SearchHandler.instance.changeTabIndex(0);
    await tester.pumpWidget(
      // The strips reach for context.loc once their content resolves, which
      // happens a frame or two in - so the page needs the translations even
      // though nothing visible at first paint uses them.
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: DoujinDetailPage(tab: tab, index: 0),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Unmounting the page runs TagContentPreview.dispose, which records the
  /// preview in the tag-preview history behind a 600ms debounce. The binding
  /// checks for pending timers at the end of the test BODY, so the page has to
  /// be torn down and the debounce run out here rather than in a tearDown -
  /// otherwise every test below fails on a timer it has nothing to do with.
  Future<void> closeDetail(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('strip sections carry their new-tab button in the HEADER, not a row of their own', (tester) async {
    await pumpDetail(tester, loadedTab());

    // The button lives in the section header, beside the chevron...
    final newTabButtons = find.byWidgetPredicate(
      (w) => w is IconButton && w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('strip-new-tab-'),
    );
    expect(newTabButtons, findsWidgets);

    // ...and the header row is the ExpansionTile's own trailing, so it costs
    // no extra vertical space: the button sits within the tile's header
    // height rather than under it.
    final ExpansionTile tile = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile)).first;
    expect(tile.trailing, isNotNull);
    expect(
      find.descendant(of: find.byType(ExpansionTile).first, matching: newTabButtons),
      findsOneWidget,
    );

    await closeDetail(tester);
  });

  testWidgets('big-cover header is capped to about half the viewport', (tester) async {
    SourceSettingsHandler.instance.updateGlobal((s) => s.detailLayout = 'cover');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpDetail(tester, loadedTab());

    final double viewportHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final Finder cover = find.byKey(const Key('doujin-big-cover'));
    expect(cover, findsOneWidget);

    final Size size = tester.getSize(cover);
    // Full width, but never more than ~55% of the screen tall — a portrait
    // cover used to run the whole viewport and push the title, actions and
    // tags below the fold.
    expect(size.height, lessThanOrEqualTo(viewportHeight * 0.55 + 1));
    expect(size.height, greaterThan(viewportHeight * 0.2));

    await closeDetail(tester);
  });

  // ── r32: the pages grid ──

  /// A book of [count] pages, tags present, so the page never reaches for
  /// the network; [handler] stands in for the source when given.
  SearchTab bookTab(int count, {BooruHandler? handler}) {
    final booru = nhentaiBooru();
    final tab = SearchTab(booru, null, 'id:1002', customHandler: handler);
    final item = BooruItem(
      fileURL: 'https://images.invalid/1002.png',
      sampleURL: 'https://images.invalid/1002.png',
      thumbnailURL: 'https://thumbs.invalid/1002.png',
      tagsList: [Tag('vanilla')],
      postURL: 'https://nhentai.net/g/1002/',
      serverId: '1002',
    )..description = 'Long Book';
    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filterFetched();
    ReaderHandler.instance.registerBook(item, [
      for (int i = 1; i <= count; i++)
        BooruItem(
          fileURL: 'https://images.invalid/1002-p$i.png',
          sampleURL: 'https://images.invalid/1002-p$i.png',
          thumbnailURL: 'https://thumbs.invalid/1002-p$i.png',
          tagsList: const [],
          postURL: 'https://nhentai.net/g/1002/$i/',
          serverId: '1002_p$i',
        ),
    ]);
    return tab;
  }

  /// Drags the page body down to its pages grid.
  Future<void> scrollToPages(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the pages grid is lazy: a 60-page book builds only the tiles in view', (tester) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpDetail(tester, bookTab(60));
    await scrollToPages(tester);
    expect(find.textContaining('Pages · 60', skipOffstage: false), findsOneWidget);
    final int built = find.byType(ThumbnailBuild, skipOffstage: false).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60), reason: 'a shrink-wrapped grid built every tile at once; it has to be a real sliver');
    await closeDetail(tester);
  });

  testWidgets('a tile asks its source for a late thumbnail and repaints with the sprite tile when it arrives', (tester) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final _LateThumbHandler handler = _LateThumbHandler(nhentaiBooru(), 20);
    await pumpDetail(tester, bookTab(6, handler: handler));
    await scrollToPages(tester);
    expect(handler.asked, contains(1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    ImageProvider unwrap(ImageProvider p) => p is ResizeImage ? p.imageProvider : p;
    final Iterable<ImageProvider> painted = tester.widgetList<Image>(find.byType(Image, skipOffstage: false)).map((i) => unwrap(i.image));
    expect(painted.whereType<SpriteTileImage>(), isNotEmpty, reason: 'the grid repainted page 1 with its tile');
    await closeDetail(tester);
  });

  testWidgets('a tile whose strip cannot be fetched falls back to the cover instead of an error tile', (tester) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Thumbnail-quality previews, as an e-hentai page (a `needToLoadItem`
    // shell) always gets: the tile is the MAIN image, not the underlay.
    SettingsHandler.instance.previewMode = PreviewQuality.thumbnail;
    addTearDown(() => SettingsHandler.instance.previewMode = PreviewQuality.defaultValue);
    final SearchTab tab = bookTab(3);
    final BooruItem first = ReaderHandler.instance.pagesFor(tab.booruHandler.fetched.first)!.first;
    first.transientThumbnailURL = 'https://strips.invalid/s.webp#xywh=0,0,200,277';
    await pumpDetail(tester, tab);
    await scrollToPages(tester);
    // The strip request and the cache-file I/O are real asynchronous work,
    // which only completes while real time passes (runAsync), not fake time.
    for (int i = 0; i < 10 && first.transientThumbnailURL != null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(first.transientThumbnailURL, isNull, reason: 'a dead strip link (they expire within days) drops the tile');
    expect(first.displayThumbnailURL, first.thumbnailURL);
    await closeDetail(tester);
  });

  /// r69: the sharp cover is a plain image layer over the site cover in a
  /// stack that is there from the first frame - never a standalone
  /// Thumbnail with its shimmer, progress ring and retry overlay, and never
  /// a swap of the site cover's element.
  testWidgets('the sharp detail cover fades in over the site cover without replacing it', (tester) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final _SharpCoverHandler handler = _SharpCoverHandler(nhentaiBooru(), 20);
    await pumpDetail(tester, bookTab(3, handler: handler));

    final Finder site = find.byKey(const ValueKey('doujin-site-cover'));
    expect(site, findsOneWidget);
    expect(find.ancestor(of: site, matching: find.byType(Stack)), findsWidgets, reason: 'the stack is there before the sharp cover');
    final Element siteElement = tester.element(site);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(handler.asked, 1);
    final Finder sharp = find.byKey(const ValueKey('doujin-sharp-cover'));
    expect(sharp, findsOneWidget);
    expect(tester.widget(sharp), isA<Image>(), reason: 'a plain image: no shimmer, no retry overlay');
    expect(site, findsOneWidget);
    expect(identical(tester.element(site), siteElement), isTrue, reason: 'the site cover was not rebuilt from scratch');
    await closeDetail(tester);
  });
}
