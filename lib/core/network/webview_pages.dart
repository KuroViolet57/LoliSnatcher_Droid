import 'package:flutter/widgets.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Builds the in-app webview page (features/webview/ui InAppWebviewView).
/// The named parameters are the ones the lower layers pass.
typedef WebviewPageBuilder =
    Widget Function({
      required String initialUrl,
      String? userAgent,
      String? title,
      String? subtitle,
      void Function(BuildContext context, InAppWebViewController controller, WebUri? url)? onLoadStop,
      void Function(InAppWebViewController controller)? onWebViewReady,
      List<UserScript> initialUserScripts,
      List<String>? restrictMainFrameHosts,
    });

/// How core and the sources open the webview page (the captcha check, the
/// Schale solver) without importing the ui layer. Bound once at start by
/// app/layer_bindings.dart.
abstract final class WebviewPages {
  static WebviewPageBuilder? page;

  /// The bound builder; throws if the app never bound one.
  static WebviewPageBuilder get build => page ?? (throw StateError('WebviewPages.page is not bound (app/layer_bindings.dart)'));
}
