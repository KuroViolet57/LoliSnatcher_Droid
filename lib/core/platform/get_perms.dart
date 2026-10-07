import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/download_folders.dart';
import 'package:lolisnatcher/core/ui/buttons/cancel_button.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';

/// True after [setPermissions] showed the system-settings dialog for a denial
/// the OS will not ask again. Callers that also show a snackbar skip it.
bool storageDenialExplained = false;

/// A permanent denial, or an OS restriction, will not show the system request again.
bool storageStatusNeedsSettings(PermissionStatus status) {
  return status.isPermanentlyDenied || status.isRestricted;
}

BuildContext? storageDialogContext() {
  if (!GetIt.instance.isRegistered<NavigationHandler>()) return null;
  final BuildContext? context = NavigationHandler.instance.navigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  return context;
}

/// Null means this platform does not ask for the legacy storage permission
/// (Android 13 and newer). The caller treats that as allowed.
Future<PermissionStatus?> requestLegacyStorageStatus() async {
  final bool legacy = (Platform.isAndroid && await ServiceHandler.getAndroidSDKVersion() < 33) || Platform.isIOS;
  if (!legacy) return null;
  return Permission.storage.request();
}

/// Granted, or not required, is true. Anything else blocks the save.
/// [explain] is for the save gate. Settings and tag saves pass false.
@visibleForTesting
Future<bool> settleStorageAccess({
  required PermissionStatus? status,
  required bool explain,
  BuildContext? context,
  String title = '',
  String body = '',
  String openSettingsLabel = '',
  String cancelLabel = '',
  Future<bool> Function()? openSettings,
}) async {
  storageDenialExplained = false;
  if (status == null || status.isGranted) return true;
  if (explain && storageStatusNeedsSettings(status) && context != null && context.mounted) {
    await showStoragePermissionBlockedDialog(
      context,
      title: title,
      body: body,
      openSettingsLabel: openSettingsLabel,
      cancelLabel: cancelLabel,
      openSettings: openSettings,
    );
    storageDenialExplained = true;
  }
  return false;
}

@visibleForTesting
Future<void> showStoragePermissionBlockedDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String openSettingsLabel,
  required String cancelLabel,
  Future<bool> Function()? openSettings,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () async {
              await (openSettings ?? openAppSettings)();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(openSettingsLabel),
          ),
        ],
      );
    },
  );
}

/// This launches the permissions dialogue to get storage permissions from the user.
///
/// Settings, tag, and booru saves call this and do not explain a denial. Those
/// files live in app-private storage. The save gate is [setPermissions].
Future<bool> getStoragePermission() async {
  final PermissionStatus? status = await requestLegacyStorageStatus();
  return settleStorageAccess(status: status, explain: false);
}

Future<bool> checkStorageAvailability() async {
  final extPath = SettingsHandler.instance.extPathOverride;
  if (extPath.isEmpty) {
    return true;
  }

  return ServiceHandler.testSAFPersistence(extPath);
}

Future<bool> setPermissions() async {
  final PermissionStatus? status = await requestLegacyStorageStatus();
  final BuildContext? context = storageDialogContext();
  bool hasAccess = context == null
      ? await settleStorageAccess(status: status, explain: false)
      : await settleStorageAccess(
          status: status,
          explain: true,
          context: context,
          title: context.loc.permissions.storageBlockedTitle,
          body: context.loc.permissions.storageBlockedBody,
          openSettingsLabel: context.loc.permissions.openAppSettings,
          cancelLabel: context.loc.cancel,
        );
  if (!hasAccess) {
    if (storageDenialExplained) {
      Logger.Inst().log(
        'Storage permission is blocked. Asked for system settings.',
        'Permissions',
        'setPermissions',
        LogTypes.settingsError,
      );
    }
    return false;
  }

  hasAccess = await checkStorageAvailability();
  if (!hasAccess) hasAccess = await showStorageNeedsUpdateDialog();
  // do a check again if user set new directory, just in case
  if (hasAccess) hasAccess = await checkStorageAvailability();
  return hasAccess;
}

Future<bool> showStorageNeedsUpdateDialog() async {
  final String extPath = SettingsHandler.instance.extPathOverride;
  final res = await showDialog(
    context: NavigationHandler.instance.navContext,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Text(context.loc.permissions.noAccessToCustomStorageDirectory),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.loc.permissions.pleaseSetStorageDirectoryAgain,
            ),
            if (extPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(context.loc.permissions.currentPath(path: extPath)),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              label: Text(context.loc.permissions.setDirectory),
              icon: const Icon(Symbols.settings_rounded),
              onPressed: () async {
                if (Platform.isAndroid) {
                  final String newPath = await ServiceHandler.setExtDir();
                  // r82: the folder left is remembered; the new one's file
                  // list is read at once ('' = the default folder, as before).
                  await DownloadFolders.change(newPath);
                  Navigator.of(context).pop(true);
                } else {
                  FlashElements.showSnackbar(
                    context: context,
                    title: Text(
                      context.loc.errorExclamation,
                      style: const TextStyle(fontSize: 20),
                    ),
                    content: Text(
                      context.loc.permissions.currentlyNotAvailableForThisPlatform,
                      style: const TextStyle(fontSize: 16),
                    ),
                    leadingIcon: Symbols.error_rounded,
                    leadingIconColor: Colors.red,
                    sideColor: Colors.red,
                  );
                  Navigator.of(context).pop(false);
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              label: Text(context.loc.permissions.resetDirectory),
              icon: const Icon(Symbols.refresh_rounded),
              style: ElevatedButtonTheme.of(context).style!.copyWith(
                backgroundColor: const WidgetStatePropertyAll(Colors.redAccent),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
              onPressed: () async {
                await DownloadFolders.change('');
                Navigator.of(context).pop(true);
              },
            ),
            Text(context.loc.permissions.afterResetFilesWillBeSavedToDefaultDirectory),
            const SizedBox(height: 24),
            const CancelButton(
              withIcon: true,
              returnData: false,
            ),
          ],
        ),
      );
    },
  );

  if (res is bool) {
    return res;
  }

  return false;
}
