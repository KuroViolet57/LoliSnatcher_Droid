import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// The Tag builder card: one chip per namespace the source can list, under
/// the Metatags card; nothing for a source without a catalog; a hint while
/// the database is off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tag_builder');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Booru booru) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TagBuilderBlock(booru: booru, onInsertTerm: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a gelbooru-family source gets five chips under a "Tag builder" title', (tester) async {
    SettingsHandler.instance.dbEnabled = true;
    await pump(tester, b('r34', BooruType.GelbooruAlike, 'https://rule34.xxx'));
    expect(find.text('Tag builder'), findsOneWidget);
    for (final key in ['artist', 'character', 'copyright', 'meta', 'tag']) {
      expect(find.byKey(ValueKey('tag-type-$key')), findsOneWidget, reason: key);
    }
    expect(find.text('Artists'), findsOneWidget);
  });

  testWidgets('a source without a catalog shows no card', (tester) async {
    SettingsHandler.instance.dbEnabled = true;
    await pump(tester, b('e', BooruType.EaHentai, 'https://eahentai.com'));
    expect(find.text('Tag builder'), findsNothing);
  });

  testWidgets('with the database off the card explains instead of listing', (tester) async {
    SettingsHandler.instance.dbEnabled = false;
    await pump(tester, b('r34', BooruType.GelbooruAlike, 'https://rule34.xxx'));
    expect(find.text('Tag builder'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-type-artist')), findsNothing);
    expect(find.textContaining('database'), findsOneWidget);
  });
}
