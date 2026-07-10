import 'dart:async';

import 'package:lolisnatcher/src/handlers/booru_handler.dart';

/// Handler backing the WebView "browser booru" type.
///
/// This booru type doesn't scrape anything — the grid UI is replaced by an
/// embedded browser rendering the site itself (see WebViewBrowserView), so
/// sites that are impossible/impractical to parse can still live in a tab.
/// The handler exists only so the tab/search plumbing has something inert
/// to talk to.
class WebViewBrowserHandler extends BooruHandler {
  WebViewBrowserHandler(super.booru, super.limit);

  @override
  bool get hasTagSuggestions => false;

  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  String validateTags(String tags) => tags;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    // Nothing to fetch — the webview renders the site directly.
    locked = true;
    return fetched;
  }

  /// Resolves the URL the embedded browser should load for [tags].
  ///
  /// If the booru's base URL contains a `{tags}` (or `%s`) placeholder, the
  /// tab's search text is URL-encoded into it — so search-by-tags works on
  /// any site whose search is expressible as a URL template. Without a
  /// placeholder the base URL is loaded as-is and the user just browses.
  static String resolveUrl(String baseUrl, String tags) {
    final String encoded = Uri.encodeComponent(tags.trim());
    if (baseUrl.contains('{tags}')) {
      return baseUrl.replaceAll('{tags}', encoded);
    }
    if (baseUrl.contains('%s')) {
      return baseUrl.replaceAll('%s', encoded);
    }
    return baseUrl;
  }
}
