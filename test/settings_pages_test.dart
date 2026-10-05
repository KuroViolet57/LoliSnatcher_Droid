import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/buttons/confirm_button.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/settings/ui/gallery_page.dart';
import 'package:lolisnatcher/features/settings/ui/save_cache_page.dart';
import 'package:lolisnatcher/features/settings/ui/sources/booru_edit_page.dart';
import 'package:lolisnatcher/features/settings/ui/sources/booru_page.dart';
import 'package:lolisnatcher/features/settings/ui/sources/source_settings_page.dart';
import 'package:lolisnatcher/features/settings/ui/user_interface_page.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/settings/gallery_button.dart';
import 'package:lolisnatcher/models/update_info.dart';

/// 1.0 M2: settings pages that commit on exit do not lose the page's changes
/// over one empty field, open with any stored value, and the booru editor
/// replaces the booru it edits.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsHandler s;
  // The app bar's marquee title asserts on the default test font size.
  final ThemeData theme = ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20)));

  // The logger replaces FlutterError.onError when it starts: start it outside
  // any widget test.
  setUpAll(Logger.Inst);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    s = SettingsHandler.instance;
    tempDir = Directory.systemTemp.createTempSync('settings_pages');
    s
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..boorusPath = '${tempDir.path}${Platform.pathSeparator}boorus${Platform.pathSeparator}'
      ..prefBooru = '';
    s.booruList.clear();
    s.hiddenTagsPerBooru.clear();
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    s.booruList.clear();
    s.hiddenTagsPerBooru.clear();
    s.isDebug.value = false;
    s.buttonOrder = [...GalleryButton.values];
    s.disabledButtons = [];
    s.cacheDuration = Duration.zero;
    s.galleryAutoScrollTime = 4000;
    s.updateInfo.value = null;
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Real file writes need real time between frames.
  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Opens [page] on top of an empty screen, so it can be left with Back.
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(420, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          theme: theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    // The route's future completes when the page is popped, which is leave().
    unawaited(NavigationHandler.instance.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> leave(WidgetTester tester) async {
    NavigationHandler.instance.navigatorKey.currentState!.pop();
    await tester.pump();
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
  }

  /// The exit handler's save is real file work: give it time to land.
  Future<bool> saved(WidgetTester tester) async {
    final File f = File('${s.path}settings.json');
    for (int i = 0; i < 40 && !f.existsSync(); i++) {
      await settle(tester, rounds: 1);
    }
    return f.existsSync();
  }

  Finder field(String text) => find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);

  testWidgets('Save & cache opens with a cache time that is not one of the choices, and keeps it', (tester) async {
    s.cacheDuration = const Duration(seconds: 7200);
    await open(tester, const SaveCachePage());
    expect(tester.takeException(), isNull);
    expect(find.byType(SaveCachePage), findsOneWidget);
    await leave(tester);
    expect(s.cacheDuration, const Duration(seconds: 7200));
  });

  testWidgets('Save & cache: an empty snatch cooldown or cache size does not stop the other changes being saved', (tester) async {
    s
      ..snatchCooldown = 4321
      ..cacheSize = 7
      ..jsonWrite = false;
    await open(tester, const SaveCachePage());
    await tester.enterText(field('4321'), '');
    await tester.enterText(field('7'), '');
    await tester.pump();
    await leave(tester);
    expect(tester.takeException(), isNull);
    expect(s.snatchCooldown, 4321, reason: 'an empty field keeps the stored value');
    expect(s.cacheSize, 7);
    expect(await saved(tester), isTrue, reason: 'the page saved on exit');
  });

  testWidgets('Viewer: resetting the toolbar order puts every button back, and that is what is saved', (tester) async {
    s.buttonOrder = [...GalleryButton.values.reversed];
    s.disabledButtons = [GalleryButton.share];
    await open(tester, const GalleryPage());
    final Finder tile = find.ancestor(of: find.text('Toolbar buttons order'), matching: find.byType(ExpansionTile));
    await tester.tap(find.descendant(of: tile, matching: find.byIcon(Symbols.refresh_rounded)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await leave(tester);
    expect(s.buttonOrder, GalleryButton.values);
    expect(s.disabledButtons, isEmpty);
  });

  testWidgets('Boorus: an empty items-per-page field keeps the stored limit and the page still saves', (tester) async {
    s.itemLimit = 42;
    // The default-tags editor reads the current tab.
    SearchHandler.instance.tabs.add(SearchTab(Booru('other', BooruType.Gelbooru, '', 'https://other.example', ''), null, ''));
    await open(tester, const BooruPage());
    await tester.enterText(field('42'), '');
    await tester.pump();
    await leave(tester);
    expect(tester.takeException(), isNull);
    expect(s.itemLimit, 42);
    expect(await saved(tester), isTrue, reason: 'the page saved on exit');
  });

  testWidgets('Interface (desktop): an empty mouse wheel field keeps the stored value and the page still saves', (tester) async {
    s.mousewheelScrollSpeed = 12;
    await open(tester, const UserInterfacePage());
    await tester.enterText(field('12.0'), '');
    await tester.pump();
    await leave(tester);
    expect(tester.takeException(), isNull);
    expect(s.mousewheelScrollSpeed, 12);
    expect(await saved(tester), isTrue, reason: 'the page saved on exit');
  }, skip: !SettingsHandler.isDesktopPlatform);

  testWidgets("a doujin source's Endless recommendations override is reset by its marker", (tester) async {
    final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
    s.booruList.add(nhentai);
    SourceSettingsHandler.instance.update(nhentai, (st) => st.recommendedCount = 0);
    tester.view.physicalSize = const Size(420, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TranslationProvider(child: MaterialApp(theme: theme, home: SourceSettingsPage(booru: nhentai))));
    await tester.pump();
    final Finder marker = find.text('Overridden for this source · tap to reset');
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pump();
    expect(SourceSettingsHandler.instance.settingsFor(nhentai).recommendedCount, isNull);
    expect(marker, findsNothing);
  });

  testWidgets("What's new names the installed version, not the one on the server", (tester) async {
    s.updateInfo.value = const UpdateInfo(
      versionName: '0.0.1',
      buildNumber: 1,
      title: 'old',
      changelog: 'old',
      isInStore: false,
      isImportant: false,
      storePackage: '',
      githubURL: '',
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          theme: theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    s.showUpdate(true, isAfterUpdate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final String installed = '${Constants.updateInfo.versionName}+${Constants.updateInfo.buildNumber}';
    expect(find.textContaining(installed), findsWidgets);
    expect(find.textContaining('0.0.1+1'), findsNothing);
  });

  /// Long-press Save (debug: no network test), confirm, and give the file
  /// work real time until [done] holds (or long enough that it never will).
  Future<void> saveBooru(WidgetTester tester, bool Function() done) async {
    await tester.longPress(find.text('Save Booru'));
    await settle(tester, rounds: 3);
    await tester.tap(find.byType(ConfirmButton));
    await settle(tester);
    for (int i = 0; i < 60 && !done(); i++) {
      await settle(tester, rounds: 1);
    }
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets("editing a booru's URL and name replaces it instead of adding a second one", (tester) async {
    final Booru x = Booru('X', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    await tester.runAsync(() => s.saveBooru(x, onlySave: true));
    s.booruList.addAll([x, other]);
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(x));
    await tester.enterText(field('X'), 'Y');
    await tester.enterText(field('https://a.example'), 'https://b.example');
    await tester.pump();
    await saveBooru(tester, () => File('${s.boorusPath}Y.json').existsSync() && s.booruList.any((b) => b.name == 'Y'));

    expect(s.booruList.map((b) => b.name), unorderedEquals(['Y', 'other']));
    expect(File('${s.boorusPath}X.json').existsSync(), isFalse, reason: 'the old config is gone');
    expect(File('${s.boorusPath}Y.json').existsSync(), isTrue);
  });

  void expectPreferred(String name) {
    expect(s.prefBooru, name);
    // Sync: a file read awaited in the test zone never completes.
    final Map<String, dynamic> disk = jsonDecode(File('${s.path}settings.json').readAsStringSync()) as Map<String, dynamic>;
    expect(disk['prefBooru'], name, reason: 'the preference is what the next launch reads');
  }

  /// True once the save has landed. Memory is updated a step before the file.
  bool preferredOnDisk(String name) {
    final File f = File('${s.path}settings.json');
    if (!f.existsSync()) return false;
    try {
      final Map<String, dynamic> disk = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return s.prefBooru == name && disk['prefBooru'] == name;
    } catch (_) {
      return false;
    }
  }

  testWidgets('editing the preferred booru URL keeps it preferred', (tester) async {
    final Booru x = Booru('X', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    await tester.runAsync(() => s.saveBooru(x, onlySave: true));
    s.booruList.addAll([x, other]);
    s.prefBooru = 'X';
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(x));
    await tester.enterText(field('https://a.example'), 'https://b.example');
    await tester.pump();
    await saveBooru(tester, () => File('${s.boorusPath}X.json').existsSync() && preferredOnDisk('X'));

    expect(s.booruList.map((b) => b.name), unorderedEquals(['X', 'other']));
    final Booru saved = s.booruList.firstWhere((b) => b.name == 'X');
    expect(saved.baseURL, 'https://b.example');
    expectPreferred('X');
  });

  testWidgets('renaming the preferred booru moves the preference to the new name', (tester) async {
    final Booru x = Booru('X', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    await tester.runAsync(() => s.saveBooru(x, onlySave: true));
    s.booruList.addAll([x, other]);
    s.prefBooru = 'X';
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(x));
    await tester.enterText(field('X'), 'Y');
    await tester.pump();
    await saveBooru(tester, () => File('${s.boorusPath}Y.json').existsSync() && preferredOnDisk('Y'));

    expect(s.booruList.map((b) => b.name), contains('Y'));
    expectPreferred('Y');
  });

  testWidgets('editing a booru that is not preferred leaves the preference', (tester) async {
    final Booru x = Booru('X', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    await tester.runAsync(() => s.saveBooru(x, onlySave: true));
    await tester.runAsync(() => s.saveBooru(other, onlySave: true));
    s.booruList.addAll([x, other]);
    s.prefBooru = 'other';
    await tester.runAsync(() => s.saveSettings(restate: false));
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(x));
    await tester.enterText(field('https://a.example'), 'https://b.example');
    await tester.pump();
    await saveBooru(tester, () => s.booruList.any((b) => b.name == 'X' && b.baseURL == 'https://b.example'));

    expectPreferred('other');
  });

  testWidgets('a renamed booru keeps its own hidden lines', (tester) async {
    final Booru x = Booru('X', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    await tester.runAsync(() => s.saveBooru(x, onlySave: true));
    s.booruList.addAll([x, other]);
    s.hiddenTagsPerBooru['X'] = {'male solo'};
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(x));
    await tester.enterText(field('X'), 'Y');
    await tester.pump();
    await saveBooru(tester, () => s.booruList.any((b) => b.name == 'Y') && s.hiddenTagsForBooru('Y').isNotEmpty);

    expect(s.booruList.map((b) => b.name), unorderedEquals(['Y', 'other']));
    expect(s.hiddenTagsForBooru('Y'), {'male solo'});
    expect(s.hiddenTagsForBooru('X'), isEmpty);
  });

  testWidgets('hidden lines added on "Add new booru" before saving belong to the saved booru', (tester) async {
    final Booru other = Booru('other', BooruType.Gelbooru, '', 'https://other.example', '');
    s.booruList.add(other);
    // What the add page's per-booru editor stores before the first save.
    s.hiddenTagsPerBooru['New'] = {'male solo'};
    s.isDebug.value = true;
    SearchHandler.instance.tabs.add(SearchTab(other, null, 'tag'));

    await open(tester, BooruEdit(Booru('New', null, '', '', '')));
    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Z');
    await tester.enterText(fields.at(1), 'https://z.example');
    tester.widget<SettingsDropdown<BooruType>>(find.byType(SettingsDropdown<BooruType>)).onChanged!(BooruType.Gelbooru);
    await tester.pump();
    await saveBooru(tester, () => s.booruList.any((b) => b.name == 'Z') && s.hiddenTagsForBooru('Z').isNotEmpty);

    expect(s.booruList.map((b) => b.name), unorderedEquals(['Z', 'other']));
    expect(s.hiddenTagsForBooru('Z'), {'male solo'});
    expect(s.hiddenTagsForBooru('New'), isEmpty);
  });

  testWidgets('Viewer: a slideshow time over 10 s is kept', (tester) async {
    s.galleryAutoScrollTime = 4100;
    await open(tester, const GalleryPage());
    await tester.enterText(field('4100'), '30000');
    await tester.pump();
    await leave(tester);
    expect(s.galleryAutoScrollTime, 30000);
  });

  testWidgets('Doujin global settings show the choice that applies while none is set', (tester) async {
    tester.view.physicalSize = const Size(420, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TranslationProvider(child: MaterialApp(theme: theme, home: const SourceSettingsPage())));
    await tester.pump();
    bool selected(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;
    expect(selected('Left-to-right'), isTrue);
    expect(selected('Right-to-left'), isFalse);
    expect(selected('Animated'), isTrue);
  });

  testWidgets('importing a booru link from the clipboard does not log its key', (tester) async {
    final Booru shared = Booru.withKey('Shared', BooruType.Gelbooru, '', 'https://shared.example', '', 'SECRETKEY', '4242');
    final String link = shared.toLink(true);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': link};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    SearchHandler.instance.tabs.add(SearchTab(Booru('other', BooruType.Gelbooru, '', 'https://other.example', ''), null, ''));
    final int before = Logger.talker.history.length;

    await open(tester, const BooruPage());
    await tester.tap(find.text('Import Booru config from clipboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final String logged = [for (final e in Logger.talker.history.skip(before)) e.message ?? ''].join('\n');
    expect(logged, contains('https://www.loli.snatcher'));
    expect(logged, isNot(contains(link.split('?')[1])));
    expect(find.byType(BooruEdit), findsOneWidget, reason: 'the import still opens the editor');
  });
}
