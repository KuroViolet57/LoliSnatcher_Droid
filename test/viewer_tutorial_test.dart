import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/settings/ui/gallery_page.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/viewer_tutorial.dart';

/// The viewer hint is mounted and, until now, forced hidden. Closing it must
/// leave the viewer up, hide the hint, and stay off after a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsHandler settings;

  setUpAll(Logger.Inst);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    settings = SettingsHandler.instance;
    tempDir = Directory.systemTemp.createTempSync('viewer_tutorial');
    settings
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..boorusPath = '${tempDir.path}${Platform.pathSeparator}boorus${Platform.pathSeparator}'
      ..prefBooru = '';
    settings.showViewerTutorial = true;
  });

  tearDown(() {
    settings.showViewerTutorial = true;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the hint follows the setting, and an older file without the key shows it once', () async {
    expect(viewerTutorialIsShown(settings.showViewerTutorial), isTrue);
    expect(settings.map['showViewerTutorial']!['default'], isTrue);

    settings.showViewerTutorial = false;
    expect(settings.getByString('showViewerTutorial'), isFalse);
    expect(settings.toJson()['showViewerTutorial'], isFalse);

    settings.showViewerTutorial = true;
    await settings.loadFromJSON('{"showViewerTutorial": false}', false);
    expect(settings.showViewerTutorial, isFalse);
    expect(viewerTutorialIsShown(settings.showViewerTutorial), isFalse);

    await settings.loadFromJSON('{}', true);
    expect(
      settings.showViewerTutorial,
      isTrue,
      reason: 'an older settings file has no key, so the hint shows once',
    );
  });

  testWidgets('Close hides the hint and a tap on the scrim does not reach the picture', (tester) async {
    var dismissed = 0;
    var behind = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => behind++,
                    child: const ColoredBox(
                      color: Color(0xFF111111),
                      child: Text('viewer stays'),
                    ),
                  ),
                ),
                ViewerTutorial(
                  shown: true,
                  onDismiss: () => dismissed++,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tap/Long tap: toggle immersive mode'), findsOneWidget);
    expect(find.text('Double tap: fit to screen / original size / reset zoom'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(behind, 0, reason: 'the scrim takes the tap so the picture does not');
    expect(dismissed, 0, reason: 'a tap on the scrim does not dismiss');
    expect(find.text('viewer stays'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(dismissed, 1);
    expect(find.text('Tap/Long tap: toggle immersive mode'), findsNothing);
    expect(find.text('viewer stays'), findsOneWidget);
  });

  testWidgets('a turned-off hint draws nothing', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: const MaterialApp(
          home: ViewerTutorial(shown: false, onDismiss: _noop),
        ),
      ),
    );
    expect(find.text('Close'), findsNothing);
    expect(find.text('Tap/Long tap: toggle immersive mode'), findsNothing);
  });

  testWidgets('Settings → Viewer saves the hint switch', (tester) async {
    tester.view.physicalSize = const Size(420, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ThemeData theme = ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20)));
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          theme: theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    unawaited(
      NavigationHandler.instance.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GalleryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Show viewer hints'), findsOneWidget);
    await tester.tap(find.text('Show viewer hints'));
    await tester.pump();

    NavigationHandler.instance.navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(settings.showViewerTutorial, isFalse);
  });

  test('the overlay does not pop the viewer or draw the unfinished video thirds', () {
    final String source = File('lib/features/viewer/ui/viewer_tutorial.dart').readAsStringSync();
    expect(source.contains('Navigator.of(context).pop'), isFalse);
    expect(source.contains('TransparentPointer'), isFalse);
    expect(source.contains('Colors.red'), isFalse);
    final String page = File('lib/features/viewer/ui/gallery_view_page.dart').readAsStringSync();
    expect(page, contains('showViewerTutorial = false'));
    expect(page, contains('saveSettings(restate: false)'));
  });
}

void _noop() {}
