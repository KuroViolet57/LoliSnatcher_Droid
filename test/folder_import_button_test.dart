import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/encoder_handler.dart';
import 'package:lolisnatcher/features/recommender/ui/recommendations_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a folder import does not offer Download again', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SettingsHandler.register();
    SettingsHandler.instance
      ..dbEnabled = false
      ..encoderModel = 'files:wd-local';
    EncoderHandler.unregister();
    EncoderHandler.register();
    addTearDown(EncoderHandler.unregister);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EncoderModelSection(onChanged: () async {})),
      ),
    );

    expect(find.text('Imported from a folder'), findsOneWidget);
    expect(find.text('Download again'), findsNothing);
    final FilledButton button = tester.widget<FilledButton>(find.byKey(const ValueKey('encoder-download')));
    expect(button.onPressed, isNull);
    expect(find.byKey(const ValueKey('encoder-import')), findsOneWidget);
  });

  testWidgets('quotes around a folder id do not offer Download again', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SettingsHandler.register();
    SettingsHandler.instance
      ..dbEnabled = false
      ..encoderModel = '"files:wd-local"';
    EncoderHandler.unregister();
    EncoderHandler.register();
    addTearDown(EncoderHandler.unregister);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EncoderModelSection(onChanged: () async {})),
      ),
    );

    expect(find.text('Imported from a folder'), findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(find.byKey(const ValueKey('encoder-download')));
    expect(button.onPressed, isNull);
  });
}
