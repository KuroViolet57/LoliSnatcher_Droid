import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 6 items 2 and 3.
///
/// The reader was building page URLs by substituting 896 into each grid
/// thumbnail's path. Verified against the live API: on that endpoint only 320
/// and 896 exist, 896 exists ONLY for the cover, and every other size returns
/// 400. So page 1 was the cover thumbnail and pages 2+ were 404s.
///
/// Real pages live behind a clearance token, on a different endpoint entirely.
/// The assertions below are written to separate a real page URL from the
/// plausible wrong one — an "it produced a URL" test would pass just as happily
/// while serving 320px thumbnails as pages.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('schale_reader');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SchaleClearanceHandler.instance.resetForTests();
  });

  tearDown(() {
    SchaleClearanceHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  SchaleHandler handler([String url = 'https://niyaniya.moe']) =>
      SchaleHandler(Booru('niyaniya', BooruType.NiyaNiya, '', url, ''), 20);

  group('a page URL is a page, not a thumbnail', () {
    // The exact shape the site's own bundle builds:
    //   GET {api}/books/data/{id}/{key}/{entry.id}/{entry.key}/{index}?crt=
    const String thumbPath =
        'https://hikari.erocdn.net/thumbnail/116566/a8761aa5efb3/5cc19/6ff7f/320.jpg';

    test('it addresses /books/data on the API host, carrying the clearance', () {
      final url = handler().readUrlFor(
        id: '27557',
        key: 'ed1cbb746a2b',
        entryId: 'e1',
        entryKey: 'k1',
        index: 3,
        clearance: 'CRT-TOKEN',
      );

      expect(url, 'https://api.schale.network/books/data/27557/ed1cbb746a2b/e1/k1/3?crt=CRT-TOKEN');
    });

    test('it is not the thumbnail endpoint, and carries no size segment', () {
      // The two properties that separate a real page from what was shipped.
      final url = handler().readUrlFor(
        id: '27557',
        key: 'k',
        entryId: 'e',
        entryKey: 'ek',
        index: 0,
        clearance: 't',
      );

      expect(url, isNot(contains('/thumbnail/')));
      expect(url, isNot(contains('erocdn')));
      expect(url, isNot(contains('896.jpg')));
      expect(url, isNot(contains('320.jpg')));
      expect(url, isNot(equals(thumbPath)));
    });

    test('a page URL never collides with its own grid thumbnail', () {
      // The failure this is built to make impossible: pages that are really
      // 320px thumbnails would pass any "an image loaded" check.
      final h = handler();
      final page = h.readUrlFor(
        id: '1', key: 'k', entryId: 'e', entryKey: 'ek', index: 0, clearance: 'c',
      );
      expect(page, isNot(thumbPath));
      expect(Uri.parse(page).host, 'api.schale.network');
    });

    test('the clearance is escaped, so a token with URL characters survives', () {
      final url = handler().readUrlFor(
        id: '1', key: 'k', entryId: 'e', entryKey: 'ek', index: 0,
        clearance: 'a+b/c=d&e',
      );
      expect(Uri.parse(url).queryParameters['crt'], 'a+b/c=d&e');
    });

    test('the page list is requested from the detail path with a clearance', () {
      expect(
        handler().extraUrlFor(id: '27557', key: 'ed1cbb746a2b', clearance: 'T'),
        'https://api.schale.network/books/detail/27557/ed1cbb746a2b?crt=T',
      );
    });
  });

  group('the clearance token', () {
    test('survives a restart', () {
      SchaleClearanceHandler.instance.store('token-abc');
      expect(SchaleClearanceHandler.instance.token, 'token-abc');

      // A fresh read from disk, as if the app had been killed.
      SchaleClearanceHandler.instance.resetForTests();
      SchaleClearanceHandler.instance
        ..ensureLoaded()
        ..hashCode;
      expect(File('${SettingsHandler.instance.path}${SchaleClearanceHandler.fileName}').existsSync(), isTrue);
    });

    test('invalidating removes it from disk, so the next read re-challenges', () {
      SchaleClearanceHandler.instance.store('token-abc');
      SchaleClearanceHandler.instance.invalidate();

      expect(SchaleClearanceHandler.instance.hasToken, isFalse);
      expect(
        File('${SettingsHandler.instance.path}${SchaleClearanceHandler.fileName}').existsSync(),
        isFalse,
      );
    });

    test('reads the value the site stores, whatever shape the bridge returns', () {
      // evaluateJavascript hands back a bare string on one platform and a
      // quoted one on another; both are the same token.
      expect(SchaleClearanceHandler.tokenFromLocalStorage('abc123'), 'abc123');
      expect(SchaleClearanceHandler.tokenFromLocalStorage('"abc123"'), 'abc123');
      expect(SchaleClearanceHandler.tokenFromLocalStorage("'abc123'"), 'abc123');
    });

    test('an unsolved challenge yields no token rather than a junk one', () {
      // Storing "null" would poison every later request with a token that can
      // never work.
      expect(SchaleClearanceHandler.tokenFromLocalStorage(null), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('null'), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('undefined'), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('  '), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('""'), isNull);
    });

    test('an empty value is never stored', () {
      SchaleClearanceHandler.instance.store('');
      expect(SchaleClearanceHandler.instance.hasToken, isFalse);
    });
  });

  group('the mirror is followed, not hardcoded', () {
    test('headers point at the configured mirror', () {
      final headers = handler('https://shupogaki.moe').getHeaders();
      expect(headers['Referer'], 'https://shupogaki.moe/');
      expect(headers['Origin'], 'https://shupogaki.moe');
    });

    test('a source with no URL falls back to the default mirror', () {
      final headers = handler('').getHeaders();
      expect(headers['Referer'], '${SchaleHandler.defaultSite}/');
    });

    test('the API host stays shared across mirrors', () {
      // Only the front end differs; both mirrors talk to the same API.
      expect(
        handler('https://shupogaki.moe').readUrlFor(
          id: '1', key: 'k', entryId: 'e', entryKey: 'ek', index: 0, clearance: 'c',
        ),
        startsWith('https://api.schale.network/'),
      );
    });
  });
}
