import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/widgets/common/downloads_check.dart';

/// r84: "Check downloads against disk" - finds the Downloads entries whose
/// file is in no download folder and forgets them on request. It was in a
/// drawer panel the app stopped showing on 14 July; now it is in
/// Settings → Save & cache, and it is offered by itself on the first start
/// after the whole database came back from a backup (a backup carries the
/// list of downloads, not the files).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int forgot;
  late int audits;
  // Snackbars show nothing in tests (Tools.isTestMode): the check's messages
  // are recorded instead, as 'title | content'.
  late List<String> said;
  late ({int scanned, int missing, int unknown, String? problem}) result;
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('downloads_check');
    forgot = 0;
    audits = 0;
    said = [];
    result = (scanned: 693, missing: 680, unknown: 3, problem: null);
    DownloadsCheck.audit = () async {
      audits++;
      return result;
    };
    DownloadsCheck.forget = () async {
      forgot++;
      return result.missing;
    };
    DownloadsCheck.configDir = () async => '${tempDir.path}${Platform.pathSeparator}';
    DownloadsCheck.contextNow = () => navigator.currentContext;
    DownloadsCheck.whereFound = () => const ['13 in the current folder'];
    DownloadsCheck.say = (context, title, content, color) => said.add('$title | $content');
  });

  tearDown(() {
    DownloadsCheck.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('check'),
                onPressed: () => DownloadsCheck.run(context),
                child: const Text('Check'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('the check says how many downloads have no file and forgets them on request', (tester) async {
    await host(tester);
    await tester.tap(find.byKey(const ValueKey('check')));
    await settle(tester);
    expect(find.text('680 of 693 downloads have no file'), findsOneWidget);
    expect(find.textContaining('13 in the current folder'), findsOneWidget);
    expect(find.textContaining('3 entries could not be checked'), findsOneWidget);
    await tester.tap(find.text('Forget 680'));
    await settle(tester);
    expect(forgot, 1);
    expect(said.last, startsWith('Forgot 680 entries'));
    await close(tester);
  });

  testWidgets('Keep forgets nothing; with every file there it only says so', (tester) async {
    await host(tester);
    await tester.tap(find.byKey(const ValueKey('check')));
    await settle(tester);
    await tester.tap(find.text('Keep'));
    await settle(tester);
    expect(forgot, 0);

    result = (scanned: 12, missing: 0, unknown: 0, problem: null);
    await tester.tap(find.byKey(const ValueKey('check')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(said.last, 'All 12 media downloads have a file | 13 in the current folder');
    expect(forgot, 0);
    await close(tester);
  });

  testWidgets('after a whole-database restore the check is offered once, on the next start', (tester) async {
    await host(tester);
    File('${tempDir.path}${Platform.pathSeparator}${BackupRunner.checkDownloadsMarker}').writeAsStringSync('restored');
    await tester.runAsync(DownloadsCheck.offerAfterRestore);
    await settle(tester);
    expect(find.text('Downloads restored without their files'), findsOneWidget);
    expect(find.textContaining('680 of them have no file on this phone'), findsOneWidget);
    expect(File('${tempDir.path}${Platform.pathSeparator}${BackupRunner.checkDownloadsMarker}').existsSync(), isFalse, reason: 'asked once');
    await tester.tap(find.text('Forget 680'));
    await settle(tester);
    // The dialog was opened from real async (the marker is a real file), so
    // its answer is handled there too.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(forgot, 1);
    expect(said.last, startsWith('Forgot 680 entries'));

    // The next start: no marker, nothing asked, nothing checked.
    await tester.runAsync(DownloadsCheck.offerAfterRestore);
    await settle(tester);
    expect(find.text('Downloads restored without their files'), findsNothing);
    expect(audits, 1);
    await close(tester);
  });

  testWidgets('after a restore with every file there, nothing is asked', (tester) async {
    await host(tester);
    result = (scanned: 12, missing: 0, unknown: 0, problem: null);
    File('${tempDir.path}${Platform.pathSeparator}${BackupRunner.checkDownloadsMarker}').writeAsStringSync('restored');
    await tester.runAsync(DownloadsCheck.offerAfterRestore);
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(audits, 1);
    expect(said, isEmpty);
    await close(tester);
  });
}
