import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/core/ui/text/marquee_text.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/tabs/ui/widgets/tab_row.dart';

/// 1.0 M2 (tabs): the tab rows of the tab manager and the mini manager.
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
    tempDir = Directory.systemTemp.createTempSync('tab_row_highlight');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('tab row', () {
    testWidgets('the filter highlight ignores case and surrounding spaces, as the filter does', (tester) async {
      final SearchTab tab = searchTab('cat_ears');
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(home: Scaffold(body: TabRow(tab: tab, filterText: 'Cat '))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final MarqueeText marquee = tester.widget<MarqueeText>(find.byType(MarqueeText));
      final List<TextSpan> spans = (marquee.textSpan?.children ?? const []).whereType<TextSpan>().toList();
      expect(marquee.textSpan?.toPlainText(), 'cat_ears', reason: 'the tab keeps its own spelling');
      expect(spans.where((s) => s.style?.color == Colors.green).map((s) => s.text).toList(), ['cat']);
    });
  });
}
