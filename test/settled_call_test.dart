import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/settled_call.dart';

/// r54: each post's details panel fetched the post page as soon as it was
/// built, even for posts swiped straight past; with instant swipes that tripped
/// rule34.xxx's rate limit (429 and its CAPTCHA page), and the answer arriving
/// after the panel was gone threw "Null check operator used on a null value".
/// The first load now waits until the post has been on screen for a moment.
void main() {
  testWidgets('the call runs once the post has stayed on screen for the delay', (tester) async {
    await tester.pumpWidget(const SizedBox());
    int runs = 0;
    final SettledCall call = SettledCall(SettledCall.itemDataDelay);
    call.schedule(() => runs++);
    await tester.pump(SettledCall.itemDataDelay - const Duration(milliseconds: 1));
    expect(runs, 0);
    expect(call.isPending, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(runs, 1);
    expect(call.isPending, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(runs, 1, reason: 'once');
  });

  testWidgets('a post swiped past before the delay sends nothing (the panel cancels it on dispose)', (tester) async {
    await tester.pumpWidget(const SizedBox());
    int runs = 0;
    final SettledCall call = SettledCall(SettledCall.itemDataDelay);
    call.schedule(() => runs++);
    await tester.pump(const Duration(milliseconds: 300));
    call.cancel();
    await tester.pump(const Duration(seconds: 2));
    expect(runs, 0);
  });

  testWidgets('scheduling again replaces the pending call', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final List<String> runs = [];
    final SettledCall call = SettledCall(const Duration(milliseconds: 500));
    call.schedule(() => runs.add('first'));
    await tester.pump(const Duration(milliseconds: 400));
    call.schedule(() => runs.add('second'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(runs, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(runs, ['second']);
    expect(SettledCall.itemDataDelay, const Duration(milliseconds: 800));
  });
}
