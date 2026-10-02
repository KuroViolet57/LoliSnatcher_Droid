import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The e-hentai forum login in a WebView, the way JHenTai and EhViewer do
/// it: the person logs in (captcha included), the forum sets
/// `ipb_member_id` and `ipb_pass_hash` for `.e-hentai.org`, and this page
/// copies the two into [EHentaiSessionHandler] and removes them from the
/// shared cookie jar (see that class for why), then asks exhentai.org for
/// its `igneous`. Pops with `(ok, message)`.
class EHentaiLoginPage extends StatefulWidget {
  const EHentaiLoginPage({super.key});

  static const String loginUrl = 'https://forums.e-hentai.org/index.php?act=Login&CODE=00';
  static const List<String> cookieOrigins = ['https://e-hentai.org/', 'https://forums.e-hentai.org/'];

  @override
  State<EHentaiLoginPage> createState() => _EHentaiLoginPageState();

}

class _EHentaiLoginPageState extends State<EHentaiLoginPage> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _done = false;
  bool _finishing = false;
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
    if (_done || _finishing) return;
    final Map<String, String> pairs = await EHentaiSessionHandler.instance.readJar();
    final parsed = EHentaiSessionHandler.fromCookiePairs(pairs);
    if (parsed.memberId == null || parsed.passHash == null) return;
    _finishing = true;
    _poll?.cancel();
    final EHentaiSessionHandler session = EHentaiSessionHandler.instance;
    session.store(memberId: parsed.memberId!, passHash: parsed.passHash!, igneous: parsed.igneous);
    // The igneous probe is a Dio call, and the client writes every
    // Set-Cookie into the shared jar — so scrub AFTER it, not before.
    final (bool ok, String message) = await session.fetchIgneous();
    await session.scrubJar();
    _done = true;
    if (!mounted) return;
    Navigator.of(context).pop((true, ok ? 'Logged in. $message' : 'Logged in to e-hentai. $message'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log in to e-hentai'),
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
              'Sign in with your forum account. The app keeps only the two session cookies, in its own file, '
              'and never sends them to image servers. Reading exhentai needs an account with access.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(EHentaiLoginPage.loginUrl)),
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
