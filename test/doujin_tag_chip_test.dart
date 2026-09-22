import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/doujin_tag_chip.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';

/// Round 2, item 5: doujin tag chips — the menu is a CENTERED popup, and the
/// "Tag chip tap" setting swaps tap/long-press between menu and
/// open-as-background-tab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_tag_chip_test');
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

  Future<ValueNotifier<int>> pumpChip(WidgetTester tester) async {
    final booru = nhentaiBooru();
    // an existing tab so background-tab opens have a "current" to not switch from
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'origin'));
    SearchHandler.instance.changeTabIndex(0);
    final menuOpens = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DoujinTagChip(
              tag: Tag('vanilla'),
              booru: booru,
              onOpenMenu: () => menuOpens.value++,
            ),
          ),
        ),
      ),
    );
    return menuOpens;
  }

  testWidgets('default: tap = menu, long-press = background tab', (tester) async {
    final menuOpens = await pumpChip(tester);

    await tester.tap(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuOpens.value, 1);
    expect(SearchHandler.instance.tabs.length, 1); // no tab opened

    await tester.longPress(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuOpens.value, 1); // long-press did NOT open the menu
    expect(SearchHandler.instance.tabs.length, 2);
    expect(SearchHandler.instance.tabs[1].tags.trim(), 'vanilla');
    // background: current tab unchanged
    expect(SearchHandler.instance.currentTab, SearchHandler.instance.tabs[0]);
  });

  testWidgets("setting 'newtab': tap = background tab, long-press = menu", (tester) async {
    SourceSettingsHandler.instance.updateGlobal((s) => s.tagChipTap = 'newtab');
    final menuOpens = await pumpChip(tester);

    await tester.tap(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuOpens.value, 0);
    expect(SearchHandler.instance.tabs.length, 2);

    await tester.longPress(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuOpens.value, 1);
    expect(SearchHandler.instance.tabs.length, 2); // long-press did NOT open a tab
  });

  testWidgets('background tab honours the tab-placement setting (next)', (tester) async {
    SourceSettingsHandler.instance.updateGlobal((s) => s.tagChipTap = 'newtab');
    SourceSettingsHandler.instance.updateGlobal((s) => s.tabPlacement = 'next');
    await pumpChip(tester);
    // a trailing tab so 'next' != 'end'
    SearchHandler.instance.tabs.add(SearchTab(nhentaiBooru(), null, 'trailing'));

    await tester.tap(find.text('vanilla'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(SearchHandler.instance.tabs.length, 3);
    expect(SearchHandler.instance.tabs[1].tags.trim(), 'vanilla'); // right after current
    expect(SearchHandler.instance.tabs[2].tags.trim(), 'trailing');
  });

  testWidgets('the doujin tag menu presents as a CENTERED Dialog, not a bottom sheet', (tester) async {
    final booru = nhentaiBooru();
    final handler = NHentaiHandler(booru, 20);
    // the menu content reads the current tab's booru
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'origin'));
    SearchHandler.instance.changeTabIndex(0);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
        navigatorKey: NavigationHandler.instance.navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showTagDialog(
                  context: context,
                  tag: 'vanilla',
                  handler: handler,
                  isHidden: false,
                  isMarked: false,
                  isInSearch: false,
                  hasTabWithTag: HasTabWithTagResult.noTag,
                  onUpdate: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // the tag itself is shown in the menu header
    expect(find.textContaining('vanilla'), findsWidgets);
  });
}
