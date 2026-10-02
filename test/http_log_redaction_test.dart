import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker/talker.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/log_redaction.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Answers every request itself: [status], a JSON body, and the cookies a
/// Danbooru-engine site sets.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      '[]',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'set-cookie': [
          '_req_id=69688.3; path=/; httponly',
          '_danbooru2_session=SESSIONVALUE0123456789; domain=example.online; path=/; secure; httponly',
          'pass_hash=HASHVALUE0123456789; path=/',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// r85: the exported log of 2026-10-02 printed an AiBooru login and API key
/// in clear in the [http-request] / [http-response] lines (the URL is their
/// title) and every Set-Cookie in full - the app's own lines were already
/// redacted, talker's Dio logger was not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(SettingsHandler.register);

  const String url = 'https://aibooru.online/posts.json?tags=tomboy&limit=20&page=1&login=someuser42&api_key=SECRETKEY0123456789';

  Future<String> exported(int status) async {
    final Talker talker = Talker(settings: TalkerSettings(useConsoleLogs: false));
    final Dio dio = Dio()
      ..httpClientAdapter = _Adapter(status)
      ..interceptors.add(Logger.dioLoggerFor(talker));
    try {
      await dio.get<dynamic>(url, options: Options(headers: {'Cookie': '_danbooru2_session=REQUESTCOOKIE0123'}));
    } catch (_) {}
    return talker.history.map((d) => d.generateTextMessage()).join('\n');
  }

  void expectClean(String text) {
    for (final String secret in ['someuser42', 'SECRETKEY0123456789', 'SESSIONVALUE0123456789', 'HASHVALUE0123456789', 'REQUESTCOOKIE0123']) {
      expect(text, isNot(contains(secret)), reason: '"$secret" must not reach the log');
    }
    expect(text, contains('tags=tomboy'), reason: 'the rest of the address stays readable');
    expect(text, contains('aibooru.online/posts.json'));
  }

  test('a request and its answer are logged without the key, the login or the cookies', () async {
    final String text = await exported(200);
    expect(text, contains('[http-request]'));
    expect(text, contains('[http-response]'));
    expectClean(text);
  });

  test('a failed request is logged without them too', () async {
    final String text = await exported(401);
    expect(text, contains('[http-error]'));
    expectClean(text);
  });

  test('the cookie arrays of response headers are hidden whole', () {
    const String headers = '''
Headers: {
  "set-cookie": [
    "_req_id=69688.3; path=/",
    "sk=UNKNOWNCOOKIE0123; path=/"
  ],
  "content-type": [
    "application/json"
  ]
}''';
    final String out = redactSecrets(headers);
    expect(out, isNot(contains('UNKNOWNCOOKIE0123')));
    expect(out, contains('"content-type"'));
    expect(out, contains('application/json'));
  });

  test("r88: a source's default tags hide only what looks like a credential", () {
    final settings = SettingsHandler.instance;
    settings.booruList
      ..clear()
      ..addAll([
        Booru('Plain', BooruType.Gelbooru, '', 'https://gelbooru.com', 'explicit'),
        Booru('Keyed', BooruType.Gelbooru, '', 'https://rule34.xxx', 'api_key=KEYVALUE0123456789&user_id=7654321'),
      ]);
    addTearDown(settings.booruList.clear);
    expect(
      redactSecrets('tagger: rating explicit 0.98; explicitly added the CPU EP'),
      'tagger: rating explicit 0.98; explicitly added the CPU EP',
      reason: 'log 2026-10-02 showed "rating <redacted>"',
    );
    final String out = redactSecrets('defaults KEYVALUE0123456789 and 7654321');
    expect(out, isNot(contains('KEYVALUE0123456789')));
    expect(out, isNot(contains('7654321')));
  });

  test('r88: a bare secret in the default tags is still hidden; ordinary tags beside it are not', () {
    // source_capture_test's guard (b1ec3dbf): installs put credentials in
    // the default tags, sometimes without a name.
    final settings = SettingsHandler.instance;
    settings.booruList
      ..clear()
      ..addAll([
        Booru('Bare', BooruType.Gelbooru, '', 'https://gelbooru.com', 'rating:explicit a1b2c3d4e5f6a7b8c9d0'),
        Booru('Tags', BooruType.Danbooru, '', 'https://danbooru.donmai.us', 'rating:explicit -video order:score highres 1girl'),
      ]);
    addTearDown(settings.booruList.clear);
    final String out = redactSecrets('GET /posts?tags=rating:explicit -video order:score highres 1girl key=a1b2c3d4e5f6a7b8c9d0');
    expect(out, isNot(contains('a1b2c3d4e5f6a7b8c9d0')));
    expect(out, contains('tags=rating:explicit -video order:score highres 1girl'));
  });

  test("a login cookie's pass_hash is hidden wherever it is spelled out", () {
    expect(redactSecrets('Cookie: user_id=1234; pass_hash=HASHVALUE0123456789'), isNot(contains('HASHVALUE0123456789')));
  });
}
