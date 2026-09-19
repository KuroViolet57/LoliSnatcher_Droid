import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/navigation_trace.dart';

/// r77: twice on 19 Sep the viewer closed right after a tap on a tag's
/// preview icon, and the log could not say what closed it. Every viewer
/// close now logs the code path that closed it, and every system Back and
/// Back gesture is logged, so the next log names the cause.

final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

void closeTheViewerFromTheBackArrow() => _nav.currentState!.pop();

void main() {
  late List<String> lines;

  setUp(() {
    lines = [];
    NavigationTrace.log = lines.add;
  });

  tearDown(NavigationTrace.resetForTests);

  Future<void> app(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _nav,
        navigatorObservers: [ViewerCloseObserver()],
        home: const Scaffold(body: Text('feed')),
      ),
    );
    unawaited(_nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'viewer'),
        builder: (_) => const Scaffold(body: Text('viewer')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a viewer closed by code logs the code path that closed it', (tester) async {
    await app(tester);
    closeTheViewerFromTheBackArrow();
    await tester.pumpAndSettle();
    final String line = lines.singleWhere((l) => l.startsWith('viewer closed'));
    expect(line, contains('closeTheViewerFromTheBackArrow'));
    expect(line, isNot(contains('package:flutter/')), reason: 'framework frames are left out');
  });

  testWidgets('other pages closing log nothing', (tester) async {
    await app(tester);
    unawaited(_nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('settings'))));
    await tester.pumpAndSettle();
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(lines.where((l) => l.startsWith('viewer closed')), isEmpty);
  });

  testWidgets('a system Back is logged with the page it reached, and the viewer close after it', (tester) async {
    // Added before the app, like BackGestureLogger.attach() in main().
    final BackGestureLogger backs = BackGestureLogger();
    WidgetsBinding.instance.addObserver(backs);
    await app(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    WidgetsBinding.instance.removeObserver(backs);
    expect(lines.first, 'Back pressed (system)');
    expect(lines.where((l) => l.startsWith('viewer closed')), hasLength(1));
    expect(lines.singleWhere((l) => l.startsWith('viewer closed')), isNot(contains('asynchronous suspension')));
  });
}
