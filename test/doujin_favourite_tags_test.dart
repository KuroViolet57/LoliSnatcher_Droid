import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_favourite_tags_page.dart';

/// Round 2, item 9: the doujin drawer's "Favourite tags" entry opens a REAL
/// marked-tags screen (not the tag browser): chips, filter, open-as-search,
/// unmark.
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
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.markedTags.clear();
  });

  tearDown(() {
    SettingsHandler.instance.markedTags.clear();
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('shows marked tags, filters, opens a search tab, unmarks', (tester) async {
    final booru = nhentaiBooru();
    SettingsHandler.instance.markedTags.addAll(['vanilla', 'glasses', 'ponytail']);
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'origin'));
    SearchHandler.instance.changeTabIndex(0);

    await tester.pumpWidget(MaterialApp(home: DoujinFavouriteTagsPage(booru: booru)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('vanilla'), findsOneWidget);
    expect(find.text('glasses'), findsOneWidget);
    expect(find.text('ponytail'), findsOneWidget);

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
    expect(SettingsHandler.instance.markedTags.contains('glasses'), isFalse);
    // unmark fires an async settings.json save — let it flush inside the
    // test's lifetime instead of exploding after the temp dir is gone.
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
