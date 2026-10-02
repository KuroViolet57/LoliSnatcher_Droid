import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r82: the download folders. New downloads go to the current one (the
/// folder picked in Settings → Save & cache, or the default Pictures
/// folder); a folder you move away from is remembered, and the Downloads
/// list, the "downloaded" badge and the doujin downloads look for their
/// files there too. Changing the folder never moved the files, so before
/// r82 every earlier download vanished from the list.
///
/// The app keeps its access to a picked folder (MainActivity takes a
/// persistable grant and never releases it), so an earlier folder stays
/// readable. Nothing is ever written there.
/// r83: what a download folder holds at its top, for the Downloads log.
class FolderProbe {
  const FolderProbe({
    required this.files,
    required this.dirs,
    this.sampleFiles = const [],
    this.sampleDirs = const [],
    this.access,
    this.error,
  });

  final int files;
  final int dirs;
  final List<String> sampleFiles;
  final List<String> sampleDirs;

  /// Whether the app still holds its access to a picked folder (null for a
  /// plain folder).
  final bool? access;
  final String? error;

  static String _count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';

  /// "1,204 files, 1 folder (LoliSnatcher), access kept, e.g. a.jpg, b.mp4".
  String describe() {
    final StringBuffer b = StringBuffer('${_count(files, 'file')}, ${_count(dirs, 'folder')}');
    if (sampleDirs.isNotEmpty) b.write(' (${sampleDirs.join(', ')}${dirs > sampleDirs.length ? ', …' : ''})');
    if (access != null) b.write(access! ? ', access kept' : ', NO access kept');
    if (error != null) b.write(', could not be read: $error');
    if (sampleFiles.isNotEmpty) b.write(', e.g. ${sampleFiles.join(', ')}');
    return b.toString();
  }
}

class DownloadFolders {
  const DownloadFolders._();

  /// Newest first; never the current folder.
  static List<String> get earlier => SettingsHandler.instance.earlierDownloadFolders;

  static bool isSaf(String folder) => folder.startsWith('content://');

  // Seams, replaced in tests.
  /// The folder downloads go to when none is picked.
  @visibleForTesting
  static Future<String> Function() defaultFolder = ServiceHandler.getPicturesDir;

  /// The file names at the top of a folder; null when it cannot be read.
  @visibleForTesting
  static Future<Set<String>?> Function(String folder) listNames = _defaultListNames;

  /// What a folder holds at its top (the Downloads log); replaced in tests.
  static Future<FolderProbe> Function(String folder) probe = _defaultProbe;

  /// The current folder changed: its cached file list is read again.
  @visibleForTesting
  static void Function(String folder) onChanged = _defaultOnChanged;

  @visibleForTesting
  static Future<void> Function() save = _defaultSave;

  @visibleForTesting
  static void resetForTests() {
    defaultFolder = ServiceHandler.getPicturesDir;
    listNames = _defaultListNames;
    probe = _defaultProbe;
    onChanged = _defaultOnChanged;
    save = _defaultSave;
  }

  static Future<String> _current() async {
    final String picked = SettingsHandler.instance.extPathOverride;
    return picked.isNotEmpty ? picked : await defaultFolder();
  }

  /// Makes [folder] ('' = the default) the download folder; the one left
  /// becomes an earlier folder.
  static Future<void> change(String folder) async {
    final SettingsHandler s = SettingsHandler.instance;
    if (s.extPathOverride == folder) return;
    final String left = await _current();
    s.extPathOverride = folder;
    final String now = await _current();
    s.earlierDownloadFolders.remove(now);
    if (left.isNotEmpty && left != now && !s.earlierDownloadFolders.contains(left)) {
      s.earlierDownloadFolders.insert(0, left);
    }
    forgetListings();
    onChanged(folder);
    Logger.Inst().log('download folder changed; the one left is remembered (${s.earlierDownloadFolders.length} earlier)', 'DownloadFolders', 'change', LogTypes.settingsLoad);
    await save();
  }

  /// A folder used before (picked again by hand); false when it is the
  /// current folder, already listed or empty.
  static Future<bool> addEarlier(String folder) async {
    if (folder.isEmpty || earlier.contains(folder) || folder == await _current()) return false;
    earlier.insert(0, folder);
    _listings.remove(folder);
    Logger.Inst().log('download folders: "${describe(folder)}" added as an earlier folder (${earlier.length} now)', 'DownloadFolders', 'addEarlier', LogTypes.settingsLoad);
    await save();
    return true;
  }

  static Future<void> removeEarlier(String folder) async {
    if (!earlier.remove(folder)) return;
    _listings.remove(folder);
    Logger.Inst().log('download folders: "${describe(folder)}" removed from the earlier folders (${earlier.length} left)', 'DownloadFolders', 'removeEarlier', LogTypes.settingsLoad);
    await save();
  }

  /// The earlier folders' file lists, read once per run (the app writes
  /// nothing there, so they only change by hand).
  static final Map<String, Set<String>?> _listings = {};

  static void forgetListings() => _listings.clear();

  static Future<Set<String>?> namesIn(String folder) async {
    if (_listings.containsKey(folder)) return _listings[folder];
    Set<String>? names;
    try {
      names = await listNames(folder);
    } catch (e) {
      Logger.Inst().log('an earlier download folder could not be read: $e', 'DownloadFolders', 'namesIn', LogTypes.booruHandlerInfo);
    }
    _listings[folder] = names;
    return names;
  }

  /// The earlier folder holding [fileName] at its top, or null.
  static Future<String?> earlierFolderWith(String fileName) async {
    for (final String folder in List<String>.of(earlier)) {
      final Set<String>? names = await namesIn(folder);
      if (names != null && names.contains(fileName)) return folder;
    }
    return null;
  }

  /// A folder as a person reads it: `Download/Loli` for a picked folder on
  /// the phone's own storage, `1234-ABCD: Pictures` on a card, a path as it is.
  static String describe(String folder) {
    if (!isSaf(folder)) return folder;
    final int at = folder.indexOf('/tree/');
    if (at < 0) return Uri.decodeComponent(folder);
    String id = folder.substring(at + '/tree/'.length);
    final int slash = id.indexOf('/');
    if (slash >= 0) id = id.substring(0, slash);
    id = Uri.decodeComponent(id);
    final int colon = id.indexOf(':');
    if (colon < 0) return id;
    final String volume = id.substring(0, colon);
    final String path = id.substring(colon + 1);
    return volume == 'primary' ? path : '$volume: $path';
  }

  // ── defaults ──

  static Future<Set<String>?> _defaultListNames(String folder) async {
    if (isSaf(folder)) {
      if (!Platform.isAndroid) return null;
      return (await ServiceHandler.listFileNamesFromSAFDirectory(folder)).toSet();
    }
    final Directory d = Directory(folder);
    if (!await d.exists()) return null;
    final Set<String> names = {};
    await for (final FileSystemEntity e in d.list(followLinks: false)) {
      if (e is File) names.add(e.path.split(Platform.pathSeparator).last);
    }
    return names;
  }

  static Future<FolderProbe> _defaultProbe(String folder) async {
    if (isSaf(folder)) {
      if (!Platform.isAndroid) return const FolderProbe(files: 0, dirs: 0, error: 'a picked folder is readable on the phone only');
      final Map<String, dynamic>? p = await ServiceHandler.probeSafFolder(folder);
      if (p == null) return const FolderProbe(files: 0, dirs: 0, error: 'the app could not ask the folder');
      return FolderProbe(
        files: (p['files'] as num?)?.toInt() ?? 0,
        dirs: (p['dirs'] as num?)?.toInt() ?? 0,
        sampleFiles: [for (final dynamic s in (p['sampleFiles'] as List?) ?? const []) s.toString()],
        sampleDirs: [for (final dynamic s in (p['sampleDirs'] as List?) ?? const []) s.toString()],
        access: p['access'] == true,
        error: p['error']?.toString(),
      );
    }
    final Directory d = Directory(folder);
    if (!await d.exists()) return const FolderProbe(files: 0, dirs: 0, error: 'the folder does not exist');
    int files = 0;
    int dirs = 0;
    final List<String> sampleFiles = [];
    final List<String> sampleDirs = [];
    await for (final FileSystemEntity e in d.list(followLinks: false)) {
      final String name = e.path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        dirs++;
        if (sampleDirs.length < 5) sampleDirs.add(name);
      } else if (e is File) {
        files++;
        if (sampleFiles.length < 5) sampleFiles.add(name);
      }
    }
    return FolderProbe(files: files, dirs: dirs, sampleFiles: sampleFiles, sampleDirs: sampleDirs);
  }

  static void _defaultOnChanged(String folder) {
    SAFFileCache.instance.invalidate();
    if (Platform.isAndroid && folder.isNotEmpty) unawaited(SAFFileCache.instance.populate(folder));
  }

  static Future<void> _defaultSave() => SettingsHandler.instance.saveSettings(restate: false);
}
