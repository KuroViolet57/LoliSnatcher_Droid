import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/doujin/nhentai/nhentai_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_list_card.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_list_sliver.dart';

/// 2026-10-10 (F42, "scrolling didn't improve"): a trace on the Thor showed
/// the slow List-view frames each rebuilding every row the list had built
/// (DoujinListCard x 26 in one 22-37 ms frame), because anything that rebuilt
/// the list - a page appended, a loading flag, the fling cache window -
/// rebuilt all its rows. A row now rebuilds only when what it shows changed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem doujin(int i) => BooruItem(
    fileURL: 'https://images.invalid/$i.png',
    sampleURL: 'https://images.invalid/$i.png',
    thumbnailURL: 'https://thumbs.invalid/$i.png',
    tagsList: [Tag('english'), Tag('tag $i')],
    postURL: 'https://nhentai.net/g/${1000 + i}/',
    serverId: '${1000 + i}',
  )..description = 'Gallery $i';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_list_sliver');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinCoverAspects.instance.resetForTests();
    PerfTrace.instance.clearForTests();
  });

  tearDown(() {
    PerfTrace.instance.clearForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  int rowBuilds() => PerfTrace.instance.builds['DoujinListCard'] ?? 0;

  /// GetX hands a list change to its listeners a moment later: one pump for
  /// the change to arrive, one for the frame it schedules.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('rebuilding the list rebuilds only rows whose item or look changed', (tester) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    handler.filteredFetched.value = [for (int i = 0; i < 4; i++) doujin(i)];
    final RxList<BooruItem> selected = RxList<BooruItem>.from([]);
    final AutoScrollController controller = AutoScrollController();
    double height = 176;
    late StateSetter rebuildParent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuildParent = setState;
                return CustomScrollView(
                  controller: controller,
                  cacheExtent: 250,
                  slivers: [
                    DoujinListSliver(
                      handler: handler,
                      selected: selected,
                      scrollController: controller,
                      height: height,
                      coverWidth: 116,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DoujinListCard), findsNWidgets(4));

    PerfTrace.instance.start();

    // The parent rebuilds (the fling cache window, a loading flag): no row does.
    rebuildParent(() {});
    await tester.pump();
    expect(rowBuilds(), 0, reason: 'nothing a row shows changed');

    // A page is appended: only the new rows are built.
    handler.filteredFetched.value = [...handler.filteredFetched, for (int i = 4; i < 6; i++) doujin(i)];
    await settle(tester);
    // Rows built in the cache area just off screen count too.
    final int built = find.byType(DoujinListCard, skipOffstage: false).evaluate().length;
    expect(built, greaterThan(4), reason: 'the new rows near the screen are built');
    expect(rowBuilds(), built - 4, reason: 'the four rows already there are not rebuilt');

    // A different gallery at index 1 (a filter hid one): that row rebuilds.
    final int before = rowBuilds();
    final List<BooruItem> items = [...handler.filteredFetched];
    items[1] = doujin(99);
    handler.filteredFetched.value = items;
    await settle(tester);
    expect(rowBuilds(), before + 1);
    expect(find.text('Gallery 99'), findsOneWidget);

    // The row height setting changed: every built row follows it.
    final int beforeHeight = rowBuilds();
    rebuildParent(() => height = 200);
    await tester.pump();
    expect(rowBuilds(), beforeHeight + built);
    expect(tester.getSize(find.byKey(const ValueKey('doujin-list-card-row')).first).height, 200);

    // Selecting a row still updates it at once (its own listener).
    final int beforeSelect = rowBuilds();
    selected.add(items[0]);
    await settle(tester);
    expect(rowBuilds(), greaterThan(beforeSelect));
  });

  testWidgets('every row keeps the fixed extent', (tester) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    handler.filteredFetched.value = [for (int i = 0; i < 3; i++) doujin(i)];
    final AutoScrollController controller = AutoScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              DoujinListSliver(
                handler: handler,
                selected: RxList<BooruItem>.from([]),
                scrollController: controller,
                height: 184,
                coverWidth: 140,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (final Element row in find.byType(DoujinListCard).evaluate()) {
      expect(tester.getSize(find.byElementPredicate((e) => e == row)).height, DoujinListCard.rowExtent(184));
    }
  });
}
