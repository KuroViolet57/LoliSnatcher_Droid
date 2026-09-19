import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/doujin_tab_view.dart';

/// r34, reported from the phone: a doujin tab whose gallery could not be
/// loaded (an hdoujin session that expired while the tab waited) showed
/// "Could not load this doujin" with a Retry and nothing else — no back, no
/// tabs, no way out. The error screen keeps the ways out and says why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentai() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_tab_view');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a doujin tab that failed to load still has a way out: the reason, the tabs, close', (tester) async {
    final SearchTab other = SearchTab(nhentai(), null, 'vanilla');
    // Something in the other tab, so switching to it triggers no search.
    other.booruHandler.fetched.add(
      BooruItem(fileURL: 'https://nhentai.net/g/9/', sampleURL: '', thumbnailURL: '', tagsList: [Tag('vanilla')], postURL: 'https://nhentai.net/g/9/'),
    );
    other.booruHandler.filterFetched();
    final SearchTab tab = SearchTab(nhentai(), null, 'id:123', doujinPostURL: 'https://nhentai.net/g/123/', doujinTitle: 'Pending book');
    // r34 seeds a stub from the saved URL; a retry that failed empties the
    // handler again and leaves the reason — that is when this screen shows.
    tab.booruHandler.fetched.clear();
    tab.booruHandler.filterFetched();
    tab.booruHandler.errorString = 'The session expired; log in again from Source settings.';
    SearchHandler.instance.tabs.addAll([other, tab]);
    SearchHandler.instance.changeTabIndex(1, switchOnly: true);
    // Keeps the view's first frame from firing a real search.
    SearchHandler.instance.isLoading.value = true;

    await tester.pumpWidget(MaterialApp(home: DoujinTabView(tab: tab)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    SearchHandler.instance.isLoading.value = false;
    await tester.pump();

    expect(find.text('Pending book'), findsOneWidget);
    expect(find.text('Could not load this doujin'), findsOneWidget);
    expect(find.byKey(const Key('doujin-tab-reason')), findsOneWidget);
    expect(find.textContaining('session expired'), findsOneWidget, reason: "the source's own reason, not a generic line");
    expect(find.byKey(const Key('doujin-tab-tabs')), findsOneWidget);
    expect(find.byKey(const Key('doujin-tab-open-browser')), findsOneWidget);
    expect(find.byKey(const Key('mini-manager-edge-handle')), findsOneWidget, reason: 'the tab-manager grip the loaded page has');
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.byKey(const Key('doujin-tab-close')));
    await tester.pump();
    expect(SearchHandler.instance.tabs.map((t) => t.tags), ['vanilla']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
