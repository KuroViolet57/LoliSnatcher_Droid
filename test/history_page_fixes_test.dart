import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/history/ui/history.dart';

/// 1.0 M2 (tabs): the Search history page. Seeded through the doujin
/// history (doujinData.json), which needs no database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('history_page_fixes');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SettingsHandler.instance.booruList.add(nhentai);
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.tabs.add(SearchTab(nhentai, null, 'vanilla'));
    SearchHandler.instance.index.value = 0;

    final int now = DateTime.now().millisecondsSinceEpoch;
    DoujinDataHandler.instance.ensureLoaded();
    DoujinDataHandler.instance.searchHistory.addAll([
      DoujinSearchHistoryEntry(id: 1, query: 'vanilla', booruHost: 'nhentai.net', at: now),
      DoujinSearchHistoryEntry(id: 2, query: 'glasses', booruHost: 'nhentai.net', at: now - 60000),
    ]);
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    DoujinDataHandler.instance.resetForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpHistory(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: theme,
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: const HistoryList(),
        ),
      ),
    );
    // getHistory runs 100 ms after the first frame; the list then loads a page.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('ticking an entry, typing in the filter, then Delete still opens the confirm dialog', (tester) async {
    await pumpHistory(tester);
    expect(find.text('vanilla'), findsWidgets);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Delete 1 item'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'v');
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Delete 1 item'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull, reason: 'the dialog must build (it threw a RangeError: history[-1])');
    expect(find.text('Delete history entries'), findsOneWidget);
  });

  testWidgets('typing in the filter uses the list already loaded', (tester) async {
    await pumpHistory(tester);
    expect(find.text('vanilla'), findsWidgets);
    expect(find.text('glasses'), findsWidgets);

    DoujinDataHandler.instance.searchHistory.add(
      DoujinSearchHistoryEntry(
        id: 3,
        query: 'vampire',
        booruHost: 'nhentai.net',
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'v');
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('vanilla'), findsWidgets);
    expect(find.text('vampire'), findsNothing, reason: 'a keystroke must not reload the store');
    expect(find.text('glasses'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the count under the title takes the app bar text colour, not onPrimary', (tester) async {
    const Color barText = Colors.white;
    final ThemeData theme = ThemeData(
      colorScheme: const ColorScheme.dark(primary: Color(0xFFFFE082), onPrimary: Colors.black),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF15151A),
        foregroundColor: barText,
        titleTextStyle: TextStyle(color: barText, fontSize: 19),
      ),
    );
    await pumpHistory(tester, theme: theme);

    final Text count = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('2')));
    expect(count.style?.color, barText, reason: 'black (onPrimary) on the dark bar was unreadable');
  });
}
