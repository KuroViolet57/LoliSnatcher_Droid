import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/drive_backup.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;
  String backupPath = '';

  /// The doujin side's own store files, backed up alongside the booru data.
  static const List<String> _doujinStoreFiles = [
    'doujinData.json',
    'sourceSettings.json',
    'bookmarks.json',
  ];

  /// After restoring the doujin store files, drop the lazily-loaded singleton
  /// state so the next read comes from the restored files.
  void _reloadDoujinStores() {
    DoujinDataHandler.instance.reloadFromDisk();
    SourceSettingsHandler.instance.reloadFromDisk();
    BookmarkHandler.instance.reloadFromDisk();
  }

  /// A restored store.db may predate the doujin split and still carry doujin
  /// rows in the shared stores — re-arm the one-time migration so they get
  /// moved out again on the post-restore restart. The migration is additive
  /// and idempotent, so re-running it on already-migrated data is safe.
  void _rearmDoujinMigration() {
    final store = DoujinDataHandler.instance..ensureLoaded();
    store.migrationDone = false;
    store.save();
  }

  bool inProgress = false;
  int progress = 0, total = 0;

  // Google Drive
  bool driveLinked = false;
  bool driveHasCreds = false;
  bool driveBusy = false;
  String driveStatus = '';
  List<DriveFile> driveFiles = const [];

  @override
  void initState() {
    super.initState();
    backupPath = settingsHandler.backupPath;
    validateBackupPathAccess();
    unawaited(_refreshDriveState());
  }

  Future<void> validateBackupPathAccess() async {
    if (!Platform.isAndroid || backupPath.isEmpty) {
      return;
    }

    try {
      final success = await ServiceHandler.testSAFPersistence(backupPath);
      if (!success) {
        Logger.Inst().log(
          'Invalid backup path',
          'BackupRestorePage',
          'validateBackupPathAccess',
          LogTypes.exception,
        );
        setState(() {
          backupPath = '';
          settingsHandler.backupPath = '';
        });
        await settingsHandler.saveSettings(restate: false);
      }
    } catch (_) {}
  }

  void showSnackbar(
    String text, {
    required bool isError,
  }) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        isError ? context.loc.errorExclamation : context.loc.successExclamation,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(
        text,
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: isError ? Symbols.error_rounded : Symbols.done_rounded,
      leadingIconColor: isError ? Colors.red : Colors.green,
      sideColor: isError ? Colors.red : Colors.green,
    );
  }

  Future<bool> detectedDuplicateFile(String fileName) async {
    final bool? res = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.loc.settings.backupAndRestore.duplicateFileDetectedTitle),
          content: Text(context.loc.settings.backupAndRestore.duplicateFileDetectedMsg(fileName: fileName)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.loc.no),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(true);
                await ServiceHandler.deleteFileFromSAFDirectory(backupPath, fileName);
              },
              child: Text(context.loc.yes),
            ),
          ],
        );
      },
    );

    return res ?? false;
  }

  Future<bool> confirmRestore(String title) async {
    final bool? res = await showDialog<bool>(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: Text(title),
          actionButtons: [
            const CancelButton(withIcon: true),
            ConfirmButton(
              withIcon: true,
              returnData: true,
              label: context.loc.confirm,
            ),
          ],
        );
      },
    );

    return res ?? false;
  }

  // Bulk backup — runs settings + boorus + database sequentially after one
  // confirmation. Overwrites existing files silently (you opted in to the
  // bulk action, so we don't gate each file behind the duplicate prompt).
  Future<void> _runBackupAll(BuildContext context) async {
    if (backupPath.isEmpty) {
      showSnackbar(context.loc.settings.backupAndRestore.noBackupDirSelected, isError: true);
      return;
    }
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => const SettingsDialog(
            title: Text('Backup all'),
            contentItems: [
              Text('This will back up settings.json, boorus.json and store.db to the selected directory, overwriting any existing copies.'),
            ],
            actionButtons: [
              CancelButton(withIcon: true),
              ConfirmButton(withIcon: true, returnData: true, label: 'Backup all'),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    inProgress = true;
    setState(() {});

    final List<String> failures = [];

    Future<void> step(String label, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, s) {
        failures.add(label);
        Logger.Inst().log(e.toString(), 'BackupRestorePage', 'backupAll/$label', LogTypes.exception, s: s);
      }
    }

    // settings.json
    await step('settings', () async {
      final File file = File('${await ServiceHandler.getConfigDir()}settings.json');
      if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'settings.json')) {
        await ServiceHandler.deleteFileFromSAFDirectory(backupPath, 'settings.json');
      }
      await ServiceHandler.writeImage(
        await file.readAsBytes(),
        'settings',
        'text/json',
        'json',
        backupPath,
      );
    });

    // boorus.json
    await step('boorus', () async {
      final List<Booru> booruList =
          settingsHandler.booruList.where((e) => BooruType.saveable.contains(e.type)).toList();
      if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'boorus.json')) {
        await ServiceHandler.deleteFileFromSAFDirectory(backupPath, 'boorus.json');
      }
      await ServiceHandler.writeImage(
        utf8.encode(json.encode(booruList)),
        'boorus',
        'text',
        'json',
        backupPath,
      );
    });

    // Doujin-side stores (favourites/collections/pins/history + doujin
    // settings + bookmarks) — separate files, so the separated data
    // round-trips through backups too. Missing files just aren't written yet.
    // SAF createFile never overwrites (it dedupes to "name (1).json", which
    // restore would never read), so delete any existing copy first — the
    // bulk dialog already promises overwriting.
    for (final name in _doujinStoreFiles) {
      await step(name, () async {
        final File file = File('${await ServiceHandler.getConfigDir()}$name');
        if (!await file.exists()) return;
        if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, name)) {
          await ServiceHandler.deleteFileFromSAFDirectory(backupPath, name);
        }
        await ServiceHandler.writeImage(
          await file.readAsBytes(),
          name.replaceAll('.json', ''),
          'text/json',
          'json',
          backupPath,
        );
      });
    }

    // store.db
    await step('database', () async {
      final File file = File('${await ServiceHandler.getConfigDir()}store.db');
      if (!await file.exists()) throw Exception('database file not found');
      await ServiceHandler.copyFileToSafDir(
        await ServiceHandler.getConfigDir(),
        'store.db',
        backupPath,
        'application/x-sqlite3',
      );
    });

    inProgress = false;
    setState(() {});

    if (failures.isEmpty) {
      showSnackbar('Backed up settings, boorus and database.', isError: false);
    } else {
      showSnackbar('Backup finished with errors: ${failures.join(", ")}', isError: true);
    }
  }

  // Bulk restore — confirms once with a stronger warning, then restores all
  // three sequentially. Database is restored last and triggers the standard
  // app restart on success (already part of the single-file flow).
  Future<void> _runRestoreAll(BuildContext context) async {
    if (backupPath.isEmpty) {
      showSnackbar(context.loc.settings.backupAndRestore.noBackupDirSelected, isError: true);
      return;
    }
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => const SettingsDialog(
            title: Text('Restore all'),
            contentItems: [
              Text(
                'This will replace your current settings, boorus and database with the files from the backup directory. '
                'The app will restart at the end. This cannot be undone.',
              ),
            ],
            actionButtons: [
              CancelButton(withIcon: true),
              ConfirmButton(withIcon: true, returnData: true, label: 'Restore all'),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    inProgress = true;
    setState(() {});

    final List<String> failures = [];

    // settings.json
    try {
      final Uint8List? bytes = await ServiceHandler.getFileFromSAFDirectory(backupPath, 'settings.json');
      if (bytes != null) {
        final File f = File('${await ServiceHandler.getConfigDir()}settings.json');
        if (!await f.exists()) await f.create();
        await f.writeAsBytes(bytes);
        await settingsHandler.loadSettingsJson();
      } else {
        failures.add('settings (file not found)');
      }
    } catch (e, s) {
      failures.add('settings');
      Logger.Inst().log(e.toString(), 'BackupRestorePage', 'restoreAll/settings', LogTypes.exception, s: s);
    }

    // boorus.json
    try {
      final Uint8List? bytes = await ServiceHandler.getFileFromSAFDirectory(backupPath, 'boorus.json');
      if (bytes != null) {
        final String boorusStr = String.fromCharCodes(bytes);
        if (boorusStr.isNotEmpty) {
          final List<dynamic> parsed = jsonDecode(boorusStr);
          final String configBoorusPath = '${await ServiceHandler.getConfigDir()}boorus/';
          final Directory configBoorusDir = await Directory(configBoorusPath).create(recursive: true);
          for (int i = 0; i < parsed.length; i++) {
            final Booru booru = Booru.fromMap(parsed[i]);
            final bool alreadyExists = settingsHandler.booruList.indexWhere(
                  (el) => el.baseURL == booru.baseURL && el.name == booru.name,
                ) !=
                -1;
            final bool isAllowed = BooruType.saveable.contains(booru.type);
            if (!alreadyExists && isAllowed) {
              final File booruFile = File('${configBoorusDir.path}${booru.name}.json');
              final writer = booruFile.openWrite();
              writer.write(jsonEncode(booru.toJson()));
              await writer.close();
            }
          }
          await settingsHandler.loadBoorus();
        }
      } else {
        failures.add('boorus (file not found)');
      }
    } catch (e, s) {
      failures.add('boorus');
      Logger.Inst().log(e.toString(), 'BackupRestorePage', 'restoreAll/boorus', LogTypes.exception, s: s);
    }

    // Doujin-side stores — absent in older backups, so missing files are
    // skipped silently rather than reported.
    for (final name in _doujinStoreFiles) {
      try {
        final Uint8List? bytes = await ServiceHandler.getFileFromSAFDirectory(backupPath, name);
        if (bytes != null) {
          final File f = File('${await ServiceHandler.getConfigDir()}$name');
          if (!await f.exists()) await f.create();
          await f.writeAsBytes(bytes);
        }
      } catch (e, s) {
        failures.add(name);
        Logger.Inst().log(e.toString(), 'BackupRestorePage', 'restoreAll/$name', LogTypes.exception, s: s);
      }
    }
    _reloadDoujinStores();

    // store.db — last because it restarts the app on success
    try {
      final fileExists = await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'store.db');
      if (!fileExists) {
        failures.add('database (file not found)');
      } else {
        searchHandler.canBackup.value = false;
        final String configDir = await ServiceHandler.getConfigDir();
        await settingsHandler.dbHandler.closeDb();
        for (final suffix in ['-wal', '-shm']) {
          final sidecar = File('${configDir}store.db$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
        final bool copied = await ServiceHandler.copySafFileToDir(backupPath, 'store.db', configDir);
        if (!copied) {
          failures.add('database (copy failed)');
          searchHandler.canBackup.value = true;
        } else {
          final File newFile = File('${configDir}store.db');
          if (!await newFile.exists()) {
            failures.add('database (post-copy missing)');
            searchHandler.canBackup.value = true;
          } else {
            _rearmDoujinMigration();
          }
        }
      }
    } catch (e, s) {
      failures.add('database');
      Logger.Inst().log(e.toString(), 'BackupRestorePage', 'restoreAll/database', LogTypes.exception, s: s);
      searchHandler.canBackup.value = true;
    }

    inProgress = false;
    setState(() {});

    if (failures.isEmpty) {
      showSnackbar('Restored. App will restart in a moment.', isError: false);
      await Future.delayed(const Duration(seconds: 3));
      unawaited(ServiceHandler.restartApp());
    } else {
      showSnackbar('Restore finished with errors: ${failures.join(", ")}', isError: true);
    }
  }

  // ───────────────────────────── Google Drive ─────────────────────────────

  Future<void> _refreshDriveState() async {
    final bool linked = await DriveBackup.isLinked;
    final bool hasCreds = await DriveBackup.hasCredentials;
    final List<DriveFile> files = linked ? await DriveBackup.list() : const [];
    if (!mounted) return;
    setState(() {
      driveLinked = linked;
      driveHasCreds = hasCreds;
      driveFiles = files;
    });
  }

  Future<void> _editDriveCredentials() async {
    final idController = TextEditingController(text: await DriveBackup.clientId ?? '');
    final secretController = TextEditingController(text: await DriveBackup.clientSecret ?? '');
    if (!mounted) return;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google OAuth client'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These are not stored in the app source, so you paste them once here and '
                'they stay in the phone’s encrypted storage.\n\n'
                'Create them at console.cloud.google.com → APIs & Services → Credentials → '
                'Create credentials → OAuth client ID, application type "Desktop app", '
                'and enable the Google Drive API for that project.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: idController,
                decoration: const InputDecoration(labelText: 'Client ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secretController,
                decoration: const InputDecoration(labelText: 'Client secret', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      await DriveBackup.setCredentials(idController.text, secretController.text);
      await _refreshDriveState();
    }
  }

  Future<void> _linkDrive() async {
    setState(() {
      driveBusy = true;
      driveStatus = 'Waiting for Google sign-in in your browser…';
    });
    final String? error = await DriveBackup.link();
    if (!mounted) return;
    setState(() {
      driveBusy = false;
      driveStatus = '';
    });
    showSnackbar(error ?? 'Google Drive linked.', isError: error != null);
    await _refreshDriveState();
  }

  /// Uploads the same three artefacts the folder backup writes.
  Future<void> _backupToDrive() async {
    setState(() {
      driveBusy = true;
      driveStatus = 'Starting…';
    });
    final List<String> failures = [];

    Future<void> step(String label, String name, String mime, Future<List<int>> Function() read) async {
      if (!mounted) return;
      setState(() => driveStatus = 'Uploading $label…');
      try {
        final List<int> bytes = await read();
        final String? error = await DriveBackup.upload(
          name,
          bytes,
          mime,
          onProgress: (sent, total) {
            if (!mounted || total == 0) return;
            setState(() => driveStatus = 'Uploading $label — ${(100 * sent / total).round()}%');
          },
        );
        if (error != null) failures.add('$label: $error');
      } catch (e) {
        failures.add('$label: $e');
      }
    }

    final String configDir = await ServiceHandler.getConfigDir();

    await step('settings', 'settings.json', 'application/json', () async {
      return File('${configDir}settings.json').readAsBytes();
    });
    await step('boorus', 'boorus.json', 'application/json', () async {
      final List<Booru> booruList =
          settingsHandler.booruList.where((e) => BooruType.saveable.contains(e.type)).toList();
      return utf8.encode(json.encode(booruList));
    });
    for (final name in _doujinStoreFiles) {
      final File file = File('$configDir$name');
      if (await file.exists()) {
        await step(name, name, 'application/json', file.readAsBytes);
      }
    }
    await step('database', 'store.db', 'application/x-sqlite3', () async {
      final File file = File('${configDir}store.db');
      if (!await file.exists()) throw Exception('database file not found');
      return file.readAsBytes();
    });

    if (!mounted) return;
    setState(() {
      driveBusy = false;
      driveStatus = '';
    });
    showSnackbar(
      failures.isEmpty ? 'Backed up to Google Drive.' : 'Finished with errors: ${failures.join(", ")}',
      isError: failures.isNotEmpty,
    );
    await _refreshDriveState();
  }

  Future<void> _restoreFromDrive() async {
    final bool ok = await confirmRestore('Restore everything from Google Drive');
    if (!ok) return;

    setState(() {
      driveBusy = true;
      driveStatus = 'Downloading…';
    });
    final List<String> failures = [];
    final String configDir = await ServiceHandler.getConfigDir();

    // Settings and boorus first, database last — restoring the database is
    // what triggers the restart, same order the folder restore uses.
    try {
      final bytes = await DriveBackup.download('settings.json');
      if (bytes == null) {
        failures.add('settings: not on Drive');
      } else {
        await File('${configDir}settings.json').writeAsBytes(bytes, flush: true);
        await settingsHandler.loadSettings();
      }
    } catch (e) {
      failures.add('settings: $e');
    }

    try {
      final bytes = await DriveBackup.download('boorus.json');
      if (bytes == null) {
        failures.add('boorus: not on Drive');
      } else {
        final List<dynamic> raw = json.decode(utf8.decode(bytes)) as List<dynamic>;
        final List<Booru> boorus = raw.map((e) => Booru.fromMap(e)).toList();
        for (final booru in boorus) {
          if (!settingsHandler.booruList.contains(booru)) {
            await settingsHandler.saveBooru(booru);
          }
        }
      }
    } catch (e) {
      failures.add('boorus: $e');
    }

    for (final name in _doujinStoreFiles) {
      try {
        final bytes = await DriveBackup.download(name);
        // Older backups simply don't have these files — skip silently.
        if (bytes != null) {
          await File('$configDir$name').writeAsBytes(bytes, flush: true);
        }
      } catch (e) {
        failures.add('$name: $e');
      }
    }
    _reloadDoujinStores();

    try {
      final bytes = await DriveBackup.download('store.db');
      if (bytes == null) {
        failures.add('database: not on Drive');
      } else {
        await settingsHandler.dbHandler.closeDb();
        await File('${configDir}store.db').writeAsBytes(bytes, flush: true);
        _rearmDoujinMigration();
      }
    } catch (e) {
      failures.add('database: $e');
    }

    if (!mounted) return;
    setState(() {
      driveBusy = false;
      driveStatus = '';
    });

    if (failures.isEmpty) {
      showSnackbar('Restored from Drive. App will restart in a moment.', isError: false);
      await Future.delayed(const Duration(seconds: 3));
      unawaited(ServiceHandler.restartApp());
    } else {
      showSnackbar('Restore finished with errors: ${failures.join(", ")}', isError: true);
    }
  }

  String _driveSummary() {
    if (!driveHasCreds) return 'No OAuth client set yet';
    if (!driveLinked) return 'Client set — not linked to an account yet';
    if (driveFiles.isEmpty) return 'Linked — nothing backed up yet';
    final DriveFile newest = driveFiles.reduce(
      (a, b) => (a.modifiedTime ?? DateTime(0)).isAfter(b.modifiedTime ?? DateTime(0)) ? a : b,
    );
    final DateTime? when = newest.modifiedTime?.toLocal();
    final String stamp = when == null
        ? 'unknown time'
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
              '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return 'Last backup: $stamp — ${driveFiles.length} file(s)';
  }

  //called when page is closed, sets settingshandler variables and then writes settings to disk
  Future<void> _onPopInvoked(bool didPop, _) async {
    if (didPop) {
      return;
    }

    if (inProgress) {
      FlashElements.showSnackbar(
        title: Text(context.loc.pleaseWait),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(title: context.loc.settings.backupAndRestore.title),
        body: Center(
          child: ListView(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                width: double.infinity,
                child: Text(context.loc.settings.backupAndRestore.androidOnlyFeatureMsg),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !inProgress,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(title: context.loc.settings.backupAndRestore.title),
        body: Center(
          child: Stack(
            children: [
              ListView(
                children: [
                  // Backup Directory
                  SettingsButton(
                    name: context.loc.settings.backupAndRestore.selectBackupDir,
                    icon: const Icon(Symbols.folder_rounded),
                    action: () async {
                      final String path = await ServiceHandler.getSAFDirectoryAccess();
                      if (path.isNotEmpty) {
                        setState(() {
                          backupPath = path;
                          settingsHandler.backupPath = path;
                          settingsHandler.saveSettings(restate: false);
                        });
                      } else {
                        showSnackbar(
                          context.loc.settings.backupAndRestore.failedToGetBackupPath,
                          isError: true,
                        );
                      }
                    },
                    drawTopBorder: true,
                  ),
                  //
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    width: double.infinity,
                    child: Text(
                      backupPath.isNotEmpty
                          ? context.loc.settings.backupAndRestore.backupPathMsg(backupPath: backupPath)
                          : context.loc.settings.backupAndRestore.noBackupDirSelected,
                    ),
                  ),
                  //
                  if (backupPath.isNotEmpty)
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.resetBackupDir,
                      icon: const Icon(Symbols.refresh_rounded),
                      action: () async {
                        setState(() {
                          backupPath = '';
                          settingsHandler.backupPath = '';
                          settingsHandler.saveSettings(restate: false);
                        });
                      },
                      drawTopBorder: true,
                    ),
                  //
                  if (backupPath.isNotEmpty) ...[
                    // Backup
                    const SettingsButton(name: '', enabled: false),
                    SettingsButton(
                      name: 'Backup all (settings + boorus + database)',
                      icon: const Icon(Symbols.cloud_upload_rounded),
                      action: () => _runBackupAll(context),
                      drawTopBorder: true,
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.backupSettings,
                      icon: const Icon(Symbols.settings_rounded),
                      action: () async {
                        inProgress = true;
                        setState(() {});
                        try {
                          final File file = File('${await ServiceHandler.getConfigDir()}settings.json');
                          if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'settings.json')) {
                            final bool res = await detectedDuplicateFile('settings.json');
                            if (!res) {
                              showSnackbar(
                                context.loc.settings.backupAndRestore.backupCancelled,
                                isError: true,
                              );
                              inProgress = false;
                              setState(() {});
                              return;
                            }
                          }

                          await ServiceHandler.writeImage(
                            await file.readAsBytes(),
                            'settings',
                            'text/json',
                            'json',
                            backupPath,
                          );
                          showSnackbar(
                            context.loc.settings.backupAndRestore.settingsBackedUp,
                            isError: false,
                          );
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.backupSettingsError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'backupSettings',
                            LogTypes.exception,
                            s: s,
                          );
                        }
                        inProgress = false;
                        setState(() {});
                      },
                      drawTopBorder: true,
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.backupBoorus,
                      icon: const Icon(Symbols.image_search_rounded),
                      action: () async {
                        inProgress = true;
                        setState(() {});
                        try {
                          final List<Booru> booruList = settingsHandler.booruList
                              .where((e) => BooruType.saveable.contains(e.type))
                              .toList();
                          if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'boorus.json')) {
                            final bool res = await detectedDuplicateFile('boorus.json');
                            if (!res) {
                              showSnackbar(
                                context.loc.settings.backupAndRestore.backupCancelled,
                                isError: true,
                              );
                              inProgress = false;
                              setState(() {});
                              return;
                            }
                          }

                          await ServiceHandler.writeImage(
                            utf8.encode(json.encode(booruList)),
                            'boorus',
                            'text',
                            'json',
                            backupPath,
                          );
                          showSnackbar(
                            context.loc.settings.backupAndRestore.boorusBackedUp,
                            isError: false,
                          );
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.backupBoorusError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'backupBoorus',
                            LogTypes.exception,
                            s: s,
                          );
                        }
                        inProgress = false;
                        setState(() {});
                      },
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.backupDatabase,
                      icon: const Icon(Symbols.list_alt_rounded),
                      action: () async {
                        inProgress = true;
                        setState(() {});
                        try {
                          final File file = File('${await ServiceHandler.getConfigDir()}store.db');
                          if (!await file.exists()) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.databaseFileNotFound,
                              isError: true,
                            );
                            inProgress = false;
                            setState(() {});
                            return;
                          }
                          if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'store.db')) {
                            final bool res = await detectedDuplicateFile('store.db');
                            if (!res) {
                              showSnackbar(
                                context.loc.settings.backupAndRestore.backupCancelled,
                                isError: true,
                              );
                              inProgress = false;
                              setState(() {});
                              return;
                            }
                          }

                          // WAL mode keeps store.db in a consistent readable state
                          // at all times, so we can copy it safely while it's open.
                          await ServiceHandler.copyFileToSafDir(
                            await ServiceHandler.getConfigDir(),
                            'store.db',
                            backupPath,
                            'application/x-sqlite3',
                          );
                          showSnackbar(
                            context.loc.settings.backupAndRestore.databaseBackedUp,
                            isError: false,
                          );
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.backupDatabaseError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'backupDatabase',
                            LogTypes.exception,
                            s: s,
                          );
                        }
                        inProgress = false;
                        setState(() {});
                      },
                    ),
                    if (settingsHandler.isDebug.value)
                      SettingsButton(
                        name: context.loc.settings.backupAndRestore.backupTags,
                        icon: const Icon(CupertinoIcons.tag),
                        action: () async {
                          inProgress = true;
                          setState(() {});
                          try {
                            if (await ServiceHandler.existsFileFromSAFDirectory(backupPath, 'tags.json')) {
                              final bool res = await detectedDuplicateFile('tags.json');
                              if (!res) {
                                showSnackbar(
                                  context.loc.settings.backupAndRestore.backupCancelled,
                                  isError: true,
                                );
                                inProgress = false;
                                setState(() {});
                                return;
                              }
                            }

                            await ServiceHandler.writeImage(
                              utf8.encode(json.encode(tagHandler.toList())),
                              'tags',
                              'text',
                              'json',
                              backupPath,
                            );
                            showSnackbar(
                              context.loc.settings.backupAndRestore.tagsBackedUp,
                              isError: false,
                            );
                          } catch (e, s) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.backupTagsError,
                              isError: true,
                            );
                            Logger.Inst().log(
                              e.toString(),
                              'BackupRestorePage',
                              'backupTags',
                              LogTypes.exception,
                              s: s,
                            );
                          }
                          inProgress = false;
                          setState(() {});
                        },
                      ),

                    // ── Google Drive ────────────────────────────────
                    const SettingsButton(name: '', enabled: false),
                    Container(
                      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                      width: double.infinity,
                      child: Text(
                        'Google Drive',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      width: double.infinity,
                      child: Text(
                        'Backs up settings, boorus and the database into a "${DriveBackup.folderName}" '
                        'folder on your Drive. The app only ever sees files it created there — it has no '
                        'access to the rest of your Drive.\n\n${_driveSummary()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (driveBusy && driveStatus.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        width: double.infinity,
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(driveStatus)),
                          ],
                        ),
                      ),
                    SettingsButton(
                      name: driveHasCreds ? 'Change OAuth client' : 'Set OAuth client…',
                      icon: const Icon(Symbols.key_rounded),
                      action: driveBusy ? null : _editDriveCredentials,
                      drawTopBorder: true,
                    ),
                    if (driveHasCreds && !driveLinked)
                      SettingsButton(
                        name: 'Link Google account',
                        icon: const Icon(Symbols.link_rounded),
                        action: driveBusy ? null : _linkDrive,
                      ),
                    if (driveLinked) ...[
                      SettingsButton(
                        name: 'Back up to Google Drive',
                        icon: const Icon(Symbols.cloud_upload_rounded),
                        action: driveBusy ? null : _backupToDrive,
                      ),
                      SettingsButton(
                        name: 'Restore from Google Drive',
                        icon: const Icon(Symbols.cloud_download_rounded),
                        action: driveBusy ? null : _restoreFromDrive,
                      ),
                      SettingsButton(
                        name: 'Unlink Google account',
                        icon: const Icon(Symbols.link_off_rounded),
                        action: driveBusy
                            ? null
                            : () async {
                                await DriveBackup.unlink();
                                await _refreshDriveState();
                                showSnackbar('Google account unlinked.', isError: false);
                              },
                      ),
                    ],

                    // Restore
                    const SettingsButton(name: '', enabled: false),
                    Container(
                      margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      width: double.infinity,
                      child: Text(context.loc.settings.backupAndRestore.restoreInfoMsg),
                    ),
                    SettingsButton(
                      name: 'Restore all (settings + boorus + database)',
                      icon: const Icon(Symbols.cloud_download_rounded),
                      action: () => _runRestoreAll(context),
                      drawTopBorder: true,
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.restoreSettings,
                      icon: const Icon(Symbols.settings_backup_restore_rounded),
                      subtitle: const Text('settings.json'),
                      action: () async {
                        final bool res = await confirmRestore(context.loc.settings.backupAndRestore.restoreSettings);
                        if (!res) return;

                        inProgress = true;
                        setState(() {});
                        try {
                          final Uint8List? settingsFileBytes = await ServiceHandler.getFileFromSAFDirectory(
                            backupPath,
                            'settings.json',
                          );
                          if (settingsFileBytes != null) {
                            final File newFile = File('${await ServiceHandler.getConfigDir()}settings.json');
                            if (!(await newFile.exists())) {
                              await newFile.create();
                            }
                            await newFile.writeAsBytes(settingsFileBytes);
                            await settingsHandler.loadSettingsJson();
                            showSnackbar(
                              context.loc.settings.backupAndRestore.settingsRestored,
                              isError: false,
                            );
                          } else {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.backupFileNotFound,
                              isError: true,
                            );
                          }
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.restoreSettingsError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'restoreSettings',
                            LogTypes.exception,
                            s: s,
                          );
                        }
                        inProgress = false;
                        setState(() {});
                      },
                      drawTopBorder: true,
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.restoreBoorus,
                      icon: const Icon(Symbols.image_search_rounded),
                      subtitle: const Text('boorus.json'),
                      action: () async {
                        final bool res = await confirmRestore(context.loc.settings.backupAndRestore.restoreBoorus);
                        if (!res) return;

                        inProgress = true;
                        setState(() {});
                        try {
                          final Uint8List? booruFileBytes = await ServiceHandler.getFileFromSAFDirectory(
                            backupPath,
                            'boorus.json',
                          );
                          String boorusJSONString = '';
                          if (booruFileBytes != null) {
                            boorusJSONString = String.fromCharCodes(booruFileBytes);

                            if (boorusJSONString.isNotEmpty) {
                              final List<dynamic> json = jsonDecode(boorusJSONString);
                              final String configBoorusPath = '${await ServiceHandler.getConfigDir()}boorus/';
                              final Directory configBoorusDir = await Directory(
                                configBoorusPath,
                              ).create(recursive: true);
                              if (json.isNotEmpty) {
                                for (int i = 0; i < json.length; i++) {
                                  final Booru booru = Booru.fromMap(json[i]);
                                  final bool alreadyExists =
                                      settingsHandler.booruList.indexWhere(
                                        (el) => el.baseURL == booru.baseURL && el.name == booru.name,
                                      ) !=
                                      -1;
                                  final bool isAllowed = BooruType.saveable.contains(booru.type);
                                  if (!alreadyExists && isAllowed) {
                                    final File booruFile = File('${configBoorusDir.path}${booru.name}.json');
                                    final writer = booruFile.openWrite();
                                    writer.write(jsonEncode(booru.toJson()));
                                    await writer.close();
                                  }
                                }
                                await settingsHandler.loadBoorus();
                                showSnackbar(
                                  context.loc.settings.backupAndRestore.boorusRestored,
                                  isError: false,
                                );
                              }
                            } else {
                              showSnackbar(
                                context.loc.settings.backupAndRestore.backupFileNotFound,
                                isError: true,
                              );
                            }
                          } else {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.backupFileNotFound,
                              isError: true,
                            );
                          }
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.restoreBoorusError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'restoreBoorus',
                            LogTypes.exception,
                            s: s,
                          );
                        }
                        inProgress = false;
                        setState(() {});
                      },
                    ),
                    SettingsButton(
                      name: context.loc.settings.backupAndRestore.restoreDatabase,
                      icon: const Icon(Symbols.list_alt_rounded),
                      subtitle: Text('store.db (${context.loc.settings.backupAndRestore.restoreDatabaseInfo})'),
                      action: () async {
                        final bool res = await confirmRestore(context.loc.settings.backupAndRestore.restoreDatabase);
                        if (!res) return;

                        inProgress = true;
                        setState(() {});
                        try {
                          final fileExists = await ServiceHandler.existsFileFromSAFDirectory(
                            backupPath,
                            'store.db',
                          );
                          if (!fileExists) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.backupFileNotFound,
                              isError: true,
                            );
                            inProgress = false;
                            setState(() {});
                            return;
                          }

                          // disable backupping while restoring the db
                          searchHandler.canBackup.value = false;

                          final String configDir = await ServiceHandler.getConfigDir();

                          // Close the DB before overwriting the file on disk.
                          await settingsHandler.dbHandler.closeDb();

                          // Delete stale WAL/SHM sidecars before copying.
                          for (final suffix in ['-wal', '-shm']) {
                            final sidecar = File('${configDir}store.db$suffix');
                            if (await sidecar.exists()) await sidecar.delete();
                          }

                          final bool res = await ServiceHandler.copySafFileToDir(
                            backupPath,
                            'store.db',
                            configDir,
                          );

                          if (!res) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.restoreDatabaseError,
                              isError: true,
                            );
                            searchHandler.canBackup.value = true;
                            inProgress = false;
                            setState(() {});
                            return;
                          }

                          final File newFile = File('${configDir}store.db');
                          if (!(await newFile.exists())) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.restoreDatabaseError,
                              isError: true,
                            );
                            searchHandler.canBackup.value = true;
                            inProgress = false;
                            setState(() {});
                            return;
                          }
                          _rearmDoujinMigration();
                          showSnackbar(
                            context.loc.settings.backupAndRestore.databaseRestored,
                            isError: false,
                          );
                          await Future.delayed(const Duration(seconds: 3));
                          unawaited(ServiceHandler.restartApp());
                        } catch (e, s) {
                          showSnackbar(
                            context.loc.settings.backupAndRestore.restoreDatabaseError,
                            isError: true,
                          );
                          Logger.Inst().log(
                            e.toString(),
                            'BackupRestorePage',
                            'restoreDatabase',
                            LogTypes.exception,
                            s: s,
                          );
                          searchHandler.canBackup.value = true;
                        }
                        inProgress = false;
                        setState(() {});
                      },
                    ),
                    if (settingsHandler.isDebug.value)
                      SettingsButton(
                        name: context.loc.settings.backupAndRestore.restoreTags,
                        icon: const Icon(CupertinoIcons.tag),
                        subtitle: Text('tags.json (${context.loc.settings.backupAndRestore.restoreTagsInfo})'),
                        action: () async {
                          final bool res = await confirmRestore(context.loc.settings.backupAndRestore.restoreTags);
                          if (!res) return;

                          inProgress = true;
                          setState(() {});
                          try {
                            final Uint8List? tagFileBytes = await ServiceHandler.getFileFromSAFDirectory(
                              backupPath,
                              'tags.json',
                            );
                            String tagJSONString = '';
                            if (tagFileBytes != null) {
                              tagJSONString = String.fromCharCodes(tagFileBytes);

                              if (tagJSONString.isNotEmpty) {
                                await tagHandler.loadFromJSON(
                                  tagJSONString,
                                  onProgress: (newProgress, newTotal) {
                                    progress = newProgress;
                                    total = newTotal;
                                    if (mounted) {
                                      setState(() {});
                                    }
                                  },
                                );
                                showSnackbar(
                                  context.loc.settings.backupAndRestore.tagsRestored,
                                  isError: false,
                                );
                              } else {
                                showSnackbar(
                                  context.loc.settings.backupAndRestore.tagsFileNotFound,
                                  isError: true,
                                );
                              }
                            } else {
                              showSnackbar(
                                context.loc.settings.backupAndRestore.tagsFileNotFound,
                                isError: true,
                              );
                            }
                          } catch (e, s) {
                            showSnackbar(
                              context.loc.settings.backupAndRestore.restoreTagsError,
                              isError: true,
                            );
                            Logger.Inst().log(
                              e.toString(),
                              'BackupRestorePage',
                              'restoreTags',
                              LogTypes.exception,
                              s: s,
                            );
                          }
                          inProgress = false;
                          progress = 0;
                          total = 0;
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                  ],
                ],
              ),
              //
              if (inProgress)
                Positioned.fill(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    color: Colors.black38,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(context.loc.pleaseWait),
                        if (progress != 0 && total != 0) ...[
                          Text('$progress / $total'),
                          Text(context.loc.settings.backupAndRestore.operationTakesTooLongMsg),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            child: Text(context.loc.hide),
                            onPressed: () async {
                              inProgress = false;
                              setState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
