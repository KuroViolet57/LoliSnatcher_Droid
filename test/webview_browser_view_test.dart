import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/webview/ui/webview_browser_view.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';

/// 1.0 M2: a WebView-type tab's browser kept its page progress and address in
/// two ValueNotifiers that were never disposed with the view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    SearchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('webview_browser_view');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('closing the browser view disposes its notifiers', (tester) async {
    final Set<Object> live = {};
    final Set<Type> tracked = {ValueNotifier<int>, ValueNotifier<String>};
    void listener(ObjectEvent event) {
      if (event is ObjectCreated && tracked.contains(event.object.runtimeType)) {
        live.add(event.object);
      } else if (event is ObjectDisposed) {
        live.remove(event.object);
      }
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

    final SearchTab tab = SearchTab(Booru('browser', BooruType.WebView, '', 'https://example.com/?q={tags}', ''), null, 'cats');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WebViewBrowserView(tab: tab))));
    // Unit tests have no webview platform: the InAppWebView in the view asserts
    // while it builds. That, and only that, is expected here.
    final Object? error = tester.takeException();
    if (error != null) expect('$error', contains('InAppWebViewPlatform'));
    expect(live.length, greaterThanOrEqualTo(2), reason: 'the progress and the address');

    await tester.pumpWidget(const SizedBox());
    expect(live, isEmpty, reason: '${live.length} notifiers were never disposed');
  });
}
