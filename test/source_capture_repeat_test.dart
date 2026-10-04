import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/debug/logic/source_capture_handler.dart';

/// A recording webview whose page answers every in-page fetch with [body].
class _Page implements InAppWebViewController {
  _Page(this.body);

  final String body;
  int fetches = 0;

  @override
  Future<dynamic> evaluateJavascript({required String source, ContentWorld? contentWorld}) async {
    fetches++;
    return jsonEncode({'ok': true, 'status': 200, 'contentType': 'application/json', 'body': body});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Settings → Debug → Source capture: recording a site again, the size cap,
/// and the "Fetch the response bodies" button.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const String api = 'https://hentaipaw.com/api/library?page=1';

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('capture_repeat');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceCaptureHandler.instance
      ..clear()
      ..detachController();
  });

  tearDown(() async {
    SourceCaptureHandler.instance
      ..clear()
      ..detachController();
    await SourceCaptureHandler.instance.journalFlushed;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('recording the site again without Discard', () {
    test("1.0: the page's api calls are recorded again", () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      capture.recordXhr(method: 'GET', url: api, status: 200, body: '{"items":[1]}');
      capture.stop();

      capture.start('https://hentaipaw.com');
      capture.recordXhr(method: 'GET', url: api, status: 200, body: '{"items":[2]}');

      expect(capture.entries.where((e) => e.kind == CaptureKind.xhr).map((e) => e.body), ['{"items":[2]}']);
    });

    test('1.0: the resource bodies are read again', () async {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      capture.recordResource(api);
      capture.attachController(_Page('{"first":true}'));
      expect(await capture.fetchPendingBodies(), 1);
      capture
        ..detachController()
        ..stop();

      capture.start('https://hentaipaw.com');
      capture.recordResource(api);
      expect(capture.pendingResources, [api]);
    });
  });

  group('the session cap', () {
    test('1.0: api bodies count toward the 8 MB cap like pages do', () {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      final String body = 'x' * SourceCaptureHandler.maxBodyChars;
      for (int i = 0; i < 20; i++) {
        capture.recordXhr(method: 'GET', url: 'https://hentaipaw.com/api/library?page=$i', status: 200, body: body);
      }
      expect(
        capture.totalChars,
        lessThanOrEqualTo(SourceCaptureHandler.maxTotalChars + SourceCaptureHandler.maxBodyChars),
      );
      expect(capture.totalChars, greaterThanOrEqualTo(SourceCaptureHandler.maxTotalChars), reason: 'filled up to the cap');
    });

    test('1.0: bodies read from the page count toward the cap too', () async {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      final _Page page = _Page('y' * SourceCaptureHandler.maxBodyChars);
      capture.attachController(page);
      for (int i = 0; i < 20; i++) {
        await capture.fetchBodyInPage('https://hentaipaw.com/api/gallery/$i');
      }
      expect(
        capture.totalChars,
        lessThanOrEqualTo(SourceCaptureHandler.maxTotalChars + SourceCaptureHandler.maxBodyChars),
      );
    });
  });

  group('Fetch the response bodies', () {
    test('1.0: a body already read from the live page is not fetched again', () async {
      final capture = SourceCaptureHandler.instance..start('https://hentaipaw.com');
      capture.recordResource(api);
      capture.attachController(_Page('{"items":[]}'));
      await capture.fetchPendingBodies();
      capture
        ..detachController()
        ..stop();
      expect(capture.fetchCount, 1);

      // The button, after the browser closed.
      final CaptureEntry? again = await capture.fetchBody(api);

      expect(capture.fetchCount, 1, reason: 'no second entry, and no FETCH FAILED line');
      expect(again?.body, '{"items":[]}');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
