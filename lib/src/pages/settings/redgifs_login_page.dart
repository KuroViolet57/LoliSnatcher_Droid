import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// A WebView-based RedGifs login.
///
/// RedGifs' login endpoint requires a hCaptcha, which can only be solved in a
/// real browser context — so instead of scripting the API we open the site's
/// own login page and let the user sign in. A small JS shim hooks `fetch` and
/// `XMLHttpRequest` to record the `Authorization: Bearer …` header the page
/// sends once it's authenticated; when we see a *user* token (as opposed to the
/// anonymous guest token), we hand it back.
///
/// The captured token is IP- and User-Agent-bound, so this page runs the
/// WebView with the exact same User-Agent the app uses for API calls
/// ([Tools.browserUserAgent]); the handler replays the token with that same
/// User-Agent.
///
/// Pops with the captured token string on success, or null if cancelled.
class RedGifsLoginPage extends StatefulWidget {
  const RedGifsLoginPage({super.key});

  @override
  State<RedGifsLoginPage> createState() => _RedGifsLoginPageState();
}

class _RedGifsLoginPageState extends State<RedGifsLoginPage> {
  static const String _loginUrl = 'https://www.redgifs.com/login';

  // Injected at document start: wrap fetch + XHR to stash any bearer token the
  // page sends. Idempotent (guards against double-injection on SPA nav).
  static const String _hookScript = '''
(function(){
  if (window.__rgHooked) return; window.__rgHooked = true;
  window.__rg_bearer = null;
  function cap(h){
    try{
      if(!h) return;
      var m = /Bearer\\s+([A-Za-z0-9._-]+)/.exec(String(h));
      if(m && m[1]) window.__rg_bearer = m[1];
    }catch(e){}
  }
  var of = window.fetch;
  if(of){
    window.fetch = function(input, init){
      try{
        if(init && init.headers){
          var hs = init.headers;
          if(typeof Headers!=='undefined' && hs instanceof Headers){ cap(hs.get('Authorization')); }
          else if(Array.isArray(hs)){ hs.forEach(function(p){ if(String(p[0]).toLowerCase()==='authorization') cap(p[1]); }); }
          else { for(var k in hs){ if(k.toLowerCase()==='authorization') cap(hs[k]); } }
        }
      }catch(e){}
      return of.apply(this, arguments);
    };
  }
  var os = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(k, v){
    try{ if(String(k).toLowerCase()==='authorization') cap(v); }catch(e){}
    return os.apply(this, arguments);
  };
})();
''';

  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? _controller;
  Timer? _pollTimer;
  bool _done = false;
  int _loadingPercentage = 0;

  late final InAppWebViewSettings _settings = InAppWebViewSettings(
    userAgent: Tools.browserUserAgent,
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    useHybridComposition: true,
    thirdPartyCookiesEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
  );

  late final UnmodifiableListView<UserScript> _userScripts = UnmodifiableListView([
    UserScript(
      source: _hookScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ]);

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _checkForToken());
  }

  Future<void> _checkForToken() async {
    if (_done || _controller == null) return;
    try {
      final result = await _controller!.evaluateJavascript(source: 'window.__rg_bearer');
      final String? token = result?.toString();
      if (token == null || token.isEmpty || token == 'null') return;
      if (_isUserToken(token)) {
        _finish(token);
      }
    } catch (_) {
      // page mid-navigation — try again on the next tick
    }
  }

  // A guest token has `sub: "client/…"` and read-only scope; a signed-in user
  // token identifies the user. Only accept the latter.
  bool _isUserToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final Map<String, dynamic> claims = jsonDecode(utf8.decode(base64.decode(payload)));
      final String sub = claims['sub']?.toString() ?? '';
      final String userId = claims['userId']?.toString() ?? claims['user_id']?.toString() ?? '';
      // Signed-in tokens carry a user subject / userId; guests are `client/…`.
      if (userId.isNotEmpty) return true;
      if (sub.isNotEmpty && !sub.startsWith('client/')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  void _finish(String token) {
    if (_done) return;
    _done = true;
    _pollTimer?.cancel();
    if (mounted) Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to RedGifs'),
        actions: [
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Symbols.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              'Sign in with your RedGifs account below. Once you are logged in, '
              'the app captures your session automatically and this window closes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_loadingPercentage < 100)
            LinearProgressIndicator(value: _loadingPercentage / 100.0),
          Expanded(
            child: Tools.isOnPlatformWithWebviewSupport
                ? InAppWebView(
                    key: webViewKey,
                    initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
                    initialSettings: _settings,
                    initialUserScripts: _userScripts,
                    webViewEnvironment: webViewEnvironment,
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      _startPolling();
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() => _loadingPercentage = progress);
                    },
                    onLoadStop: (controller, url) async {
                      setState(() => _loadingPercentage = 100);
                      await _checkForToken();
                    },
                  )
                : const Center(child: Text('WebView is not supported on this device.')),
          ),
        ],
      ),
    );
  }
}
