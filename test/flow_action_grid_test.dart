import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/flow_action_grid.dart';

/// r79: in a post's info sheet, "Find this post elsewhere", "Find posts like
/// this (new board)", Comments, "Posts like this" and "Recommend more like
/// this" were full-width rows under the Favorite / Save / Collect / Details
/// block, taking half a screen. They are now buttons in that block - icon and
/// one word, like the other four - behind a Modular UI switch that brings the
/// old rows back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which buttons a post gets', () {
    test('a booru post with everything gets all five, in this order', () {
      expect(
        FlowExtras.of(doujin: false, comments: true, hasPicture: true, recommend: true),
        [FlowExtra.comments, FlowExtra.elsewhere, FlowExtra.board, FlowExtra.similar, FlowExtra.recommend],
      );
    });

    test('a doujin post keeps only Comments - the other four were booru-only rows', () {
      expect(FlowExtras.of(doujin: true, comments: true, hasPicture: true, recommend: true), [FlowExtra.comments]);
      expect(FlowExtras.of(doujin: true, comments: false, hasPicture: true, recommend: true), isEmpty);
    });

    test("each button keeps its old row's condition", () {
      expect(
        FlowExtras.of(doujin: false, comments: false, hasPicture: false, recommend: false),
        [FlowExtra.elsewhere, FlowExtra.board],
        reason: 'no comments support, no picture for Similar, no seeds for Recommend',
      );
    });

    test('one word each', () {
      for (final FlowExtra e in FlowExtra.values) {
        expect(FlowExtras.labelOf(e).contains(' '), isFalse, reason: e.name);
      }
      expect(FlowExtra.values.map(FlowExtras.labelOf), ['Comments', 'Elsewhere', 'Board', 'Similar', 'Recommend']);
    });
  });

  group('the block', () {
    test('up to five a row, never more than two rows, tiles of one width', () {
      expect(FlowActionGrid.shapeFor(4), (1, 4), reason: 'as today');
      expect(FlowActionGrid.shapeFor(5), (1, 5), reason: 'a doujin post with comments');
      expect(FlowActionGrid.shapeFor(6), (2, 3));
      expect(FlowActionGrid.shapeFor(7), (2, 4));
      expect(FlowActionGrid.shapeFor(8), (2, 4));
      expect(FlowActionGrid.shapeFor(9), (2, 5));
    });

    List<Widget> nine(List<String> tapped) => [
      for (final String l in ['Favorite', 'Save', 'Collect', 'Details', 'Comments', 'Elsewhere', 'Board', 'Similar', 'Recommend'])
        FlowActionTile(key: ValueKey('flow-$l'), icon: Symbols.star_rounded, label: l, onTap: () => tapped.add(l)),
    ];

    for (final double width in [412, 330]) {
      testWidgets('nine buttons fit at $width dp wide: no overflow, every one tappable', (tester) async {
        tester.view.physicalSize = Size(width * 2, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final List<String> tapped = [];
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: FlowActionGrid(tiles: nine(tapped)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final String l in ['Favorite', 'Recommend', 'Elsewhere', 'Comments']) {
          expect(find.text(l), findsOneWidget);
          expect(tester.getSize(find.byKey(ValueKey('flow-$l'))).width, greaterThanOrEqualTo(48), reason: 'a touch target');
        }
        final double top = tester.getTopLeft(find.byKey(const ValueKey('flow-Favorite'))).dy;
        expect(tester.getTopLeft(find.byKey(const ValueKey('flow-Comments'))).dy, top, reason: 'row 1 ends with Comments');
        expect(tester.getTopLeft(find.byKey(const ValueKey('flow-Elsewhere'))).dy, greaterThan(top), reason: 'row 2');
        expect(
          tester.getSize(find.byKey(const ValueKey('flow-Recommend'))).width,
          moreOrLessEquals(tester.getSize(find.byKey(const ValueKey('flow-Favorite'))).width, epsilon: 0.5),
          reason: 'the half-empty last row keeps the same tile width',
        );
        await tester.tap(find.byKey(const ValueKey('flow-Recommend')));
        await tester.tap(find.byKey(const ValueKey('flow-Board')));
        expect(tapped, ['Recommend', 'Board']);
      });
    }

    testWidgets('a larger system font still fits the longest word', (tester) async {
      tester.view.physicalSize = const Size(660, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(330, 800), textScaler: TextScaler.linear(1.3)),
            child: Scaffold(body: FlowActionGrid(tiles: nine([]))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Recommend'), findsOneWidget);
    });

    testWidgets('four buttons are one row, as before', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FlowActionGrid(tiles: nine([]).take(4).toList()))));
      final double top = tester.getTopLeft(find.byKey(const ValueKey('flow-Favorite'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('flow-Details'))).dy, top);
    });
  });

  group('the Modular UI switch', () {
    late Directory tempDir;

    setUp(() {
      SettingsHandler.register();
      tempDir = Directory.systemTemp.createTempSync('flow_actions');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      SettingsHandler.instance.modularUi.clear();
    });

    tearDown(() {
      SettingsHandler.instance.modularUi.clear();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('is on by default, in the Viewer area, and listed with the others', () {
      expect(ModularUi.isOn(ModularUi.viewerPostActionsAsButtons), isTrue);
      expect(ModularUi.viewerPostActionsAsButtons.area, ModularUi.viewerArea);
      expect(ModularUi.all, contains(ModularUi.viewerPostActionsAsButtons));
    });
  });
}
