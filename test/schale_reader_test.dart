import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The niyaniya read contract, as Keiyoushi's Koharu extension implements it
/// (src/all/koharu/.../Koharu.kt, pageListParse + getImagesByMangaData):
///
///   POST {api}/books/detail/{id}/{key}?crt=
///     → { data: { "0": DataKey, "780"?, "980"?, "1280"?, "1600"? }, similar: [...] }
///   GET  {api}/books/data/{id}/{key}/{dk.id}/{dk.key}/{realQuality}?crt=
///     → { base, entries: [ { path } ] }
///   page = {base}/{path}?w={realQuality}
///
/// The previous contract here was per-page-index and wrong. Every test below
/// is written to separate the real shape from that one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('schale_reader');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SchaleClearanceHandler.instance.resetForTests();
    SchaleHandler.resetDomainsForTests();
  });

  tearDown(() {
    SchaleClearanceHandler.instance.resetForTests();
    SchaleHandler.resetDomainsForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  SchaleHandler handler([String url = 'https://niyaniya.moe']) =>
      SchaleHandler(Booru('niyaniya', BooruType.NiyaNiya, '', url, ''), 20);

  /// A dataset with every size present.
  Map<String, dynamic> fullData() => {
    '0': {'id': 10, 'key': 'k0', 'size': 90000000.0},
    '780': {'id': 11, 'key': 'k780', 'size': 20000000.0},
    '980': {'id': 12, 'key': 'k980', 'size': 30000000.0},
    '1280': {'id': 13, 'key': 'k1280', 'size': 40000000.0},
    '1600': {'id': 14, 'key': 'k1600', 'size': 60000000.0},
  };

  group('choosing the image set', () {
    test('the requested size is used when present, and named as realQuality', () {
      final r = SchaleHandler.pickDataKey(fullData(), '1280')!;
      expect(r.id, '13');
      expect(r.key, 'k1280');
      expect(r.realQuality, '1280');
    });

    test("Koharu's fallback order for every preference", () {
      // Each row: the sizes present → what each preference resolves to.
      // 0 is the only guaranteed key; the chains come straight from
      // getImagesByMangaData.
      Map<String, dynamic> only(List<String> sizes) => {
        for (final s in sizes) s: {'id': int.parse(s.isEmpty ? '0' : s) + 1, 'key': 'k$s'},
      };

      // 1280 → 1280, 1600, 0, 980, 780
      expect(SchaleHandler.pickDataKey(only(['0', '1600']), '1280')!.realQuality, '1600');
      expect(SchaleHandler.pickDataKey(only(['0', '980']), '1280')!.realQuality, '0');
      expect(SchaleHandler.pickDataKey(only(['980', '780']), '1280')!.realQuality, '980');
      // 1600 → 1600, 1280, 0, 980, 780
      expect(SchaleHandler.pickDataKey(only(['0', '1280']), '1600')!.realQuality, '1280');
      // 980 → 980, 1280, 0, 1600, 780
      expect(SchaleHandler.pickDataKey(only(['0', '1600', '1280']), '980')!.realQuality, '1280');
      expect(SchaleHandler.pickDataKey(only(['1600', '780']), '980')!.realQuality, '1600');
      // 780 → 780, 980, 0, 1280, 1600
      expect(SchaleHandler.pickDataKey(only(['1280', '1600']), '780')!.realQuality, '1280');
      // 0 → 0, 1600, 1280, 980, 780
      expect(SchaleHandler.pickDataKey(only(['780', '1600']), '0')!.realQuality, '1600');
    });

    test('an unknown preference behaves as original', () {
      expect(SchaleHandler.pickDataKey(fullData(), 'huge')!.realQuality, '0');
    });

    test('a size entry missing its id or key is skipped, not chosen', () {
      final data = fullData();
      data['1280'] = {'size': 1.0};
      expect(SchaleHandler.pickDataKey(data, '1280')!.realQuality, '1600');
    });

    test('no usable set at all is null, never an exception', () {
      expect(SchaleHandler.pickDataKey({}, '1280'), isNull);
      expect(SchaleHandler.pickDataKey(null, '1280'), isNull);
    });
  });

  group('the two gated URLs and the page URL', () {
    test('the dataset comes from a POST to the detail path with the clearance', () {
      expect(
        handler().detailPostUrl(id: '27557', key: 'ed1cbb746a2b', clearance: 'T'),
        'https://api.schale.network/books/detail/27557/ed1cbb746a2b?crt=T',
      );
    });

    test('the page list comes from /books/data with the chosen set and its size', () {
      expect(
        handler().imagesUrl(
          id: '27557',
          key: 'ed1cbb746a2b',
          dataId: '13',
          dataKey: 'k1280',
          quality: '1280',
          clearance: 'T',
        ),
        'https://api.schale.network/books/data/27557/ed1cbb746a2b/13/k1280/1280?crt=T',
      );
    });

    test('it is NOT per page index — the old, wrong shape', () {
      final url = handler().imagesUrl(
        id: '1', key: 'k', dataId: 'd', dataKey: 'dk', quality: '1280', clearance: 'c',
      );
      expect(url, isNot(matches(RegExp(r'/\d+\?crt=$'))), reason: 'no trailing page index');
      expect(url, endsWith('/1280?crt=c'));
    });

    test('a page is base/path?w=quality', () {
      expect(
        SchaleHandler.pageUrl(base: 'https://hikari.erocdn.net/data/1/2', path: 'abc/001.webp', quality: '1280'),
        'https://hikari.erocdn.net/data/1/2/abc/001.webp?w=1280',
      );
    });

    test('a base with a trailing slash and a path with a leading one do not double up', () {
      expect(
        SchaleHandler.pageUrl(base: 'https://cdn.test/x/', path: '/p.webp', quality: '0'),
        'https://cdn.test/x/p.webp?w=0',
      );
    });

    test('the size in ?w= is the size actually resolved to, never the preference', () {
      // The failure this guards: asking for 1280, getting the 1600 set, and
      // requesting ?w=1280 against it.
      final picked = SchaleHandler.pickDataKey({'0': {'id': 1, 'key': 'a'}, '1600': {'id': 2, 'key': 'b'}}, '1280')!;
      final url = SchaleHandler.pageUrl(base: 'https://cdn.test', path: 'p.webp', quality: picked.realQuality);
      expect(url, endsWith('?w=1600'));
    });

    test('the clearance is escaped, so a token with URL characters survives', () {
      final url = handler().detailPostUrl(id: '1', key: 'k', clearance: 'a+b/c=d&e');
      expect(Uri.parse(url).queryParameters['crt'], 'a+b/c=d&e');
    });
  });

  group('the mirror', () {
    test('until resolved, headers follow the configured base', () {
      final headers = handler('https://shupogaki.moe').getHeaders();
      expect(headers['Referer'], 'https://shupogaki.moe/');
      expect(headers['Origin'], 'https://shupogaki.moe');
    });

    test('a source with no URL falls back to the default mirror', () {
      expect(handler('').getHeaders()['Referer'], '${SchaleHandler.defaultSite}/');
    });

    test('the API host is shared and never follows the mirror', () {
      expect(
        handler('https://shupogaki.moe').detailPostUrl(id: '1', key: 'k', clearance: 'c'),
        startsWith('https://api.schale.network/'),
      );
    });

    test('the API is sent the same reduced Chrome agent the solver presents', () {
      // A token earned by one client and spent by another is what 403'd for a
      // whole day.
      final ua = handler().getHeaders()['User-Agent']!;
      expect(ua, contains('Android 10; K'));
      expect(ua, isNot(contains('wv')));
      expect(ua, isNot(contains('SM-')));
    });
  });

  group('the clearance token', () {
    test('survives a restart', () {
      SchaleClearanceHandler.instance.store('token-abc');
      expect(SchaleClearanceHandler.instance.token, 'token-abc');
      expect(File('${SettingsHandler.instance.path}${SchaleClearanceHandler.fileName}').existsSync(), isTrue);
    });

    test('invalidating removes it from disk and remembers it as refused', () {
      SchaleClearanceHandler.instance.store('token-abc');
      SchaleClearanceHandler.instance.invalidate();

      expect(SchaleClearanceHandler.instance.hasToken, isFalse);
      expect(SchaleClearanceHandler.instance.rejectedToken, 'token-abc');
      expect(
        File('${SettingsHandler.instance.path}${SchaleClearanceHandler.fileName}').existsSync(),
        isFalse,
      );
    });

    test('reads the value the site stores, whatever shape the bridge returns', () {
      expect(SchaleClearanceHandler.tokenFromLocalStorage('abc123'), 'abc123');
      expect(SchaleClearanceHandler.tokenFromLocalStorage('"abc123"'), 'abc123');
      expect(SchaleClearanceHandler.tokenFromLocalStorage("'abc123'"), 'abc123');
    });

    test('an unsolved challenge yields no token rather than a junk one', () {
      expect(SchaleClearanceHandler.tokenFromLocalStorage(null), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('null'), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('undefined'), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('  '), isNull);
      expect(SchaleClearanceHandler.tokenFromLocalStorage('""'), isNull);
    });
  });
}
