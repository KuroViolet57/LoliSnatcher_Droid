// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get_it/get_it.dart';
import 'package:local_auth/local_auth.dart';

import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';

class LocalAuthHandler {
  LocalAuthHandler() {
    init();
  }

  static LocalAuthHandler get instance => GetIt.instance<LocalAuthHandler>();

  static LocalAuthHandler register() {
    if (!GetIt.instance.isRegistered<LocalAuthHandler>()) {
      GetIt.instance.registerSingleton(LocalAuthHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<LocalAuthHandler>();

  final LocalAuthentication auth = LocalAuthentication();

  ValueNotifier<bool?> isAuthenticated = ValueNotifier(null);
  bool manuallyLocked = false;
  ValueNotifier<bool> deviceSupportsBiometrics = ValueNotifier(false);

  int? lastLeaveTime, lastUnlockTime;

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  Future<void> init() async {
    // The overlay treats null as "show the feed". Settings are already loaded,
    // so a lock that is on covers the feed before the biometric check returns.
    if (SettingsHandler.instance.useLockscreen.value) {
      isAuthenticated.value = false;
    }
    await canCheckBiometrics();
    await lock();
  }

  Future<void> canCheckBiometrics() async {
    bool result = false;
    if (isSupportedPlatform) {
      result = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    }
    deviceSupportsBiometrics.value = result;
  }

  Future<void> authenticate({
    bool initial = false,
    bool forceUnlock = false,
  }) async {
    if (!forceUnlock && initial && manuallyLocked) {
      manuallyLocked = false;
      return;
    }

    if (isAuthenticated.value == true) {
      return;
    }

    if (deviceSupportsBiometrics.value == true) {
      try {
        final bool authenticated =
            forceUnlock ||
            await auth.authenticate(
              localizedReason: NavigationHandler.instance.navContext.loc.authentication.pleaseAuthenticateToUseTheApp,
              persistAcrossBackgrounding: true,
              sensitiveTransaction: false,
              biometricOnly: false,
            );

        if (authenticated) {
          lastUnlockTime = DateTime.now().millisecondsSinceEpoch;
          lastLeaveTime = null;
        }
        await Future.delayed(const Duration(milliseconds: 300));
        isAuthenticated.value = authenticated;
      } on LocalAuthException catch (e, s) {
        Logger.Inst().log(
          e.description ?? e.code.name,
          'LocalAuthHandler',
          'authenticate',
          LogTypes.exception,
          s: s,
        );

        final context = NavigationHandler.instance.navContext;
        switch (e.code) {
          case LocalAuthExceptionCode.noBiometricHardware:
            FlashElements.showSnackbar(
              title: Text(context.loc.authentication.noBiometricHardwareAvailable),
              leadingIcon: Symbols.warning_amber_rounded,
            );
            break;
          case LocalAuthExceptionCode.temporaryLockout:
          case LocalAuthExceptionCode.biometricLockout:
            FlashElements.showSnackbar(
              title: Text(context.loc.authentication.temporaryLockout),
              leadingIcon: Symbols.warning_amber_rounded,
            );
            break;
          case LocalAuthExceptionCode.authInProgress:
            // do nothing
            break;

          // TODO handle all errors
          default:
            FlashElements.showSnackbar(
              title: Text(context.loc.authentication.somethingWentWrong(error: e.code.name)),
              leadingIcon: Symbols.warning_amber_rounded,
            );
            break;
        }
      } on Object catch (e, s) {
        Logger.Inst().log(
          e.toString(),
          'LocalAuthHandler',
          'authenticate',
          LogTypes.exception,
          s: s,
        );
      }
    } else {
      lastUnlockTime = DateTime.now().millisecondsSinceEpoch;
      lastLeaveTime = null;
      isAuthenticated.value = true;
    }
    return;
  }

  Future<void> lock({
    bool manually = false,
  }) async {
    await canCheckBiometrics();
    final bool shouldLock = deviceSupportsBiometrics.value && SettingsHandler.instance.useLockscreen.value;

    if (!shouldLock) {
      lastUnlockTime = DateTime.now().millisecondsSinceEpoch;
    } else {
      manuallyLocked = manually;
    }

    lastLeaveTime = null;
    isAuthenticated.value = !shouldLock;
  }

  void onLeave() {
    lastLeaveTime ??= DateTime.now().millisecondsSinceEpoch;
  }

  /// True when the user has been away longer than the lock timeout, and the
  /// last unlock was long enough ago that the system auth screen's own
  /// pause does not count as leaving.
  bool lockIsDue() {
    if (lastLeaveTime == null) return false;
    final int leaveTimeoutMs = 1000 * SettingsHandler.instance.autoLockTimeout;
    final int timeSinceLastLeave = DateTime.now().millisecondsSinceEpoch - (lastLeaveTime ?? 0);
    const int unlockDelayMs = 1000;
    final int timeSinceLastUnlock = DateTime.now().millisecondsSinceEpoch - (lastUnlockTime ?? 0);
    return leaveTimeoutMs != 0 && timeSinceLastLeave > leaveTimeoutMs && timeSinceLastUnlock > unlockDelayMs;
  }

  Future<void> onReturn() async {
    if (lastLeaveTime == null) {
      return;
    }
    if (lockIsDue()) {
      isAuthenticated.value = false;
    }
    await Future.delayed(const Duration(milliseconds: 10));
    if (lockIsDue()) {
      await lock();
    }
  }
}
