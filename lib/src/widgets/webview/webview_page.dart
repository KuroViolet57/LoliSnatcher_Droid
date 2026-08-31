import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_navigation_controls.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_navigation_menu.dart';

WebViewEnvironment? webViewEnvironment;
Map<String, List<Cookie>> globalWindowsCookies = {};

/// Hosts a locked-down webview may navigate to.
///
/// Kept as a pure top-level function so the rule can be tested against the
/// exact ad hosts seen in the wild rather than by eye.
bool isWebviewNavigationAllowed(
  String url, {
  required String initialUrl,
  List<String> allowedHosts = const [],
}) {
  final Uri? uri = Uri.tryParse(url);
  final String host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) {
    // about:blank and data: are the page's own scaffolding, not a navigation.
    return uri?.scheme == 'about' || uri?.scheme == 'data';
  }
  // A challenge cannot run without Cloudflare.
  if (host == 'challenges.cloudflare.com' || host.endsWith('.cloudflare.com')) {
    return true;
  }
  final List<String> allowed = [
    ...allowedHosts,
    if (allowedHosts.isEmpty) Uri.tryParse(initialUrl)?.host ?? '',
  ].where((e) => e.isNotEmpty).map((e) => e.toLowerCase()).toList();

  for (final String a in allowed) {
    if (host == a || host.endsWith('.$a')) return true;
  }
  return false;
}

class InAppWebviewView extends StatefulWidget {
  const InAppWebviewView({
    required this.initialUrl,
    this.userAgent,
    this.title,
    this.subtitle,
    this.onLoadStop,
    this.onResourceLoaded,
    this.blockPopupsAndAds = false,
    this.allowedHosts = const [],
    this.onWebViewReady,
    this.initialUserScripts = const [],
    super.key,
  });

  final String initialUrl;
  final String? userAgent;
  final String? title;
  final String? subtitle;
  final void Function(BuildContext context, InAppWebViewController controller, WebUri? url)? onLoadStop;

  /// Every URL the page asks for, as the webview sees it. The source-capture
  /// tool uses this to discover that a site has an API at all — a front end
  /// calling `/api/…` is the only evidence of one from the outside.
  final void Function(String url)? onResourceLoaded;

  /// Refuse pop-ups, new windows, and navigations away from [allowedHosts].
  ///
  /// Some sources monetise with interstitials that replace the page the moment
  /// you touch it. When the page is there to be USED — completing a challenge,
  /// say — letting an ad take it over means the task can never be finished.
  final bool blockPopupsAndAds;

  /// Called once the controller exists, before anything has loaded, so a caller
  /// can register JavaScript handlers the injected scripts will post back to.
  final void Function(InAppWebViewController controller)? onWebViewReady;

  /// Scripts injected at document start, before the page's own bundle runs.
  final List<UserScript> initialUserScripts;

  /// Hosts the page may navigate to when [blockPopupsAndAds] is on. Cloudflare's
  /// challenge host is always allowed, since a challenge cannot run without it.
  /// Empty means "the initial URL's host and its subdomains".
  final List<String> allowedHosts;

  @override
  State<InAppWebviewView> createState() => _InAppWebviewViewState();
}

class _InAppWebviewViewState extends State<InAppWebviewView> {
  final GlobalKey webViewKey = GlobalKey();

  Completer<InAppWebViewController> controller = Completer<InAppWebViewController>();
  late final InAppWebViewSettings settings;

  PullToRefreshController? pullToRefreshController;
  int loadingPercentage = 0;
  bool hideSubtitle = false;

  @override
  void initState() {
    super.initState();

    settings = InAppWebViewSettings(
      userAgent: widget.userAgent ?? Tools.browserUserAgent,
      mediaPlaybackRequiresUserGesture: false,
      javaScriptEnabled: true,
      cacheEnabled: false,
      useHybridComposition: true,
      allowsInlineMediaPlayback: true,
      useShouldInterceptAjaxRequest: false,
      thirdPartyCookiesEnabled: true,
      javaScriptCanOpenWindowsAutomatically: !widget.blockPopupsAndAds,
      supportMultipleWindows: !widget.blockPopupsAndAds,
      useShouldOverrideUrlLoading: widget.blockPopupsAndAds,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: Colors.blue,
        ),
        onRefresh: () async {
          if (Platform.isAndroid) {
            await controller.future.then((controller) {
              controller.reload();
            });
          } else if (Platform.isIOS) {
            await controller.future.then((controller) async {
              await controller.loadUrl(urlRequest: URLRequest(url: await controller.getUrl()));
            });
          }
        },
      );
    }
  }

  bool isNavigationAllowed(String url) => isWebviewNavigationAllowed(
    url,
    initialUrl: widget.initialUrl,
    allowedHosts: widget.allowedHosts,
  );

  Future<void> saveCookiesOnWidnows(
    InAppWebViewController controller,
    WebUri? uri,
  ) async {
    // dirty workaround to keep cookies in memory outside of webview pages, to allow getting them in image/auth logic
    // probably should redo cookie logic to store them independently from webview implementation
    if (Platform.isWindows && uri != null) {
      final cookies = await CookieManager.instance(webViewEnvironment: webViewEnvironment).getCookies(
        url: uri,
        webViewController: controller,
      );

      if (globalWindowsCookies[uri.host] == null) {
        globalWindowsCookies[uri.host] = [];
      } else {
        globalWindowsCookies[uri.host]!.clear();
      }

      globalWindowsCookies[uri.host]!.addAll(cookies);

      setState(() {});
    }
  }

  @override
  void dispose() {
    pullToRefreshController?.dispose();
    controller.future.then((controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? context.loc.webview.title),
        actions: [
          WebviewNavigationControls(controller: controller),
          WebviewNavigationMenu(initialUrl: widget.initialUrl, controller: controller),
        ],
      ),
      body: Stack(
        children: [
          if (Tools.isOnPlatformWithWebviewSupport)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: settings,
              pullToRefreshController: pullToRefreshController,
              webViewEnvironment: webViewEnvironment,
              initialUserScripts: UnmodifiableListView(widget.initialUserScripts),
              onWebViewCreated: (webViewController) {
                controller.complete(webViewController);
                widget.onWebViewReady?.call(webViewController);
                // webViewController.clearCache();
              },
              onCreateWindow: widget.blockPopupsAndAds
                  ? (controller, createWindowAction) async {
                      // Refuse it outright: returning false tells the webview
                      // not to open the window at all.
                      return false;
                    }
                  : null,
              shouldOverrideUrlLoading: widget.blockPopupsAndAds
                  ? (controller, action) async {
                      final String? url = action.request.url?.toString();
                      if (url == null || url.isEmpty) {
                        return NavigationActionPolicy.CANCEL;
                      }
                      return isNavigationAllowed(url)
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    }
                  : null,
              onLoadStart: (controller, url) {
                setState(() {
                  loadingPercentage = 0;
                });
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  loadingPercentage = progress;
                });
              },
              onLoadResource: (controller, res) {
                widget.onResourceLoaded?.call(res.url?.toString() ?? '');
                setState(() {
                  loadingPercentage = 100;
                });
              },
              onLoadStop: (controller, url) {
                setState(() {
                  loadingPercentage = 100;
                  saveCookiesOnWidnows(controller, url);
                });
                widget.onLoadStop?.call(context, controller, url);
              },
              onUpdateVisitedHistory: (controller, url, isReload) {
                setState(() {
                  loadingPercentage = 0;
                });
              },
            )
          else
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.8,
              child: Center(
                child: Text(context.loc.webview.notSupportedOnDevice),
              ),
            ),
          //
          if (loadingPercentage < 100)
            LinearProgressIndicator(
              value: loadingPercentage / 100.0,
            ),
          //
          if (kDebugMode && !hideSubtitle)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              child: Container(
                width: MediaQuery.sizeOf(context).width - 16,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      spreadRadius: 0,
                      blurRadius: 4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SizedBox(
                        height: 100,
                        child: ListView(
                          children: [
                            Text(
                              globalWindowsCookies[WebUri(widget.initialUrl).host]
                                      ?.map((e) => '${e.name}\n->\n${e.value}')
                                      .join('\n\n') ??
                                  '',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Symbols.close_rounded),
                      onPressed: () {
                        setState(() {
                          hideSubtitle = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (widget.subtitle != null && !hideSubtitle)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom,
              child: Container(
                width: MediaQuery.sizeOf(context).width - 16,
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      spreadRadius: 0,
                      blurRadius: 4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: .min,
                  mainAxisAlignment: .start,
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        widget.subtitle ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Symbols.close_rounded),
                      onPressed: () {
                        setState(() {
                          hideSubtitle = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          //
          if (widget.subtitle != null && hideSubtitle)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              right: 20,
              child: IconButton.filled(
                icon: const Icon(Symbols.info_rounded),
                onPressed: () {
                  setState(() {
                    hideSubtitle = false;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}
