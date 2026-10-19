import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/long_press_repeater.dart';

/// 1.0 M2: holding a repeat button (the viewer's page buttons, the feed's
/// scroll buttons, number steppers) and letting go moved one more time after
/// the finger was lifted, and after onStop had already run: the tick that was
/// waiting when the press ended still called onStart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  Future<void> pumpRepeater(WidgetTester tester, {required void Function() onStart, required void Function() onStop}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: LongPressRepeater(
            onStart: () async => onStart(),
            onStop: () async => onStop(),
            tick: 100,
            child: Container(width: 100, height: 100, color: Colors.red),
          ),
        ),
      ),
    );
  }

  testWidgets('nothing repeats after the finger is lifted', (tester) async {
    int calls = 0;
    int callsAtStop = -1;
    await pumpRepeater(tester, onStart: () => calls++, onStop: () => callsAtStop = calls);

    final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byType(LongPressRepeater)));
    await tester.pump(kLongPressTimeout);
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 3, reason: 'one action per 100 ms tick while held');

    await gesture.up();
    await tester.pump();
    expect(callsAtStop, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3, reason: 'the tick that was waiting when the press ended must not fire');
  });

  testWidgets('a long press let go before the first tick still acts once, as before', (tester) async {
    int calls = 0;
    await pumpRepeater(tester, onStart: () => calls++, onStop: () {});

    final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byType(LongPressRepeater)));
    await tester.pump(kLongPressTimeout);
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });
}
