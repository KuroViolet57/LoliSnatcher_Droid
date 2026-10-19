import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The WebView2 environment on Windows (created in main); null elsewhere.
/// Every CookieManager and webview in the app uses it.
WebViewEnvironment? webViewEnvironment;

/// Cookies the Windows webview saw, by host (WebView2 does not share its
/// cookie jar with CookieManager there).
Map<String, List<Cookie>> globalWindowsCookies = {};
