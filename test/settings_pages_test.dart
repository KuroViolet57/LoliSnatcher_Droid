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
import 'package:lolisnatcher/gen/strings.g.dart';
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
    NavigationHandler.instance.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
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

}
