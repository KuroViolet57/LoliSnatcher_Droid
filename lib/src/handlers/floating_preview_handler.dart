import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
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
    this.doujinItem,
  }) : id = const Uuid().v4();

  final String id;
  final String tag;
  final Booru booru;
  final Route<dynamic>? ownerRoute;

  /// When set, the window hosts this doujin's DETAIL PAGE (with its own
  /// nested navigator, so Read opens the reader inside the window) instead
  /// of a tag-result grid.
  final BooruItem? doujinItem;
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

  // Windows render in the root overlay, ABOVE any dialog/bottom sheet pushed
  // on the navigator. UI launched FROM a window (group picker etc.) wraps
  // itself in push/popSuppress so the windows duck out of the way instead of
  // burying the modal.
  int _suppressCount = 0;
  bool get isSuppressed => _suppressCount > 0;

  void pushSuppress() {
    _suppressCount++;
    notifyListeners();
  }

  void popSuppress() {
    if (_suppressCount > 0) _suppressCount--;
    notifyListeners();
  }

  bool isEntryVisible(FloatingPreviewEntry entry) => !isSuppressed && entry.ownerRoute == topPageRoute;

  /// r77: the page a preview asked for from [owner] belongs to - [owner]
  /// itself for a page still up, the page under it for a dialog or sheet
  /// still up; null when that is gone. Without an owner, the top page.
  Route<dynamic>? _pageFor(Route<dynamic>? owner) {
    if (owner == null) return topPageRoute;
    if (owner is PageRoute) return _pageRoutes.contains(owner) ? owner : null;
    return owner.isActive ? topPageRoute : null;
  }

  /// r77: a preview window is shown for [route] (its page's own Back
  /// handlers stand down while one is: this Back closes the window).
  bool hasWindowFor(Route<dynamic>? route) => route != null && entries.any((e) => e.ownerRoute == route);

  /// Opens (or replaces, when that page already has one) the floating preview
  /// window for [tag] on [booru]. r77: [owner] is the route the user tapped
  /// on; when that page has closed meanwhile, nothing opens (the window used
  /// to land on whatever page was left - on 19 Sep, the main feed).
  void open({
    required String tag,
    required Booru booru,
    Route<dynamic>? owner,
  }) {
    final Route<dynamic>? page = _pageFor(owner);
    if (page == null && owner != null) {
      Logger.Inst().log('preview of "$tag" dropped: the page it was asked from has closed', 'FloatingPreviewHandler', 'open', LogTypes.booruHandlerInfo);
      return;
    }
    // One window per owner route — opening a new preview on the same page
    // replaces the previous window instead of stacking an unbounded pile.
    entries.removeWhere((e) => e.ownerRoute == page);
    entries.add(
      FloatingPreviewEntry(
        tag: tag,
        booru: booru,
        ownerRoute: page,
      ),
    );
    _syncBackEntries();
    _ensureOverlay();
    // Doujin tag previews must not feed the booru taste profile.
    if (!DoujinDataHandler.isDoujinBooru(booru)) {
      InterestsHandler.instance.onTagPreviewOpened(tag, booru: booru);
    }
    notifyListeners();
  }

  /// Opens a floating DETAIL-PAGE window for one doujin. Same ownership
  /// rules as tag windows; never feeds the booru taste profile.
  void openDoujinPreview({
    required BooruItem item,
    required Booru booru,
    Route<dynamic>? owner,
  }) {
    final Route<dynamic>? page = _pageFor(owner);
    if (page == null && owner != null) return;
    entries.removeWhere((e) => e.ownerRoute == page);
    entries.add(
      FloatingPreviewEntry(
        tag: 'id:${item.serverId}',
        booru: booru,
        ownerRoute: page,
        doujinItem: item,
      ),
    );
    _syncBackEntries();
    _ensureOverlay();
    notifyListeners();
  }

  void close(FloatingPreviewEntry entry) {
    entries.remove(entry);
    _syncBackEntries();
    notifyListeners();
    _maybeRemoveOverlay();
  }

  void closeAll() {
    entries.clear();
    _syncBackEntries();
    notifyListeners();
    _maybeRemoveOverlay();
  }

  // r77: a page with a preview window gets a Back entry that blocks its pop
  // and closes the window instead - Back goes preview, then the page's own
  // steps (the viewer's info sheet), then the page. Code pops (the back arrow,
  // swipe-down) are not blocked by it and take the window with the page.
  final Map<Route<dynamic>, _PreviewBackEntry> _backEntries = {};

  void _syncBackEntries() {
    final Set<Route<dynamic>> owners = {
      for (final FloatingPreviewEntry e in entries)
        if (e.ownerRoute != null) e.ownerRoute!,
    };
    for (final Route<dynamic> route in _backEntries.keys.toList()) {
      if (owners.contains(route)) continue;
      final _PreviewBackEntry? back = _backEntries.remove(route);
      if (back != null && route is ModalRoute) route.unregisterPopEntry(back);
    }
    for (final Route<dynamic> route in owners) {
      if (_backEntries.containsKey(route) || route is! ModalRoute) continue;
      final _PreviewBackEntry back = _PreviewBackEntry(this, route);
      _backEntries[route] = back;
      route.registerPopEntry(back);
    }
  }

  /// Back on [route] while it shows a window: the newest window goes.
  void _closeTopFor(Route<dynamic> route) {
    for (int i = entries.length - 1; i >= 0; i--) {
      if (entries[i].ownerRoute == route) {
        close(entries[i]);
        return;
      }
    }
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
      _syncBackEntries();
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

/// r77: blocks Back on a page that shows a preview window and closes the
/// window instead. The close waits a microtask: every Back handler of the
/// page hears this same Back, and they check [FloatingPreviewHandler.hasWindowFor]
/// to stand down - the window must still be there when they look.
class _PreviewBackEntry extends PopEntry<Object?> {
  _PreviewBackEntry(this.handler, this.route);

  final FloatingPreviewHandler handler;
  final Route<dynamic> route;
  final ValueNotifier<bool> _canPop = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) return;
    scheduleMicrotask(() => handler._closeTopFor(route));
  }
}
