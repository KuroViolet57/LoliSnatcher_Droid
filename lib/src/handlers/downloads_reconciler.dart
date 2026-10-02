import 'dart:io';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/download_folders.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Checks the Downloads list (rows in store.db with isSnatched = 1) against
/// the files actually under the download root.
///
/// The app never SCANS a directory for downloads: the list is the database,
/// written when a snatch finishes. A file deleted from a file manager leaves
/// its row behind, so the list showed phantoms. This looks each row's file up
/// by the same name the writer used, keeps the ones present, reports the
/// missing ones, and on request forgets them — nothing is dropped silently.
///
/// r82: the download folders used before the current one are looked in
/// too (DownloadFolders), so changing the folder no longer empties the list.
class DownloadsReconciler {
  DownloadsReconciler._();

  static final DownloadsReconciler instance = DownloadsReconciler._();

  /// Rows whose file could not be found, gathered as pages of the Downloads
  /// tab load. Cleared by [forgetMissing].
  final List<BooruItem> missing = [];

  /// Set when the storage itself could not be read (no reconciling then).
  String? storageProblem;

  /// r83: where the check writes its report; replaced in tests.
  void Function(String line) logLine = _defaultLog;

  static void _defaultLog(String line) => Logger.Inst().log(line, 'DownloadsReconciler', 'check', LogTypes.booruHandlerInfo);

  /// r83: folders already described in the log this run (a key per folder).
  final Set<String> _described = {};

  void forgetDescribed() => _described.clear();

  /// r83: how many downloads the checks found in each folder ('' = the
  /// current one), for the drawer's report. Cleared by [audit].
  final Map<String, int> foundIn = {};

  void resetForTests() {
    logLine = _defaultLog;
    _described.clear();
    foundIn.clear();
  }

  /// r83: once per folder per run, what it holds - so a log says why a
  /// download is not found (no access, an empty folder, files one level down).
  Future<void> _describeFolders({required String current, required String currentLabel}) async {
    if (_described.add('current:$current')) {
      try {
        logLine('downloads: current folder "$currentLabel": ${(await DownloadFolders.probe(current)).describe()}');
      } catch (e) {
        logLine('downloads: current folder "$currentLabel" could not be described: $e');
      }
    }
    for (final String folder in List<String>.of(DownloadFolders.earlier)) {
      if (!_described.add('earlier:$folder')) continue;
      try {
        final Set<String>? names = await DownloadFolders.namesIn(folder);
        logLine(
          'downloads: earlier folder "${DownloadFolders.describe(folder)}": ${(await DownloadFolders.probe(folder)).describe()}'
          '${names == null ? ' - its file list could not be read' : ''}',
        );
      } catch (e) {
        logLine('downloads: earlier folder "${DownloadFolders.describe(folder)}" could not be described: $e');
      }
    }
  }

  /// The row's booru — the writer's file name starts with its NAME, so the
  /// row alone cannot be resolved to a file without it. Matched by the post
  /// URL host (then the file host) against the configured boorus.
  static Booru? booruFor(BooruItem item, List<Booru> boorus) {
    final String postHost = Uri.tryParse(item.postURL)?.host ?? '';
    final String fileHost = Uri.tryParse(item.fileURL)?.host ?? '';
    Booru? byHost(String host) {
      if (host.isEmpty) return null;
      for (final b in boorus) {
        if (!BooruType.saveable.contains(b.type) || DoujinDataHandler.isDoujinBooru(b)) continue;
        final String bh = Uri.tryParse(b.baseURL ?? '')?.host ?? '';
        if (bh.isNotEmpty && bh == host) return b;
      }
      return null;
    }

    return byHost(postHost) ?? byHost(fileHost);
  }

  /// Splits [items] into those with a file on disk, those without, and those
  /// that cannot be checked (no configured booru to derive the name from).
  Future<({List<BooruItem> present, List<BooruItem> missing, List<BooruItem> unknown})> check(
    List<BooruItem> items,
  ) async {
    final settings = SettingsHandler.instance;
    final List<BooruItem> present = [], gone = [], unknown = [];
    final writer = ImageWriter();
    await writer.setPaths();
    final String extPath = settings.extPathOverride;
    final bool saf = Platform.isAndroid && extPath.isNotEmpty;

    if (saf) {
      if (!SAFFileCache.instance.isPopulated) await SAFFileCache.instance.populate(extPath);
      if (!SAFFileCache.instance.isPopulated) {
        storageProblem = 'the chosen storage folder could not be listed';
        return (present: items, missing: <BooruItem>[], unknown: items);
      }
    } else if (!await Directory(writer.path).exists()) {
      storageProblem = 'download folder does not exist: ${writer.path}';
      return (present: items, missing: <BooruItem>[], unknown: items);
    }
    storageProblem = null;
    await _describeFolders(current: saf ? extPath : writer.path, currentLabel: saf ? DownloadFolders.describe(extPath) : writer.path);

    String? firstMissing;
    for (final item in items) {
      final Booru? booru = booruFor(item, settings.booruList);
      if (booru == null) {
        unknown.add(item);
        present.add(item);
        continue;
      }
      final String name = writer.getFilename(item, booru);
      final bool here = saf ? SAFFileCache.instance.fileNames.contains(name) : await File(writer.path + name).exists();
      // r82: a file saved before the download folder changed is still in the
      // folder it was saved to.
      final String? where = here ? '' : await DownloadFolders.earlierFolderWith(name);
      if (where != null) {
        present.add(item);
        foundIn[where] = (foundIn[where] ?? 0) + 1;
      } else {
        gone.add(item);
        firstMissing ??= name;
      }
    }
    if (firstMissing != null) {
      logLine('downloads: ${gone.length} of ${items.length} not found in any folder; the first was looked for as "$firstMissing"');
    }
    return (present: present, missing: gone, unknown: unknown);
  }

  /// Walks EVERY snatched row and returns how many have no file. Nothing is
  /// changed; [forgetMissing] does that, on request.
  Future<({int scanned, int missing, int unknown, String? problem})> audit({
    List<String> customConditions = const [],
  }) async {
    final db = SettingsHandler.instance.dbHandler;
    int scanned = 0, gone = 0, unknown = 0;
    final List<BooruItem> found = [];
    foundIn.clear();
    const int page = 500;
    for (int offset = 0; ; offset += page) {
      final rows = await db.searchDB('', '$offset', '$page', isDownloads: true, customConditions: customConditions);
      if (rows.isEmpty) break;
      final r = await check(rows);
      if (storageProblem != null) return (scanned: scanned, missing: 0, unknown: 0, problem: storageProblem);
      scanned += rows.length;
      gone += r.missing.length;
      unknown += r.unknown.length;
      found.addAll(r.missing);
      if (rows.length < page) break;
    }
    missing
      ..clear()
      ..addAll(found);
    Logger.Inst().log(
      'downloads audit: $scanned rows, $gone without a file, $unknown could not be checked',
      'DownloadsReconciler',
      'audit',
      LogTypes.booruHandlerInfo,
    );
    return (scanned: scanned, missing: gone, unknown: unknown, problem: null);
  }

  /// Clears the snatched flag on the rows [audit] found missing.
  Future<int> forgetMissing() async {
    if (missing.isEmpty) return 0;
    final int changed = await SettingsHandler.instance.dbHandler.clearSnatchedFlags(
      missing.map((i) => i.postURL).toSet().toList(),
    );
    missing.clear();
    return changed;
  }
}
