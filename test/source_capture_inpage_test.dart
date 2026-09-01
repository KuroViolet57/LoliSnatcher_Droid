import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_capture_handler.dart';

/// Why the hentaipaw.com capture came back with URLs and no bodies.
///
/// From that log, once per resource:
///
///   `[http-error] [GET] https://hentaipaw.com/_next/static/chunks/webpack-....js`
///   `capture fetch failed for ...: DioException [unknown]: null`
///
/// The webview had loaded every one of those files seconds earlier. The capture
/// then re-fetched them with Dio, which holds none of the clearance the webview
/// earned, so Cloudflare cut every request. Reading the body from inside the
/// live page instead sends it with the page's own cookies.
///
/// FALSIFIER: a fetch script that does not send credentials, or a result parser
/// that turns a failed fetch into an empty-but-successful body — either would
/// put a Cloudflare block page into the capture as if it were the API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('capture_inpage');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceCaptureHandler.instance
      ..clear()
      ..detachController();
  });

  tearDown(() {
    SourceCaptureHandler.instance
      ..clear()
      ..detachController();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the script the page runs', () {
    const String url = 'https://hentaipaw.com/api/search?q=a&page=1';

    test('it sends the page own credentials, which is the entire point', () {
      expect(SourceCaptureHandler.fetchScript(url), contains("credentials: 'include'"));
    });

    test('the url is embedded as JSON, so a query string cannot break out', () {
      // A naive '...' interpolation would let a url containing a quote inject
      // script into the page being captured.
      final String script = SourceCaptureHandler.fetchScript(
        "https://x.test/a'; alert(1); //",
      );
      expect(script, contains(jsonEncode("https://x.test/a'; alert(1); //")));
      expect(script, isNot(contains("fetch('https://x.test/a'; alert(1)")));
    });

    test('it reports the status and content type, not just the text', () {
      // Without the status a Cloudflare 403 page is indistinguishable from the
      // API answering.
      final String script = SourceCaptureHandler.fetchScript(url);
      expect(script, contains('status: r.status'));
      expect(script, contains("r.headers.get('content-type')"));
    });

    test('a thrown fetch is reported as a failure, not as an empty body', () {
      expect(SourceCaptureHandler.fetchScript(url), contains('ok: false'));
    });
  });

  group('reading what the bridge hands back', () {
    test('a JSON string, which is what Android returns', () {
      final r = SourceCaptureHandler.parseFetchResult(
        jsonEncode({'ok': true, 'status': 200, 'contentType': 'application/json', 'body': '{"a":1}'}),
      );
      expect(r!.status, 200);
      expect(r.contentType, 'application/json');
      expect(r.body, '{"a":1}');
      expect(r.error, isNull);
    });

    test('an already-decoded Map, which is what iOS returns', () {
      final r = SourceCaptureHandler.parseFetchResult({
        'ok': true,
        'status': 403,
        'contentType': 'text/html',
        'body': 'blocked',
      });
      expect(r!.status, 403);
      expect(r.body, 'blocked');
    });

    test('a failed fetch comes back as an error, never as a body', () {
      final r = SourceCaptureHandler.parseFetchResult(
        jsonEncode({'ok': false, 'error': 'TypeError: Failed to fetch'}),
      );
      expect(r!.error, contains('Failed to fetch'));
      expect(r.body, isNull);
    });

    test('null, empty and junk are all "no result", not a blank success', () {
      expect(SourceCaptureHandler.parseFetchResult(null), isNull);
      expect(SourceCaptureHandler.parseFetchResult(''), isNull);
      expect(SourceCaptureHandler.parseFetchResult('   '), isNull);
      expect(SourceCaptureHandler.parseFetchResult('not json'), isNull);
      expect(SourceCaptureHandler.parseFetchResult(42), isNull);
    });

    test('a real 200 with an empty body is still a success', () {
      // A 204 or an empty array is a legitimate answer and must be recorded.
      final r = SourceCaptureHandler.parseFetchResult(
        jsonEncode({'ok': true, 'status': 204, 'contentType': null, 'body': ''}),
      );
      expect(r!.status, 204);
      expect(r.body, '');
      expect(r.error, isNull);
    });
  });

  group('the page own API calls are caught as it makes them', () {
    // The second half of the problem: even with bodies working, the capture
    // only saw URLs the WEBVIEW requested. A Next.js app fetches its API from
    // client-side JavaScript, which never reaches onLoadResource — so the one
    // thing a handler needs was the one thing never recorded.
    test('the hook wraps both fetch and XMLHttpRequest', () {
      const String js = SourceCaptureHandler.networkHookScript;
      expect(js, contains('window.fetch = '));
      expect(js, contains('XMLHttpRequest.prototype.open'));
      expect(js, contains('XMLHttpRequest.prototype.send'));
    });

    test('it reads the body without consuming it from the app', () {
      // Reading res.text() directly would leave the site's own code with an
      // already-used stream and break the page being captured.
      expect(SourceCaptureHandler.networkHookScript, contains('res.clone()'));
    });

    test('it installs once, however many times it is injected', () {
      expect(SourceCaptureHandler.networkHookScript, contains('__lsCaptureInstalled'));
    });

    test('it never throws into the page it is watching', () {
      // A capture tool that breaks the site cannot capture it.
      expect('catch'.allMatches(SourceCaptureHandler.networkHookScript).length, greaterThan(3));
    });

    test('an api call is recorded with its method, status and body', () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      capture.recordXhr(
        method: 'GET',
        url: 'https://hentaipaw.com/api/library?page=1',
        status: 200,
        contentType: 'application/json',
        body: '{"items":[]}',
      );

      final bundle = capture.buildBundle();
      expect(bundle, contains('api calls the page made itself'));
      expect(bundle, contains('GET https://hentaipaw.com/api/library?page=1'));
      expect(bundle, contains('{"items":[]}'));
      expect(bundle, contains('200'));
    });

    test('the same endpoint paging twice is recorded once', () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      for (int i = 0; i < 3; i++) {
        capture.recordXhr(
          method: 'GET',
          url: 'https://hentaipaw.com/api/library?page=1',
          status: 200,
          body: 'x',
        );
      }
      expect(
        'GET https://hentaipaw.com/api/library?page=1'.allMatches(capture.buildBundle()).length,
        lessThanOrEqualTo(2), // once in the index, once in the body dump
      );
    });

    test('nothing is recorded when not recording', () {
      final capture = SourceCaptureHandler.instance..clear();
      capture.recordXhr(method: 'GET', url: 'https://x.test/api', status: 200, body: 'x');
      expect(capture.buildBundle(), isNot(contains('https://x.test/api')));
    });
  });

  group('a big capture can still leave the device', () {
    // From the device log, twice:
    //   PlatformException(error, android.os.TransactionTooLargeException:
    //   data parcel size 5726632 bytes) ... at _SourceCapturePageState._copy
    // Android moves clipboard data across a Binder transaction with a ~1MB
    // ceiling for the whole parcel, so Copy silently did nothing at all.
    String bundleOf(int bodies, int chars) {
      final capture = SourceCaptureHandler.instance
        ..clear()
        ..start('https://hentaipaw.com');
      for (int i = 0; i < bodies; i++) {
        capture.recordXhr(
          method: 'GET',
          url: 'https://hentaipaw.com/api/library?page=$i',
          status: 200,
          contentType: 'application/json',
          body: 'x' * chars,
        );
      }
      return capture.buildClipboardBundle();
    }

    test('a small capture is copied whole', () {
      final capture = SourceCaptureHandler.instance
        ..clear()
        ..start('https://hentaipaw.com');
      capture.recordXhr(
        method: 'GET',
        url: 'https://hentaipaw.com/api/library?page=1',
        status: 200,
        body: '{"items":[]}',
      );
      final String clip = capture.buildClipboardBundle();
      // Same content; the header carries a timestamp so they are not identical
      // strings when built a microsecond apart.
      expect(clip, isNot(contains('SHORTENED')));
      expect(clip, contains('{"items":[]}'));
      expect(clip, contains('api calls the page made itself'));
    });

    test('a capture the size of the real one is cut to fit the clipboard', () {
      final String clip = bundleOf(20, 300 * 1024); // ~6MB, as on the device
      expect(clip.length, lessThanOrEqualTo(SourceCaptureHandler.maxClipboardChars));
    });

    test('what survives the cut is the API calls, not the page markup', () {
      // Cutting the wrong half would hand back something useless.
      final String clip = bundleOf(3, 200 * 1024);
      expect(clip, contains('https://hentaipaw.com/api/library?page=0'));
    });

    test('it says it was shortened rather than pretending to be complete', () {
      final String clip = bundleOf(20, 300 * 1024);
      expect(clip, contains('SHORTENED'));
      expect(clip, contains('Share'));
    });

    test('the ceiling is well under the Binder limit', () {
      // The parcel carries more than the string; leave room.
      expect(SourceCaptureHandler.maxClipboardChars, lessThan(1024 * 1024));
    });
  });

  group('bodies are read while the page is alive', () {
    test('with no live webview nothing is attempted', () async {
      final capture = SourceCaptureHandler.instance;
      expect(capture.hasLiveController, isFalse);
      expect(await capture.fetchPendingBodies(), 0);
    });

    test('media urls are never queued, only the ones that could be an API', () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      // The exact resource mix from the hentaipaw capture.
      for (final url in [
        'https://hentaipaw.com/_next/static/chunks/webpack-2924c077c2315839.js',
        'https://hentaipaw.com/api/library?page=1',
        'https://hentaipaw.com/cover/1.webp',
        'https://hentaipaw.com/style.css',
        'https://hentaipaw.com/font.woff2',
      ]) {
        capture.recordResource(url);
      }

      expect(capture.pendingResources, contains('https://hentaipaw.com/api/library?page=1'));
      expect(
        capture.pendingResources,
        isNot(contains('https://hentaipaw.com/cover/1.webp')),
        reason: 'a cover is not an API response',
      );
      expect(capture.pendingResources.any((u) => u.endsWith('.css')), isFalse);
      expect(capture.pendingResources.any((u) => u.endsWith('.woff2')), isFalse);
    });

    test('clearing a capture forgets what was already read', () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      capture.recordResource('https://hentaipaw.com/api/library?page=1');
      expect(capture.pendingResources, hasLength(1));

      capture.clear();
      expect(capture.pendingResources, isEmpty);
    });
  });
}
