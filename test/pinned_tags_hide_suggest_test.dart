import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag_visibility.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/pinned_tags_page.dart';

class _MemStore extends PinnedTagsStore {
  final List<PinnedTag> pins = [];

  @override
  bool get supportsTitles => true;

  @override
  Future<List<PinnedTag>> list() async => List.of(pins);

  @override
  Future<void> add(String tags, {String? title, required bool global}) async =>
      pins.add(PinnedTag(id: pins.length + 1, tagName: tags, title: title, pinnedAt: 1));

  @override
  Future<void> update(PinnedTag pin, String tags, {String? title, required bool global}) async {}

  @override
  Future<void> remove(PinnedTag pin) async {}

  @override
  Future<void> reorder(List<PinnedTag> ordered) async {}
}

/// r52: a pin can be hidden on one source (it keeps its place on the others
/// and in this page); the builder suggests tags as you type; the builder
/// stays above the keyboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  final Booru dan = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '');
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('pinned_hide');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('hiding is per source: database pins by id, doujin pins by name', () {
    final PinnedTag global = PinnedTag(id: 7, tagName: 'animated', pinnedAt: 1);
    final PinnedTag doujin = PinnedTag(id: -1, tagName: 'vanilla', pinnedAt: 1);
    PinnedTagVisibility.setHidden(global, e621, true);
    expect(PinnedTagVisibility.isHidden(global, e621), isTrue);
    expect(PinnedTagVisibility.isHidden(global, dan), isFalse, reason: 'still shown on the other sources');
    expect(PinnedTagVisibility.visible([global, doujin], e621), [doujin]);
    PinnedTagVisibility.setHidden(doujin, e621, true);
    expect(PinnedTagVisibility.isHidden(PinnedTag(id: -3, tagName: 'vanilla', pinnedAt: 2), e621), isTrue);
    PinnedTagVisibility.setHidden(global, e621, false);
    expect(PinnedTagVisibility.isHidden(global, e621), isFalse);
  });

  testWidgets('the page hides a pin on this source with the button left of edit, and can show it again', (tester) async {
    final _MemStore store = _MemStore()..pins.add(PinnedTag(id: 1, tagName: 'order:random', pinnedAt: 1));
    await tester.pumpWidget(MaterialApp(home: PinnedTagsPage(booru: e621, store: store, onOpen: (_) {})));
    await tester.pumpAndSettle();
    final double hideX = tester.getCenter(find.byKey(const ValueKey('pinned-hide-1'))).dx;
    expect(hideX, lessThan(tester.getCenter(find.byKey(const ValueKey('pinned-edit-1'))).dx));
    await tester.tap(find.byKey(const ValueKey('pinned-hide-1')));
    await tester.pumpAndSettle();
    expect(PinnedTagVisibility.isHidden(store.pins.single, e621), isTrue);
    expect(find.textContaining('Hidden on e621'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pinned-hide-1')));
    await tester.pumpAndSettle();
    expect(PinnedTagVisibility.isHidden(store.pins.single, e621), isFalse);
  });

  testWidgets('the builder suggests tags as you type; a suggestion becomes a chip (a leading - is kept)', (tester) async {
    final List<String> asked = [];
    Future<List<TagSuggestion>> suggest(String input) async {
      asked.add(input);
      return input.contains('fo') ? [TagSuggestion(tag: 'fox_(species)')] : const [];
    }

    await tester.pumpWidget(
      MaterialApp(home: PinnedTagsPage(booru: e621, store: _MemStore(), onOpen: (_) {}, suggest: suggest)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pinned-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pin-builder-tag')), '-fo');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pin-builder-suggestion-fox_(species)')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pin-builder-suggestion-fox_(species)')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pin-builder-chip--fox_(species)')), findsOneWidget);
    expect(asked.last, '-fo');
  });

  testWidgets('the builder stays above the keyboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PinnedTagsPage(booru: e621, store: _MemStore(), onOpen: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pinned-add')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(const ValueKey('pin-builder-save'))).dy, lessThanOrEqualTo(900 - 360));
  });
}
