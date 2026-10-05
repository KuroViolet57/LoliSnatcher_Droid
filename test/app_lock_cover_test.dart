import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/local_auth_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';

/// Skips the platform biometric call. Reports that the device can lock, so
/// [LocalAuthHandler.lock] keeps the cover up when the setting is on.
class _LockProbe extends LocalAuthHandler {
  @override
  Future<void> canCheckBiometrics() async {
    deviceSupportsBiometrics.value = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.useLockscreen.value = false;
    SettingsHandler.instance.autoLockTimeout = 120;
  });

  test('a lock that is on covers the feed before biometrics answer', () {
    SettingsHandler.instance.useLockscreen.value = true;
    final LocalAuthHandler handler = _LockProbe();
    expect(handler.isAuthenticated.value, isFalse);
  });

  test('a lock that is off does not cover the feed', () {
    final LocalAuthHandler handler = _LockProbe();
    expect(handler.isAuthenticated.value, isNull);
  });

  test('coming back after the timeout covers the feed before the next check', () async {
    SettingsHandler.instance.useLockscreen.value = true;
    SettingsHandler.instance.autoLockTimeout = 1;
    final LocalAuthHandler handler = _LockProbe();
    await Future<void>.delayed(Duration.zero);
    handler.isAuthenticated.value = true;
    final int ago = DateTime.now().millisecondsSinceEpoch - 5000;
    handler.lastLeaveTime = ago;
    handler.lastUnlockTime = ago;

    final Future<void> returned = handler.onReturn();
    expect(handler.isAuthenticated.value, isFalse);
    await returned;
    expect(handler.isAuthenticated.value, isFalse);
  });

  test('coming back inside the timeout leaves the feed open', () async {
    SettingsHandler.instance.useLockscreen.value = true;
    SettingsHandler.instance.autoLockTimeout = 120;
    final LocalAuthHandler handler = _LockProbe();
    await Future<void>.delayed(Duration.zero);
    handler.isAuthenticated.value = true;
    handler.lastLeaveTime = DateTime.now().millisecondsSinceEpoch;
    handler.lastUnlockTime = DateTime.now().millisecondsSinceEpoch;

    await handler.onReturn();
    expect(handler.isAuthenticated.value, isTrue);
  });
}
