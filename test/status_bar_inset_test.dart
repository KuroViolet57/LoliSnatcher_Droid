import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/status_bar_inset.dart';

/// r50: with the status bar hidden, the app used to strip the top inset, so
/// every top bar's back arrow sat in the edge Android watches for the swipe
/// that brings the status bar back — taps there were often lost. The inset
/// is now kept (the old full-height layout is a Modular UI switch).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
  });

  const MediaQueryData hidden = MediaQueryData(viewPadding: EdgeInsets.only(top: 40, bottom: 24), padding: EdgeInsets.only(bottom: 24));

  test('a hidden status bar keeps its space at the top, so top bars stay clear of the swipe edge', () {
    final MediaQueryData kept = StatusBarInset.apply(hidden, hideStatusBar: true, drawUnder: false);
    expect(kept.padding.top, 40);
    expect(kept.padding.bottom, 24);
  });

  test('the old layout, switched on, draws into the top edge', () {
    final MediaQueryData under = StatusBarInset.apply(hidden, hideStatusBar: true, drawUnder: true);
    expect((under.padding.top, under.viewPadding.top), (0.0, 0.0));
  });

  test('a visible status bar is left as the system reports it; the switch exists and is off', () {
    const MediaQueryData shown = MediaQueryData(viewPadding: EdgeInsets.only(top: 40), padding: EdgeInsets.only(top: 40));
    expect(StatusBarInset.apply(shown, hideStatusBar: false, drawUnder: true), shown);
    expect(ModularUi.all, contains(ModularUi.appDrawUnderHiddenStatusBar));
    expect(ModularUi.isOn(ModularUi.appDrawUnderHiddenStatusBar), isFalse);
  });
}
