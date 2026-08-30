import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_favourite_tags_page.dart';

/// Round 3, item 2: the doujin drawer's "Favourite tags" screen lists ONLY
/// tags starred in the DOUJIN star store — booru markedTags never appear —
/// with filter, open-as-search and unstar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_fav_tags_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.markedTags.clear();
  });

  tearDown(() {
    SettingsHandler.instance.markedTags.clear();
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('shows DOUJIN starred tags only (never booru marked), filters, opens a search tab, unstars', (tester) async {
    final booru = nhentaiBooru();
    // Booru marked tags must NOT appear on this screen.
    SettingsHandler.instance.markedTags.addAll(['booru_artist_a', 'booru_artist_b']);
    DoujinDataHandler.instance.starTag('vanilla');
    DoujinDataHandler.instance.starTag('glasses');
    DoujinDataHandler.instance.starTag('ponytail');
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'origin'));
    SearchHandler.instance.changeTabIndex(0);

    await tester.pumpWidget(MaterialApp(home: DoujinFavouriteTagsPage(booru: booru)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('vanilla'), findsOneWidget);
    expect(find.text('glasses'), findsOneWidget);
    expect(find.text('ponytail'), findsOneWidget);
    expect(find.textContaining('booru artist', findRichText: true), findsNothing);
    expect(find.text('booru_artist_a'), findsNothing);

    // filter
    await tester.enterText(find.byType(TextField), 'gla');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('vanilla'), findsNothing);
    expect(find.text('glasses'), findsOneWidget);

    // unmark via the star
    await tester.tap(
      find.descendant(of: find.byType(Wrap), matching: find.byIcon(Symbols.star_rounded)).first,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(DoujinDataHandler.instance.starredTags.contains('glasses'), isFalse);
    // Unstar must NOT touch the booru marked list.
    expect(SettingsHandler.instance.markedTags.length, 2);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));

    // clear filter, tap a chip -> opens a search tab on this source
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(SearchHandler.instance.tabs.length, 2);
    expect(SearchHandler.instance.tabs.last.tags.trim(), 'vanilla');
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  });
}
