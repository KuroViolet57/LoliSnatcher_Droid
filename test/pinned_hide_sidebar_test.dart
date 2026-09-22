import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag_visibility.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/drawer_quick_access.dart';

/// r79: a pin hidden on one source (the pins editor says "Hidden on
/// rule34xxx") still showed in the left sidebar's Pinned tags while that
/// source was open. Only the search window's pinned row read the hide, and
/// that row is off by default - so for the user the hide did nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;
  final Booru r34 = Booru('rule34xxx', BooruType.Gelbooru, '', 'https://rule34.xxx', '');
  final Booru gel = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() async {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('pinned_hide_sidebar');
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

  Future<void> openSidebarOn(WidgetTester tester, Booru booru) async {
    SettingsHandler.instance.booruList.add(booru);
    SearchHandler.instance.tabs.add(SearchTab(booru, null, ''));
    SearchHandler.instance.changeTabIndex(SearchHandler.instance.tabs.length - 1);
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

  Future<PinnedTag> pin(String tags) async {
    await SettingsHandler.instance.dbHandler.addPinnedTag(tags);
    final List<PinnedTag> all = await SettingsHandler.instance.dbHandler.getAllPinnedTags();
    return all.firstWhere((p) => p.tagName == tags);
  }

  testWidgets('a pin hidden on this source is not in the sidebar; the other pins are', (tester) async {
    if (!dbReady) return;
    late PinnedTag gif;
    await tester.runAsync(() async {
      await pin('animated');
      gif = await pin('-animated_gif');
    });
    PinnedTagVisibility.setHidden(gif, r34, true);
    await openSidebarOn(tester, r34);
    expect(find.textContaining('animated'), findsWidgets, reason: 'the visible pin is there - the list did load');
    expect(find.textContaining('-animated'), findsNothing, reason: 'hidden on rule34xxx');
  });

  testWidgets('the same pin still shows on another source', (tester) async {
    if (!dbReady) return;
    late PinnedTag gif;
    await tester.runAsync(() async {
      gif = await pin('-animated_gif');
    });
    PinnedTagVisibility.setHidden(gif, r34, true);
    await openSidebarOn(tester, gel);
    expect(find.textContaining('-animated'), findsWidgets);
  });

  testWidgets('a doujin pin hidden on one doujin source is not in its sidebar', (tester) async {
    DoujinDataHandler.instance
      ..addPin('ponytail', nhentai)
      ..addPin('vanilla', nhentai);
    PinnedTagVisibility.setHidden(PinnedTag(id: -1, tagName: 'ponytail', pinnedAt: 1), nhentai, true);
    await openSidebarOn(tester, nhentai);
    expect(find.text('vanilla'), findsOneWidget, reason: 'the visible pin is there - the list did load');
    expect(find.text('ponytail'), findsNothing);
  });

  test('deleting a pin forgets its hide everywhere, so a new pin that gets the same id is not born hidden', () async {
    if (!dbReady) return;
    final PinnedTag gif = await pin('-animated_gif');
    PinnedTagVisibility.setHidden(gif, r34, true);
    PinnedTagVisibility.setHidden(gif, gel, true);
    await SettingsHandler.instance.dbHandler.removePinnedTag(gif.id);
    final PinnedTag fresh = await pin('ai_generated');
    expect(fresh.id, gif.id, reason: 'SQLite hands the freed id out again (no AUTOINCREMENT)');
    expect(PinnedTagVisibility.isHidden(fresh, r34), isFalse);
    expect(PinnedTagVisibility.isHidden(fresh, gel), isFalse);
  });

  test('hides left behind by pins deleted before r79 are dropped once the full pin list is known', () async {
    if (!dbReady) return;
    final PinnedTag kept = await pin('animated');
    PinnedTagVisibility.setHidden(kept, r34, true);
    PinnedTagVisibility.setHidden(PinnedTag(id: 999, tagName: 'gone', pinnedAt: 1), r34, true);
    PinnedTagVisibility.setHidden(PinnedTag(id: -1, tagName: 'vanilla', pinnedAt: 1), nhentai, true);
    PinnedTagVisibility.forgetMissing(await SettingsHandler.instance.dbHandler.getAllPinnedTags());
    expect(PinnedTagVisibility.isHidden(kept, r34), isTrue);
    expect(PinnedTagVisibility.isHidden(PinnedTag(id: 999, tagName: 'gone', pinnedAt: 1), r34), isFalse);
    expect(
      PinnedTagVisibility.isHidden(PinnedTag(id: -1, tagName: 'vanilla', pinnedAt: 1), nhentai),
      isTrue,
      reason: 'doujin pins live in their own store; their hides are left alone',
    );
  });
}
