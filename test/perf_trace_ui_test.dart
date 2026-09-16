import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// A widget that reports its own life to the trace, the way the app's heavy
/// widgets do (r67).
class _Traced extends StatefulWidget {
  const _Traced();

  @override
  State<_Traced> createState() => _TracedState();
}

class _TracedState extends State<_Traced> with TraceLifecycle {
  @override
  Widget build(BuildContext context) {
    PerfTrace.instance.built('Traced');
    return const SizedBox(width: 10, height: 10);
  }
}

/// r67: the trace also records what the user did and what the UI did about
/// it - taps and swipes with their direction, scrolls with axis and depth,
/// which widgets were created and disposed and how often they were rebuilt -
/// all on the same timeline as the frames, so "what triggered this?" can be
/// read off the report.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PerfTrace.instance.clearForTests);

  test('the timeline is long enough for gestures and scrolls to fit', () {
    expect(PerfTrace.maxEvents, greaterThanOrEqualTo(2000));
  });

  test('builds are counted per widget, only while recording', () {
    final PerfTrace t = PerfTrace.instance;
    t.built('DoujinListCard');
    expect(t.builds, isEmpty, reason: 'not recording');

    t.start();
    t.built('DoujinListCard');
    t.built('DoujinListCard');
    t.built('TagView');
    expect(t.builds['DoujinListCard'], 2);
    expect(t.builds['TagView'], 1);
    expect(t.report(), contains('WIDGET BUILDS'));
    expect(t.report(), contains('DoujinListCard × 2'));
  });

  test('widgets created and disposed land on the timeline and in the counts', () {
    final PerfTrace t = PerfTrace.instance..start();
    t.lifecycle('MediaKitPlayerView', alive: true);
    t.lifecycle('MediaKitPlayerView', alive: true);
    t.lifecycle('MediaKitPlayerView', alive: false);

    expect(t.counts['widget.init'], 2);
    expect(t.counts['widget.dispose'], 1);
    expect(t.events.map((e) => '${e.kind} ${e.detail}'), [
      'widget.init MediaKitPlayerView',
      'widget.init MediaKitPlayerView',
      'widget.dispose MediaKitPlayerView',
    ]);
    expect(t.report(), contains('WIDGETS ALIVE'));
    expect(t.report(), contains('MediaKitPlayerView: 2 created, 1 disposed, 1 alive'));
  });

  testWidgets('a widget with the lifecycle mixin reports itself, and its builds are counted', (tester) async {
    final PerfTrace t = PerfTrace.instance..start();

    await tester.pumpWidget(const MaterialApp(home: _Traced()));
    expect(t.counts['widget.init'], 1);
    expect(t.events.last.detail, '_TracedState');
    expect(t.builds['Traced'], 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(t.counts['widget.dispose'], 1);
  });

  group('the gesture layer', () {
    Future<PerfTrace> pumpLayer(WidgetTester tester, {Widget? child}) async {
      final PerfTrace t = PerfTrace.instance..start();
      await tester.pumpWidget(
        MaterialApp(
          home: PerfTraceGestureLayer(
            child: child ??
                ListView(
                  key: const ValueKey('list'),
                  children: [for (int i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i'))],
                ),
          ),
        ),
      );
      return t;
    }

    testWidgets('a tap is a tap', (tester) async {
      final PerfTrace t = await pumpLayer(tester);
      await tester.tap(find.text('row 3'));
      await tester.pump();
      expect(t.counts['ui.tap'], 1);
    });

    testWidgets('a swipe says which way it went', (tester) async {
      final PerfTrace t = await pumpLayer(tester, child: const SizedBox.expand());
      await tester.drag(find.byType(SizedBox), const Offset(-200, 0));
      await tester.pump();
      await tester.drag(find.byType(SizedBox), const Offset(0, 180));
      await tester.pump();

      final List<String?> swipes = t.events.where((e) => e.kind == 'ui.swipe').map((e) => e.detail).toList();
      expect(swipes, ['left', 'down']);
      expect(t.counts['ui.tap'], isNull, reason: 'a drag is not a tap');
    });

    testWidgets('a scroll is recorded once, with its axis and depth', (tester) async {
      final PerfTrace t = await pumpLayer(tester);
      await tester.drag(find.byKey(const ValueKey('list')), const Offset(0, -300));
      await tester.pumpAndSettle();

      final List<TraceEvent> scrolls = t.events.where((e) => e.kind == 'ui.scroll').toList();
      expect(scrolls.length, 1, reason: 'one line per scroll, not one per frame');
      expect(scrolls.single.detail, contains('vertical'));
      expect(scrolls.single.detail, contains('depth 0'));
    });
  });
}
