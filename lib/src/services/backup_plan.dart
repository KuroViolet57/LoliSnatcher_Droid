import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'package:lolisnatcher/src/services/db_parts.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r80: what a backup can carry. Each item is ticked on its own, for a
/// backup and for a restore.
enum BackupItem {
  settings,
  sources,
  doujinLibrary,
  sourceSettings,
  bookmarks,
  boards,
  boardPictures,
  tagTypes,
  database,

  /// r81: the vectors, in a database of their own (vectors.db).
  vectors,
  recommender,
}

class BackupItems {
  const BackupItems._();

  /// The recommender's files and the boards' pictures are many; each goes
  /// under its own prefix in a backup, which is a flat list of files.
  static const String recommenderPrefix = 'recommender.';
  static const String boardPicturePrefix = 'board-picture.';

  /// The items that are one file, by their name here and in a backup (the
  /// same names older backups used).
  static const Map<BackupItem, String> fileOf = {
    BackupItem.settings: 'settings.json',
    BackupItem.sources: 'boorus.json',
    BackupItem.doujinLibrary: 'doujinData.json',
    BackupItem.sourceSettings: 'sourceSettings.json',
    BackupItem.bookmarks: 'bookmarks.json',
    BackupItem.boards: 'boards.json',
    BackupItem.tagTypes: 'tags.json',
    BackupItem.database: 'store.db',
    BackupItem.vectors: 'vectors.db',
  };

  static String labelOf(BackupItem item) {
    switch (item) {
      case BackupItem.settings:
        return 'Settings';
      case BackupItem.sources:
        return 'Sources';
      case BackupItem.doujinLibrary:
        return 'Doujin library';
      case BackupItem.sourceSettings:
        return 'Source settings';
      case BackupItem.bookmarks:
        return 'Bookmarks';
      case BackupItem.boards:
        return 'Boards';
      case BackupItem.boardPictures:
        return 'Board pictures';
      case BackupItem.tagTypes:
        return 'Tag types';
      case BackupItem.database:
        return 'Database';
      case BackupItem.vectors:
        return 'Vector cache';
      case BackupItem.recommender:
        return 'Recommendations';
    }
  }

  static String describe(BackupItem item) {
    switch (item) {
      case BackupItem.settings:
        return 'Every setting of the app (settings.json).';
      case BackupItem.sources:
        return 'The booru and doujin sources you added (boorus.json).';
      case BackupItem.doujinLibrary:
        return 'Doujin favourites, collections, pins and history (doujinData.json).';
      case BackupItem.sourceSettings:
        return 'Per-source settings, blacklists and hidden pins (sourceSettings.json).';
      case BackupItem.bookmarks:
        return 'Reader bookmarks (bookmarks.json).';
      case BackupItem.boards:
        return 'Your boards and the SauceNAO key (boards.json).';
      case BackupItem.boardPictures:
        return "The boards' reference pictures, kept on this device.";
      case BackupItem.tagTypes:
        return 'Tag types and colours you set (tags.json).';
      case BackupItem.database:
        return 'Favourites, history, collections, pins, pulled tags and the recommendation log (store.db). A restore can take only some parts.';
      case BackupItem.vectors:
        return 'What the text and looks models worked out for posts (vectors.db), so they are not read again. It can be large; a restore adds it to what is here.';
      case BackupItem.recommender:
        return 'What the recommender learned: its weights and your text and visual taste. With the same models on the other device, it recommends the same way.';
    }
  }

  /// Which item a backup file belongs to; null for a file that is none.
  static BackupItem? itemOf(String name) {
    for (final MapEntry<BackupItem, String> e in fileOf.entries) {
      if (e.value == name) return e.key;
    }
    if (name.startsWith(recommenderPrefix) && name.length > recommenderPrefix.length) return BackupItem.recommender;
    if (name.startsWith(boardPicturePrefix) && name.length > boardPicturePrefix.length) return BackupItem.boardPictures;
    return null;
  }

  /// The items a backup holds, from its file names (older backups included).
  static Set<BackupItem> itemsIn(Iterable<String> names) => {
    for (final String n in names)
      if (itemOf(n) != null) itemOf(n)!,
  };

  /// The file type a Drive upload or a folder file is given.
  static String mimeOf(String name) {
    final String n = name.toLowerCase();
    if (n.endsWith('.json')) return 'application/json';
    if (n.endsWith('.db')) return 'application/x-sqlite3';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }
}

/// Where a backup goes and comes from: a folder you chose, or a snapshot
/// folder on Google Drive. Names are flat file names.
abstract class BackupTarget {
  String get label;

  /// The file names there now.
  Future<Set<String>> names();

  Future<void> write(String name, List<int> bytes);

  /// Null when there is no such file.
  Future<Uint8List?> read(String name);

  /// A large file (the database) straight from disk.
  Future<void> writeFile(String name, File file);

  /// A large file straight to disk; false when there is no such file.
  Future<bool> readToFile(String name, File to);
}

/// What a backup and a restore need from the rest of the app. Replaced in
/// tests.
class BackupHooks {
  const BackupHooks({
    required this.sourcesJson,
    required this.restoreSources,
    required this.tagTypesJson,
    required this.restoreTagTypes,
    required this.reloadStores,
    required this.stopRecommenderWrites,
    required this.checkpointDatabase,
    required this.closeDatabase,
    required this.rearmDoujinMigration,
    required this.boardPicturesDir,
    required this.liveDatabase,
    required this.checkpointVectors,
    required this.liveVectors,
  });

  final String Function() sourcesJson;
  final Future<void> Function(String json) restoreSources;
  final String Function() tagTypesJson;
  final Future<void> Function(String json) restoreTagTypes;

  /// The doujin, source-settings, bookmark and board stores read their files
  /// again.
  final void Function() reloadStores;

  /// The recommender forgets what it holds in memory and stops writing, so it
  /// cannot write over the files being restored.
  final void Function() stopRecommenderWrites;

  /// The database's journal is written into the file before it is copied.
  final Future<void> Function() checkpointDatabase;
  final Future<void> Function() closeDatabase;
  final void Function() rearmDoujinMigration;

  /// With a trailing separator.
  final String Function() boardPicturesDir;
  final Database? Function() liveDatabase;

  /// r81: the vectors' database: its journal written in before a copy, and
  /// the open one a restore adds to.
  final Future<void> Function() checkpointVectors;
  final Database? Function() liveVectors;
}

class BackupResult {
  const BackupResult(this.failures, {this.needsRestart = false, this.done = const {}});

  final List<String> failures;
  final bool needsRestart;

  /// The items that went through.
  final Set<BackupItem> done;
}

/// How the database is restored.
enum DbRestore { whole, parts }

class BackupRunner {
  BackupRunner({required this.configDir, required this.hooks});

  /// The app's config folder, with a trailing separator.
  final String configDir;
  final BackupHooks hooks;

  static final String _sep = Platform.pathSeparator;

  String get _recommenderDir => '${configDir}recommender$_sep';

  /// Writes the [items] to [target]. An item this device has nothing of yet
  /// is skipped, not a failure.
  Future<BackupResult> backup(Set<BackupItem> items, BackupTarget target, {void Function(String step)? onStep}) async {
    final List<String> failures = [];
    final Set<BackupItem> done = {};
    for (final BackupItem item in BackupItem.values) {
      if (!items.contains(item)) continue;
      onStep?.call('Backing up ${BackupItems.labelOf(item)}…');
      try {
        if (await _backupOne(item, target)) done.add(item);
      } catch (e, s) {
        failures.add('${BackupItems.labelOf(item)}: $e');
        Logger.Inst().log('backup of ${item.name} failed: $e', 'BackupRunner', 'backup', LogTypes.exception, s: s);
      }
    }
    return BackupResult(failures, done: done);
  }

  Future<bool> _backupOne(BackupItem item, BackupTarget target) async {
    switch (item) {
      case BackupItem.sources:
        await target.write(BackupItems.fileOf[item]!, utf8.encode(hooks.sourcesJson()));
        return true;
      case BackupItem.tagTypes:
        await target.write(BackupItems.fileOf[item]!, utf8.encode(hooks.tagTypesJson()));
        return true;
      case BackupItem.database:
        final File db = File('${configDir}store.db');
        if (!await db.exists()) return false;
        await hooks.checkpointDatabase();
        await target.writeFile('store.db', db);
        return true;
      case BackupItem.vectors:
        final File vectors = File('${configDir}vectors.db');
        if (!await vectors.exists()) return false;
        await hooks.checkpointVectors();
        await target.writeFile('vectors.db', vectors);
        return true;
      case BackupItem.recommender:
        return _backupFolder(Directory(_recommenderDir), BackupItems.recommenderPrefix, target);
      case BackupItem.boardPictures:
        return _backupFolder(Directory(hooks.boardPicturesDir()), BackupItems.boardPicturePrefix, target);
      case BackupItem.settings:
      case BackupItem.doujinLibrary:
      case BackupItem.sourceSettings:
      case BackupItem.bookmarks:
      case BackupItem.boards:
        final String name = BackupItems.fileOf[item]!;
        final File f = File('$configDir$name');
        if (!await f.exists()) return false;
        await target.write(name, await f.readAsBytes());
        return true;
    }
  }

  Future<bool> _backupFolder(Directory dir, String prefix, BackupTarget target) async {
    if (!await dir.exists()) return false;
    bool any = false;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File) continue;
      await target.write('$prefix${e.uri.pathSegments.last}', await e.readAsBytes());
      any = true;
    }
    return any;
  }

  /// Brings the [items] back from [target], the database last. [db] picks
  /// the whole database or only [parts] of it.
  Future<BackupResult> restore(
    Set<BackupItem> items,
    BackupTarget target, {
    DbRestore db = DbRestore.whole,
    Set<DbPart> parts = const {},
    void Function(String step)? onStep,
  }) async {
    final List<String> failures = [];
    final Set<BackupItem> done = {};
    final Set<String> names = await target.names();
    bool restart = false;
    _dbClosed = false;
    bool stores = false;
    final List<BackupItem> order = [
      for (final BackupItem i in BackupItem.values)
        if (i != BackupItem.database && items.contains(i)) i,
      if (items.contains(BackupItem.database)) BackupItem.database,
    ];
    for (final BackupItem item in order) {
      onStep?.call('Restoring ${BackupItems.labelOf(item)}…');
      try {
        final String? missing = await _restoreOne(item, target, names, db, parts);
        if (missing != null) {
          failures.add('${BackupItems.labelOf(item)}: $missing');
          continue;
        }
        done.add(item);
        // r81: the vectors are added to the open database: no restart.
        if (item != BackupItem.tagTypes && item != BackupItem.vectors) restart = true;
        if (item == BackupItem.doujinLibrary || item == BackupItem.sourceSettings || item == BackupItem.bookmarks || item == BackupItem.boards) {
          stores = true;
        }
      } catch (e, s) {
        failures.add('${BackupItems.labelOf(item)}: $e');
        Logger.Inst().log('restore of ${item.name} failed: $e', 'BackupRunner', 'restore', LogTypes.exception, s: s);
      }
    }
    if (stores) hooks.reloadStores();
    // A closed database is only opened again by a restart, even when its
    // copy failed.
    if (_dbClosed) restart = true;
    return BackupResult(failures, needsRestart: restart, done: done);
  }

  /// Null when it went through, else why not.
  Future<String?> _restoreOne(BackupItem item, BackupTarget target, Set<String> names, DbRestore db, Set<DbPart> parts) async {
    switch (item) {
      case BackupItem.sources:
        final Uint8List? b = await target.read(BackupItems.fileOf[item]!);
        if (b == null) return 'not in this backup';
        await hooks.restoreSources(utf8.decode(b));
        return null;
      case BackupItem.tagTypes:
        final Uint8List? b = await target.read(BackupItems.fileOf[item]!);
        if (b == null) return 'not in this backup';
        await hooks.restoreTagTypes(utf8.decode(b));
        return null;
      case BackupItem.recommender:
        final List<String> files = names.where((String n) => BackupItems.itemOf(n) == BackupItem.recommender).toList();
        if (files.isEmpty) return 'not in this backup';
        // Before anything is written: its memory would write over the files.
        hooks.stopRecommenderWrites();
        return _restoreFolder(files, BackupItems.recommenderPrefix, Directory(_recommenderDir), target);
      case BackupItem.boardPictures:
        final List<String> files = names.where((String n) => BackupItems.itemOf(n) == BackupItem.boardPictures).toList();
        if (files.isEmpty) return 'not in this backup';
        return _restoreFolder(files, BackupItems.boardPicturePrefix, Directory(hooks.boardPicturesDir()), target);
      case BackupItem.database:
        if (!names.contains('store.db')) return 'not in this backup';
        return db == DbRestore.whole ? _restoreWholeDatabase(target) : _restoreDatabaseParts(target, parts);
      case BackupItem.vectors:
        if (!names.contains('vectors.db')) return 'not in this backup';
        return _restoreVectors(target);
      case BackupItem.settings:
      case BackupItem.doujinLibrary:
      case BackupItem.sourceSettings:
      case BackupItem.bookmarks:
      case BackupItem.boards:
        final String name = BackupItems.fileOf[item]!;
        final Uint8List? b = await target.read(name);
        if (b == null) return 'not in this backup';
        await File('$configDir$name').writeAsBytes(b, flush: true);
        return null;
    }
  }

  Future<String?> _restoreFolder(List<String> files, String prefix, Directory into, BackupTarget target) async {
    await into.create(recursive: true);
    for (final String n in files) {
      final Uint8List? b = await target.read(n);
      if (b == null) return '$n could not be read';
      await File('${into.path.endsWith(_sep) ? into.path : '${into.path}$_sep'}${n.substring(prefix.length)}').writeAsBytes(b, flush: true);
    }
    return null;
  }

  bool _dbClosed = false;

  Future<String?> _restoreWholeDatabase(BackupTarget target) async {
    await hooks.closeDatabase();
    _dbClosed = true;
    for (final String suffix in ['-wal', '-shm']) {
      final File sidecar = File('${configDir}store.db$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    if (!await target.readToFile('store.db', File('${configDir}store.db'))) return 'the copy failed';
    hooks.rearmDoujinMigration();
    return null;
  }

  /// r81: a backup's vectors added to the open vectors' database.
  Future<String?> _restoreVectors(BackupTarget target) async {
    final Database? live = hooks.liveVectors();
    if (live == null) return 'the vector database is not open';
    final File copy = File('${configDir}restore-vectors.db');
    try {
      if (!await target.readToFile('vectors.db', copy)) return 'the copy failed';
      await DbParts.mergeVectors(copy, live);
      return null;
    } finally {
      if (await copy.exists()) await copy.delete();
    }
  }

  Future<String?> _restoreDatabaseParts(BackupTarget target, Set<DbPart> parts) async {
    if (parts.isEmpty) return 'no part of the database was chosen';
    final Database? live = hooks.liveDatabase();
    if (live == null) return 'the database is not open';
    final File copy = File('${configDir}restore-parts.db');
    try {
      if (!await target.readToFile('store.db', copy)) return 'the copy failed';
      final List<String> skipped = await DbParts.restore(copy, parts, live, vectors: hooks.liveVectors());
      if (skipped.isNotEmpty) {
        Logger.Inst().log('restore: the backup has no ${skipped.join(', ')}', 'BackupRunner', 'restore', LogTypes.booruHandlerInfo);
      }
      return null;
    } finally {
      if (await copy.exists()) await copy.delete();
    }
  }
}
