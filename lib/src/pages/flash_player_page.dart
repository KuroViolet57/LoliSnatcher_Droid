import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Plays a Flash movie (.swf) in the app (r42b) through Ruffle, the Flash
/// emulator FurAffinity itself embeds: a small page in a WebView loads
/// Ruffle's script and hands it the movie's address. FurAffinity serves both
/// with `access-control-allow-origin: *`, so the page can fetch them; the
/// page's base is the site so the movie is asked for as the site asks for it.
class FlashPlayerPage extends StatefulWidget {
  const FlashPlayerPage({required this.swfUrl, this.title, this.ruffleUrl = defaultRuffle, super.key});

  /// The Ruffle FurAffinity's Flash pages load (checked 2026-09-15).
  static const String defaultRuffle = 'https://d.furaffinity.net/media/ruffle-0.2.0/ruffle.js';
  static const String baseUrl = 'https://www.furaffinity.net/';

  final String swfUrl;
  final String? title;
  final String ruffleUrl;

  static bool isFlashUrl(String url) => (Uri.tryParse(url)?.path ?? url).toLowerCase().endsWith('.swf');

  /// [item] is a Flash submission: its file is a movie, or its listing said so.
  static bool isFlash(BooruItem item) =>
      item.fileExt?.toLowerCase() == 'swf' || isFlashUrl(item.fileURL) || item.tagsList.any((t) => t.fullString == 'type:flash');

  /// The player page: Ruffle, then the movie at the page's full size.
  static String html({required String swfUrl, required String ruffleUrl}) {
    final String movie = jsonEncode(swfUrl).replaceAll('</', r'<\/');
    final String script = const HtmlEscape(HtmlEscapeMode.attribute).convert(ruffleUrl);
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{width:100%;height:100%}#error{color:#eee;font-family:sans-serif;padding:16px}</style>
<script>window.RufflePlayer = window.RufflePlayer || {}; window.RufflePlayer.config = {autoplay: "on", unmuteOverlay: "hidden", letterbox: "on"};</script>
<script src="$script"></script>
</head>
<body>
<div id="player"></div>
<script>
window.addEventListener("load", function () {
  try {
    var ruffle = window.RufflePlayer.newest();
    var player = ruffle.createPlayer();
    player.style.width = "100%";
    player.style.height = "100%";
    document.getElementById("player").appendChild(player);
    player.load({url: $movie});
  } catch (e) {
    document.body.innerHTML = '<div id="error">Ruffle could not start: ' + e + '</div>';
  }
});
</script>
</body>
</html>
''';
  }

  /// Opens [item]'s movie, reading its submission page first when the file
  /// is not known yet.
  static Future<void> openFor(BuildContext context, BooruHandler handler, BooruItem item) async {
    if (!isFlashUrl(item.fileURL) && handler.hasLoadItemSupport) {
      await handler.loadItem(item: item);
    }
    if (!context.mounted) return;
    if (!isFlashUrl(item.fileURL)) {
      FlashElements.showSnackbar(context: context, title: const Text('The Flash movie is not on the page'), content: const Text('It may need you to log in.'));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashPlayerPage(swfUrl: item.fileURL, title: item.description),
      ),
    );
  }

  @override
  State<FlashPlayerPage> createState() => _FlashPlayerPageState();
}

class _FlashPlayerPageState extends State<FlashPlayerPage> {
  InAppWebViewController? _controller;
  int _progress = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title?.isNotEmpty == true ? widget.title! : 'Flash', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Restart', icon: const Icon(Symbols.restart_alt_rounded), onPressed: () => _controller?.reload()),
        ],
      ),
      body: !Tools.isOnPlatformWithWebviewSupport
          ? const Center(
              child: Text('Flash needs a WebView, which this device does not have.', style: TextStyle(color: Colors.white)),
            )
          : Column(
              children: [
                if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
                Expanded(
                  child: InAppWebView(
                    initialData: InAppWebViewInitialData(
                      data: FlashPlayerPage.html(swfUrl: widget.swfUrl, ruffleUrl: widget.ruffleUrl),
                      baseUrl: WebUri(FlashPlayerPage.baseUrl),
                      mimeType: 'text/html',
                      encoding: 'utf-8',
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useHybridComposition: true,
                      userAgent: Tools.browserUserAgent,
                      supportZoom: false,
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
