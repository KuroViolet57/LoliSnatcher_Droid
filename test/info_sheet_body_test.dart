import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/viewer/logic/info_sheet_body.dart';
import 'package:lolisnatcher/features/viewer/ui/info/item_info_bottom_sheet.dart';

const double _openSize = 2 / 3;

class _Harness {
  final DraggableScrollableController controller = DraggableScrollableController();
  final ValueNotifier<double> extent = ValueNotifier(0);
  final InfoSheetContentGate gate = InfoSheetContentGate();
  int liveBuilds = 0;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            InfoSheetFrame(
              sheetController: controller,
              extentNotifier: extent,
              gate: gate,
              openSize: _openSize,
              liveBuilder: (context, scrollController) {
                liveBuilds++;
                // Stands in for TagView: its own scrollable on the sheet's
                // controller, like the real one.
                return CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverList(
                      delegate: SliverChildListDelegate([
                        for (int i = 0; i < 40; i++) SizedBox(height: 40, child: Text('tag $i')),
                      ]),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('InfoSheetContentGate', () {
    test('a shut sheet does not build the tag view until asked', () {
      final gate = InfoSheetContentGate();
      expect(gate.live.value, isFalse);
      gate.onExtent(0);
      expect(gate.live.value, isFalse);
      gate.requestOpen();
      expect(gate.live.value, isTrue);
    });

    test('a drag above 0 makes the content live', () {
      final gate = InfoSheetContentGate()..onExtent(0.01);
      expect(gate.live.value, isTrue);
    });

    test('closing keeps the tag view for the same post', () {
      final gate = InfoSheetContentGate()
        ..requestOpen()
        ..onExtent(0);
      expect(gate.live.value, isTrue);
    });

    test('a new post drops the tag view only while the sheet is shut', () {
      final gate = InfoSheetContentGate()..requestOpen();
      gate.onPageChanged(_openSize);
      expect(gate.live.value, isTrue, reason: 'open sheet follows the new post');
      gate.onPageChanged(0);
      expect(gate.live.value, isFalse, reason: 'shut sheet must not load the next post');
    });

    test('the peek zone ends at 0.06', () {
      expect(infoSheetInPeekZone(0), isTrue);
      expect(infoSheetInPeekZone(0.059), isTrue);
      expect(infoSheetInPeekZone(0.06), isFalse);
      expect(infoSheetInPeekZone(_openSize), isFalse);
    });
  });

  group('InfoSheetFrame', () {
    testWidgets('one tap on the info button opens the sheet fully', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());
      expect(h.controller.isAttached, isTrue);

      openInfoSheet(controller: h.controller, gate: h.gate, size: _openSize);
      await tester.pumpAndSettle();

      expect(h.controller.size, closeTo(_openSize, 0.001));
    });

    testWidgets('the content builds a bounded number of times while opening', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());

      openInfoSheet(controller: h.controller, gate: h.gate, size: _openSize);
      // 300 ms at 60 Hz is ~18 frames; pump them one by one.
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(h.controller.size, closeTo(_openSize, 0.001));
      expect(h.liveBuilds, lessThanOrEqualTo(2), reason: 'built per frame: ${h.liveBuilds}');
    });

    testWidgets('a drag from shut (swipe-up path) then a close keeps the content and reopens fully', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.build());

      // What the swipe-up listener does: request content, then jumpTo per move.
      h.gate.requestOpen();
      for (double e = 0.02; e <= 0.5; e += 0.02) {
        h.controller.jumpTo(e);
        await tester.pump(const Duration(milliseconds: 8));
      }
      h.controller.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      await tester.pumpAndSettle();
      expect(h.controller.size, closeTo(0, 0.001));
      expect(h.gate.live.value, isTrue);

      final int before = h.liveBuilds;
      openInfoSheet(controller: h.controller, gate: h.gate, size: _openSize);
      await tester.pumpAndSettle();
      expect(h.controller.size, closeTo(_openSize, 0.001));
      expect(h.liveBuilds - before, lessThanOrEqualTo(1));
    });
  });
}
