import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/sync/logic/loli_sync_handler.dart';
import 'package:lolisnatcher/features/sync/ui/loli_sync_page.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru_item.dart';

/// The part of an HttpRequest the receiver reads: method, uri, body, response.
class _Response {
  int statusCode = 0;
  final StringBuffer written = StringBuffer();

  void write(Object? object) => written.write(object);
}

class _Request extends Stream<List<int>> {
  _Request(this.method, String path, String body) : uri = Uri.parse(path), _bytes = utf8.encode(body);

  final String method;
  final Uri uri;
  final List<int> _bytes;
  final _Response response = _Response();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

/// LoliSync (Settings → LoliSync): one phone sends, the other receives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;

  BooruItem post(int id) => BooruItem(
    fileURL: 'https://img3.gelbooru.com/images/aa/bb/$id.jpg',
    sampleURL: 'https://img3.gelbooru.com/samples/aa/bb/$id.jpg',
    thumbnailURL: 'https://img3.gelbooru.com/thumbnails/aa/bb/thumbnail_$id.jpg',
    tagsList: const [],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$id',
  );

  setUp(() async {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    SearchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('loli_sync');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      SettingsHandler.instance.dbEnabled = true;
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
  });

  tearDown(() async {
    final SettingsHandler s = SettingsHandler.instance;
    s.earlierDownloadFolders.clear();
    s.modelThreads.clear();
    s.modelRunOn.clear();
    s.hiddenTags.clear();
    s.invalidateBlacklistCache();
    try {
      await s.dbHandler.db?.close();
    } catch (_) {}
    s.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('receiving', () {
    test("settings from another phone keep this phone's model threads, Run on choices and earlier download folders", () async {
      final SettingsHandler s = SettingsHandler.instance;
      s.earlierDownloadFolders
        ..clear()
        ..add('content://tree/old-folder');
      s.modelThreads
        ..clear()
        ..addAll({'tagger.waiting': 6});
      s.modelRunOn
        ..clear()
        ..addAll({'text': 'xnnpack'});
      // The sender leaves its device-specific settings out.
      final _Request req = _Request('POST', '/lolisync/settings', jsonEncode({'hiddenTags': ['sent_tag']}));

      final String result = await LoliSync().storeSettings(req, s);

      expect(result, 'Settings Saved');
      expect(s.hiddenTags, ['sent_tag'], reason: 'what was sent is taken');
      expect(s.earlierDownloadFolders, ['content://tree/old-folder']);
      expect(s.modelThreads, {'tagger.waiting': 6});
      expect(s.modelRunOn, {'text': 'xnnpack'});
    });
  });
}
