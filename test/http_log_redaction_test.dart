import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker/talker.dart';

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

  test("a login cookie's pass_hash is hidden wherever it is spelled out", () {
    expect(redactSecrets('Cookie: user_id=1234; pass_hash=HASHVALUE0123456789'), isNot(contains('HASHVALUE0123456789')));
  });
}
