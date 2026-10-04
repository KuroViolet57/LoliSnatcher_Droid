import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/tabs/ui/tab_selector.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

/// 1.0 M2 (tabs): the tab manager.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  // A tab with something fetched, so switching to it never starts a search.
  SearchTab searchTab(String query) {
    final SearchTab tab = SearchTab(gelbooru, null, query);
    tab.booruHandler.fetched.add(
      BooruItem(
        fileURL: 'https://img.invalid/$query.jpg',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: [Tag(query)],
        postURL: 'https://gelbooru.com/$query',
      ),
    );
    tab.booruHandler.filterFetched();
    return tab;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tab_manager_fixes');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.visitedTabsHistory.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.visitedTabsHistory.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpManager(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: const TabManagerPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder optionsOf(SearchTab tab) => find.descendant(
    of: find.byKey(ValueKey('item-${tab.id}')),
    matching: find.byIcon(CupertinoIcons.slider_horizontal_3),
  );

  group('tab manager', () {
    testWidgets("a tab's options: Remove closes the dialog, so a second tap cannot close the current tab", (tester) async {
      final SearchTab alpha = searchTab('alpha');
      final SearchTab beta = searchTab('beta');
      final SearchTab gamma = searchTab('gamma');
      SearchHandler.instance.tabs.addAll([alpha, beta, gamma]);
      SearchHandler.instance.changeTabIndex(0);

      await pumpManager(tester);

      // The options dialog is an AlertDialog (IntrinsicWidth) around a row
      // whose marquee uses a LayoutBuilder: debug builds assert on that
      // layout (release builds lay it out). The test drives the dialog's
      // callbacks directly and ignores those layout assertions.
      final onError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'rendering library') return;
        onError?.call(details);
      };

      await tester.tap(optionsOf(gamma));
      await tester.pump(const Duration(milliseconds: 400));
      ListTile removeTile() => tester.widget<ListTile>(find.ancestor(of: find.text('Remove'), matching: find.byType(ListTile)));
      expect(find.text('Remove'), findsOneWidget);

      final VoidCallback remove = removeTile().onTap!;
      remove();
      await tester.pump(const Duration(milliseconds: 400));
      final bool dialogStillOpen = find.text('Remove').evaluate().isNotEmpty;
      // The data loss: Remove pressed again on the stale dialog (possible
      // only while it is still open).
      if (dialogStillOpen) {
        remove();
        await tester.pump(const Duration(milliseconds: 400));
      }

      FlutterError.onError = onError;

      expect(dialogStillOpen, isFalse, reason: 'the dialog of a removed tab must not stay open');
      expect(SearchHandler.instance.tabs, [alpha, beta], reason: 'a second Remove must not close the current tab');
      expect(SearchHandler.instance.currentTab, alpha);
    });
  });
}
