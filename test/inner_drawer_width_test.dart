import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/ui/inner_drawer.dart';

/// 1.0 M2: the drawer re-measures itself after a frame in which the screen
/// size or orientation changed. That callback force-unwrapped the drawer's
/// context before asking whether the drawer was still there, so a drawer
/// removed in that same frame threw a null-check error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a drawer removed in the frame its width changed does not throw', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ValueNotifier<double> width = ValueNotifier(800);
    addTearDown(width.dispose);
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            cacheExtent: 0,
            children: [
              SizedBox(
                height: 600,
                child: ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (context, w, _) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: Size(w, 600)),
                    child: const InnerDrawer(
                      leftChild: SizedBox.expand(),
                      scaffold: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // One frame: the size changes (the drawer rebuilds and schedules its
    // re-measure) and the drawer leaves the tree (scrolled out of the list).
    width.value = 700;
    scroll.jumpTo(3000);
    await tester.pump();
    expect(find.byType(InnerDrawer), findsNothing, reason: 'the drawer left the tree in that frame');
    expect(tester.takeException(), isNull);
  });
}
