import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_app.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/services/db_parts.dart';
import 'package:lolisnatcher/src/services/drive_backup.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Settings → Backup & restore.
///
/// r80: one list of everything a backup can carry, ticked item by item, for
/// a folder you chose and for Google Drive alike. Drive keeps named snapshots
/// (a folder each) instead of one set of files, and is there on a fresh
/// install without choosing a folder first. The database can come back whole
/// or in parts, and the recommender's learning is an item of its own.
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  /// Seams for tests: the page is Android-only, and Drive is the network.
  static bool Function() isAndroid = _defaultIsAndroid;
  static Future<bool> Function() driveHasCredentials = _defaultHasCredentials;
  static Future<bool> Function() driveIsLinked = _defaultIsLinked;
  static Future<List<DriveSnapshot>> Function() driveSnapshots = DriveBackup.snapshots;
  static Future<String?> Function({void Function(String status)? onProgress}) driveLink = _defaultLink;

  static bool _defaultIsAndroid() => Platform.isAndroid;
  static Future<bool> _defaultHasCredentials() => DriveBackup.hasCredentials;
  static Future<bool> _defaultIsLinked() => DriveBackup.isLinked;
  static Future<String?> _defaultLink({void Function(String status)? onProgress}) => DriveBackup.link(onProgress: onProgress);

  static void resetForTests() {
    isAndroid = _defaultIsAndroid;
    driveHasCredentials = _defaultHasCredentials;
    driveIsLinked = _defaultIsLinked;
    driveSnapshots = DriveBackup.snapshots;
    driveLink = _defaultLink;
  }

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  String backupPath = '';

  /// What a backup or a restore carries; everything to begin with.
  final Set<BackupItem> selected = BackupItem.values.toSet();

  bool inProgress = false;
  String status = '';

  bool driveLinked = false;
  bool driveHasCreds = false;
  bool driveBusy = false;
  String driveStatus = '';
  List<DriveSnapshot> snapshots = const [];

  @override
  void initState() {
    super.initState();
    backupPath = settingsHandler.backupPath;
    unawaited(validateBackupPathAccess());
    unawaited(_refreshDriveState());
  }

  Future<void> validateBackupPathAccess() async {
    if (!BackupRestorePage.isAndroid() || backupPath.isEmpty) return;
    try {
      final bool success = await ServiceHandler.testSAFPersistence(backupPath);
      if (!success && mounted) {
        Logger.Inst().log('Invalid backup path', 'BackupRestorePage', 'validateBackupPathAccess', LogTypes.exception);
        setState(() {
          backupPath = '';
          settingsHandler.backupPath = '';
        });
        await settingsHandler.saveSettings(restate: false);
      }
    } catch (_) {}
  }

  void showSnackbar(String text, {required bool isError}) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        isError ? context.loc.errorExclamation : context.loc.successExclamation,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(text, style: const TextStyle(fontSize: 16)),
      leadingIcon: isError ? Symbols.error_rounded : Symbols.done_rounded,
      leadingIconColor: isError ? Colors.red : Colors.green,
      sideColor: isError ? Colors.red : Colors.green,
    );
  }

  // ───────────────────────────── Google Drive ─────────────────────────────

  /// r80: whether Drive is set up is shown first; the list of snapshots after.
  /// The listing is a network call: right after the Google sign-in it could
  /// fail and, before r80, took the page's update down with it - the options
  /// only appeared after a restart.
  Future<void> _refreshDriveState() async {
    bool hasCreds = false;
    bool linked = false;
    try {
      hasCreds = await BackupRestorePage.driveHasCredentials();
      linked = await BackupRestorePage.driveIsLinked();
    } catch (e) {
      Logger.Inst().log('drive state could not be read: $e', 'BackupRestorePage', '_refreshDriveState', LogTypes.exception);
    }
    if (!mounted) return;
    setState(() {
      driveHasCreds = hasCreds;
      driveLinked = linked;
      if (!linked) snapshots = const [];
    });
    if (!linked) return;
    try {
      final List<DriveSnapshot> list = await BackupRestorePage.driveSnapshots();
      if (mounted) setState(() => snapshots = list);
    } catch (e) {
      Logger.Inst().log('drive snapshots could not be listed: $e', 'BackupRestorePage', '_refreshDriveState', LogTypes.exception);
    }
  }

  Future<void> _editDriveCredentials() async {
    final TextEditingController idController = TextEditingController(text: await DriveBackup.clientId ?? '');
    final TextEditingController secretController = TextEditingController(text: await DriveBackup.clientSecret ?? '');
    if (!mounted) return;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
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
    String? error;
    try {
      error = await BackupRestorePage.driveLink(
        onProgress: (String s) {
          if (mounted) setState(() => driveStatus = s);
        },
      );
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      driveBusy = false;
      driveStatus = '';
    });
    if (error == null) {
      showSnackbar('Google Drive linked.', isError: false);
    } else {
      // r42: a dialog, not a snackbar: the person is often still coming back
      // from the browser when this lands.
      final String message = error;
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Google Drive was not linked'),
          content: SelectableText(message),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      if (!mounted) return;
    }
    await _refreshDriveState();
  }

  Future<void> _unlinkDrive() async {
    await DriveBackup.unlink();
    await _refreshDriveState();
  }

  String _driveSummary() {
    if (!driveHasCreds) return 'No OAuth client set yet.';
    if (!driveLinked) return 'Client set - not linked to an account yet.';
    if (snapshots.isEmpty) return 'Linked - nothing backed up yet.';
    final DriveSnapshot newest = snapshots.first;
    return 'Linked - ${snapshots.length} backup${snapshots.length == 1 ? '' : 's'}, newest "${newest.name}" (${_when(newest.created)}).';
  }

  static String _when(DateTime? t) {
    if (t == null) return 'unknown date';
    final DateTime l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  // ───────────────────────────── back up / restore ─────────────────────────────

  Future<BackupRunner> _runner() async => BackupRunner(configDir: await ServiceHandler.getConfigDir(), hooks: appBackupHooks());

  void _setStatus(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<void> _backupTo(BackupTarget target) async {
    setState(() {
      inProgress = true;
      status = 'Starting…';
    });
    BackupResult result;
    try {
      result = await (await _runner()).backup(selected, target, onStep: _setStatus);
    } catch (e) {
      result = BackupResult(['$e']);
    }
    if (!mounted) return;
    setState(() {
      inProgress = false;
      status = '';
    });
    showSnackbar(
      result.failures.isEmpty
          ? 'Backed up ${result.done.length} item${result.done.length == 1 ? '' : 's'} to ${target.label}.'
          : 'Finished with errors: ${result.failures.join(', ')}',
      isError: result.failures.isNotEmpty,
    );
  }

  Future<void> _backupToFolder() async {
    if (!_checkSelection()) return;
    await _backupTo(FolderBackupTarget(backupPath, scratchDir: await backupScratchDir()));
  }

  Future<void> _backupToDrive() async {
    if (!_checkSelection()) return;
    final String? name = await _askSnapshotName();
    if (name == null || !mounted) return;
    setState(() {
      inProgress = true;
      status = 'Making the snapshot folder…';
    });
    DriveSnapshot? snapshot;
    try {
      snapshot = await DriveBackup.createSnapshot(name);
    } catch (e) {
      Logger.Inst().log('drive snapshot folder not made: $e', 'BackupRestorePage', '_backupToDrive', LogTypes.exception);
    }
    if (!mounted) return;
    if (snapshot == null) {
      setState(() {
        inProgress = false;
        status = '';
      });
      showSnackbar('The snapshot folder could not be made on Google Drive.', isError: true);
      return;
    }
    await _backupTo(
      DriveBackupTarget(
        snapshot,
        onProgress: (String file, int sent, int total) {
          if (total > 0) _setStatus('Uploading $file - ${(100 * sent / total).round()}%');
        },
      ),
    );
    await _refreshDriveState();
  }

  bool _checkSelection() {
    if (selected.isNotEmpty) return true;
    showSnackbar('Tick at least one item to back up.', isError: true);
    return false;
  }

  Future<void> _restoreFromFolder() async {
    final FolderBackupTarget target = FolderBackupTarget(backupPath, scratchDir: await backupScratchDir());
    if (!mounted) return;
    setState(() {
      inProgress = true;
      status = 'Reading the folder…';
    });
    Set<BackupItem> present = {};
    try {
      present = BackupItems.itemsIn(await target.names());
    } catch (e) {
      Logger.Inst().log('the backup folder could not be listed: $e', 'BackupRestorePage', '_restoreFromFolder', LogTypes.exception);
    }
    if (!mounted) return;
    setState(() {
      inProgress = false;
      status = '';
    });
    final Set<BackupItem>? items = await _pickItems('Restore from the folder', present);
    if (items == null || items.isEmpty || !mounted) return;
    await _restore(target, items);
  }

  Future<void> _restoreFromDrive() async {
    final DriveSnapshot? snapshot = await _pickSnapshot();
    if (snapshot == null || !mounted) return;
    final DriveBackupTarget target = DriveBackupTarget(snapshot);
    setState(() {
      inProgress = true;
      status = 'Reading "${snapshot.name}"…';
    });
    Set<BackupItem> present = {};
    try {
      present = BackupItems.itemsIn(await target.names());
    } catch (e) {
      Logger.Inst().log('drive snapshot could not be listed: $e', 'BackupRestorePage', '_restoreFromDrive', LogTypes.exception);
    }
    if (!mounted) return;
    setState(() {
      inProgress = false;
      status = '';
    });
    final Set<BackupItem>? items = await _pickItems('Restore from "${snapshot.name}"', present);
    if (items == null || items.isEmpty || !mounted) return;
    await _restore(target, items);
  }

  Future<void> _restore(BackupTarget target, Set<BackupItem> items) async {
    DbRestore mode = DbRestore.whole;
    Set<DbPart> parts = const {};
    if (items.contains(BackupItem.database)) {
      final (DbRestore, Set<DbPart>)? choice = await _askDatabaseRestore();
      if (choice == null || !mounted) return;
      (mode, parts) = choice;
    }
    final bool ok = await _confirmRestore(items, mode, parts, target.label);
    if (!ok || !mounted) return;
    setState(() {
      inProgress = true;
      status = 'Starting…';
    });
    BackupResult result;
    try {
      result = await (await _runner()).restore(items, target, db: mode, parts: parts, onStep: _setStatus);
    } catch (e) {
      result = BackupResult(['$e']);
    }
    if (!mounted) return;
    setState(() {
      inProgress = false;
      status = '';
    });
    if (result.failures.isNotEmpty) {
      showSnackbar('Restore finished with errors: ${result.failures.join(', ')}', isError: true);
    }
    if (result.needsRestart) {
      if (result.failures.isEmpty) showSnackbar('Restored. The app restarts in a moment.', isError: false);
      await Future<void>.delayed(const Duration(seconds: 3));
      unawaited(ServiceHandler.restartApp());
    } else if (result.failures.isEmpty) {
      showSnackbar('Restored.', isError: false);
    }
  }

  // ───────────────────────────── dialogs ─────────────────────────────

  Future<String?> _askSnapshotName() async {
    final TextEditingController name = TextEditingController(text: DriveBackup.defaultSnapshotName(DateTime.now()));
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('New backup on Google Drive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'It goes into a folder of its own inside LoliSnatcher on your Drive. Earlier backups stay as they are.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('snapshot-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(name.text.trim()), child: const Text('Back up')),
        ],
      ),
    );
  }

  /// The backups on Drive, newest first; tap one to restore from it. A
  /// snapshot can be deleted here too.
  Future<DriveSnapshot?> _pickSnapshot() async {
    await _refreshDriveState();
    if (!mounted) return null;
    return showDialog<DriveSnapshot>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialog) => AlertDialog(
          title: const Text('Restore from Google Drive'),
          content: SizedBox(
            width: double.maxFinite,
            child: snapshots.isEmpty
                ? const Text('There is no backup on your Drive yet.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final DriveSnapshot s in snapshots)
                        ListTile(
                          key: ValueKey('snapshot-${s.id}'),
                          leading: Icon(s.earlier ? Symbols.history_rounded : Symbols.folder_rounded),
                          title: Text(s.name),
                          subtitle: Text(s.earlier ? '${_when(s.created)} - made before backups had their own folders' : _when(s.created)),
                          onTap: () => Navigator.of(ctx).pop(s),
                          trailing: s.earlier
                              ? null
                              : IconButton(
                                  tooltip: 'Delete this backup',
                                  icon: const Icon(Symbols.delete_rounded),
                                  onPressed: () async {
                                    final bool sure =
                                        await showDialog<bool>(
                                          context: ctx,
                                          builder: (BuildContext c) => AlertDialog(
                                            title: Text('Delete "${s.name}"?'),
                                            content: const Text('Its files are removed from your Google Drive.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!sure) return;
                                    final bool gone = await DriveBackup.deleteSnapshot(s);
                                    if (!gone) {
                                      showSnackbar('"${s.name}" could not be deleted.', isError: true);
                                      return;
                                    }
                                    await _refreshDriveState();
                                    if (ctx.mounted) setDialog(() {});
                                  },
                                ),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
        ),
      ),
    );
  }

  /// Which of the items this backup holds come back; the ticks start from
  /// the page's own.
  Future<Set<BackupItem>?> _pickItems(String title, Set<BackupItem> present) async {
    final Set<BackupItem> chosen = selected.intersection(present).isNotEmpty ? selected.intersection(present) : present.toSet();
    return showDialog<Set<BackupItem>>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: present.isEmpty
                ? const Text('No backup files were found there.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final BackupItem i in BackupItem.values)
                        CheckboxListTile(
                          key: ValueKey('restore-item-${i.name}'),
                          dense: true,
                          value: chosen.contains(i),
                          title: Text(BackupItems.labelOf(i)),
                          subtitle: present.contains(i) ? null : const Text('not in this backup'),
                          onChanged: present.contains(i)
                              ? (bool? v) => setDialog(() => v == true ? chosen.add(i) : chosen.remove(i))
                              : null,
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: chosen.isEmpty ? null : () => Navigator.of(ctx).pop(chosen),
              child: Text('Restore ${chosen.length}'),
            ),
          ],
        ),
      ),
    );
  }

  /// The database back whole, or only some of its parts.
  Future<(DbRestore, Set<DbPart>)?> _askDatabaseRestore() async {
    DbRestore mode = DbRestore.whole;
    final Set<DbPart> parts = DbPart.values.toSet();
    return showDialog<(DbRestore, Set<DbPart>)>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialog) => AlertDialog(
          title: const Text('Restore the database'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioGroup<DbRestore>(
                  groupValue: mode,
                  onChanged: (DbRestore? v) => setDialog(() => mode = v ?? mode),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<DbRestore>(
                        key: ValueKey('db-whole'),
                        value: DbRestore.whole,
                        title: Text('The whole database'),
                        subtitle: Text('Replaces favourites, history, collections, pins, pulled tags and the recommendation log.'),
                      ),
                      RadioListTile<DbRestore>(
                        key: ValueKey('db-parts'),
                        value: DbRestore.parts,
                        title: Text('Only these parts'),
                        subtitle: Text('Favourites, history and the rest stay as they are here.'),
                      ),
                    ],
                  ),
                ),
                for (final DbPart p in DbPart.values)
                  CheckboxListTile(
                    key: ValueKey('db-part-${p.name}'),
                    dense: true,
                    value: parts.contains(p),
                    title: Text(DbParts.labelOf(p)),
                    subtitle: Text(DbParts.describe(p)),
                    onChanged: mode == DbRestore.parts ? (bool? v) => setDialog(() => v == true ? parts.add(p) : parts.remove(p)) : null,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: mode == DbRestore.parts && parts.isEmpty ? null : () => Navigator.of(ctx).pop((mode, parts.toSet())),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmRestore(Set<BackupItem> items, DbRestore mode, Set<DbPart> parts, String from) async {
    final List<String> what = [
      for (final BackupItem i in BackupItem.values)
        if (items.contains(i))
          i == BackupItem.database && mode == DbRestore.parts
              ? 'Database: ${[for (final DbPart p in DbPart.values) if (parts.contains(p)) DbParts.labelOf(p)].join(', ')}'
              : BackupItems.labelOf(i),
    ];
    // Tag types and the vector cache come back without a restart.
    final bool restarts = items.any((BackupItem i) => i != BackupItem.tagTypes && i != BackupItem.vectors);
    final bool merges = items.contains(BackupItem.database) && mode == DbRestore.parts;
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Restore?'),
            content: SingleChildScrollView(
              child: Text(
                'From $from:\n\n${what.map((String w) => '• $w').join('\n')}\n\n'
                'What is on this device for these is replaced'
                '${merges ? ' (pulled tags and vectors are added to what is here)' : ''}.'
                '${restarts ? ' The app restarts at the end.' : ''}',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(key: const ValueKey('confirm-restore'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Restore')),
            ],
          ),
        ) ??
        false;
  }

  // ───────────────────────────── page ─────────────────────────────

  Future<void> _chooseFolder() async {
    final String path = await ServiceHandler.getSAFDirectoryAccess();
    if (!mounted) return;
    if (path.isEmpty) {
      showSnackbar(context.loc.settings.backupAndRestore.failedToGetBackupPath, isError: true);
      return;
    }
    setState(() {
      backupPath = path;
      settingsHandler.backupPath = path;
    });
    await settingsHandler.saveSettings(restate: false);
  }

  Future<void> _resetFolder() async {
    setState(() {
      backupPath = '';
      settingsHandler.backupPath = '';
    });
    await settingsHandler.saveSettings(restate: false);
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    if (!BackupRestorePage.isAndroid()) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(title: context.loc.settings.backupAndRestore.title),
        body: Center(
          child: ListView(
            children: [
              Container(
                margin: const EdgeInsets.all(10),
                width: double.infinity,
                child: Text(context.loc.settings.backupAndRestore.androidOnlyFeatureMsg),
              ),
            ],
          ),
        ),
      );
    }

    final bool busy = inProgress || driveBusy;
    final bool hasFolder = backupPath.isNotEmpty;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop) return;
        FlashElements.showSnackbar(
          title: Text(context.loc.pleaseWait),
          leadingIcon: Symbols.warning_amber_rounded,
          leadingIconColor: Colors.yellow,
          sideColor: Colors.yellow,
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(title: context.loc.settings.backupAndRestore.title),
        body: Stack(
          children: [
            ListView(
              children: [
                // ── what ──
                _section('What to back up or restore'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      TextButton(
                        key: const ValueKey('backup-all'),
                        onPressed: busy ? null : () => setState(() => selected.addAll(BackupItem.values)),
                        child: const Text('All'),
                      ),
                      TextButton(
                        key: const ValueKey('backup-none'),
                        onPressed: busy ? null : () => setState(selected.clear),
                        child: const Text('None'),
                      ),
                      const Spacer(),
                      Text('${selected.length} of ${BackupItem.values.length}', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                for (final BackupItem i in BackupItem.values)
                  CheckboxListTile(
                    key: ValueKey('backup-item-${i.name}'),
                    value: selected.contains(i),
                    title: Text(BackupItems.labelOf(i)),
                    subtitle: Text(BackupItems.describe(i)),
                    onChanged: busy ? null : (bool? v) => setState(() => v == true ? selected.add(i) : selected.remove(i)),
                  ),
                // ── a folder ──
                _section('A folder on this device'),
                SettingsButton(
                  name: context.loc.settings.backupAndRestore.selectBackupDir,
                  icon: const Icon(Symbols.folder_rounded),
                  action: busy ? null : _chooseFolder,
                  drawTopBorder: true,
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  width: double.infinity,
                  child: Text(
                    hasFolder
                        ? context.loc.settings.backupAndRestore.backupPathMsg(backupPath: backupPath)
                        : context.loc.settings.backupAndRestore.noBackupDirSelected,
                  ),
                ),
                if (hasFolder) ...[
                  SettingsButton(
                    key: const ValueKey('backup-to-folder'),
                    name: 'Back up to the folder',
                    subtitle: const Text('The ticked items; older copies there are replaced.'),
                    icon: const Icon(Symbols.upload_rounded),
                    action: busy ? null : _backupToFolder,
                  ),
                  SettingsButton(
                    key: const ValueKey('restore-from-folder'),
                    name: 'Restore from the folder…',
                    subtitle: const Text('Pick what comes back.'),
                    icon: const Icon(Symbols.download_rounded),
                    action: busy ? null : _restoreFromFolder,
                  ),
                  SettingsButton(
                    name: context.loc.settings.backupAndRestore.resetBackupDir,
                    icon: const Icon(Symbols.refresh_rounded),
                    action: busy ? null : _resetFolder,
                  ),
                ],
                // ── Google Drive ── (r80: no folder needed first)
                _section('Google Drive'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(driveStatus.isNotEmpty ? driveStatus : _driveSummary(), key: const ValueKey('drive-summary')),
                ),
                SettingsButton(
                  key: const ValueKey('drive-client'),
                  name: driveHasCreds ? 'Change OAuth client' : 'Set OAuth client…',
                  icon: const Icon(Symbols.key_rounded),
                  action: busy ? null : _editDriveCredentials,
                ),
                if (driveHasCreds && !driveLinked)
                  SettingsButton(
                    key: const ValueKey('drive-link'),
                    name: 'Link Google account',
                    icon: const Icon(Symbols.link_rounded),
                    action: busy ? null : _linkDrive,
                  ),
                if (driveLinked) ...[
                  SettingsButton(
                    key: const ValueKey('backup-to-drive'),
                    name: 'Back up to Google Drive…',
                    subtitle: const Text('A new named backup in a folder of its own.'),
                    icon: const Icon(Symbols.cloud_upload_rounded),
                    action: busy ? null : _backupToDrive,
                  ),
                  SettingsButton(
                    key: const ValueKey('restore-from-drive'),
                    name: 'Restore from Google Drive…',
                    subtitle: const Text('Pick a backup by name and date, then what comes back.'),
                    icon: const Icon(Symbols.cloud_download_rounded),
                    action: busy ? null : _restoreFromDrive,
                  ),
                  SettingsButton(
                    name: 'Unlink Google account',
                    icon: const Icon(Symbols.link_off_rounded),
                    action: busy ? null : _unlinkDrive,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
            if (busy)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Material(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(status.isNotEmpty ? status : driveStatus, key: const ValueKey('backup-status')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
