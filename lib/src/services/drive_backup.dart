import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/handlers/secure_storage_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// One file as Drive reports it.
class DriveFile {
  const DriveFile({required this.id, required this.name, this.modifiedTime, this.size});

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? size;
}

/// Google Drive backup target.
///
/// Deliberately credential-less in the source: the OAuth client id/secret are
/// entered once by the user and kept in secure storage, never compiled in.
/// A client secret committed to a public repository is detected and revoked
/// automatically by Google, and it would be a shared secret for every install
/// of this build besides.
///
/// Uses the **installed-application loopback flow**, which is what Google
/// requires for desktop/native clients:
///   1. bind an HTTP server on 127.0.0.1 with an OS-assigned port;
///   2. open the consent screen in the SYSTEM BROWSER — Google refuses OAuth
///      inside embedded WebViews (`disallowed_useragent`), so the app's own
///      webview is not an option here;
///   3. the browser redirects back to the loopback with `?code=…`;
///   4. exchange that for a refresh token and keep only the refresh token.
///
/// Scope is `drive.file`: the app can only ever see and touch files it
/// created itself, so it has no access to the rest of the user's Drive.
class DriveBackup {
  DriveBackup._();

  static const String scope = 'https://www.googleapis.com/auth/drive.file';
  static const String folderName = 'LoliSnatcher';

  static const String _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _api = 'https://www.googleapis.com/drive/v3';
  static const String _uploadApi = 'https://www.googleapis.com/upload/drive/v3';

  /// Cached access token; Google's last an hour, refreshed a minute early.
  static String? _accessToken;
  static DateTime? _accessExpiry;
  static String? _folderId;

  // ─────────────────────────── credentials ───────────────────────────

  static Future<String?> get clientId => SecureStorageHandler.instance.read(SecureStorageKey.driveClientId);
  static Future<String?> get clientSecret => SecureStorageHandler.instance.read(SecureStorageKey.driveClientSecret);

  static Future<void> setCredentials(String id, String secret) async {
    await SecureStorageHandler.instance.write(SecureStorageKey.driveClientId, id.trim());
    await SecureStorageHandler.instance.write(SecureStorageKey.driveClientSecret, secret.trim());
  }

  static Future<bool> get hasCredentials async => (await clientId)?.isNotEmpty == true;

  static Future<bool> get isLinked async =>
      (await SecureStorageHandler.instance.read(SecureStorageKey.driveRefreshToken))?.isNotEmpty == true;

  static Future<void> unlink() async {
    _accessToken = null;
    _accessExpiry = null;
    _folderId = null;
    await SecureStorageHandler.instance.delete(SecureStorageKey.driveRefreshToken);
  }

  // ──────────────────────────── sign in ────────────────────────────

  /// Runs the loopback consent flow. Returns null on success, otherwise a
  /// message describing what went wrong.
  static Future<String?> link({Duration timeout = const Duration(minutes: 3)}) async {
    final String id = (await clientId) ?? '';
    final String secret = (await clientSecret) ?? '';
    if (id.isEmpty || secret.isEmpty) {
      return 'Enter your Google OAuth client ID and secret first.';
    }

    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final String redirect = 'http://127.0.0.1:${server.port}';

      final Uri authUrl = Uri.parse(_authEndpoint).replace(
        queryParameters: {
          'client_id': id,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': scope,
          // offline + consent is what actually yields a refresh token; without
          // `prompt=consent` Google omits it on every authorisation after the
          // first, and the link would silently work once and never again.
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

      final bool opened = await launchUrlString(
        authUrl.toString(),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        return 'Could not open a browser for the Google sign-in page.';
      }

      final HttpRequest request = await server.first.timeout(timeout);
      final String? code = request.uri.queryParameters['code'];
      final String? error = request.uri.queryParameters['error'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_landingPage(linked: code != null));
      await request.response.close();

      if (code == null) {
        return error == null ? 'No authorisation code was returned.' : 'Google returned: $error';
      }

      final Map<String, dynamic>? tokens = await _postForm(_tokenEndpoint, {
        'client_id': id,
        'client_secret': secret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect,
      });
      final String? refresh = tokens?['refresh_token']?.toString();
      if (refresh == null || refresh.isEmpty) {
        return 'Google did not return a refresh token. Revoke the app at '
            'myaccount.google.com/permissions and try again.';
      }

      await SecureStorageHandler.instance.write(SecureStorageKey.driveRefreshToken, refresh);
      _accessToken = tokens?['access_token']?.toString();
      _accessExpiry = DateTime.now().add(
        Duration(seconds: (int.tryParse(tokens?['expires_in']?.toString() ?? '') ?? 3600) - 60),
      );
      return null;
    } on TimeoutException {
      return 'Timed out waiting for Google to redirect back.';
    } catch (e, s) {
      Logger.Inst().log('drive link failed: $e', 'DriveBackup', 'link', LogTypes.exception, s: s);
      return 'Sign-in failed: $e';
    } finally {
      await server?.close(force: true);
    }
  }

  /// What the browser shows after the redirect, before the user comes back.
  static String _landingPage({required bool linked}) {
    final String heading = linked ? 'LoliSnatcher is linked' : 'Sign-in cancelled';
    return '''
<!doctype html>
<meta name="viewport" content="width=device-width">
<body style="font-family:sans-serif;background:#141018;color:#eeeeee;display:flex;align-items:center;justify-content:center;height:90vh">
  <div style="text-align:center">
    <h2>$heading</h2>
    <p>You can close this tab and go back to the app.</p>
  </div>
</body>
''';
  }

  // ──────────────────────────── plumbing ────────────────────────────

  static Future<Map<String, dynamic>?> _postForm(String url, Map<String, String> body) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(
        body.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'),
      );
      final HttpClientResponse res = await req.close();
      final String text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        Logger.Inst().log('token endpoint $url -> ${res.statusCode}: $text', 'DriveBackup', '_postForm', LogTypes.exception);
        return null;
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  static Future<String?> _token() async {
    if (_accessToken != null && (_accessExpiry?.isAfter(DateTime.now()) ?? false)) {
      return _accessToken;
    }
    final String? refresh = await SecureStorageHandler.instance.read(SecureStorageKey.driveRefreshToken);
    final String id = (await clientId) ?? '';
    final String secret = (await clientSecret) ?? '';
    if (refresh == null || refresh.isEmpty || id.isEmpty) return null;

    final Map<String, dynamic>? tokens = await _postForm(_tokenEndpoint, {
      'client_id': id,
      'client_secret': secret,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    final String? access = tokens?['access_token']?.toString();
    if (access == null) return null;
    _accessToken = access;
    _accessExpiry = DateTime.now().add(
      Duration(seconds: (int.tryParse(tokens?['expires_in']?.toString() ?? '') ?? 3600) - 60),
    );
    return access;
  }

  static Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    required String token,
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentLength = body.length;
        req.add(body);
      }
      return await req.close();
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  static Future<String?> _ensureFolder(String token) async {
    if (_folderId != null) return _folderId;
    final Uri query = Uri.parse('$_api/files').replace(
      queryParameters: {
        'q': "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false",
        'fields': 'files(id,name)',
        'pageSize': '5',
      },
    );
    final HttpClientResponse res = await _send('GET', query, token: token);
    final String text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) {
      final List files = (jsonDecode(text) as Map)['files'] as List? ?? const [];
      if (files.isNotEmpty) {
        return _folderId = files.first['id'].toString();
      }
    }

    final HttpClientResponse created = await _send(
      'POST',
      Uri.parse('$_api/files').replace(queryParameters: {'fields': 'id'}),
      token: token,
      headers: {'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'name': folderName, 'mimeType': 'application/vnd.google-apps.folder'})),
    );
    final String createdText = await created.transform(utf8.decoder).join();
    if (created.statusCode != 200 && created.statusCode != 201) return null;
    return _folderId = (jsonDecode(createdText) as Map)['id'].toString();
  }

  static Future<DriveFile?> _find(String token, String folderId, String name) async {
    final Uri query = Uri.parse('$_api/files').replace(
      queryParameters: {
        'q': "name = '$name' and '$folderId' in parents and trashed = false",
        'fields': 'files(id,name,modifiedTime,size)',
        'pageSize': '5',
      },
    );
    final HttpClientResponse res = await _send('GET', query, token: token);
    final String text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) return null;
    final List files = (jsonDecode(text) as Map)['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    final Map f = files.first as Map;
    return DriveFile(
      id: f['id'].toString(),
      name: f['name'].toString(),
      modifiedTime: DateTime.tryParse(f['modifiedTime']?.toString() ?? ''),
      size: int.tryParse(f['size']?.toString() ?? ''),
    );
  }

  // ───────────────────────── upload / download ─────────────────────────

  /// Uploads (or replaces) one file in the app's Drive folder.
  ///
  /// Resumable rather than simple upload because `store.db` can run to tens
  /// of megabytes, which is past the point where a single request is safe on
  /// a phone connection, and because it gives the UI real progress.
  static Future<String?> upload(
    String name,
    List<int> bytes,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final String? token = await _token();
    if (token == null) return 'Not signed in to Google Drive.';
    final String? folderId = await _ensureFolder(token);
    if (folderId == null) return 'Could not create the $folderName folder.';

    try {
      final DriveFile? existing = await _find(token, folderId, name);
      final Uri start = Uri.parse(
        existing == null
            ? '$_uploadApi/files?uploadType=resumable'
            : '$_uploadApi/files/${existing.id}?uploadType=resumable',
      );
      final Map<String, dynamic> metadata = existing == null
          ? {'name': name, 'parents': [folderId]}
          : {'name': name};

      final HttpClientResponse init = await _send(
        existing == null ? 'POST' : 'PATCH',
        start,
        token: token,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': mimeType,
          'X-Upload-Content-Length': bytes.length.toString(),
        },
        body: utf8.encode(jsonEncode(metadata)),
      );
      await init.drain<void>();
      final String? location = init.headers.value('location');
      if (location == null) return 'Drive refused the upload (HTTP ${init.statusCode}).';

      // One PUT for the whole body; chunking only pays off for retries, which
      // are not worth the complexity for files this size.
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest put = await client.putUrl(Uri.parse(location));
        put.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        put.headers.contentType = ContentType.parse(mimeType);
        put.headers.contentLength = bytes.length;

        const int chunk = 256 * 1024;
        for (int offset = 0; offset < bytes.length; offset += chunk) {
          final int end = (offset + chunk).clamp(0, bytes.length);
          put.add(bytes.sublist(offset, end));
          await put.flush();
          onProgress?.call(end, bytes.length);
        }
        final HttpClientResponse res = await put.close();
        await res.drain<void>();
        if (res.statusCode != 200 && res.statusCode != 201) {
          return 'Upload of $name failed (HTTP ${res.statusCode}).';
        }
      } finally {
        client.close();
      }
      return null;
    } catch (e, s) {
      Logger.Inst().log('drive upload failed: $e', 'DriveBackup', 'upload', LogTypes.exception, s: s);
      return 'Upload of $name failed: $e';
    }
  }

  static Future<Uint8List?> download(String name) async {
    final String? token = await _token();
    if (token == null) return null;
    final String? folderId = await _ensureFolder(token);
    if (folderId == null) return null;
    final DriveFile? file = await _find(token, folderId, name);
    if (file == null) return null;

    try {
      final HttpClientResponse res = await _send(
        'GET',
        Uri.parse('$_api/files/${file.id}').replace(queryParameters: {'alt': 'media'}),
        token: token,
      );
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (e, s) {
      Logger.Inst().log('drive download failed: $e', 'DriveBackup', 'download', LogTypes.exception, s: s);
      return null;
    }
  }

  /// What is currently in the backup folder, for the "last backed up" line.
  static Future<List<DriveFile>> list() async {
    final String? token = await _token();
    if (token == null) return const [];
    final String? folderId = await _ensureFolder(token);
    if (folderId == null) return const [];
    try {
      final Uri query = Uri.parse('$_api/files').replace(
        queryParameters: {
          'q': "'$folderId' in parents and trashed = false",
          'fields': 'files(id,name,modifiedTime,size)',
          'orderBy': 'modifiedTime desc',
          'pageSize': '25',
        },
      );
      final HttpClientResponse res = await _send('GET', query, token: token);
      final String text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return const [];
      final List files = (jsonDecode(text) as Map)['files'] as List? ?? const [];
      return [
        for (final f in files)
          if (f is Map)
            DriveFile(
              id: f['id'].toString(),
              name: f['name'].toString(),
              modifiedTime: DateTime.tryParse(f['modifiedTime']?.toString() ?? ''),
              size: int.tryParse(f['size']?.toString() ?? ''),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
