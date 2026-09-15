import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/instant_page_swipe.dart';

/// r53: the viewer changed pages with a slide (the page shifted by half the
/// drag, a spring settle, 100 ms cross-fades), which the r52 thumbnail cover
/// made visible. Swipes now jump straight to the next page: the page never
/// follows the finger (Modular UI).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
  });

  test('a swipe decides its direction: a short distance or a flick; swipe left or up is the next page', () {
    expect(InstantPageSwipe.stepFor(offset: -10, velocity: 0), 0, reason: 'a small wobble is not a swipe');
    expect(InstantPageSwipe.stepFor(offset: -60, velocity: 0), 1);
    expect(InstantPageSwipe.stepFor(offset: 60, velocity: 0), -1);
    expect(InstantPageSwipe.stepFor(offset: -20, velocity: -900), 1, reason: 'a flick');
    expect(InstantPageSwipe.stepFor(offset: 20, velocity: 900), -1);
    expect(InstantPageSwipe.stepFor(offset: -20, velocity: 900), 0, reason: 'a flick back cancels');
    expect(ModularUi.all, contains(ModularUi.viewerInstantPageSwipe));
    expect(ModularUi.isOn(ModularUi.viewerInstantPageSwipe), isTrue);
  });

  test('one page per gesture, as soon as the swipe is clear; nothing while blocked (a zoomed image pans)', () {
    final List<int> steps = [];
    bool blocked = false;
    final InstantPageSwipe swipe = InstantPageSwipe(onStep: steps.add, isBlocked: () => blocked);

    swipe.start();
    swipe.update(-30);
    expect(steps, isEmpty);
    swipe.update(-30);
    expect(steps, [1], reason: 'jumps during the drag, not at the end');
    swipe.update(-200);
    swipe.end(-1500);
    expect(steps, [1], reason: 'the rest of the gesture does nothing');

    swipe.start();
    swipe.update(12);
    swipe.end(1200);
    expect(steps, [1, -1], reason: 'a short flick jumps when it ends');

    blocked = true;
    swipe.start();
    swipe.update(-300);
    swipe.end(-2000);
    expect(steps, [1, -1]);
  });

  testWidgets('a pager driven by it lands on the next page in one frame, without sliding', (tester) async {
    final PageController controller = PageController();
    addTearDown(controller.dispose);
    final InstantPageSwipe swipe = InstantPageSwipe(
      onStep: (step) => controller.jumpToPage((controller.page!.round() + step).clamp(0, 2)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onHorizontalDragStart: (_) => swipe.start(),
          onHorizontalDragUpdate: (d) => swipe.update(d.primaryDelta ?? 0),
          onHorizontalDragEnd: (d) => swipe.end(d.primaryVelocity ?? 0),
          child: PageView(
            controller: controller,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (int i = 0; i < 3; i++) Center(child: Text('page $i'))],
          ),
        ),
      ),
    );
    await tester.drag(find.text('page 0'), const Offset(-120, 0));
    await tester.pump();
    expect(controller.page, 1.0, reason: 'no in-between offsets: the page did not follow the finger');
    expect(find.text('page 1'), findsOneWidget);
  });
}
