import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// r61: the tab manager's "Visited tabs history" would not scroll. Its list
/// sits inside the dialog's own scroll view, and a scrollable inside a
/// scrollable eats the drag: the inner list has nothing to scroll (it is built
/// at full height) and the dialog never moves. The list must leave scrolling
/// to the dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<TabVisit> visits(int count) => [
    for (int i = 0; i < count; i++)
      TabVisit(
        tabId: 'tab$i',
        tags: 'search number $i',
        booruName: 'booru',
        booruType: null,
        visitedAt: DateTime(2026, 9, 16, 12, i % 60),
      ),
  ];

  Future<void> pumpList(WidgetTester tester, List<TabVisit> entries) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // The dialog scrolls its content; the list is inside it.
            child: SizedBox(
              height: 300,
              width: 400,
              child: SingleChildScrollView(
                child: VisitedTabsHistoryList(
                  entries: entries,
                  isStillOpen: (_) => true,
                  booruFor: (_) => null,
                  timeLabel: (_) => 'just now',
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the history scrolls: dragging it reaches entries below the fold', (tester) async {
    await pumpList(tester, visits(40));

    // Every row is laid out; what changes with scrolling is where they sit,
    // so the check is about position, not about being found.
    final double viewportBottom = tester.getRect(find.byType(SingleChildScrollView)).bottom;
    double topOf(String text) => tester.getRect(find.text(text, skipOffstage: false)).top;

    final double firstBefore = topOf('search number 0');
    final double laterBefore = topOf('search number 30');
    expect(firstBefore, lessThan(viewportBottom), reason: 'on screen to start with');
    expect(laterBefore, greaterThan(viewportBottom), reason: 'below the fold to start with');

    await tester.drag(find.text('search number 0'), const Offset(0, -1600));
    await tester.pumpAndSettle();

    expect(
      laterBefore - topOf('search number 30'),
      closeTo(1600, 60),
      reason: 'the drag must scroll the dialog content, not be swallowed by the list',
    );
    expect(topOf('search number 0'), lessThan(firstBefore - 1000), reason: 'the top entry scrolled away');
  });

  testWidgets('the list itself does not scroll, so the dialog around it can', (tester) async {
    await pumpList(tester, visits(40));

    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect(list.physics, isA<NeverScrollableScrollPhysics>());
    expect(list.shrinkWrap, isTrue);
  });

  testWidgets('an empty history says so and needs no scrolling', (tester) async {
    await pumpList(tester, visits(0));
    expect(find.textContaining('No visited tabs yet'), findsOneWidget);
  });
}
