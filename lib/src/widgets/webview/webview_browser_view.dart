import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/boorus/webview_browser_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Embedded browser that replaces the thumbnail grid for WebView-type boorus.
///
/// Lets any media site live in a tab even when it can't be scraped: the tab's
/// search text is templated into the booru URL ({tags} / %s placeholder), the
/// cookie store is shared with the captcha webview (so Cloudflare clearances
/// carry over), and file downloads started in the page are routed into the
/// app's own snatcher queue.
class WebViewBrowserView extends StatefulWidget {
  const WebViewBrowserView({required this.tab, super.key});

  final SearchTab tab;

  @override
  State<WebViewBrowserView> createState() => _WebViewBrowserViewState();
}

class _WebViewBrowserViewState extends State<WebViewBrowserView> {
  InAppWebViewController? controller;
  final ValueNotifier<int> progress = ValueNotifier(0);
  final ValueNotifier<String> currentUrl = ValueNotifier('');

  String get homeUrl => WebViewBrowserHandler.resolveUrl(
        widget.tab.selectedBooru.value.baseURL ?? '',
        widget.tab.tags,
      );

  late final InAppWebViewSettings settings = InAppWebViewSettings(
    userAgent: Tools.browserUserAgent,
    mediaPlaybackRequiresUserGesture: true,
    javaScriptEnabled: true,
    cacheEnabled: true,
    useHybridComposition: true,
    allowsInlineMediaPlayback: true,
    thirdPartyCookiesEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    useOnDownloadStart: true,
  );

  Future<void> _goBack() async {
    if (await controller?.canGoBack() ?? false) {
      await controller?.goBack();
    }
  }

  Future<void> _goForward() async {
    if (await controller?.canGoForward() ?? false) {
      await controller?.goForward();
    }
  }

  void _snatchUrls(List<String> urls) {
    if (urls.isEmpty) return;
    final booru = widget.tab.selectedBooru.value;
    final items = urls
        .map(
          (url) => BooruItem(
            fileURL: url,
            sampleURL: url,
            thumbnailURL: url,
            tagsList: const [],
            postURL: currentUrl.value.isNotEmpty ? currentUrl.value : url,
          ),
        )
        .toList();
    SnatchHandler.instance.queue(items, booru, 0, false);
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Sent ${items.length} to snatcher', style: const TextStyle(fontSize: 18)),
      leadingIcon: Icons.download,
      sideColor: Colors.green,
    );
  }

  void _snatchUrl(String url) => _snatchUrls([url]);

  // Injects JS that walks the DOM for real media: <video>/<source> srcs, large
  // <img> srcs, and background-image urls. Lets the user snatch media off sites
  // the app can't scrape via an API/handler.
  static const String _collectMediaJs = r'''
    (function () {
      var out = {};
      function add(u, kind) {
        if (!u) return;
        try { u = new URL(u, document.baseURI).href; } catch (e) { return; }
        if (u.indexOf('http') !== 0) return;
        if (u.indexOf('data:') === 0) return;
        if (!out[u]) out[u] = kind;
      }
      document.querySelectorAll('video').forEach(function (v) {
        add(v.currentSrc || v.src, 'video');
        v.querySelectorAll('source').forEach(function (s) { add(s.src, 'video'); });
      });
      document.querySelectorAll('source').forEach(function (s) { add(s.src, 'video'); });
      document.querySelectorAll('img').forEach(function (i) {
        if ((i.naturalWidth || 0) >= 256 || (i.naturalHeight || 0) >= 256) add(i.currentSrc || i.src, 'image');
      });
      document.querySelectorAll('a').forEach(function (a) {
        var h = a.href || '';
        if (/\.(mp4|webm|m4v|mov|gif|jpg|jpeg|png|webp)(\?|$)/i.test(h)) add(h, 'link');
      });
      return JSON.stringify(Object.keys(out).map(function (u) { return { url: u, kind: out[u] }; }));
    })();
  ''';

  Future<void> _grabMedia() async {
    List<Map<String, String>> media = [];
    try {
      final result = await controller?.evaluateJavascript(source: _collectMediaJs);
      final decoded = result is String ? (result.isEmpty ? [] : jsonDecode(result)) : (result ?? []);
      media = (decoded as List)
          .map((e) => {'url': e['url'].toString(), 'kind': e['kind'].toString()})
          .toList();
    } catch (_) {}

    if (!mounted) return;
    if (media.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: const Text('No media found on this page', style: TextStyle(fontSize: 16)),
        leadingIcon: Icons.search_off,
        sideColor: Colors.orange,
      );
      return;
    }

    final selected = <String>{...media.map((m) => m['url']!)};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text('Found ${media.length} media', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          FilledButton.icon(
                            icon: const Icon(Icons.download, size: 18),
                            label: Text('Snatch ${selected.length}'),
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    _snatchUrls(selected.toList());
                                  },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: media.length,
                        itemBuilder: (context, i) {
                          final m = media[i];
                          final url = m['url']!;
                          final isVideo = m['kind'] == 'video';
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(url),
                            secondary: Icon(isVideo ? Icons.movie : Icons.image, size: 20),
                            title: Text(
                              Uri.tryParse(url)?.pathSegments.lastOrNull ?? url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                            onChanged: (v) => setSheet(() {
                              if (v == true) {
                                selected.add(url);
                              } else {
                                selected.remove(url);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // slim toolbar: nav controls + current host + external open
        SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: _goBack,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _goForward,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => controller?.reload(),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Home (search url)',
                icon: const Icon(Icons.home_outlined, size: 20),
                onPressed: () => controller?.loadUrl(urlRequest: URLRequest(url: WebUri(homeUrl))),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: currentUrl,
                  builder: (_, url, _) => Text(
                    Uri.tryParse(url)?.host ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Grab media on this page',
                icon: const Icon(Icons.download_for_offline_outlined, size: 20),
                onPressed: _grabMedia,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Open in external browser',
                icon: const Icon(Icons.open_in_browser, size: 20),
                onPressed: () {
                  final url = currentUrl.value.isNotEmpty ? currentUrl.value : homeUrl;
                  launchUrlString(url, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: progress,
          builder: (_, value, _) => value >= 100
              ? const SizedBox(height: 2)
              : LinearProgressIndicator(value: value / 100, minHeight: 2),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(homeUrl)),
            initialSettings: settings,
            onWebViewCreated: (c) => controller = c,
            onLoadStop: (c, url) async {
              if (url != null) currentUrl.value = url.toString();
              progress.value = 100;
            },
            onProgressChanged: (c, p) => progress.value = p,
            onUpdateVisitedHistory: (c, url, _) {
              if (url != null) currentUrl.value = url.toString();
            },
            onDownloadStarting: (c, request) async {
              _snatchUrl(request.url.toString());
              return null;
            },
          ),
        ),
      ],
    );
  }
}
