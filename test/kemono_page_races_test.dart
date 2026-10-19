import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/kemono/ui/kemono_artists_page.dart';
import 'package:lolisnatcher/features/kemono/ui/kemono_creator_header.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/kemono/kemono_creator_store.dart';
import 'package:lolisnatcher/sources/kemono/kemono_handler.dart';
import 'package:lolisnatcher/sources/kemono/kemono_query.dart';
import 'package:lolisnatcher/sources/kemono/kemono_session_handler.dart';
import 'package:lolisnatcher/sources/kemono/kemono_site.dart';

Map<String, Object?> _row(String id, String name) => {
  'service': 'patreon',
  'id': id,
  'name': name,
  'indexed': 0,
  'updated': 0,
  'favorited': 5,
};

/// The creator index, answering each look-up only when the test says so.
class _SlowIndex extends DBHandler {
  final List<({String orderBy, Completer<List<Map<String, Object?>>> answer})> searches = [];
  final Map<String, Completer<List<Map<String, Object?>>>> lookups = {};

  @override
  Future<List<Map<String, Object?>>> queryKemonoCreators({
    String? nameLike,
    Set<String>? services,
    String orderBy = 'favorited',
    Set<String>? keys,
    int limit = 60,
    int offset = 0,
    String table = 'KemonoCreator',
  }) {
    final Completer<List<Map<String, Object?>>> answer = Completer();
    searches.add((orderBy: orderBy, answer: answer));
    return answer.future;
  }

  @override
  Future<List<Map<String, Object?>>> getKemonoCreatorsByKeys(
    List<({String service, String id})> pairs, {
    String table = 'KemonoCreator',
  }) {
    final Completer<List<Map<String, Object?>>> answer = Completer();
    lookups[pairs.single.id] = answer;
    return answer.future;
  }
}

/// m2 (1.0): kemono pages that load in the background must show the query
/// on screen, not the one whose answer came back last.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DBHandler originalDb;
  late _SlowIndex index;
  final Booru kemono = Booru('kemono', BooruType.Kemono, '', 'https://kemono.cr', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('kemono_page_races_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    KemonoSessionHandler.instance.resetForTests();
    final KemonoCreatorStore store = KemonoCreatorStore.forSite(KemonoSite.kemono)..resetForTests();
    // A fresh index: the page does not start a download.
    store.state.value = KemonoIndexState(count: 2, refreshedAt: DateTime.now().millisecondsSinceEpoch);
    originalDb = SettingsHandler.instance.dbHandler;
    index = _SlowIndex();
    SettingsHandler.instance.dbHandler = index;
  });

  tearDown(() {
    SettingsHandler.instance.dbHandler = originalDb;
    KemonoCreatorStore.forSite(KemonoSite.kemono).resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('Artists: a sort chosen while a page loads shows the new order, never the old rows', (tester) async {
    // A tap that lands on the menu's barrier instead of the item must fail
    // the test, not quietly close the menu.
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    await tester.pumpWidget(MaterialApp(home: KemonoArtistsPage(booru: kemono)));
    await tester.pump();
    expect(index.searches.map((s) => s.orderBy), ['favorited']);

    await tester.tap(find.byTooltip('Sort'));
    // One frame starts the menu's animation, the next one ends it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Name'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    index.searches.first.answer.complete([_row('1', 'Old order')]);
    await tester.pump();
    await tester.pump();

    expect(index.searches.map((s) => s.orderBy), ['favorited', 'name'], reason: 'the new sort is asked for');
    index.searches.last.answer.complete([_row('2', 'New order')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('New order'), findsOneWidget);
    expect(find.text('Old order'), findsNothing);
  });

  testWidgets('creator header: switching creators fast shows the creator on screen, not the one looked up last', (tester) async {
    final KemonoHandler handler = KemonoHandler(kemono, 50)..current = KemonoQuery.parse('creator:patreon:1');
    final SearchTab tab = SearchTab(kemono, null, 'creator:patreon:1', customHandler: handler);
    final ValueNotifier<int> rebuild = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (_, _, _) => KemonoCreatorHeader(tab: tab),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    handler.current = KemonoQuery.parse('creator:patreon:2');
    rebuild.value++;
    await tester.pump();
    expect(index.lookups.keys, ['1', '2']);

    index.lookups['2']!.complete([_row('2', 'Second creator')]);
    await tester.pump();
    index.lookups['1']!.complete([_row('1', 'First creator')]);
    await tester.pump();

    expect(find.text('Second creator'), findsOneWidget);
    expect(find.text('First creator'), findsNothing);
  });
}
