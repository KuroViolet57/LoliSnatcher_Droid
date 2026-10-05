import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/app/drawers/downloads_drawer.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/tag.dart';

/// The phone pin drawer used to be the only place a multi-select could be
/// snatched. It was replaced by quick access and the actions went with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Booru gel = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    SettingsHandler.instance.dbEnabled = true;
    SettingsHandler.instance.booruList
      ..clear()
      ..add(gel);
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.tabs.add(SearchTab(gel, null, ''));
    SearchHandler.instance.changeTabIndex(0);
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(body: DownloadsDrawer(toggleDrawer: () {})),
        ),
      ),
    );
    await tester.pump();
  }

  BooruItem item() => BooruItem(
    fileURL: 'https://img.invalid/1.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag('solo')],
    postURL: 'https://gelbooru.com/1',
    serverId: '1',
  );

  testWidgets('a selection shows snatch, collection, and clear on the pin drawer', (tester) async {
    SearchHandler.instance.currentTab.selected.add(item());
    await pumpDrawer(tester);

    expect(find.textContaining('Snatch selected'), findsOneWidget);
    expect(find.textContaining('Add to collection'), findsOneWidget);
    expect(find.textContaining('Clear selected'), findsOneWidget);
    expect(find.text('Pinned tags'), findsOneWidget);
  });

  testWidgets('clear drops the selection and the bar', (tester) async {
    SearchHandler.instance.currentTab.selected.add(item());
    await pumpDrawer(tester);

    await tester.tap(find.textContaining('Clear selected'));
    await tester.pump();

    expect(SearchHandler.instance.currentTab.selected, isEmpty);
    expect(find.textContaining('Snatch selected'), findsNothing);
    expect(find.text('Pinned tags'), findsOneWidget);
  });

  testWidgets('an empty selection leaves the pin drawer as navigation', (tester) async {
    await pumpDrawer(tester);

    expect(find.textContaining('Snatch selected'), findsNothing);
    expect(find.textContaining('Select all'), findsNothing);
    expect(find.text('Pinned tags'), findsOneWidget);
  });
}
