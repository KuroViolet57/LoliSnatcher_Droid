import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/navigation_trace.dart';
import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// r77: twice on 19 Sep the viewer closed right after a tap on a tag's
/// preview icon, and the log could not say what closed it.
///
/// r79: r77 read the closer off the stack. In a release build that names the
/// wrong function - identical little closures share one copy of machine code,
/// so on 20 Sep all 34 closes named the Google Drive dialog's OK button,
/// including every tap on the back arrow. Each of the app's own closes now
/// says why it closes; a close nobody marked says so, and a system Back or
/// Back gesture names itself.

final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

void main() {
  late List<String> lines;
  late DateTime now;

  setUp(() {
    lines = [];
    now = DateTime(2026, 9, 21, 12);
    NavigationTrace.log = lines.add;
    NavigationTrace.now = () => now;
  });

  tearDown(NavigationTrace.resetForTests);

  Iterable<String> closes() => lines.where((l) => l.startsWith('viewer closed'));

  Future<void> app(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _nav,
        navigatorObservers: [ViewerCloseObserver()],
        home: const Scaffold(body: Text('feed')),
      ),
    );
    unawaited(
      _nav.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: ViewerCloseObserver.viewerRoute),
          builder: (_) => const Scaffold(body: Text('viewer')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pushDialog(WidgetTester tester, String name) async {
    unawaited(
      _nav.currentState!.push(
        DialogRoute<void>(
          context: _nav.currentContext!,
          settings: RouteSettings(name: name),
          builder: (_) => Text(name),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("the app's own close says what closed it", (tester) async {
    await app(tester);
    NavigationTrace.closing('back arrow', () => _nav.currentState!.pop());
    await tester.pumpAndSettle();
    expect(closes(), ['viewer closed by: back arrow']);
  });

  testWidgets('closing through a dialog down to the feed logs one line, for the viewer', (tester) async {
    await app(tester);
    await pushDialog(tester, 'some dialog');
    NavigationTrace.closing('tab list: switched tab', () => _nav.currentState!.popUntil((r) => r.isFirst));
    await tester.pumpAndSettle();
    expect(closes(), ['viewer closed by: tab list: switched tab']);
  });

  testWidgets('a reason does not outlive its own close', (tester) async {
    await app(tester);
    NavigationTrace.closing('share cancelled', () {});
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(closes().single, startsWith('viewer closed by: unmarked'));
  });

  testWidgets('a close nobody marked says so', (tester) async {
    await app(tester);
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(closes().single, startsWith('viewer closed by: unmarked'));
  });

  testWidgets('a system Back names itself', (tester) async {
    // Added before the app, like BackGestureLogger.attach() in main().
    final BackGestureLogger backs = BackGestureLogger();
    WidgetsBinding.instance.addObserver(backs);
    addTearDown(() => WidgetsBinding.instance.removeObserver(backs));
    await app(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(lines.first, 'Back pressed (system)');
    expect(closes(), ['viewer closed by: Back button (system)']);
  });

  testWidgets('a system Back long ago does not label a later close', (tester) async {
    final BackGestureLogger backs = BackGestureLogger();
    await app(tester);
    await backs.didPopRoute();
    now = now.add(const Duration(seconds: 3));
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(closes().single, startsWith('viewer closed by: unmarked'));
  });

  testWidgets('a Back gesture names itself, even though its commit never passes the system Back', (tester) async {
    final BackGestureLogger backs = BackGestureLogger();
    await app(tester);
    backs.handleStartBackGesture(
      PredictiveBackEvent.fromMap(const <String?, Object?>{
        'touchOffset': <double>[0, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      }),
    );
    now = now.add(const Duration(seconds: 2));
    // The app's predictive-back detector commits with a plain pop.
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(lines.first, 'Back gesture started (left edge)');
    expect(closes(), ['viewer closed by: Back gesture (system)']);
  });

  testWidgets('the close goes on the trace timeline with its reason', (tester) async {
    PerfTrace.instance.start();
    addTearDown(PerfTrace.instance.stop);
    await app(tester);
    NavigationTrace.closing('swipe down', () => _nav.currentState!.pop());
    await tester.pumpAndSettle();
    expect(
      PerfTrace.instance.events.where((e) => e.kind == 'viewer.close').map((e) => e.detail),
      ['swipe down'],
    );
  });

  testWidgets('other pages closing log nothing', (tester) async {
    await app(tester);
    unawaited(_nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('settings'))));
    await tester.pumpAndSettle();
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(closes(), isEmpty);
  });

  group('closes that could take the viewer with them', () {
    testWidgets("the tag previews' breadcrumb stops at the viewer when its tag's dialog is already gone", (tester) async {
      await app(tester);
      // The chain a-then-b: opening b closed a's dialog first.
      await pushDialog(tester, 'tagDialog/b');
      _nav.currentState!.popUntil((r) => NavigationTrace.tagDialogOrViewer(r, 'a'));
      await tester.pumpAndSettle();
      expect(find.text('viewer'), findsOneWidget, reason: 'r77 fell through to the feed here');
      expect(closes(), isEmpty);
    });

    testWidgets('the breadcrumb still closes the dialogs down to its own tag', (tester) async {
      await app(tester);
      await pushDialog(tester, 'tagDialog/a');
      await pushDialog(tester, 'tagDialog/b');
      _nav.currentState!.popUntil((r) => NavigationTrace.tagDialogOrViewer(r, 'a'));
      await tester.pumpAndSettle();
      expect(find.text('tagDialog/a'), findsOneWidget);
      expect(find.text('tagDialog/b'), findsNothing);
      expect(closes(), isEmpty);
    });

    testWidgets('a dialog that asks to close after it has already gone closes nothing', (tester) async {
      await app(tester);
      late BuildContext dialogContext;
      unawaited(
        showDialog<void>(
          context: _nav.currentContext!,
          builder: (BuildContext ctx) {
            dialogContext = ctx;
            return const Text('snatch dialog');
          },
        ),
      );
      await tester.pumpAndSettle();
      // Dismissed while its action was still waiting (a tap outside, a Back).
      _nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(NavigationTrace.popIfOnTop(dialogContext, 'snatch dialog'), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('viewer'), findsOneWidget, reason: 'before r79 this pop closed the viewer');
      expect(closes(), isEmpty);
      expect(lines.last, contains('snatch dialog'));
    });

    testWidgets('a dialog still open closes as before', (tester) async {
      await app(tester);
      late BuildContext dialogContext;
      unawaited(
        showDialog<void>(
          context: _nav.currentContext!,
          builder: (BuildContext ctx) {
            dialogContext = ctx;
            return const Text('snatch dialog');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(NavigationTrace.popIfOnTop(dialogContext, 'snatch dialog'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('snatch dialog'), findsNothing);
      expect(find.text('viewer'), findsOneWidget);
    });
  });
}
