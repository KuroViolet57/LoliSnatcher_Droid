import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_plan.dart';
import 'package:lolisnatcher/src/services/download_folders.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

typedef DownloadsAudit = ({int scanned, int missing, int unknown, String? problem});

/// r84: "Check downloads against disk". Walks every media download in the
/// database, looks for its file in the download folder and the earlier ones
/// (DownloadsReconciler), and offers to forget the ones with no file: only
/// the downloaded mark goes, the posts stay and can be saved again.
///
/// Before r84 it lived in a drawer panel the app stopped showing on 14 July
/// (the drawer redesign), so it could not be reached. Now it is in
/// Settings → Save & cache, and it is offered by itself on the first start
/// after a whole database came back from a backup - a backup carries the
/// list of downloads, not the files, so a restore on a fresh install lists
/// downloads this phone never had.
class DownloadsCheck {
  const DownloadsCheck._();

  // Seams, replaced in tests.
  static Future<DownloadsAudit> Function() audit = _defaultAudit;
  static Future<int> Function() forget = _defaultForget;
  static Future<String> Function() configDir = ServiceHandler.getConfigDir;
  static BuildContext? Function() contextNow = _defaultContext;

  /// Where the check found downloads, one line per folder.
  static List<String> Function() whereFound = _defaultWhereFound;

  /// The check's short messages (snackbars; they show nothing in tests).
  static void Function(BuildContext context, String title, String? content, Color color) say = _defaultSay;

  static void resetForTests() {
    audit = _defaultAudit;
    forget = _defaultForget;
    configDir = ServiceHandler.getConfigDir;
    contextNow = _defaultContext;
    whereFound = _defaultWhereFound;
    say = _defaultSay;
  }

  /// Settings → Save & cache → Check downloads against disk.
  static Future<void> run(BuildContext context) async {
    say(context, 'Checking downloads against the folders…', null, Colors.blue);
    final DownloadsAudit r = await audit();
    if (!context.mounted) return;
    if (r.problem != null) {
      say(context, 'Could not check the download folder', r.problem, Colors.red);
      return;
    }
    if (r.missing == 0) {
      final String details = [
        ...whereFound(),
        if (r.unknown > 0) '${r.unknown} could not be checked (no matching booru config).',
      ].join('\n');
      say(context, 'All ${r.scanned} media downloads have a file', details.isEmpty ? 'Every entry has its file.' : details, Colors.green);
      return;
    }
    await _ask(context, r, afterRestore: false);
  }

  /// On start: once after a whole-database restore (BackupRunner leaves a
  /// marker), the check runs and, when downloads have no file, asks.
  static Future<void> offerAfterRestore() async {
    if (!await _takeMarker()) return;
    final DownloadsAudit r = await audit();
    Logger.Inst().log(
      'downloads after a restore: ${r.scanned} listed, ${r.missing} without a file, ${r.unknown} unchecked${r.problem != null ? ' - ${r.problem}' : ''}',
      'DownloadsCheck',
      'offerAfterRestore',
      LogTypes.booruHandlerInfo,
    );
    if (r.problem != null || r.missing == 0) return;
    BuildContext? context = contextNow();
    for (int i = 0; context == null && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      context = contextNow();
    }
    if (context == null || !context.mounted) return;
    // Not awaited: the answer comes whenever the person gives it.
    unawaited(_ask(context, r, afterRestore: true));
  }

  static Future<bool> _takeMarker() async {
    try {
      final File marker = File('${await configDir()}${BackupRunner.checkDownloadsMarker}');
      if (!await marker.exists()) return false;
      await marker.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _ask(BuildContext context, DownloadsAudit r, {required bool afterRestore}) async {
    final List<String> where = whereFound();
    final String found = where.isEmpty ? '' : '\n\nFound:\n${where.join('\n')}';
    final String unchecked = r.unknown > 0 ? '\n\n${r.unknown} entries could not be checked (no matching booru config) and are left alone.' : '';
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(afterRestore ? 'Downloads restored without their files' : '${r.missing} of ${r.scanned} downloads have no file'),
        content: SingleChildScrollView(
          child: Text(
            afterRestore
                ? 'The database came back from a backup. It lists ${r.scanned} downloads, and ${r.missing} of them have no file on this phone: '
                      'a backup carries the list of downloads, not the files.\n\n'
                      'Forgetting removes them from the Downloads list; the posts are not touched and can be saved again.$found$unchecked'
                : 'Their files are in neither the download folder nor an earlier download folder (Settings → Save & cache).\n\n'
                      'Forgetting removes them from the Downloads list; the posts are not touched and can be saved again.$found$unchecked',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Forget ${r.missing}')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final int changed = await forget();
    if (!context.mounted) return;
    say(context, 'Forgot $changed entries', 'Reload the Downloads tab to see the list without them.', Colors.green);
  }

  // ── defaults ──

  static Future<DownloadsAudit> _defaultAudit() =>
      DownloadsReconciler.instance.audit(customConditions: DownloadsHandler.doujinExclusionConditions());

  static Future<int> _defaultForget() => DownloadsReconciler.instance.forgetMissing();

  static BuildContext? _defaultContext() {
    try {
      return NavigationHandler.instance.navigatorKey.currentContext;
    } catch (_) {
      return null;
    }
  }

  static void _defaultSay(BuildContext context, String title, String? content, Color color) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(title),
      content: content == null ? const SizedBox(height: 20) : Text(content),
      duration: Duration(seconds: color == Colors.blue ? 2 : 4),
      sideColor: color,
      leadingIcon: color == Colors.green ? Symbols.check_rounded : Symbols.info_rounded,
    );
  }

  static List<String> _defaultWhereFound() => [
    for (final MapEntry<String, int> e in DownloadsReconciler.instance.foundIn.entries)
      '${e.value} in ${e.key.isEmpty ? 'the current folder' : DownloadFolders.describe(e.key)}',
  ];
}
