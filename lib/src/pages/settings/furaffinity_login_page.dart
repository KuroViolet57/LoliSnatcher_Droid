import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The FurAffinity login in a WebView (r40): the person logs in, Cloudflare's
/// check included; when the site has set its `a` and `b` session cookies they
/// are copied into [FurAffinitySessionHandler] and stay in the shared jar
/// (r41), so the site's pages in any webview are logged in. Pops with `(ok, message)`.
class FurAffinityLoginPage extends StatefulWidget {
  const FurAffinityLoginPage({super.key});

  static const String loginUrl = 'https://www.furaffinity.net/login/';

  @override
  State<FurAffinityLoginPage> createState() => _FurAffinityLoginPageState();
}

class _FurAffinityLoginPageState extends State<FurAffinityLoginPage> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _done = false;
  int _progress = 0;

  late final InAppWebViewSettings _settings = InAppWebViewSettings(
    userAgent: Tools.browserUserAgent,
    javaScriptEnabled: true,
    useHybridComposition: true,
    thirdPartyCookiesEnabled: true,
    cacheEnabled: false,
  );

  @override
  void dispose() {
    _poll?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _checkCookies());
  }

  Future<void> _checkCookies() async {
    if (_done) return;
    final FurAffinitySessionHandler session = FurAffinitySessionHandler.instance;
    final parsed = FurAffinitySessionHandler.fromCookiePairs(await session.readJar());
    if (parsed.a == null || parsed.b == null) return;
    _done = true;
    _poll?.cancel();
    session.store(a: parsed.a!, b: parsed.b!);
    if (!mounted) return;
    Navigator.of(context).pop((true, 'Logged in to FurAffinity.'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log in to FurAffinity'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              'Sign in with your FurAffinity account. The app keeps only the two session cookies, in its own file, and '
              'sends them to furaffinity.net only. Mature and adult submissions also need them enabled in your account settings.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(FurAffinityLoginPage.loginUrl)),
              initialSettings: _settings,
              onWebViewCreated: (controller) {
                _controller = controller;
                _startPolling();
              },
              onProgressChanged: (controller, progress) {
                if (mounted) setState(() => _progress = progress);
              },
              onLoadStop: (controller, url) => _checkCookies(),
            ),
          ),
        ],
      ),
    );
  }
}
