import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/secure_storage_handler.dart';
import 'package:lolisnatcher/features/backup/logic/drive_backup.dart';

/// Google Drive as this test plays it: the token address answers a token, and
/// a folder listing answers [pages] one after the other by page token.
class _DriveClient implements HttpClient {
  _DriveClient(this.pages);

  final Map<String?, Map<String, Object>> pages;
  bool closed = false;

  Future<HttpClientRequest> _answer(Uri url) async {
    if (url.path.endsWith('/files')) return _DriveRequest(200, jsonEncode(pages[url.queryParameters['pageToken']]));
    return _DriveRequest(200, jsonEncode({'access_token': 'a', 'expires_in': 3600}));
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _answer(url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _answer(url);

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DriveRequest implements HttpClientRequest {
  _DriveRequest(this.status, this.body);

  final int status;
  final String body;

  @override
  final HttpHeaders headers = _DriveHeaders();

  @override
  Future<HttpClientResponse> close() async => _DriveResponse(status, body);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DriveHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DriveResponse extends Stream<List<int>> implements HttpClientResponse {
  _DriveResponse(this.statusCode, this.body);

  @override
  final int statusCode;
  final String body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// r80: Google Drive keeps named snapshots - a folder per backup inside the
/// LoliSnatcher folder - instead of one set of files overwritten each time.
/// The backup made before snapshots existed is still offered, as "Earlier
/// backup".
void main() {
  test('each folder is a snapshot, newest first; files at the top are the earlier backup', () {
    final List<DriveSnapshot> s = DriveBackup.snapshotsFrom(
      [
        {'id': 'f1', 'name': 'before the update', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-20T10:00:00Z'},
        {'id': 'f2', 'name': '2026-09-22 09.30', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-22T09:30:00Z'},
        {'id': 'x1', 'name': 'store.db', 'mimeType': 'application/x-sqlite3', 'modifiedTime': '2026-09-01T08:00:00Z'},
        {'id': 'x2', 'name': 'settings.json', 'mimeType': 'application/json', 'modifiedTime': '2026-09-02T08:00:00Z'},
      ],
      rootId: 'root',
    );
    expect(s.map((e) => e.name).toList(), ['2026-09-22 09.30', 'before the update', DriveBackup.earlierBackupName]);
    expect(s.last.id, 'root', reason: 'the earlier backup is the folder itself');
    expect(s.last.earlier, isTrue);
    expect(s.last.created, DateTime.utc(2026, 9, 2, 8), reason: 'dated by its newest file');
    expect(s.first.created, DateTime.utc(2026, 9, 22, 9, 30));
  });

  test('no files at the top: no earlier backup entry', () {
    final List<DriveSnapshot> s = DriveBackup.snapshotsFrom(
      [
        {'id': 'f1', 'name': 'a', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-20T10:00:00Z'},
      ],
      rootId: 'root',
    );
    expect(s.single.earlier, isFalse);
  });

  test('a snapshot name you already used gets a number', () {
    expect(DriveBackup.uniqueName('weekly', ['daily']), 'weekly');
    expect(DriveBackup.uniqueName('weekly', ['weekly']), 'weekly (2)');
    expect(DriveBackup.uniqueName('weekly', ['weekly', 'weekly (2)']), 'weekly (3)');
    expect(DriveBackup.uniqueName('   ', []), isNotEmpty, reason: 'a blank name gets the default');
  });

  test("the default name is the date and time, and a quote in a name cannot break Drive's search", () {
    expect(DriveBackup.defaultSnapshotName(DateTime(2026, 9, 22, 9, 5)), '2026-09-22 09.05');
    expect(DriveBackup.quoted("it's"), r"it\'s");
    expect(DriveBackup.quoted(r'a\b'), r'a\\b');
  });

  test('1.0: a snapshot listing reads every page Drive answers, not only the first 200 files', () async {
    final List<String?> asked = [];
    final List<Map<dynamic, dynamic>> files = await DriveBackup.allPages((String? token) async {
      asked.add(token);
      if (token == null) {
        return {
          'files': [
            {'id': '1', 'name': 'store.db'},
          ],
          'nextPageToken': 'p2',
        };
      }
      if (token == 'p2') {
        return {
          'files': [
            {'id': '2', 'name': 'board-picture.a.jpg'},
          ],
          'nextPageToken': 'p3',
        };
      }
      return {
        'files': [
          {'id': '3', 'name': 'board-picture.b.jpg'},
        ],
      };
    });
    expect(files.map((f) => f['name']).toList(), ['store.db', 'board-picture.a.jpg', 'board-picture.b.jpg']);
    expect(asked, [null, 'p2', 'p3']);
  });

  test('1.0: a failed later page keeps the files already listed; a failed first page lists none', () async {
    final List<Map<dynamic, dynamic>> partial = await DriveBackup.allPages((String? token) async {
      if (token == null) {
        return {
          'files': [
            {'id': '1', 'name': 'store.db'},
          ],
          'nextPageToken': 'p2',
        };
      }
      return null;
    });
    expect(partial.map((f) => f['name']).toList(), ['store.db']);
    expect(await DriveBackup.allPages((String? token) async => null), isEmpty);
  });

  test('1.0: a snapshot is listed past its first 200 files, and every connection client is closed', () async {
    SecureStorageHandler.register();
    FlutterSecureStorage.setMockInitialValues({'driveRefreshToken': 'r', 'driveClientId': 'id', 'driveClientSecret': 's'});
    final List<_DriveClient> clients = [];
    final Map<String?, Map<String, Object>> pages = {
      null: {
        'files': [
          {'id': '1', 'name': 'store.db'},
        ],
        'nextPageToken': 'p2',
      },
      'p2': {
        'files': [
          {'id': '2', 'name': 'board-picture.a.jpg'},
        ],
      },
    };

    final List<DriveFile> files = await HttpOverrides.runZoned(
      () => DriveBackup.list(folderId: 'snapshot'),
      createHttpClient: (SecurityContext? context) {
        final _DriveClient client = _DriveClient(pages);
        clients.add(client);
        return client;
      },
    );

    expect(files.map((f) => f.name).toList(), ['store.db', 'board-picture.a.jpg']);
    expect(clients, hasLength(3), reason: 'the token, then one listing call per page');
    expect(clients.where((c) => !c.closed), isEmpty, reason: 'each kept its socket until the idle timeout');
  });
}
