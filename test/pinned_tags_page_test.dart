import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/followed_artists_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/pages/pinned_tags_page.dart';

class _MemStore extends PinnedTagsStore {
  _MemStore(this.booru);

  final Booru booru;
  final List<PinnedTag> pins = [];
  int _id = 0;

  PinnedTag seed(String tags, {String? title, List<String> labels = const []}) {
    final PinnedTag pin = PinnedTag(
      id: ++_id,
      tagName: tags,
      title: title,
      pinnedAt: _id,
      booruName: booru.name,
      booruType: booru.type,
      labels: labels,
    );
    pins.add(pin);
    return pin;
  }

  @override
  bool get supportsTitles => true;

  @override
  Future<List<PinnedTag>> list() async => List.of(pins);

  @override
  Future<void> add(String tags, {String? title, required bool global}) async {
    pins.add(
      PinnedTag(
        id: ++_id,
        tagName: tags,
        title: title,
        pinnedAt: _id,
        booruName: global ? null : booru.name,
        booruType: global ? null : booru.type,
      ),
    );
  }

  @override
  Future<void> update(PinnedTag pin, String tags, {String? title, required bool global}) async {
    final int i = pins.indexWhere((p) => p.id == pin.id);
    pins[i] = PinnedTag(
      id: pin.id,
      tagName: tags,
      title: title,
      pinnedAt: pin.pinnedAt,
      booruName: global ? null : booru.name,
      booruType: global ? null : booru.type,
    );
  }

  @override
  Future<void> remove(PinnedTag pin) async => pins.removeWhere((p) => p.id == pin.id);

  @override
  Future<void> reorder(List<PinnedTag> ordered) async {}
}

/// r50: the search window's pinned row is off by default (Modular UI), so the
/// left sidebar's Quick access gets a pinned tags page for the current
/// source: pins of several tags built as chips, named, renamed, re-scoped
/// and deleted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
  });

  Future<_MemStore> open(WidgetTester tester, {void Function(_MemStore)? seed, ValueChanged<String>? onOpen}) async {
    final _MemStore store = _MemStore(e621);
    seed?.call(store);
    await tester.pumpWidget(
      MaterialApp(home: PinnedTagsPage(booru: e621, store: store, onOpen: onOpen ?? (_) {})),
    );
    await tester.pumpAndSettle();
    return store;
  }

  test('a pin carries an optional name and its tags; the switch in Quick access is on by default', () {
    final PinnedTag named = PinnedTag.fromMap({'id': 1, 'tagName': 'fox  solo', 'pinnedAt': 1, 'title': 'Foxes'});
    expect(named.displayName, 'Foxes');
    expect(named.tags, ['fox', 'solo']);
    expect(named.toMap()['title'], 'Foxes');
    final PinnedTag plain = PinnedTag.fromMap({'id': 2, 'tagName': 'wolf', 'pinnedAt': 1});
    expect((plain.displayName, plain.title), ('wolf', null));
    expect(named.copyWith(clearTitle: true).title, isNull);
    expect(ModularUi.all, contains(ModularUi.sidebarPinnedTags));
    expect(ModularUi.isOn(ModularUi.sidebarPinnedTags), isTrue);
  });

  test('a doujin source keeps its pins in the doujin store: distinct ids, their real scope, no names', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync('pinned_doujin');
    addTearDown(() {
      DoujinDataHandler.instance.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    SearchHandler.register();
    TagHandler.register();
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    DoujinDataHandler.instance.resetForTests();
    final Booru nh = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
    DoujinDataHandler.instance.addPin('vanilla', nh);
    DoujinDataHandler.instance.addPin('ponytail', nh, global: true);

    final PinnedTagsStore store = PinnedTagsStore.forBooru(nh);
    expect(store.supportsTitles, isFalse);
    final List<PinnedTag> pins = await store.list();
    expect(pins.map((p) => p.id).toSet().length, 2, reason: "the list's keys");
    expect({for (final p in pins) p.tagName: p.isGlobal}, {'vanilla': false, 'ponytail': true});
  });

  testWidgets("lists the source's pins by name with their tags, without follows; a tap searches it", (tester) async {
    String? opened;
    await open(
      tester,
      seed: (s) {
        s.seed('fox solo', title: 'Foxes');
        s.seed('some_artist', labels: [FollowedArtistsHandler.followLabel]);
      },
      onOpen: (q) => opened = q,
    );
    expect(find.text('Foxes'), findsOneWidget);
    expect(find.text('fox solo'), findsOneWidget);
    expect(find.text('some_artist'), findsNothing, reason: 'follows have their own page');
    await tester.tap(find.text('Foxes'));
    expect(opened, 'fox solo');
  });

  testWidgets('builds a pin of several tags as chips, with a name, for this source', (tester) async {
    final _MemStore store = await open(tester);
    await tester.tap(find.byKey(const ValueKey('pinned-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pin-builder-tag')), 'fox');
    await tester.tap(find.byKey(const ValueKey('pin-builder-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('pin-builder-tag')), 'solo  -comic');
    await tester.tap(find.byKey(const ValueKey('pin-builder-add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-builder-chip--comic')), findsOneWidget, reason: 'several tags typed at once become several chips');
    await tester.enterText(find.byKey(const ValueKey('pin-builder-title')), 'Foxes');
    await tester.tap(find.byKey(const ValueKey('pin-builder-save')));
    await tester.pumpAndSettle();
    final PinnedTag pin = store.pins.single;
    expect((pin.tagName, pin.title, pin.booruName), ('fox solo -comic', 'Foxes', 'e621'));
    expect(find.text('Foxes'), findsOneWidget);
  });

  testWidgets('edits: removes a tag, renames, makes it global; deletes after confirming', (tester) async {
    final _MemStore store = await open(tester, seed: (s) => s.seed('fox solo', title: 'Foxes'));
    await tester.tap(find.byKey(const ValueKey('pinned-edit-1')));
    await tester.pumpAndSettle();
    tester.widget<InputChip>(find.byKey(const ValueKey('pin-builder-chip-solo'))).onDeleted!();
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('pin-builder-title')), 'Just foxes');
    await tester.tap(find.byKey(const ValueKey('pin-builder-global')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-builder-save')));
    await tester.pumpAndSettle();
    expect((store.pins.single.tagName, store.pins.single.title, store.pins.single.isGlobal), ('fox', 'Just foxes', true));

    await tester.tap(find.byKey(const ValueKey('pinned-delete-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.pins, isEmpty);
    expect(find.text('Just foxes'), findsNothing);
  });
}
