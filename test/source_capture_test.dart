import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_capture_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The source-capture tool exists so a site this machine cannot reach — one
/// behind a bot filter — can still be read from a real device and turned into a
/// handler. The bundle it produces is meant to be sent to someone else, so the
/// redaction below is the part that has to be right.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('capture_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceCaptureHandler.instance.clear();
  });

  tearDown(() {
    SourceCaptureHandler.instance.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('redaction — the bundle leaves the device', () {
    test('the clearance cookie the challenge just issued is stripped', () {
      // This is the one credential guaranteed to be present: it is what solving
      // the challenge produced, and it is enough to impersonate the session.
      const String page = 'document.cookie="cf_clearance=AbC123.xyz-LONGVALUE; path=/"';
      final String out = SourceCaptureHandler.redact(page);

      expect(out, contains('cf_clearance=<redacted>'));
      expect(out, isNot(contains('AbC123.xyz-LONGVALUE')));
      // The shape around it survives, so the capture is still readable.
      expect(out, contains('path=/'));
    });

    test('session and CSRF cookies go too, whatever they are called', () {
      const String body =
          'Set-Cookie: PHPSESSID=abcdef123456; Set-Cookie: csrf_token=zzz999yyy; '
          'sessionid: qqqqwwww1234';
      final String out = SourceCaptureHandler.redact(body);

      expect(out, isNot(contains('abcdef123456')));
      expect(out, isNot(contains('zzz999yyy')));
      expect(out, isNot(contains('qqqqwwww1234')));
    });

    test('authorization headers echoed into a payload are stripped', () {
      final String out = SourceCaptureHandler.redact(
        '{"headers":{"Authorization":"Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig"}}',
      );

      expect(out, contains('Bearer <redacted>'));
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
    });

    test("every booru credential in this install is stripped, not just the captured site's", () {
      // A capture of one site must never carry another site's login out with it.
      SettingsHandler.instance.booruList.value = [
        Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', 'my-secret-api-key-9999')
          ..userID = 'my-user-id-4242',
      ];

      final String out = SourceCaptureHandler.redact(
        'debug dump: key=my-secret-api-key-9999 user=my-user-id-4242 rest of page',
      );

      expect(out, isNot(contains('my-secret-api-key-9999')));
      expect(out, isNot(contains('my-user-id-4242')));
      expect(out, contains('rest of page'));
    });

    test('a very short credential is not used as a redaction rule', () {
      // Redacting a 2-character value would blank out half the markup and make
      // the capture useless.
      SettingsHandler.instance.booruList.value = [
        Booru('x', BooruType.NHentai, '', 'https://nhentai.net', 'ab')..userID = 'c',
      ];

      const String markup = '<div class="abc">cabbage</div>';
      expect(SourceCaptureHandler.redact(markup), markup);
    });

    test('ordinary markup is left completely alone', () {
      const String markup =
          '<a href="/g/12345" aria-label="Some Title"><img src="https://cdn.example/1.webp"></a>';
      expect(SourceCaptureHandler.redact(markup), markup);
    });
  });

  group('recording', () {
    test('nothing is recorded before a session starts', () {
      SourceCaptureHandler.instance
        ..recordPage('https://example.test/', '<html>hi</html>')
        ..recordResource('https://example.test/api/list');

      expect(SourceCaptureHandler.instance.entries, isEmpty);
    });

    test('a re-rendered page replaces its earlier copy rather than piling up', () {
      // A single-page app fires load-stop repeatedly while hydrating; the last
      // version is the settled one and the earlier ones are half-built.
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordPage('https://example.test/', '<html>first</html>');
      h.recordPage('https://example.test/', '<html>second, fully hydrated</html>');

      final pages = h.entries.where((e) => e.kind == CaptureKind.page).toList();
      expect(pages, hasLength(1));
      expect(pages.single.body, contains('fully hydrated'));
    });

    test('repeated resource urls are recorded once', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      for (int i = 0; i < 20; i++) {
        h.recordResource('https://cdn.example.test/thumb.webp');
      }
      h.recordResource('https://example.test/api/library?page=1');

      expect(h.resourceCount, 2);
    });

    test('an oversized body is truncated and says so', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      final String huge = 'x' * (SourceCaptureHandler.maxBodyChars + 5000);
      h.recordPage('https://example.test/big', huge);

      final entry = h.entries.single;
      expect(entry.size, SourceCaptureHandler.maxBodyChars);
      expect(entry.truncatedFrom, huge.length);
      expect(h.buildBundle(), contains('TRUNCATED'));
    });

    test('an empty page is not recorded as a capture', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordPage('https://example.test/', '   ');
      expect(h.entries, isEmpty);
    });
  });

  group('picking out what is worth fetching', () {
    test('data urls are separated from images, fonts and styling', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      for (final url in [
        'https://example.test/api/library?page=1',
        'https://example.test/_next/data/abc/index.json',
        'https://cdn.example.test/cover.webp',
        'https://cdn.example.test/cover.jpg?v=2',
        'https://example.test/style.css',
        'https://fonts.example.test/x.woff2',
        'https://example.test/clip.mp4',
      ]) {
        h.recordResource(url);
      }

      expect(h.interestingResources, [
        'https://example.test/api/library?page=1',
        'https://example.test/_next/data/abc/index.json',
      ]);
    });

    test('a query string does not disguise an image as data', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordResource('https://cdn.example.test/a/b/c.png?token=1&w=320');
      expect(h.interestingResources, isEmpty);
    });
  });

  group('the bundle', () {
    test('leads with the hosts the site talked to', () {
      // The fastest read on any new site: where it keeps images, and whether it
      // calls an API on another domain.
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordResource('https://cdn-a.example.test/1.webp');
      h.recordResource('https://cdn-a.example.test/2.webp');
      h.recordResource('https://api.example.test/v1/list');

      final String bundle = h.buildBundle();
      expect(bundle, contains('hosts the site talked to'));
      expect(bundle, contains('cdn-a.example.test'));
      expect(bundle, contains('api.example.test'));
      // Ordered by how often each was hit, so the real image host is on top.
      expect(
        bundle.indexOf('cdn-a.example.test'),
        lessThan(bundle.indexOf('api.example.test')),
      );
    });

    test('every body is delimited so it can be pulled back out unambiguously', () {
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordPage('https://example.test/g/1', '<html>gallery</html>');

      final String bundle = h.buildBundle();
      expect(bundle, contains('===== [0] PAGE'));
      expect(bundle, contains('===== https://example.test/g/1'));
      expect(bundle, contains('<html>gallery</html>'));
      expect(bundle, contains('===== end [0]'));
    });

    test('the header states what was captured and that secrets were removed', () {
      final h = SourceCaptureHandler.instance..start('https://hentaipaw.com/');
      h.recordPage('https://hentaipaw.com/', '<html>listing</html>');

      final String bundle = h.buildBundle(now: DateTime.utc(2026, 8, 30, 12));
      expect(bundle, contains('target: https://hentaipaw.com/'));
      expect(bundle, contains('2026-08-30T12:00:00.000Z'));
      expect(bundle, contains('pages: 1'));
      expect(bundle, contains('redacted'));
    });

    test('a captured page is redacted on the way in, not on the way out', () {
      // Redacting at write time would leave the secret sitting in memory and in
      // the on-screen preview.
      final h = SourceCaptureHandler.instance..start('https://example.test/');
      h.recordPage('https://example.test/', 'cf_clearance=SECRETVALUE123; rest');

      expect(h.entries.single.body, isNot(contains('SECRETVALUE123')));
    });

    test('writes a file named after the site', () async {
      final h = SourceCaptureHandler.instance..start('https://hentaipaw.com/');
      h.recordPage('https://hentaipaw.com/', '<html>listing</html>');

      final String? path = await h.writeBundle();
      expect(path, isNotNull);
      expect(path, contains('source-capture-hentaipaw-com-'));
      expect(File(path!).readAsStringSync(), contains('<html>listing</html>'));
    });
  });
}
