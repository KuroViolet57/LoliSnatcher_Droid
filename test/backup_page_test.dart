import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/backup_restore_page.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/services/drive_backup.dart';

/// r80: Settings → Backup & restore, one list of what to carry, for a folder
/// and for Google Drive alike.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.backupPath = '';
    BackupRestorePage.isAndroid = () => true;
    BackupRestorePage.driveHasCredentials = () async => false;
    BackupRestorePage.driveIsLinked = () async => false;
    BackupRestorePage.driveSnapshots = () async => const <DriveSnapshot>[];
  });

  tearDown(BackupRestorePage.resetForTests);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 9000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The title bar's shrinking text asserts on the test theme's 22 px title
    // (22 × 0.85 is not a whole number of 0.1 steps in floating point).
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20))),
          home: const BackupRestorePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> close(WidgetTester tester) async {
    // A snackbar's own timer runs out first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('a fresh install shows Google Drive without a backup folder', (tester) async {
    BackupRestorePage.driveHasCredentials = () async => true;
    BackupRestorePage.driveIsLinked = () async => true;
    await open(tester);

    expect(find.byKey(const ValueKey('backup-to-drive')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-from-drive')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-to-folder')), findsNothing, reason: 'no folder chosen yet');
    expect(find.byKey(const ValueKey('restore-from-folder')), findsNothing);
    await close(tester);
  });

  testWidgets('without an OAuth client only the client button shows for Drive', (tester) async {
    await open(tester);

    expect(find.byKey(const ValueKey('drive-client')), findsOneWidget);
    expect(find.text('Set OAuth client…'), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-link')), findsNothing);
    expect(find.byKey(const ValueKey('backup-to-drive')), findsNothing);
    await close(tester);
  });

  testWidgets('the folder buttons show once a folder is chosen', (tester) async {
    SettingsHandler.instance.backupPath = 'content://backup';
    await open(tester);

    expect(find.byKey(const ValueKey('backup-to-folder')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-from-folder')), findsOneWidget);
    await close(tester);
  });

  testWidgets('every item is on the list and ticked; None, one, All', (tester) async {
    await open(tester);

    for (final BackupItem i in BackupItem.values) {
      final Finder tile = find.byKey(ValueKey('backup-item-${i.name}'));
      expect(tile, findsOneWidget, reason: i.name);
      expect(tester.widget<CheckboxListTile>(tile).value, isTrue, reason: i.name);
    }
    final int all = BackupItem.values.length;
    expect(find.text('$all of $all'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('backup-none')));
    await tester.pump();
    expect(find.text('0 of $all'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('backup-item-recommender'))).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('backup-item-recommender')));
    await tester.pump();
    expect(find.text('1 of $all'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('backup-item-recommender'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('backup-item-database'))).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('backup-all')));
    await tester.pump();
    expect(find.text('$all of $all'), findsOneWidget);
    await close(tester);
  });

  testWidgets('after linking, the Drive buttons show even when the listing fails', (tester) async {
    bool linked = false;
    BackupRestorePage.driveHasCredentials = () async => true;
    BackupRestorePage.driveIsLinked = () async => linked;
    BackupRestorePage.driveSnapshots = () async => throw Exception('the listing failed right after the sign-in');
    BackupRestorePage.driveLink = ({void Function(String status)? onProgress}) async {
      linked = true;
      return null;
    };
    await open(tester);
    expect(find.byKey(const ValueKey('drive-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-to-drive')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drive-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('backup-to-drive')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-from-drive')), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-link')), findsNothing);
    expect(find.text('Linked - nothing backed up yet.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('restoring from Drive lists the backups by name, newest first, the earlier one marked', (tester) async {
    BackupRestorePage.driveHasCredentials = () async => true;
    BackupRestorePage.driveIsLinked = () async => true;
    BackupRestorePage.driveSnapshots = () async => [
      DriveSnapshot(id: 'b', name: 'before the reset', created: DateTime.utc(2026, 9, 21, 18)),
      DriveSnapshot(id: 'a', name: '2026-09-20 10.00', created: DateTime.utc(2026, 9, 20, 10)),
      DriveSnapshot(id: 'root', name: DriveBackup.earlierBackupName, created: DateTime.utc(2026, 9, 16), earlier: true),
    ];
    await open(tester);
    expect(find.textContaining('3 backups, newest "before the reset"'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-from-drive')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final List<String> order = [
      for (final ListTile t in tester.widgetList<ListTile>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListTile))))
        (t.title! as Text).data!,
    ];
    expect(order, ['before the reset', '2026-09-20 10.00', DriveBackup.earlierBackupName]);
    expect(find.textContaining('made before backups had their own folders'), findsOneWidget);
    expect(find.byTooltip('Delete this backup'), findsNWidgets(2), reason: 'the earlier backup is not deleted from here');

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    await close(tester);
  });
}
