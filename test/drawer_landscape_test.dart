import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/drawer_quick_access.dart';

/// r79: on an AYN Thor held sideways, the left sidebar did not scroll. It was
/// one fixed column - the pinned tags got whatever height the Quick access
/// rows left over - and in landscape those rows alone were taller than the
/// screen: the pins were squeezed to nothing and the last rows cut off. The
/// whole sidebar scrolls now; with room to spare it looks as before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;
  final Booru r34 = Booru('rule34xxx', BooruType.Gelbooru, '', 'https://rule34.xxx', '');
  const List<String> pins = ['animated|video', 'animated', 'ai_generated', '-animated_gif', 'sort:score', 'sort:random', 'human'];

  setUp(() async {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('drawer_landscape');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
    SettingsHandler.instance.dbEnabled = true;
  });

  tearDown(() async {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> sidebar(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      for (final String p in pins) {
        await SettingsHandler.instance.dbHandler.addPinnedTag(p);
      }
    });
    SettingsHandler.instance.booruList.add(r34);
    SearchHandler.instance.tabs.add(SearchTab(r34, null, ''));
    SearchHandler.instance.changeTabIndex(0);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: Scaffold(body: DrawerQuickAccess(toggleDrawer: () {})),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('landscape: nothing is cut off - the whole sidebar scrolls to its last row and back to the pins', (tester) async {
    if (!dbReady) return;
    await sidebar(tester, const Size(480, 400));
    expect(tester.takeException(), isNull, reason: 'r78 overflowed here: the rows were taller than the screen');
    expect(find.text('animated|video'), findsOneWidget, reason: 'a pin is on screen');
    final Finder list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Collections'), 120, scrollable: list);
    await tester.ensureVisible(find.text('Collections'));
    await tester.pumpAndSettle();
    expect(find.text('Collections').hitTestable(), findsOneWidget, reason: 'the last Quick access row can be reached');
    await tester.scrollUntilVisible(find.text('animated|video'), -120, scrollable: list);
    await tester.ensureVisible(find.text('animated|video'));
    await tester.pumpAndSettle();
    expect(find.text('animated|video').hitTestable(), findsOneWidget, reason: 'and the pins again');
  });

  testWidgets('portrait with room to spare: pins at the top, Quick access at the bottom, as before', (tester) async {
    if (!dbReady) return;
    await sidebar(tester, const Size(400, 1400));
    expect(tester.takeException(), isNull);
    final double panelBottom = tester.getBottomLeft(find.byType(DrawerQuickAccess)).dy;
    final double lastRowBottom = tester.getBottomLeft(find.text('Collections')).dy;
    expect(panelBottom - lastRowBottom, lessThan(60), reason: 'Quick access sits at the bottom edge');
    // Pins list newest first; whichever is first sits right under the header.
    final double firstPinTop = [
      for (final String p in pins) tester.getTopLeft(find.text(p.replaceAll('_', ' '))).dy,
    ].reduce((a, b) => a < b ? a : b);
    expect(firstPinTop, lessThan(120), reason: 'the pins start at the top');
  });
}
