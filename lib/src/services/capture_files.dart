import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Where a capture went.
class SavedCapture {
  const SavedCapture(this.where, {this.fellBack = false});

  /// In words, for the person: the folder and the file.
  final String where;

  /// No folder was chosen, or the chosen one refused the file: it is in the
  /// app's own folder instead.
  final bool fellBack;
}

/// r80: a capture - an interaction trace's report, a source capture - is kept
/// as a file where the person can reach it: the folder picked for captures
/// (Settings → Debug → Captures folder), else a "captures" folder inside the
/// download folder, else the app's own folder. Before r80 the report lived
/// only in a dialog to copy from (a long one could not be copied) and in the
/// app's private folder.
class CaptureFiles {
  const CaptureFiles._();

  static const String folderName = 'captures';

  /// Test seams: the platform, the folders and Android's folder access.
  @visibleForTesting
  static bool Function() isAndroid = _defaultIsAndroid;
  @visibleForTesting
  static Future<String> Function() scratchDir = _defaultScratchDir;
  @visibleForTesting
  static Future<String> Function() appFolder = _defaultAppFolder;
  @visibleForTesting
  static Future<String?> Function(String root, String name) makeSafDir = ServiceHandler.getOrCreateSAFDirectory;
  @visibleForTesting
  static Future<bool> Function(String sourceDir, String name, String safUri, String mime) copyToSaf = ServiceHandler.copyFileToSafDir;
  @visibleForTesting
  static Future<bool> Function(String safUri, String name) existsInSaf = ServiceHandler.existsFileFromSAFDirectory;
  @visibleForTesting
  static Future<bool> Function(String safUri, String name) deleteInSaf = ServiceHandler.deleteFileFromSAFDirectory;

  @visibleForTesting
  static void resetForTests() {
    isAndroid = _defaultIsAndroid;
    scratchDir = _defaultScratchDir;
    appFolder = _defaultAppFolder;
    makeSafDir = ServiceHandler.getOrCreateSAFDirectory;
    copyToSaf = ServiceHandler.copyFileToSafDir;
    existsInSaf = ServiceHandler.existsFileFromSAFDirectory;
    deleteInSaf = ServiceHandler.deleteFileFromSAFDirectory;
  }

  static bool _defaultIsAndroid() => Platform.isAndroid;

  static Future<String> _defaultScratchDir() async => '${await ServiceHandler.getCacheDir()}capture-out${Platform.pathSeparator}';

  static Future<String> _defaultAppFolder() async => '${await ServiceHandler.getExtDir()}/LoliSnatcher/$folderName/';

  /// Where captures go, in words (the Debug page shows it).
  static String describeTarget() {
    final SettingsHandler s = SettingsHandler.instance;
    if (s.capturesPath.isNotEmpty) return 'Into the folder you picked for captures.';
    if (s.extPathOverride.isNotEmpty) return 'Into a "captures" folder inside your download folder.';
    return "Into the app's own folder - pick a download folder (Settings → Save & cache) or a folder here to have them where you can open them.";
  }

  /// A date and time for file names: 2026-09-22-14-05-09.
  static String stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  }

  /// Writes [text] as [name] where captures go; a file of that name there is
  /// replaced (Android's folder access would otherwise add "name (1)").
  /// Null only when not even the app's own folder took it.
  static Future<SavedCapture?> save(String name, String text) async {
    final SettingsHandler s = SettingsHandler.instance;
    final String picked = s.capturesPath;
    final String downloads = s.extPathOverride;
    if (picked.isNotEmpty || downloads.isNotEmpty) {
      try {
        final String? where = isAndroid()
            ? await _toSaf(name, text, picked: picked, downloads: downloads)
            : await _toFolder(name, text, picked.isNotEmpty ? picked : '$downloads$folderName/');
        if (where != null) return SavedCapture(where);
        Logger.Inst().log('capture: the chosen folder refused $name; kept in the app folder', 'CaptureFiles', 'save', LogTypes.settingsLoad);
      } catch (e) {
        Logger.Inst().log('capture: $name could not go to the chosen folder ($e); kept in the app folder', 'CaptureFiles', 'save', LogTypes.exception);
      }
    }
    try {
      return SavedCapture(await _toFolder(name, text, await appFolder()), fellBack: true);
    } catch (e) {
      Logger.Inst().log('capture: $name could not be written at all: $e', 'CaptureFiles', 'save', LogTypes.exception);
      return null;
    }
  }

  static Future<String?> _toSaf(String name, String text, {required String picked, required String downloads}) async {
    final String? dir = picked.isNotEmpty ? picked : await makeSafDir(downloads, folderName);
    if (dir == null) return null;
    final String scratch = await scratchDir();
    await Directory(scratch).create(recursive: true);
    final File tmp = File('$scratch$name');
    await tmp.writeAsString(text, flush: true);
    try {
      if (await existsInSaf(dir, name)) await deleteInSaf(dir, name);
      if (!await copyToSaf(scratch, name, dir, 'text/plain')) return null;
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return picked.isNotEmpty ? 'your captures folder → $name' : 'Download folder → $folderName → $name';
  }

  static Future<String> _toFolder(String name, String text, String dir) async {
    final String d = dir.endsWith('/') || dir.endsWith(Platform.pathSeparator) ? dir : '$dir/';
    await Directory(d).create(recursive: true);
    final File f = File('$d$name');
    await f.writeAsString(text, flush: true);
    return f.path;
  }

  /// A stopped interaction trace: its report whole in the log (in numbered
  /// parts) and as a file where captures go.
  static Future<SavedCapture?> keepTraceReport(String report, {DateTime? now}) async {
    Logger.Inst().logParts(report, 'PerfTrace', 'report', LogTypes.settingsLoad, title: 'Trace report');
    final SavedCapture? saved = await save('trace-${stamp(now ?? DateTime.now())}.txt', report);
    if (saved != null) Logger.Inst().log('capture: the trace report is saved: ${saved.where}', 'CaptureFiles', 'keepTraceReport', LogTypes.settingsLoad);
    return saved;
  }
}
