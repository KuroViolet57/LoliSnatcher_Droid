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
}
