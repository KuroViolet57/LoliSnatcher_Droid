import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/picker_watch.dart';

/// r78: "Try it on a picture" could stop for good. If the picker's answer
/// never arrived - which is what the app's old result handling could cause -
/// the button stayed on "Reading…" and every later tap did nothing and wrote
/// nothing to the log. A pick now always ends: with a picture, with nothing,
/// with an error, or given up on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PickerWatch.resetForTests);
  tearDown(PickerWatch.resetForTests);

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
  }

  testWidgets('a picture that comes back is the answer, with how long the picker was open', (tester) async {
    late PickResult<String> res;
    await tester.runAsync(() async {
      res = await PickerWatch.run<String>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'a.jpg';
      });
    });
    expect(res.outcome, PickOutcome.picture);
    expect(res.value, 'a.jpg');
    expect(res.openMs, greaterThan(0));
    expect(res.openFor, endsWith(' s'));
  });

  testWidgets('nothing back is nothing back, not an error', (tester) async {
    late PickResult<String> res;
    await tester.runAsync(() async {
      res = await PickerWatch.run<String>(() async => null);
    });
    expect(res.outcome, PickOutcome.nothing);
    expect(res.value, isNull);
    expect(res.error, isNull);
  });

  testWidgets('a picker that throws keeps its error', (tester) async {
    late PickResult<String> res;
    await tester.runAsync(() async {
      res = await PickerWatch.run<String>(() async => throw StateError('photo picker unavailable'));
    });
    expect(res.outcome, PickOutcome.failed);
    expect(res.error.toString(), contains('photo picker unavailable'));
  });

  testWidgets('a picker that throws before it even starts is a failure, not a crash', (tester) async {
    late PickResult<String> res;
    await tester.runAsync(() async {
      res = await PickerWatch.run<String>(() => throw StateError('no picker at all'));
    });
    expect(res.outcome, PickOutcome.failed);
    expect(res.error.toString(), contains('no picker at all'));
  });

  testWidgets('the picker closed and no answer came: the pick gives up, so the button is free again', (tester) async {
    PickerWatch.afterResume = const Duration(milliseconds: 100);
    final Completer<String?> never = Completer<String?>();
    PickResult<String>? res;
    unawaited(PickerWatch.run<String>(() => never.future).then((r) => res = r));
    await tester.pump();
    await lifecycle(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(res, isNull, reason: 'while the picker is in front we wait, however long it takes');
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 40));
    expect(res, isNull, reason: 'a moment for the answer to arrive after the picker closes');
    await tester.pump(const Duration(milliseconds: 100));
    expect(res!.outcome, PickOutcome.lost);
    expect(res!.reason, contains('closed'));
    expect(res!.openMs, greaterThan(0));
  });

  testWidgets('a picker that never opens anything ends at the backstop', (tester) async {
    PickerWatch.hardLimit = const Duration(milliseconds: 200);
    final Completer<String?> never = Completer<String?>();
    PickResult<String>? res;
    unawaited(PickerWatch.run<String>(() => never.future).then((r) => res = r));
    await tester.pump(const Duration(milliseconds: 100));
    expect(res, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(res!.outcome, PickOutcome.lost);
    expect(res!.reason, contains('no answer'));
  });

  testWidgets('an answer that arrives after we gave up is still handed over', (tester) async {
    PickerWatch.afterResume = const Duration(milliseconds: 50);
    final Completer<String?> answer = Completer<String?>();
    final List<String> afterwards = <String>[];
    PickResult<String>? res;
    unawaited(PickerWatch.run<String>(() => answer.future, onLate: afterwards.add).then((r) => res = r));
    await tester.pump();
    await lifecycle(tester, AppLifecycleState.paused);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(res!.outcome, PickOutcome.lost);
    expect(afterwards, isEmpty);
    answer.complete('b.jpg');
    await tester.pump();
    expect(afterwards, ['b.jpg'], reason: 'the picture is not thrown away');
  });

  testWidgets('nothing is left running after a pick ends', (tester) async {
    PickerWatch.afterResume = const Duration(milliseconds: 50);
    PickerWatch.hardLimit = const Duration(milliseconds: 80);
    late PickResult<String> res;
    await tester.runAsync(() async {
      res = await PickerWatch.run<String>(() async => 'a.jpg');
    });
    expect(res.outcome, PickOutcome.picture);
    // A pending timer or a left-behind observer fails the test here.
    await tester.pump(const Duration(seconds: 1));
  });
}
