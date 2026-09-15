import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/item_info_bottom_sheet.dart';

/// Stands in for TagView: records every time a post's details are built.
class _FakeDetails extends StatefulWidget {
  const _FakeDetails({required this.item, required this.scrollController, required this.built});

  final BooruItem item;
  final ScrollController scrollController;
  final List<String> built;

  @override
  State<_FakeDetails> createState() => _FakeDetailsState();
}

class _FakeDetailsState extends State<_FakeDetails> {
  @override
  void initState() {
    super.initState();
    widget.built.add(widget.item.serverId!);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      children: [Text('details ${widget.item.serverId}')],
    );
  }
}

/// r56: the bottom info sheet built a post's details (TagView) for every post
/// the viewer landed on, even with the sheet closed, and on sources like
/// rule34.xxx or danbooru each one also loaded the post's page from the site;
/// landing on a post cost 35-68 ms in one frame. The details are now built
/// once the sheet opens (Modular UI switch; off builds them for every post).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  BooruItem post(String id) => BooruItem(
    fileURL: 'https://images.invalid/$id.png',
    sampleURL: 'https://images.invalid/$id.png',
    thumbnailURL: 'https://thumbs.invalid/$id.png',
    tagsList: [Tag('tag$id')],
    postURL: 'https://booru.invalid/post/$id',
    serverId: id,
  );

  SearchTab twoPostTab() {
    final tab = SearchTab(Booru('gelbooru', BooruType.Gelbooru, '', 'https://booru.invalid', ''), null, 'test');
    tab.booruHandler.fetched.addAll([post('1'), post('2')]);
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
    tempDir = Directory.systemTemp.createTempSync('info_sheet_details_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.modularUi.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
  });

  tearDown(() {
    SettingsHandler.instance.modularUi.clear();
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<({ValueNotifier<int> page, DraggableScrollableController controller, List<String> built})> pumpSheet(
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> page = ValueNotifier(0);
    final DraggableScrollableController controller = DraggableScrollableController();
    final ValueNotifier<double> extent = ValueNotifier(0);
    final List<String> built = [];
    final SearchTab tab = twoPostTab();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemInfoBottomSheet(
            tab: tab,
            currentPage: page,
            sheetController: controller,
            extentNotifier: extent,
            openSize: 0.5,
            detailsBuilder: (context, item, scrollController) =>
                _FakeDetails(item: item, scrollController: scrollController, built: built),
          ),
        ),
      ),
    );
    await tester.pump();
    return (page: page, controller: controller, built: built);
  }

  Future<void> animateSheet(WidgetTester tester, DraggableScrollableController controller, double size) async {
    unawaited(controller.animateTo(size, duration: const Duration(milliseconds: 300), curve: Curves.linear));
    await tester.pumpAndSettle();
  }

  testWidgets('a closed sheet builds no details, and the info button can still open it', (tester) async {
    final s = await pumpSheet(tester);
    expect(s.built, isEmpty);
    expect(find.text('details 1', skipOffstage: false), findsNothing);
    expect(s.controller.isAttached, isTrue, reason: 'animateTo does nothing on a detached controller');

    await animateSheet(tester, s.controller, 0.5);
    expect(s.built, ['1']);
    expect(find.text('details 1'), findsOneWidget);
  });

  testWidgets("closing keeps that post's details; a post swiped to while closed builds nothing until opened", (
    tester,
  ) async {
    final s = await pumpSheet(tester);
    await animateSheet(tester, s.controller, 0.5);
    await animateSheet(tester, s.controller, 0);
    expect(s.built, ['1'], reason: 'reopening the same post must not load it again');
    expect(find.text('details 1', skipOffstage: false), findsOneWidget);

    s.page.value = 1;
    await tester.pump();
    expect(s.built, ['1']);
    expect(find.text('details 1', skipOffstage: false), findsNothing);
    expect(find.text('details 2', skipOffstage: false), findsNothing);
    expect(s.controller.isAttached, isTrue);

    await animateSheet(tester, s.controller, 0.5);
    expect(s.built, ['1', '2']);
    expect(find.text('details 2'), findsOneWidget);
  });

  testWidgets('with the switch off every post builds its details while the sheet is closed, as before', (tester) async {
    SettingsHandler.instance.modularUi[ModularUi.viewerDetailsOnOpen.key] = false;
    final s = await pumpSheet(tester);
    expect(s.built, ['1']);
    s.page.value = 1;
    await tester.pump();
    expect(s.built, ['1', '2']);
  });

  test('the Modular UI switch is on by default', () {
    expect(ModularUi.all, contains(ModularUi.viewerDetailsOnOpen));
    expect(ModularUi.isOn(ModularUi.viewerDetailsOnOpen), isTrue);
  });
}
