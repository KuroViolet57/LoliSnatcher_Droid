import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/status_bar_inset.dart';

/// r52: with the status bar hidden, the keyboard covered bottom sheets. The
/// app's page tree lives in an Overlay entry built once, so a MediaQuery made
/// in the app builder kept the insets of the first frame. The hidden status
/// bar layout is now a widget that reads the insets where it is built.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
    SettingsHandler.instance.hideStatusBar = true;
    ModularUi.save = () async {};
  });

  tearDown(() => SettingsHandler.instance.hideStatusBar = false);

  testWidgets('a page tree built once still sees the keyboard and keeps the status bar space', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.reset);
    double keyboard = -1;
    double top = -1;
    await tester.pumpWidget(
      MaterialApp(
        // The way main.dart builds it: the entry is only read on the first frame.
        builder: (context, child) => Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => HiddenStatusBarInsets(
                child: Builder(
                  builder: (context) {
                    keyboard = MediaQuery.viewInsetsOf(context).bottom;
                    top = MediaQuery.paddingOf(context).top;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ],
        ),
        home: const SizedBox(),
      ),
    );
    expect((keyboard, top), (0.0, 40.0));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(keyboard, 300);

    ModularUi.set(ModularUi.appDrawUnderHiddenStatusBar, true);
    await tester.pump();
    expect(top, 0, reason: 'the old full-height layout, switched on');
  });
}
