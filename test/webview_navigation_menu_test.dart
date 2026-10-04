import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/webview/ui/webview_navigation_menu.dart';

class _FakeCookieManager extends PlatformCookieManager {
  _FakeCookieManager(super.params) : super.implementation();
}

/// Just enough of a webview platform for the menu's CookieManager field.
class _FakeWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformCookieManager createPlatformCookieManager(PlatformCookieManagerCreationParams params) => _FakeCookieManager(params);
}

/// 1.0 M2: the webview page's menu is built before there is a webview (a
/// FurAffinity page waiting for its session, a platform without webviews), and
/// every item force-unwrapped the controller: picking one threw "Null check
/// operator used on a null value". Without a webview the items do nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => InAppWebViewPlatform.instance = _FakeWebViewPlatform());

  testWidgets('picking a menu item before the webview exists does not throw', (tester) async {
    final Completer<InAppWebViewController> controller = Completer<InAppWebViewController>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [WebviewNavigationMenu(initialUrl: 'https://www.furaffinity.net/', controller: controller)],
            ),
          ),
        ),
      ),
    );

    for (final String Function(Translations) label in [
      (t) => t.webview.navigation.navigateTo(url: 'https://www.furaffinity.net/'),
      (t) => t.webview.navigation.copyUrl,
    ]) {
      await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label(loc)));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
