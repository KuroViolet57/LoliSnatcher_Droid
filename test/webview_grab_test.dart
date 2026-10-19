import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/sources/local/webview_browser_handler.dart';

/// The WebView tab's "Grab media" script used to skip srcset, CSS backgrounds
/// and playlists, and a snatch of what it found did not send the page as Referer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('webview_grab');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    BooruHandlerFactory.clearMediaHeaderCache();
  });

  tearDown(() {
    BooruHandlerFactory.clearMediaHeaderCache();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the grab script collects srcset, css backgrounds and playlists', () {
    final String js = WebViewBrowserHandler.collectMediaJs;
    expect(js, contains('srcset'));
    expect(js, contains('backgroundImage'));
    expect(js, contains('m3u8'));
    // The old collectors stay: a small icon is not a post, a video still is.
    expect(js, contains('naturalWidth'));
    expect(js, contains('256'));
    expect(js, contains("'video'"));
  });

  test('a new home url reloads, the same home url does not', () {
    const String template = 'https://example.com/search?q={tags}';
    final String cats = WebViewBrowserHandler.resolveUrl(template, 'cats');
    final String dogs = WebViewBrowserHandler.resolveUrl(template, 'dogs');
    expect(WebViewBrowserHandler.shouldReload(cats, dogs), isTrue);
    expect(WebViewBrowserHandler.shouldReload(cats, cats), isFalse);
    // Same search text, different site template: the tab key does not change,
    // so this is the case the widget must load itself.
    expect(
      WebViewBrowserHandler.shouldReload(
        WebViewBrowserHandler.resolveUrl('https://a.example/search?q={tags}', 'cats'),
        WebViewBrowserHandler.resolveUrl('https://b.example/search?q={tags}', 'cats'),
      ),
      isTrue,
    );
  });

  test('the browser view loads the new home when the widget updates', () {
    final String view = File(
      'lib/features/webview/ui/webview_browser_view.dart',
    ).readAsStringSync();
    expect(view, contains('didUpdateWidget'));
    expect(view, contains('shouldReload'));
    expect(view, contains('WebViewBrowserHandler.collectMediaJs'));
  });

  test('a webview snatch sends the page as Referer, a normal booru does not', () async {
    final Map<String, String> grabbed = await Tools.getFileCustomHeaders(
      Booru('browser', BooruType.WebView, '', 'https://example.com/search?q={tags}', ''),
      item: BooruItem(
        fileURL: 'https://cdn.example.com/a.jpg',
        sampleURL: 'https://cdn.example.com/a.jpg',
        thumbnailURL: 'https://cdn.example.com/a.jpg',
        tagsList: const [],
        postURL: 'https://example.com/watch/1',
      ),
      checkForReferer: true,
    );
    expect(grabbed['Referer'], 'https://example.com/watch/1');

    final Map<String, String> gelbooru = await Tools.getFileCustomHeaders(
      Booru('g', BooruType.Gelbooru, '', 'https://gelbooru.com', ''),
      item: BooruItem(
        fileURL: 'https://img.gelbooru.com/a.jpg',
        sampleURL: 'https://img.gelbooru.com/a.jpg',
        thumbnailURL: 'https://img.gelbooru.com/a.jpg',
        tagsList: const [],
        postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
      ),
      checkForReferer: true,
    );
    expect(gelbooru['Referer'], 'https://gelbooru.com');
  });
}
