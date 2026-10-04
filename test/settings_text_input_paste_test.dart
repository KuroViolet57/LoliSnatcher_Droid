import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';

/// 1.0 M2: a pasteable settings field (API key, user id, proxy, LoliSync IP)
/// read the clipboard on every build, so every keystroke read it again. On
/// Android 12+ each read shows the "pasted from your clipboard" toast, and it
/// reads whatever is there (a password manager's copy included). The field
/// reads it once when it gets focus, and Paste reads what is there now.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  testWidgets('typing in a pasteable field does not read the clipboard again', (tester) async {
    int reads = 0;
    String clipboard = 'first';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return <String, dynamic>{'text': clipboard};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTextInput(controller: controller, title: 'API key', pasteable: true),
        ),
      ),
    );
    expect(reads, 0, reason: 'nothing is read before the field has focus');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(); // the read answers
    expect(reads, 1, reason: 'focus reads the clipboard once, to know whether Paste can show');
    expect(find.byKey(const Key('paste-button')), findsOneWidget);

    for (final String typed in ['a', 'ab', 'abc', 'abcd']) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
    }
    expect(reads, 1, reason: 'keystrokes must not read the clipboard');

    // What is on the clipboard when Paste is pressed is what goes in.
    clipboard = 'second';
    await tester.tap(find.byKey(const Key('paste-button')));
    await tester.pump();
    await tester.pump();
    expect(controller.text, 'second');
  });
}
