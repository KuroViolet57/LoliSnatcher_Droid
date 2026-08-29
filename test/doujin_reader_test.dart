import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';

/// Smallest valid 1x1 transparent PNG — for tests that need a page image
/// that actually LOADS, so a live zoom viewer is on screen.
final Uint8List kTinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

/// Regression tests for the doujin reader's layout and input wiring.
///
/// The reader shipped broken twice in ways "compiles and looks right"
/// missed: its bottom bar floated mid-screen, its top buttons were dead
/// under an unclipped PhotoView's hit test area, and taps scrubbed the
/// slider instead of turning pages. These tests pin the contract:
///  * the filmstrip bar is DOCKED at the bottom of the screen, insets or not;
///  * edge taps advance/reverse pages, middle tap toggles the chrome;
///  * the top-bar buttons actually receive input and fire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel serviceChannel = MethodChannel('com.noaisu.loliSnatcher/services');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SourceSettingsHandler.instance.resetForTests();
    // Keep SourceSettingsHandler's file writes out of the repo.
    SettingsHandler.instance.path = '${Directory.systemTemp.createTempSync('reader-test').path}/';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      serviceChannel,
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      serviceChannel,
      null,
    );
  });

  Booru testBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  List<BooruItem> testPages(int count) => [
    for (int i = 0; i < count; i++)
      BooruItem(
        // .invalid TLD: guaranteed-dead URLs so slides settle into their
        // error state quickly; the chrome layout must not depend on images.
        fileURL: 'https://images.invalid/gallery/$i.png',
        sampleURL: 'https://images.invalid/gallery/$i.png',
        thumbnailURL: 'https://thumbs.invalid/gallery/${i}t.png',
        tagsList: const [],
        postURL: 'https://nhentai.net/g/123/',
        serverId: '123_p${i + 1}',
      ),
  ];

  Future<void> pumpReader(
    WidgetTester tester, {
    int pageCount = 3,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open-reader'),
                onPressed: () {
                  // The exact production route type: ordinary opaque
                  // MaterialPageRoute (see openDoujinReader).
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DoujinReaderPage(
                        pages: testPages(pageCount),
                        booru: testBooru(),
                        galleryId: '123',
                        title: 'Test book',
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-reader')));
    // Route transition + slides settling into their (failed-image) state.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Size screenSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  group('DoujinReaderPage', () {
    testWidgets('is a full-screen route: chrome docked top and bottom', (tester) async {
      await pumpReader(tester);
      final Size screen = screenSize(tester);

      expect(find.byType(DoujinReaderPage), findsOneWidget);

      // The bottom bar (the filmstrip) hugs the BOTTOM of the screen — the
      // recorded bug had it floating at 50% height.
      final Rect bottomBar = tester.getRect(find.byKey(const ValueKey('reader-bottom-bar')));
      expect(bottomBar.bottom, moreOrLessEquals(screen.height, epsilon: 1));
      expect(bottomBar.top, greaterThan(screen.height * 0.75));

      final Offset stripCenter = tester.getCenter(find.byKey(const ValueKey('reader-filmstrip')));
      expect(stripCenter.dy, greaterThan(screen.height * 0.75));

      // The top bar hugs the top and shows the reader's own controls.
      final Rect topBar = tester.getRect(find.byKey(const ValueKey('reader-top-bar')));
      expect(topBar.top, moreOrLessEquals(0, epsilon: 1));
      expect(find.text('Test book'), findsOneWidget);
    });

    testWidgets('bottom bar stays docked even under hostile view insets', (tester) async {
      // The recorded symptom looked like something lifting the bar by half a
      // screen; the reader must ignore insets outright.
      await pumpReader(tester, viewInsets: const EdgeInsets.only(bottom: 250));
      final Size screen = screenSize(tester);

      final Rect bottomBar = tester.getRect(find.byKey(const ValueKey('reader-bottom-bar')));
      expect(bottomBar.bottom, moreOrLessEquals(screen.height, epsilon: 1));
    });

    testWidgets('edge taps turn pages, in both directions', (tester) async {
      await pumpReader(tester);
      final Size screen = screenSize(tester);

      expect(find.text('1 / 3'), findsOneWidget);

      // Right edge: next page.
      await tester.tapAt(Offset(screen.width * 0.9, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 / 3'), findsOneWidget);

      // Left edge: previous page.
      await tester.tapAt(Offset(screen.width * 0.1, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('middle tap toggles the chrome', (tester) async {
      await pumpReader(tester);
      final Size screen = screenSize(tester);

      expect(find.byKey(const ValueKey('reader-top-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-bottom-bar')), findsOneWidget);

      await tester.tapAt(Offset(screen.width * 0.5, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('reader-top-bar')), findsNothing);
      expect(find.byKey(const ValueKey('reader-bottom-bar')), findsNothing);

      await tester.tapAt(Offset(screen.width * 0.5, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('reader-top-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-bottom-bar')), findsOneWidget);
    });

    testWidgets('top-bar buttons receive input: direction cycles, menu opens, close pops', (tester) async {
      await pumpReader(tester);

      // Direction button cycles LTR -> RTL.
      await tester.tap(find.byKey(const ValueKey('reader-direction-button')));
      await tester.pump(const Duration(milliseconds: 100));
      // In RTL a RIGHT-edge tap goes BACKWARD; from page 1 it clamps, so
      // instead check the LEFT edge advances.
      final Size screen = screenSize(tester);
      await tester.tapAt(Offset(screen.width * 0.1, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 / 3'), findsOneWidget);

      // Menu button opens the save menu.
      await tester.tap(find.byKey(const ValueKey('reader-menu-button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save this page'), findsOneWidget);
      expect(find.text('Save all pages'), findsOneWidget);
      // Dismiss the menu and prove it closed before going on.
      await tester.tapAt(const Offset(200, 500));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save this page'), findsNothing);

      // Close button pops the route.
      await tester.tap(find.byKey(const ValueKey('reader-close-button')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DoujinReaderPage), findsNothing);
    });

    testWidgets('filmstrip: numbered thumbs, tap jumps, highlight + auto-tracking follow', (tester) async {
      await pumpReader(tester, pageCount: 30);

      // The counter lives in the TOP bar now; the bottom bar holds only the
      // numbered strip.
      final Rect topBar = tester.getRect(find.byKey(const ValueKey('reader-top-bar')));
      final Offset counterPos = tester.getCenter(find.byKey(const ValueKey('reader-page-counter')));
      expect(counterPos.dy, lessThan(topBar.bottom + 1));
      expect(find.text('1 / 30'), findsOneWidget);

      // Numbered cells render in the strip (some virtualized off-screen).
      expect(find.byKey(const ValueKey('reader-strip-thumb-0')), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('4'), findsWidgets);

      // Tap a visible thumb via REAL hit-tested input — jumps to that page.
      await tester.tap(find.byKey(const ValueKey('reader-strip-thumb-3')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('4 / 30'), findsOneWidget);

      // The tapped thumb carries the highlight border now; page 1 does not.
      AnimatedContainer thumbBox(int i) => tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey('reader-strip-thumb-$i')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      Border borderOf(AnimatedContainer c) => (c.decoration! as BoxDecoration).border! as Border;
      expect(borderOf(thumbBox(3)).top.width, greaterThan(2));
      expect(borderOf(thumbBox(0)).top.width, lessThan(2));

      // Auto-tracking: turning pages by edge taps keeps the strip following
      // without the strip being touched (offset moves once the current cell
      // would leave the center region — just assert the controller reacted).
      final ScrollableState strip = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('reader-filmstrip')),
          matching: find.byType(Scrollable),
        ),
      );
      final double before = strip.position.pixels;
      final Size screen = screenSize(tester);
      for (int i = 0; i < 4; i++) {
        await tester.tapAt(Offset(screen.width * 0.9, screen.height * 0.5));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('8 / 30'), findsOneWidget);
      expect(strip.position.pixels, greaterThan(before));
    });

    testWidgets('openDoujinReader pushes an OPAQUE MaterialPageRoute and never stacks two readers', (tester) async {
      // The twice-shipped bug was a transparent PageRouteBuilder — pin the
      // route type at the real entry point, not a test-local route.
      final Booru booru = testBooru();
      final List<BooruItem> pages = testPages(3);
      final BooruItem gallery = BooruItem(
        fileURL: pages.first.fileURL,
        sampleURL: pages.first.sampleURL,
        thumbnailURL: pages.first.thumbnailURL,
        tagsList: const [],
        postURL: 'https://nhentai.net/g/123/',
        serverId: '123',
      );
      ReaderHandler.instance.registerBook(gallery, pages);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-real'),
                onPressed: () {
                  // Double invocation on purpose: the guard must drop the
                  // second call instead of stacking a second reader.
                  openDoujinReader(context, item: gallery, booru: booru);
                  openDoujinReader(context, item: gallery, booru: booru);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-real')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DoujinReaderPage), findsOneWidget);
      final ModalRoute<dynamic>? route = ModalRoute.of(tester.element(find.byType(DoujinReaderPage)));
      expect(route, isA<MaterialPageRoute<dynamic>>());
      expect(route!.opaque, isTrue);

      // Popping once must land back on the home page — a stacked second
      // reader would still be found here.
      Navigator.of(tester.element(find.byType(DoujinReaderPage))).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(DoujinReaderPage), findsNothing);
    });

    testWidgets('with a LIVE page image: buttons still work and rapid tap-tap turns two pages', (tester) async {
      // The dead-buttons symptom came from an unclipped zoom surface
      // hit-testing over the chrome, and rapid tap-tap paging used to be
      // eaten by an always-on double-tap zoom recognizer. Both need a real
      // image on screen to regress, so give the slides one.
      DoujinReaderPage.testImageProviderBuilder = (item) => MemoryImage(kTinyPng);
      addTearDown(() => DoujinReaderPage.testImageProviderBuilder = null);

      await pumpReader(tester, pageCount: 5);
      final Size screen = screenSize(tester);
      // Let the memory image decode and the live viewer mount.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(InteractiveViewer), findsWidgets);

      // Two rapid right-edge taps = two page turns (no zoom stealing them).
      await tester.tapAt(Offset(screen.width * 0.9, screen.height * 0.5));
      // Deliberately mid-animation: the second tap lands 60ms into the
      // first turn's 180ms animation — the exact case the old
      // GestureDetector zones dropped.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(Offset(screen.width * 0.9, screen.height * 0.5));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('3 / 5'), findsOneWidget, reason: 'second rapid tap must not be swallowed');

      // Top-bar buttons receive input over the live image.
      await tester.tap(find.byKey(const ValueKey('reader-menu-button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save all pages'), findsOneWidget);
    });
  });
}
