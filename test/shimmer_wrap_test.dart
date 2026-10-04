import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/ui/shimmer_builder.dart';

/// 1.0 M2: ShimmerWrap always built Shimmer(enabled: true), so the shimmer's
/// animation ticked every frame for as long as the feed lived in low
/// performance mode (which passes enabled: false and never mounts a shimmering
/// child that could stop it), and behind the viewer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool animating(WidgetTester tester) =>
      (tester.state<ShimmerState>(find.byType(Shimmer)).shimmerChanges as AnimationController).isAnimating;

  testWidgets('a disabled ShimmerWrap does not run the shimmer animation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShimmerWrap(enabled: false, child: SizedBox.expand())));
    expect(tester.widget<Shimmer>(find.byType(Shimmer)).enabled, isFalse);
    expect(animating(tester), isFalse, reason: 'no ticker every frame when the shimmer is off');
  });

  testWidgets('an enabled ShimmerWrap animates, and stops when it is switched off', (tester) async {
    Widget wrap(bool enabled) => MaterialApp(home: ShimmerWrap(enabled: enabled, child: const SizedBox.expand()));
    await tester.pumpWidget(wrap(true));
    expect(animating(tester), isTrue);
    await tester.pumpWidget(wrap(false));
    expect(animating(tester), isFalse, reason: 'the viewer opened over the feed: nothing is loading, so it stops');
    await tester.pumpWidget(wrap(true));
    expect(animating(tester), isTrue, reason: 'back on the feed');
  });

  testWidgets('a loading card still shimmers under a disabled wrap, as before', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShimmerWrap(enabled: false, child: SizedBox(width: 50, height: 50, child: ShimmerCard())),
      ),
    );
    expect(animating(tester), isTrue, reason: 'a ShimmerLoading child starts it, whatever enabled says');
  });
}
