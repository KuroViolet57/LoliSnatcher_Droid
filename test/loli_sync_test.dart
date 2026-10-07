import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/sync/logic/loli_sync_handler.dart';
import 'package:lolisnatcher/features/sync/logic/sync_search_payload.dart';
import 'package:lolisnatcher/models/saved_search.dart';
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

    test('a request without this session code is refused and nothing is stored', () {
      final LoliSync sync = LoliSync()..syncCode = 'AB12CD34';
      final SettingsHandler s = SettingsHandler.instance;
      s.hiddenTags
        ..clear()
        ..add('kept');
      final _Request missing = _Request('POST', '/lolisync/settings', jsonEncode({'hiddenTags': ['sent_tag']}));
      final _Request wrong = _Request('POST', '/lolisync/settings?code=AB12CD35', jsonEncode({'hiddenTags': ['sent_tag']}));
      final _Request right = _Request('POST', '/lolisync/settings?code=AB12CD34', jsonEncode({'hiddenTags': ['sent_tag']}));

      expect(sync.rejectUnlessCodeMatches(missing), isTrue);
      expect(sync.rejectUnlessCodeMatches(wrong), isTrue);
      expect(missing.response.statusCode, 403);
      expect(wrong.response.statusCode, 403);
      expect(missing.response.written.toString(), contains('code'));
      expect(sync.rejectUnlessCodeMatches(right), isFalse, reason: 'the matching code is allowed through to the store');
      final _Request lower = _Request('POST', '/lolisync/settings?code=%20ab12cd34%20', jsonEncode({'hiddenTags': ['sent_tag']}));
      expect(sync.rejectUnlessCodeMatches(lower), isFalse, reason: 'typing and spaces do not have to match the capitals');
      final LoliSync blank = LoliSync();
      final _Request any = _Request('POST', '/lolisync/settings?code=AB12CD34', jsonEncode({'hiddenTags': ['sent_tag']}));
      expect(blank.rejectUnlessCodeMatches(any), isTrue);
      expect(any.response.written.toString(), contains('missing'));
      expect(s.hiddenTags, ['kept'], reason: 'a refused request does not reach storeSettings');
      expect(SettingsHandler.instance.map.containsKey('syncCode'), isFalse);
      expect(SettingsHandler.instance.map.containsKey('lastSyncCode'), isFalse);
      expect(LoliSync.pathWithCode('/lolisync/settings', 'AB12CD34'), '/lolisync/settings?code=AB12CD34');
      expect(LoliSync.pathWithCode('/lolisync/boorubatch?amount=1&offset=0&size=1', 'AB12CD34'), endsWith('&code=AB12CD34'));
      expect(LoliSync.serverActiveLine('127.0.0.1', 8080, 'AB12CD34'), 'Server active at 127.0.0.1:8080. Code AB12CD34');
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

    test('search history and saved searches merge, and a second copy does not double', () async {
      if (!dbReady) return;
      final SettingsHandler s = SettingsHandler.instance;
      final SavedSearch local = SavedSearch(
        id: null,
        name: 'mine',
        tags: '1girl',
        booru: 'Gelbooru',
        createdAt: DateTime.utc(2026, 10, 1),
      );
      await s.dbHandler.addSavedSearch(local);
      await s.dbHandler.insertSyncedSearchHistory(
        searchText: 'cat',
        booruType: 'Danbooru',
        booruName: 'Main',
        favourite: true,
        timestamp: '2026-10-01 00:00:00',
      );

      final SavedSearch incoming = SavedSearch(
        id: null,
        name: 'theirs',
        tags: '1girl',
        booru: 'Gelbooru',
        createdAt: DateTime.utc(2026, 10, 2),
      );
      final SavedSearch fresh = SavedSearch(
        id: null,
        name: '',
        tags: '少女 🌸',
        booru: 'Gelbooru',
        secondaryBoorus: const ['B', 'A'],
        createdAt: DateTime.utc(2026, 10, 3),
      );
      final String historyBody = jsonEncode([
        const SyncHistoryRow(
          searchText: 'cat',
          booruType: 'Danbooru',
          booruName: 'Main',
          favourite: false,
          timestamp: '2026-10-07 00:00:00',
        ).toJson(),
        const SyncHistoryRow(
          searchText: '少女 🌸',
          booruType: 'Danbooru',
          booruName: 'Main',
          favourite: true,
          timestamp: '2026-10-07 01:00:00',
        ).toJson(),
        {'searchText': 'dropped', 'booruName': ''},
      ]);
      final String savedBody = jsonEncode([
        SyncSavedSearchRow.fromSavedSearch(incoming)!.toJson(),
        SyncSavedSearchRow.fromSavedSearch(fresh)!.toJson(),
        {'name': 'bad', 'payload': 'not json'},
      ]);

      final String historyResult = await LoliSync().storeSearchHistory(_Request('POST', '/lolisync/searchhistory', historyBody), s);
      final String savedResult = await LoliSync().storeSavedSearches(_Request('POST', '/lolisync/savedsearches', savedBody), s);
      expect(historyResult, contains('added 1'));
      expect(historyResult, contains('kept 1'));
      expect(savedResult, contains('added 1'));
      expect(savedResult, contains('kept 2'));

      final history = await s.dbHandler.getSearchHistory();
      expect(history.where((row) => row.searchText == 'cat'), hasLength(1));
      expect(history.firstWhere((row) => row.searchText == 'cat').isFavourite, isTrue);
      expect(history.any((row) => row.searchText == '少女 🌸'), isTrue);

      final String again = await LoliSync().storeSearchHistory(_Request('POST', '/lolisync/searchhistory', historyBody), s);
      expect(again, contains('added 0'));
      expect((await s.dbHandler.getSearchHistory()).where((row) => row.searchText == '少女 🌸'), hasLength(1));

      final saved = await s.dbHandler.getSavedSearches();
      expect(saved.where((row) => row.tags == '1girl'), hasLength(1));
      expect(saved.firstWhere((row) => row.tags == '1girl').name, 'mine');
      expect(saved.any((row) => row.tags == '少女 🌸'), isTrue);
      expect(saved.firstWhere((row) => row.tags == '少女 🌸').secondaryBoorus, ['B', 'A']);

      s.dbEnabled = false;
      expect(await LoliSync().storeSearchHistory(_Request('POST', '/lolisync/searchhistory', historyBody), s), 'DB is disabled');
      expect(await LoliSync().storeSearchHistory(_Request('GET', '/lolisync/searchhistory', historyBody), s), 'Invalid Query');
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
