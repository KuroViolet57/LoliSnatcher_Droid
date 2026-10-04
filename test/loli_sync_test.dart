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
import 'package:lolisnatcher/core/storage/database_handler.dart';

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

/// A sender's connection client that answers every request with 200 "ok"
/// and remembers whether it was closed.
class _SenderClient implements HttpClient {
  bool closed = false;

  @override
  Future<HttpClientRequest> post(String host, int port, String path) async => _SenderRequest();

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SenderRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _SenderHeaders();

  @override
  void write(Object? object) {}

  @override
  Future<HttpClientResponse> close() async => _SenderResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SenderHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SenderResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode('ok')).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test('the last batch of a favourites sync says the favourites are synced', () async {
      if (!dbReady) return;
      final _Request req = _Request(
        'POST',
        '/lolisync/boorubatch?amount=150&offset=100&size=50',
        jsonEncode([for (int i = 100; i < 150; i++) post(i).toJson()]),
      );
      final String result = await LoliSync().storeBooruBatch(req, SettingsHandler.instance);
      expect(result, 'Favourites Synced');
      expect(req.response.written.toString(), 'Added 50', reason: 'the answer to the sender is unchanged');
    });

    test('a batch before the last one says how far the sync is', () async {
      if (!dbReady) return;
      final _Request req = _Request(
        'POST',
        '/lolisync/boorubatch?amount=150&offset=0&size=100',
        jsonEncode([for (int i = 0; i < 100; i++) post(i).toJson()]),
      );
      expect(await LoliSync().storeBooruBatch(req, SettingsHandler.instance), '0-100 / 150 - Added 100');
    });
  });

  group('sending', () {
    // Requests go nowhere here: the test binding answers every HttpClient
    // request with an empty 400.
    test('each batch line counts against the total, not against itself', () async {
      if (!dbReady) return;
      final batch = SettingsHandler.instance.dbHandler.db!.batch();
      for (int i = 0; i < 150; i++) {
        batch.rawInsert(
          'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite) VALUES(?,?,?,?,?,?,?)',
          [post(i).thumbnailURL, post(i).sampleURL, post(i).fileURL, post(i).postURL, 'image', 0, 1],
        );
      }
      await batch.commit(noResult: true);

      final List<String> lines = await LoliSync()
          .startSync('127.0.0.1', '1', ['Favouritesv2'], 0, 0, TabsMode.merge, TagsMode.overwrite)
          .toList();

      expect(lines, contains('0-100 / 150 - '));
      expect(lines, contains('100-150 / 150 - '));
      expect(lines, contains('Favourites sent'));
    });

    test('1.0: every request closes its connection client once the answer is read', () async {
      if (!dbReady) return;
      await SettingsHandler.instance.dbHandler.db!.rawInsert(
        'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite) VALUES(?,?,?,?,?,?,?)',
        [post(1).thumbnailURL, post(1).sampleURL, post(1).fileURL, post(1).postURL, 'image', 0, 1],
      );
      final List<_SenderClient> clients = [];

      final List<String> lines = await HttpOverrides.runZoned(
        () => LoliSync().startSync('127.0.0.1', '1', ['Favouritesv2', 'Settings'], 0, 0, TabsMode.merge, TagsMode.overwrite).toList(),
        createHttpClient: (SecurityContext? context) {
          final _SenderClient client = _SenderClient();
          clients.add(client);
          return client;
        },
      );

      expect(lines, contains('0-1 / 1 - ok'), reason: 'the answer is still read after the client is closed');
      expect(clients, hasLength(3), reason: 'the batch, the settings and the end of the sync');
      expect(clients.where((c) => !c.closed), isEmpty, reason: 'each kept its socket until the idle timeout');
    });

    test('a snatched sync speaks of snatched items, not favourites', () async {
      if (!dbReady) return;
      final List<String> empty = await LoliSync()
          .startSync('127.0.0.1', '1', ['Snatched'], 0, 0, TabsMode.merge, TagsMode.overwrite)
          .toList();
      expect(empty, isNot(contains('No Favourites')));
      expect(empty, contains('No Snatched'));

      await SettingsHandler.instance.dbHandler.db!.rawInsert(
        'INSERT INTO BooruItem(thumbnailURL, sampleURL, fileURL, postURL, mediaType, isSnatched, isFavourite) VALUES(?,?,?,?,?,?,?)',
        [post(1).thumbnailURL, post(1).sampleURL, post(1).fileURL, post(1).postURL, 'image', 1, 0],
      );
      final List<String> one = await LoliSync()
          .startSync('127.0.0.1', '1', ['Snatched'], 0, 0, TabsMode.merge, TagsMode.overwrite)
          .toList();
      expect(one, isNot(contains('Favourites sent')));
      expect(one, contains('Snatched sent'));
    });
  });
}
