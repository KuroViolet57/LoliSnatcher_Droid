import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/ui/inner_drawer.dart';

/// The home drawer's back entry. A closed drawer must not look like a page
/// the predictive back gesture can pop. An open drawer must.
void main() {
  testWidgets('a closed drawer is not a back destination, and an open one is', (tester) async {
    Future<void> pump(double radius) {
      return tester.pumpWidget(
        MaterialApp(
          home: InnerDrawer(
            borderRadius: radius,
            leftChild: const Text('menu'),
            scaffold: const Scaffold(body: Text('feed')),
          ),
        ),
      );
    }

    await pump(0);
    await pump(12);

    final NavigatorState nav = tester.state<NavigatorState>(find.byType(Navigator));
    expect(nav.canPop(), isFalse, reason: 'a rebuild of the closed drawer must not add a back entry');

    tester.state<InnerDrawerState>(find.byType(InnerDrawer)).open(direction: InnerDrawerDirection.start);
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue, reason: 'back closes the open drawer instead of leaving the app');

    nav.pop();
    await tester.pumpAndSettle();
    expect(nav.canPop(), isFalse);
    expect(find.text('feed'), findsOneWidget, reason: 'closing the drawer does not pop the home page');
  });
}
