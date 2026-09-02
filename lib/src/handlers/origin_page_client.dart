import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Fetches pages of ONE site from inside a WebView kept on that site's
/// origin, for sites whose Cloudflare front refuses the app's plain HTTP
/// client but serves the same phone's WebView.
///
/// hentaipaw.com is the case: the plain request answers 403 "Attention
/// Required — you have been blocked" (WAF, not a challenge, so the captcha
/// window that opens on save cannot pass it), while the source-capture
/// WebView browsed every page. The document loaded here is `robots.txt`,
/// which runs none of the site's code; a same-origin fetch from it carries
/// the engine's own headers and cookies. Modelled on the niyaniya page client.
class OriginPageClient {
  OriginPageClient(this.origin);

  /// `https://host` — every fetch must stay on this origin.
  final String origin;

  static const Duration timeout = Duration(seconds: 15);

  static const String fetchScript = '''
try {
  const r = await fetch(url, { method: method, credentials: 'same-origin' });
  const t = await r.text();
  return { status: r.status, body: t };
} catch (e) {
  return { status: -1, body: String(e) };
}
''';

  HeadlessInAppWebView? _client;
  InAppWebViewController? _controller;
  Future<bool>? _starting;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<bool> _start() {
    if (!supported) return Future.value(false);
    if (_controller != null) return Future.value(true);
    final Future<bool>? starting = _starting;
    if (starting != null) return starting;
    final Completer<bool> done = Completer<bool>();
    _starting = done.future;
    () async {
      await dispose();
      try {
        final HeadlessInAppWebView client = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('$origin/robots.txt')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            blockNetworkImage: true,
            userAgent: SchaleClearanceHandler.solverUserAgent(),
          ),
          onLoadStop: (controller, url) {
            _controller = controller;
            _log('ready at ${url?.host ?? '?'}');
            if (!done.isCompleted) done.complete(true);
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) {
              _log('load error ${error.description}');
              if (!done.isCompleted) done.complete(false);
            }
          },
        );
        _client = client;
        await client.run().timeout(timeout);
        final bool ok = await done.future.timeout(timeout, onTimeout: () {
          _log('timed out after ${timeout.inSeconds}s');
          return false;
        });
        if (!ok) await dispose();
      } catch (e, s) {
        Logger.Inst().log('start failed: $e', 'OriginPageClient', '_start', LogTypes.exception, s: s);
        await dispose();
        if (!done.isCompleted) done.complete(false);
      } finally {
        _starting = null;
      }
    }();
    return done.future;
  }

  Future<void> dispose() async {
    final HeadlessInAppWebView? client = _client;
    _client = null;
    _controller = null;
    try {
      await client?.dispose();
    } catch (_) {}
  }

  /// Fetches [url] (must be on [origin]) from the page. Null when no WebView
  /// is available or the call failed — the caller then uses plain HTTP.
  Future<({int status, String body})?> fetch(String url, {String method = 'GET'}) async {
    if (!url.startsWith(origin)) return null;
    if (!await _start()) return null;
    final InAppWebViewController? controller = _controller;
    if (controller == null) return null;
    try {
      final CallAsyncJavaScriptResult? result = await controller
          .callAsyncJavaScript(functionBody: fetchScript, arguments: {'url': url, 'method': method})
          .timeout(timeout);
      final value = result?.value;
      if (result?.error != null || value is! Map) {
        _log('call failed: ${result?.error ?? value}');
        return null;
      }
      final int status = (value['status'] as num?)?.toInt() ?? -1;
      _log('$method $url → $status');
      if (status < 0) return null;
      return (status: status, body: value['body']?.toString() ?? '');
    } catch (e) {
      _log('$e');
      await dispose();
      return null;
    }
  }

  void _log(String message) =>
      Logger.Inst().log('page client ${Uri.tryParse(origin)?.host ?? origin}: $message', 'OriginPageClient', 'log', LogTypes.booruHandlerInfo);
}
