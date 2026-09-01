import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/log_redaction.dart';

/// Two problems found in a talker log that was shared for an unrelated reason.
///
/// The fixtures below are the real shapes from that file, with the secret
/// values replaced by same-shaped fakes — the point is that the PATTERN was
/// leaking, on every request, dozens of times per session.
///
/// FALSIFIER: any assertion here that still finds the secret substring in the
/// output means a shared log still carries it.
void main() {
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
