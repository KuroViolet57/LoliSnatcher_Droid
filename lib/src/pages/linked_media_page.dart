import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The linked media player (r49), styled like the Flash player: a black full
/// screen with Reload and Open in browser. A video or animation file linked
/// from a post plays in it; any other linked page opens in it.
class LinkedMediaPage extends StatefulWidget {
  const LinkedMediaPage({required this.media, this.title, super.key});

  final LinkedMedia media;
  final String? title;

  /// A page that shows one file: a video element, or an image for a GIF.
  static String mediaHtml(String url, {bool image = false}) {
    final String src = const HtmlEscape(HtmlEscapeMode.attribute).convert(url);
    final String element = image ? '<img src="$src">' : '<video src="$src" controls autoplay playsinline loop></video>';
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;display:flex;align-items:center;justify-content:center}video,img{max-width:100%;max-height:100%}</style>
</head>
<body>$element</body>
</html>
''';
  }

  @override
  State<LinkedMediaPage> createState() => _LinkedMediaPageState();
}

class _LinkedMediaPageState extends State<LinkedMediaPage> {
  InAppWebViewController? _controller;
  int _progress = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LinkedMedia media = widget.media;
    final bool isFile = media.kind == LinkedMediaKind.media;
    final Uri? uri = Uri.tryParse(media.url);
    final String origin = uri == null || uri.host.isEmpty ? 'https://localhost/' : '${uri.scheme}://${uri.host}/';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title?.isNotEmpty == true ? widget.title! : media.host, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('linked-media-reload'),
            tooltip: 'Reload',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            key: const ValueKey('linked-media-browser'),
            tooltip: 'Open in browser',
            icon: const Icon(Symbols.open_in_browser_rounded),
            onPressed: () => launchUrlString(media.url, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: !Tools.isOnPlatformWithWebviewSupport
          ? const Center(child: Text('This needs a WebView, which this device does not have.', style: TextStyle(color: Colors.white)))
          : Column(
              children: [
                if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
                Expanded(
                  child: InAppWebView(
                    initialData: isFile
                        ? InAppWebViewInitialData(
                            data: LinkedMediaPage.mediaHtml(media.url, image: media.isImage),
                            baseUrl: WebUri(origin),
                            mimeType: 'text/html',
                            encoding: 'utf-8',
                          )
                        : null,
                    initialUrlRequest: isFile ? null : URLRequest(url: WebUri(media.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      useHybridComposition: true,
                      userAgent: Tools.browserUserAgent,
                      javaScriptCanOpenWindowsAutomatically: false,
                      supportMultipleWindows: false,
                    ),
                    onWebViewCreated: (controller) => _controller = controller,
                    onProgressChanged: (controller, progress) {
                      if (mounted) setState(() => _progress = progress);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
