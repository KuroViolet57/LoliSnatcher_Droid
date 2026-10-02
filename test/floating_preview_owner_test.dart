import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/floating_preview_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r77: on 19 Sep the viewer closed while a tag's preview icon was still
/// waiting to react, and the preview window then opened on whatever page was
/// on top - the main feed. A preview now belongs to the page the user tapped
/// on; if that page is gone, nothing opens. Back closes a preview window
/// before anything else on its page; code pops (the back arrow, swipe-down)
/// still close the page at once and take its window with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  late FloatingPreviewHandler previews;
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();

  setUp(() {
    SettingsHandler.register();
    InterestsHandler.register();
    NavigationHandler.register();
    if (GetIt.instance.isRegistered<FloatingPreviewHandler>()) FloatingPreviewHandler.unregister();
    previews = FloatingPreviewHandler.register();
  });

  Future<Route<dynamic>> pushPage(WidgetTester tester, {bool canPop = true, void Function()? onBlockedBack}) async {
    late Route<dynamic> route;
    unawaited(nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) {
          route = ModalRoute.of(context)!;
          return PopScope(
            canPop: canPop,
            onPopInvokedWithResult: (bool didPop, _) {
              // Like the viewer's own Back (it closes the info sheet): it
              // stands down while a preview window is shown on this page.
              if (!didPop && !FloatingPreviewHandler.instance.hasWindowFor(route)) onBlockedBack?.call();
            },
            child: const Scaffold(body: Text('page')),
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    return route;
  }

  // Opening a booru tag's preview records the interest, which saves on a
  // 10 s timer; the tests let it run.
  Future<void> settleInterests(WidgetTester tester) => tester.pump(const Duration(seconds: 11));

  Future<void> app(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [previews.routeObserver],
        home: const Scaffold(body: Text('feed')),
      ),
    );
  }

  testWidgets('a preview opened for a page that is still up belongs to that page', (tester) async {
    await app(tester);
    final Route<dynamic> viewer = await pushPage(tester);
    previews.open(tag: 'red_hair', booru: e621, owner: viewer);
    expect(previews.entries, hasLength(1));
    expect(previews.entries.single.ownerRoute, same(viewer));
    expect(previews.entries.single.tag, 'red_hair');
    expect(previews.entries.single.booru, same(e621));
    await settleInterests(tester);
  });

  testWidgets('a preview whose page already closed opens nothing - it no longer lands on the feed', (tester) async {
    await app(tester);
    final Route<dynamic> viewer = await pushPage(tester);
    nav.currentState!.pop();
    await tester.pump();
    previews.open(tag: 'red_hair', booru: e621, owner: viewer);
    expect(previews.entries, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('a preview opened from a dialog belongs to the page under the dialog', (tester) async {
    await app(tester);
    final Route<dynamic> viewer = await pushPage(tester);
    late Route<dynamic> dialog;
    unawaited(showDialog<void>(
      context: nav.currentContext!,
      builder: (context) {
        dialog = ModalRoute.of(context)!;
        return const AlertDialog(content: Text('tag menu'));
      },
    ));
    await tester.pumpAndSettle();
    previews.open(tag: 'red_hair', booru: e621, owner: dialog);
    expect(previews.entries.single.ownerRoute, same(viewer));
    await settleInterests(tester);
  });

  testWidgets('Back closes the preview first and nothing else; the next Back reaches the page', (tester) async {
    await app(tester);
    int sheetClosed = 0;
    final Route<dynamic> viewer = await pushPage(tester, canPop: false, onBlockedBack: () => sheetClosed++);
    previews.open(tag: 'red_hair', booru: e621, owner: viewer);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(previews.entries, isEmpty, reason: 'the window closed');
    expect(sheetClosed, 0, reason: 'the page stood down for this Back');
    expect(viewer.isActive, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sheetClosed, 1, reason: "the next Back is the page's own again");
    await settleInterests(tester);
  });

  testWidgets('with no window left, Back pops the page as before', (tester) async {
    await app(tester);
    final Route<dynamic> viewer = await pushPage(tester);
    previews.open(tag: 'red_hair', booru: e621, owner: viewer);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(viewer.isActive, isTrue, reason: 'first Back: the window');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(viewer.isActive, isFalse, reason: 'second Back: the page');
    await settleInterests(tester);
  });

  testWidgets('the back arrow (a code pop) still closes the page at once and takes its preview with it', (tester) async {
    await app(tester);
    final Route<dynamic> viewer = await pushPage(tester);
    previews.open(tag: 'red_hair', booru: e621, owner: viewer);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(viewer.isActive, isFalse);
    expect(previews.entries, isEmpty);
    await settleInterests(tester);
  });
}
