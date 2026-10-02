import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/modular_ui_page.dart';

/// r41: Modular UI. A part of the interface the user asks to remove becomes a
/// switch in its own settings section instead, so it can come back with its
/// function intact. The first ones: the search window's History, Pinned tags
/// and Popular tags, off by default for every source.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  int saves = 0;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('modular_ui');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.modularUi.clear();
    saves = 0;
    ModularUi.save = () async => saves++;
  });

  tearDown(() {
    SettingsHandler.instance.modularUi.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the search window starts without History, Pinned tags and Popular tags; every switch says what it hides', () {
    for (final ModularUiToggle t in [ModularUi.searchHistory, ModularUi.searchPinned, ModularUi.searchPopular]) {
      expect(ModularUi.isOn(t), isFalse, reason: t.title);
      expect(ModularUi.all, contains(t));
    }
    expect(ModularUi.all.map((t) => t.key).toSet(), hasLength(ModularUi.all.length), reason: 'one key per switch');
    for (final ModularUiToggle t in ModularUi.all) {
      expect(t.title, isNotEmpty);
      expect(t.area, isNotEmpty);
      expect(t.description.length, greaterThan(20), reason: 'a description, not a label: ${t.title}');
    }
  });

  test('a switch is kept in the settings file and read back; a switch back to its default is not stored', () async {
    await ModularUi.set(ModularUi.searchHistory, true);
    expect(ModularUi.isOn(ModularUi.searchHistory), isTrue);
    expect(saves, 1);
    final Map<String, dynamic> json = SettingsHandler.instance.toJson();
    expect(json['modularUi'], {'search.history': true});
    SettingsHandler.instance.modularUi.clear();
    expect(ModularUi.isOn(ModularUi.searchHistory), isFalse);
    SettingsHandler.instance.modularUi.addAll(ModularUi.parse(json['modularUi']));
    expect(ModularUi.isOn(ModularUi.searchHistory), isTrue);
    expect(ModularUi.parse({'search.pinned': 'yes', 3: true, 'search.popular': false}), {'search.popular': false});
    expect(ModularUi.parse(null), isEmpty);
    await ModularUi.set(ModularUi.searchHistory, false);
    expect(SettingsHandler.instance.toJson()['modularUi'], isEmpty);
  });

  testWidgets('the Modular UI page: one switch per part, grouped by where it is; a tap turns it on', (tester) async {
    await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: ModularUiPage())));
    await tester.pump();
    expect(find.text('Search window'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Pinned tags'), findsOneWidget);
    expect(find.text('Popular tags'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('modular-ui-search.history')));
    await tester.pump();
    expect(ModularUi.isOn(ModularUi.searchHistory), isTrue);
    expect(saves, 1);
  });
}
