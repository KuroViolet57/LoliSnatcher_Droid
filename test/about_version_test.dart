import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/settings/ui/about_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('About shows the 1.0 version and codename', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SettingsHandler.register();

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20))),
          home: const AboutPage(),
        ),
      ),
    );

    expect(
      find.textContaining('${Constants.buildCodename}-${Constants.updateInfo.versionName}'),
      findsOneWidget,
    );
  });
}
