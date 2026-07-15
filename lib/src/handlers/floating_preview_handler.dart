import 'package:flutter/material.dart';

import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/floating_tag_preview_window.dart';

/// One floating tag-preview window.
///
/// Every window is owned by the [ownerRoute] (the page route that was on top
/// when it was opened). The window is only shown while its owner is the
/// top-most page route: pushing another page (e.g. opening a result in the
/// viewer) hides it — state preserved — and popping back reveals it again.
/// When the owner route itself is popped the window is dropped with it.
class FloatingPreviewEntry {
  FloatingPreviewEntry({
    required this.tag,
    required this.booru,
    required this.ownerRoute,
  }) : id = const Uuid().v4();

  final String id;
  final String tag;
  final Booru booru;
  final Route<dynamic>? ownerRoute;
}

/// Manages the floating tag-preview windows (Boorusama-style).
///
/// Windows live in the navigator's root [Overlay], above every route, so a
/// preview keeps floating over the post page / drawer / dialogs that spawned
/// it. Ties each window to a page route via [routeObserver] — see
/// [FloatingPreviewEntry] for the exact visibility semantics.
class FloatingPreviewHandler extends ChangeNotifier {
  static FloatingPreviewHandler get instance => GetIt.instance<FloatingPreviewHandler>();

  static FloatingPreviewHandler register() {
    if (!GetIt.instance.isRegistered<FloatingPreviewHandler>()) {
      GetIt.instance.registerSingleton(FloatingPreviewHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<FloatingPreviewHandler>();

  late final FloatingPreviewRouteObserver routeObserver = FloatingPreviewRouteObserver(this);

  final List<FloatingPreviewEntry> entries = [];

  // Stack of *page* routes only (dialogs/bottom sheets are popup routes and
  // don't affect window ownership/visibility).
  final List<Route<dynamic>> _pageRoutes = [];

  OverlayEntry? _overlayEntry;

  Route<dynamic>? get topPageRoute => _pageRoutes.isNotEmpty ? _pageRoutes.last : null;

  bool isEntryVisible(FloatingPreviewEntry entry) => entry.ownerRoute == topPageRoute;

  /// Opens (or replaces, when the current top route already has one) the
  /// floating preview window for [tag] on [booru].
  void open({
    required String tag,
    required Booru booru,
  }) {
    // One window per owner route — opening a new preview on the same page
    // replaces the previous window instead of stacking an unbounded pile.
    entries.removeWhere((e) => e.ownerRoute == topPageRoute);
    entries.add(
      FloatingPreviewEntry(
        tag: tag,
        booru: booru,
        ownerRoute: topPageRoute,
      ),
    );
    _ensureOverlay();
    InterestsHandler.instance.onTagPreviewOpened(tag);
    notifyListeners();
  }

  void close(FloatingPreviewEntry entry) {
    entries.remove(entry);
    notifyListeners();
    _maybeRemoveOverlay();
  }

  void closeAll() {
    entries.clear();
    notifyListeners();
    _maybeRemoveOverlay();
  }

  void _ensureOverlay() {
    if (_overlayEntry != null) {
      return;
    }
    final OverlayState? overlay = NavigationHandler.instance.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (_) => const FloatingPreviewOverlayStack(),
    );
    overlay.insert(_overlayEntry!);
  }

  void _maybeRemoveOverlay() {
    if (entries.isEmpty && _overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  //
  // Route stack bookkeeping (driven by [routeObserver])

  void _onRoutePushed(Route<dynamic> route) {
    if (route is PageRoute) {
      _pageRoutes.add(route);
      notifyListeners();
    }
  }

  void _onRouteRemoved(Route<dynamic> route) {
    if (route is PageRoute) {
      _pageRoutes.remove(route);
      // The page a window belonged to is gone — its preview goes with it.
      entries.removeWhere((e) => e.ownerRoute == route);
      notifyListeners();
      _maybeRemoveOverlay();
    }
  }

  void _onRouteReplaced(Route<dynamic>? newRoute, Route<dynamic>? oldRoute) {
    if (oldRoute is PageRoute) {
      _onRouteRemoved(oldRoute);
    }
    if (newRoute is PageRoute) {
      _onRoutePushed(newRoute);
    }
  }
}

/// Feeds navigator events into [FloatingPreviewHandler] so windows can be
/// tied to the lifetime of the page route that opened them.
class FloatingPreviewRouteObserver extends NavigatorObserver {
  FloatingPreviewRouteObserver(this.handler);

  final FloatingPreviewHandler handler;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    handler._onRoutePushed(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    handler._onRouteRemoved(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    handler._onRouteRemoved(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    handler._onRouteReplaced(newRoute, oldRoute);
  }
}
