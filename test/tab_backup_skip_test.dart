import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';

/// Counts what the tab backup writes to the TabRestore row.
class _RestoreDb extends DBHandler {
  final List<String> written = [];
  int cleared = 0;

  @override
  Future<void> addTabRestore(String restore) async => written.add(restore);

  @override
  Future<void> clearTabRestore() async => cleared++;
}

/// 1.0 M4: the 30 s tab backup encodes and writes the tabs only when they
/// changed (TabBackupGate), so thousands of tabs no longer cost a hitch every
/// 30 seconds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _RestoreDb db;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru danbooru = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '');

  SearchHandler sh() => SearchHandler.instance;

  setUpAll(Logger.Inst);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tab_backup_skip');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    db = _RestoreDb();
    SettingsHandler.instance.dbHandler = db;
    SettingsHandler.instance.booruList
      ..clear()
      ..addAll([gelbooru, danbooru]);
    sh().tabs
      ..clear()
      ..addAll([SearchTab(gelbooru, null, 'cats'), SearchTab(danbooru, null, 'dogs')]);
    sh().index.value = 0;
    sh().tabId.value = sh().tabs[0].id;
    sh().canBackup.value = true;
    sh().resetBackupGate();
  });

  tearDown(() {
    sh().tabs.clear();
    sh().index.value = 0;
    SettingsHandler.instance.booruList.clear();
    SettingsHandler.instance.dbHandler = DBHandler();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('an unchanged tab list is written once, not every 30 s', () async {
    await sh().backupTabs();
    await sh().backupTabs();
    await sh().backupTabs();
    expect(db.written.length, 1);
  });

  test('a changed query, a new tab or another current tab is written', () async {
    await sh().backupTabs();
    sh().tabs[1].tags = 'dogs solo';
    await sh().backupTabs();
    sh().tabs.add(SearchTab(gelbooru, null, 'birds'));
    await sh().backupTabs();
    sh().index.value = 2;
    sh().tabId.value = sh().tabs[2].id;
    await sh().backupTabs();
    expect(db.written.length, 4);
    expect(db.written.last, contains('birds'));
  });

  test('nothing is written while backups are paused (a database restore)', () async {
    sh().canBackup.value = false;
    await sh().backupTabs();
    expect(db.written, isEmpty);
  });
}
