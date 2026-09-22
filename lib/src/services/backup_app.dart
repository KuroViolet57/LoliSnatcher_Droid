import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/deferred_learning.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/services/drive_backup.dart';

/// r80: the backup's hooks into the running app.
BackupHooks appBackupHooks() {
  final SettingsHandler settings = SettingsHandler.instance;
  return BackupHooks(
    sourcesJson: () => json.encode(settings.booruList.where((Booru b) => BooruType.saveable.contains(b.type)).toList()),
    restoreSources: (String text) async {
      if (text.trim().isEmpty) return;
      final List<dynamic> parsed = jsonDecode(text) as List<dynamic>;
      final Directory dir = await Directory('${await ServiceHandler.getConfigDir()}boorus/').create(recursive: true);
      for (final dynamic raw in parsed) {
        final Booru booru = Booru.fromMap(raw as Map<String, dynamic>);
        final bool exists = settings.booruList.any((Booru b) => b.baseURL == booru.baseURL && b.name == booru.name);
        if (exists || !BooruType.saveable.contains(booru.type)) continue;
        await File('${dir.path}${booru.name}.json').writeAsString(jsonEncode(booru.toJson()));
      }
      await settings.loadBoorus();
    },
    tagTypesJson: () => json.encode(TagHandler.instance.toList()),
    restoreTagTypes: (String text) async {
      if (text.trim().isEmpty) return;
      await TagHandler.instance.loadFromJSON(text);
    },
    reloadStores: () {
      DoujinDataHandler.instance.reloadFromDisk();
      SourceSettingsHandler.instance.reloadFromDisk();
      BookmarkHandler.instance.reloadFromDisk();
      unawaited(BoardsHandler.instance.reloadFromDisk());
    },
    stopRecommenderWrites: () {
      RecommenderHandler.maybe?.stopWritingForRestore();
      DeferredLearning.instance.stop();
    },
    checkpointDatabase: () async {
      // The newest changes can still sit in the journal file (WAL); a copy of
      // store.db alone would miss them.
      await settings.dbHandler.db?.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    },
    closeDatabase: () async {
      SearchHandler.instance.canBackup.value = false;
      await settings.dbHandler.closeDb();
    },
    rearmDoujinMigration: () {
      // A restored store.db may predate the doujin split; the one-time move
      // runs again on the restart (it is additive and safe to repeat).
      final DoujinDataHandler store = DoujinDataHandler.instance..ensureLoaded();
      store.migrationDone = false;
      store.save();
    },
    boardPicturesDir: () => '${BoardsHandler.instance.imagesDir.path}${Platform.pathSeparator}',
    liveDatabase: () => settings.dbHandler.db,
  );
}

/// A scratch folder for files on their way to or from a backup.
Future<String> backupScratchDir() async {
  final String base = await ServiceHandler.getCacheDir();
  final Directory d = await Directory('${base}backup${Platform.pathSeparator}').create(recursive: true);
  return d.path.endsWith(Platform.pathSeparator) ? d.path : '${d.path}${Platform.pathSeparator}';
}

/// The folder you chose for backups (Android's folder access). Every file
/// passes through [scratchDir] under its own name: the native copy names the
/// target after the source, and a restore is never copied straight into the
/// config folder (a part of the database must not land on store.db).
class FolderBackupTarget implements BackupTarget {
  FolderBackupTarget(this.safUri, {required this.scratchDir});

  final String safUri;
  final String scratchDir;

  @override
  String get label => 'the backup folder';

  @override
  Future<Set<String>> names() async => (await ServiceHandler.listFileNamesFromSAFDirectory(safUri)).toSet();

  @override
  Future<void> write(String name, List<int> bytes) async {
    final File tmp = File('$scratchDir$name');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await _copyIn(name, tmp);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  @override
  Future<Uint8List?> read(String name) => ServiceHandler.getFileFromSAFDirectory(safUri, name);

  @override
  Future<void> writeFile(String name, File file) async {
    if (file.uri.pathSegments.last == name) {
      await _copyIn(name, file);
      return;
    }
    final File tmp = await file.copy('$scratchDir$name');
    try {
      await _copyIn(name, tmp);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _copyIn(String name, File file) async {
    // Android's folder access never overwrites: it would write "name (1)",
    // which a restore never reads. The old copy goes first.
    if (await ServiceHandler.existsFileFromSAFDirectory(safUri, name)) {
      await ServiceHandler.deleteFileFromSAFDirectory(safUri, name);
    }
    final String dir = file.parent.path.endsWith(Platform.pathSeparator) ? file.parent.path : '${file.parent.path}${Platform.pathSeparator}';
    final bool ok = await ServiceHandler.copyFileToSafDir(dir, name, safUri, BackupItems.mimeOf(name));
    if (!ok) throw Exception('$name could not be written to the folder');
  }

  @override
  Future<bool> readToFile(String name, File to) async {
    final File staged = File('$scratchDir$name');
    if (await staged.exists()) await staged.delete();
    if (!await ServiceHandler.copySafFileToDir(safUri, name, scratchDir)) return false;
    if (!await staged.exists()) return false;
    await to.parent.create(recursive: true);
    if (await to.exists()) await to.delete();
    try {
      await staged.rename(to.path);
    } on FileSystemException {
      await staged.copy(to.path);
      await staged.delete();
    }
    return true;
  }
}

/// A snapshot folder on Google Drive.
class DriveBackupTarget implements BackupTarget {
  DriveBackupTarget(this.snapshot, {this.onProgress});

  final DriveSnapshot snapshot;
  final void Function(String name, int sent, int total)? onProgress;

  @override
  String get label => 'Google Drive "${snapshot.name}"';

  @override
  Future<Set<String>> names() async => {for (final DriveFile f in await DriveBackup.list(folderId: snapshot.id)) f.name};

  @override
  Future<void> write(String name, List<int> bytes) async {
    final String? error = await DriveBackup.upload(
      name,
      bytes,
      BackupItems.mimeOf(name),
      folderId: snapshot.id,
      onProgress: (int sent, int total) => onProgress?.call(name, sent, total),
    );
    if (error != null) throw Exception(error);
  }

  @override
  Future<Uint8List?> read(String name) => DriveBackup.download(name, folderId: snapshot.id);

  @override
  Future<void> writeFile(String name, File file) async => write(name, await file.readAsBytes());

  @override
  Future<bool> readToFile(String name, File to) async {
    final Uint8List? bytes = await read(name);
    if (bytes == null) return false;
    await to.parent.create(recursive: true);
    await to.writeAsBytes(bytes, flush: true);
    return true;
  }
}
