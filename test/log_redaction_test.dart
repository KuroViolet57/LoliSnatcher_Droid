import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/log_redaction.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Two problems found in a talker log that was shared for an unrelated reason.
///
/// The fixtures below are the real shapes from that file, with the secret
/// values replaced by same-shaped fakes — the point is that the PATTERN was
/// leaking, on every request, dozens of times per session.
///
/// FALSIFIER: any assertion here that still finds the secret substring in the
/// output means a shared log still carries it.
void main() {
  group('e-hentai session cookies (r30)', () {
    test('the forum session is redacted wherever it is spelled out', () {
      // BooruHandler logs '<base>: <cookie string>' on every search, with no
      // `Cookie:` prefix for the header rule to catch.
      const String line = 'https://e-hentai.org: nw=1; ipb_member_id=1913944; ipb_pass_hash=deadbeefcafe1234; igneous=abc123def; sl=dm_2';
      final String out = redactSecrets(line);
      expect(out, isNot(contains('deadbeefcafe1234')));
      expect(out, isNot(contains('1913944')));
      expect(out, isNot(contains('abc123def')));
      expect(out, contains('ipb_pass_hash=<redacted>'));
      expect(out, contains('sl=dm_2'), reason: 'the display mode is not a secret and helps diagnosis');
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('credentials never reach the log', () {
    test('an api_key in a query string goes', () {
      const line =
          // ignore: missing_whitespace_between_adjacent_strings
          'fetching: https://aibooru.online/posts.json?tags=hololive&limit=20'
          '&page=1&login=someuser57&api_key=AAAAAAAAAAAAAAAAAAAAAAAA';
      final out = redactSecrets(line);

      expect(out, isNot(contains('AAAAAAAAAAAAAAAAAAAAAAAA')));
      expect(out, isNot(contains('someuser57')));
      // and the line is still readable as a diagnostic
      expect(out, contains('aibooru.online/posts.json'));
      expect(out, contains('tags=hololive'));
    });

    test('a whole session cookie goes, name kept', () {
      const line =
          // ignore: missing_whitespace_between_adjacent_strings
          'Cookie: news-ticker=11; _danbooru2_session=HT36j27cCKn9MPZR52ldIBD8Zi'
          'zqJHV7707pbslSvkKZi1G7%2BuOl2Ifs; _dib=uae073d9f007e47f9';
      final out = redactSecrets(line);

      expect(out, isNot(contains('HT36j27cCKn9MPZR52ldIBD8Zi')));
      expect(out, contains('<redacted>'));
    });

    test('a bearer token goes', () {
      final out = redactSecrets('"Authorization": "Bearer VH8uW8CG6M8wmvXQwZZ"');
      expect(out, isNot(contains('VH8uW8CG6M8wmvXQwZZ')));
      expect(out, contains('Bearer'));
    });

    test('several api keys on one line all go', () {
      // The log interleaves sources; one surviving key is one too many.
      const line =
          'a?api_key=KEYKEYKEYKEY1111&x=1 b?api_key=KEYKEYKEYKEY2222&y=2';
      final out = redactSecrets(line);
      expect(out, isNot(contains('KEYKEYKEYKEY1111')));
      expect(out, isNot(contains('KEYKEYKEYKEY2222')));
    });

    test('a password never appears even in an odd spelling', () {
      expect(redactSecrets('password=hunter2hunter2'), isNot(contains('hunter2hunter2')));
      expect(redactSecrets('password_hash=abcdef123456'), isNot(contains('abcdef123456')));
    });

    test('ordinary text is left alone', () {
      // Over-redaction makes logs useless, which is its own failure.
      const line = 'fetched 20 items for tags=undertale in 240ms';
      expect(redactSecrets(line), line);
    });

    test('an empty string is handled', () {
      expect(redactSecrets(''), '');
    });

    test('a caller can name extra secrets', () {
      expect(
        redactSecrets('token is ZZZZTOPSECRET', extraSecrets: ['ZZZZTOPSECRET']),
        isNot(contains('ZZZZTOPSECRET')),
      );
    });
  });

  /// r69: a shared log carried an eahentai login's username and password in
  /// clear, in the Dio logger's "Data:" block, which never passed through
  /// redactSecrets. JSON fields are redacted, and the request-body line the
  /// app writes itself is built redacted.
  group('request bodies (r69)', () {
    test('JSON credential fields are redacted, names kept', () {
      const String body = 'Data: {\n  "login": "someone57",\n  "password": "Sup3r-Secret!Pass",\n  "turnstileToken": "abc"\n}';
      final String out = redactSecrets(body);
      expect(out, isNot(contains('Sup3r-Secret!Pass')));
      expect(out, isNot(contains('someone57')));
      expect(out, contains('"password": "<redacted>"'));
      expect(out, contains('"login": "<redacted>"'));
    });

    test('a token in an answer is redacted', () {
      final String out = redactSecrets('{"accessToken":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abc"}');
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains('accessToken'));
    });

    test('the request-body log line the app writes is redacted before it exists', () {
      final String line = Logger.requestDataLine(
        method: 'POST',
        url: 'https://eahentai.com/api/auth/login',
        data: {'login': 'someone57', 'password': 'Sup3r-Secret!Pass'},
      );
      expect(line, contains('https://eahentai.com/api/auth/login'));
      expect(line, isNot(contains('Sup3r-Secret!Pass')));
      expect(line, isNot(contains('someone57')));
    });

    test('a long body is redacted before it is cut, so a secret near the cut cannot survive in half', () {
      final String filler = 'a' * 1990;
      final String line = Logger.requestDataLine(
        method: 'POST',
        url: 'https://x.invalid/login',
        data: {'login': 'someone57', 'filler': filler, 'password': 'Sup3r-Secret!Pass'},
      );
      expect(line, isNot(contains('Sup3r')));
      expect(line, isNot(contains('someone57')));
    });

    test("a gallery token is an address, not a credential: e-hentai's gdata answers stay readable", () {
      const String gdata = '{"gid":4178032,"token":"49d94b3d3c","title":"x"}';
      expect(redactSecrets(gdata), contains('"token":"49d94b3d3c"'));
    });

    test('a form body is redacted too', () {
      final String line = Logger.requestDataLine(method: 'POST', url: 'https://x.invalid/login', data: 'username=a&password=hunter2hunter2');
      expect(line, isNot(contains('hunter2hunter2')));
    });
  });

  group('a non-list response cannot kill a search', () {
    // From the same log:
    //   type 'String' is not a subtype of type 'List<dynamic>'
    //   at DanbooruHandler.parseTagSuggestionsList
    //   ... TagAliasResolver._resolveRemote ... ForYouHandler.search
    // The site answered a tag-suggestion lookup with a bot-check HTML page, and
    // the blind cast took the whole For You search down with it.
    test('a challenge page yields no suggestions rather than throwing', () {
      const html = '<html><body><div id="challenge-result"></div></body></html>';
      expect(BooruHandler.asResponseList(html), isEmpty);
    });

    test('a real list is passed through untouched', () {
      final list = [
        {'value': 'hatsune_miku'},
      ];
      expect(BooruHandler.asResponseList(list), same(list));
    });

    test('a JSON array arriving as text is still parsed', () {
      // Some endpoints answer with a string body that IS the array.
      expect(BooruHandler.asResponseList('[{"value":"a"}]'), hasLength(1));
    });

    test('a JSON object is not a list, and does not throw', () {
      expect(BooruHandler.asResponseList('{"error":"nope"}'), isEmpty);
    });

    test('null and numbers are handled', () {
      expect(BooruHandler.asResponseList(null), isEmpty);
      expect(BooruHandler.asResponseList(42), isEmpty);
    });
  });
}
