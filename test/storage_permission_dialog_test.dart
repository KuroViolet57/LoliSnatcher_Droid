import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/core/platform/get_perms.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('only a denial the system will not ask again needs the settings screen', () {
    expect(storageStatusNeedsSettings(PermissionStatus.permanentlyDenied), isTrue);
    expect(storageStatusNeedsSettings(PermissionStatus.restricted), isTrue);
    expect(storageStatusNeedsSettings(PermissionStatus.denied), isFalse);
    expect(storageStatusNeedsSettings(PermissionStatus.granted), isFalse);
    expect(storageStatusNeedsSettings(PermissionStatus.limited), isFalse);
  });

  testWidgets('a permanent storage denial blocks the save and offers system settings', (tester) async {
    var openedSettings = false;
    late BuildContext homeContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            homeContext = context;
            return const Text('feed');
          },
        ),
      ),
    );

    final Future<bool> pending = settleStorageAccess(
      status: PermissionStatus.permanentlyDenied,
      explain: true,
      context: homeContext,
      title: 'Storage permission is blocked',
      body: 'The system will not ask again.',
      openSettingsLabel: 'Open settings',
      cancelLabel: 'Cancel',
      openSettings: () async {
        openedSettings = true;
        return true;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Storage permission is blocked'), findsOneWidget);
    expect(find.text('feed'), findsOneWidget, reason: 'the dialog blocks the save, it does not leave the page');
    expect(storageDenialExplained, isFalse, reason: 'the flag is set when the dialog closes');

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(openedSettings, isTrue);
    expect(await pending, isFalse);
    expect(storageDenialExplained, isTrue);
    expect(find.text('Storage permission is blocked'), findsNothing);
  });

  testWidgets('a first denial and a grant do not open that dialog', (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            homeContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      await settleStorageAccess(
        status: PermissionStatus.granted,
        explain: true,
        context: homeContext,
        title: 'Storage permission is blocked',
        body: 'The system will not ask again.',
        openSettingsLabel: 'Open settings',
        cancelLabel: 'Cancel',
      ),
      isTrue,
    );
    expect(storageDenialExplained, isFalse);

    final Future<bool> denied = settleStorageAccess(
      status: PermissionStatus.denied,
      explain: true,
      context: homeContext,
      title: 'Storage permission is blocked',
      body: 'The system will not ask again.',
      openSettingsLabel: 'Open settings',
      cancelLabel: 'Cancel',
    );
    await tester.pump();
    expect(find.text('Storage permission is blocked'), findsNothing);
    expect(await denied, isFalse);
    expect(storageDenialExplained, isFalse);

    expect(
      await settleStorageAccess(
        status: null,
        explain: true,
        context: homeContext,
        title: 'Storage permission is blocked',
        body: 'The system will not ask again.',
        openSettingsLabel: 'Open settings',
        cancelLabel: 'Cancel',
      ),
      isTrue,
      reason: 'Android 13 and newer do not request this permission',
    );

    final Future<bool> quiet = settleStorageAccess(
      status: PermissionStatus.permanentlyDenied,
      explain: false,
      context: homeContext,
      title: 'Storage permission is blocked',
      body: 'The system will not ask again.',
      openSettingsLabel: 'Open settings',
      cancelLabel: 'Cancel',
    );
    await tester.pump();
    expect(find.text('Storage permission is blocked'), findsNothing, reason: 'settings and tag saves do not explain');
    expect(await quiet, isFalse);
  });
}
