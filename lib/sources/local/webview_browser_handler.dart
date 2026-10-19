import 'dart:async';

import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// Handler backing the WebView "browser booru" type.
///
/// This booru type doesn't scrape anything — the grid UI is replaced by an
/// embedded browser rendering the site itself (see WebViewBrowserView), so
/// sites that are impossible/impractical to parse can still live in a tab.
/// The handler exists only so the tab/search plumbing has something inert
/// to talk to.
class WebViewBrowserHandler extends BooruHandler {
  WebViewBrowserHandler(super.booru, super.limit);

  // Reads neither field (audited): the fields are hidden on the edit page.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


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

  /// True when the embedded browser is showing a different search URL than the
  /// one it loaded. The tab key only contains the search text, so a new site
  /// template with the same text has to be loaded by the view itself.
  static bool shouldReload(String previousHome, String nextHome) => previousHome != nextHome;

  /// Injected into the page by "Grab media". Walks the DOM for real media:
  /// video and source srcs, large images, srcset, CSS backgrounds, and file
  /// links including playlists.
  static const String collectMediaJs = r'''
    (function () {
      var out = {};
      function add(u, kind) {
        if (!u) return;
        try { u = new URL(u, document.baseURI).href; } catch (e) { return; }
        if (u.indexOf('http') !== 0) return;
        if (u.indexOf('data:') === 0) return;
        if (!out[u]) out[u] = kind;
      }
      function addSrcset(srcset, kind, onlyLarge) {
        if (!srcset) return;
        String(srcset).split(',').forEach(function (part) {
          var bits = part.trim().split(/\s+/);
          var u = bits[0];
          if (!u) return;
          if (onlyLarge && bits[1] && /w$/i.test(bits[1])) {
            var w = parseInt(bits[1], 10) || 0;
            if (w > 0 && w < 256) return;
          }
          add(u, kind);
        });
      }
      function addCssUrls(css, kind) {
        if (!css || css === 'none') return;
        var re = /url\(\s*(['"]?)(.*?)\1\s*\)/g;
        var m;
        while ((m = re.exec(css))) add(m[2], kind);
      }
      document.querySelectorAll('video').forEach(function (v) {
        add(v.currentSrc || v.src, 'video');
        v.querySelectorAll('source').forEach(function (s) {
          add(s.src, 'video');
          addSrcset(s.srcset, 'video', false);
        });
      });
      document.querySelectorAll('source').forEach(function (s) {
        add(s.src, 'video');
        addSrcset(s.srcset, 'video', false);
      });
      document.querySelectorAll('img').forEach(function (i) {
        if ((i.naturalWidth || 0) >= 256 || (i.naturalHeight || 0) >= 256) add(i.currentSrc || i.src, 'image');
        addSrcset(i.srcset, 'image', true);
      });
      document.querySelectorAll('div, a, span, figure, li, section').forEach(function (el) {
        addCssUrls(el.style && el.style.backgroundImage, 'image');
        try { addCssUrls(getComputedStyle(el).backgroundImage, 'image'); } catch (e) {}
      });
      document.querySelectorAll('a').forEach(function (a) {
        var h = a.href || '';
        if (/\.(mp4|webm|m4v|mov|gif|jpg|jpeg|png|webp|m3u8)(\?|#|$)/i.test(h)) add(h, 'link');
      });
      return JSON.stringify(Object.keys(out).map(function (u) { return { url: u, kind: out[u] }; }));
    })();
  ''';
}
