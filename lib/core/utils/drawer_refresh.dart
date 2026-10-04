import 'package:flutter/foundation.dart';

/// Shared "the drawers should re-read their data" signal.
///
/// Drawer sections cache counts and lists that come from async sources (the
/// booru DB) which can't be observed directly, so they used to snapshot once
/// at tab creation and then drift: deleting favourites left the old count,
/// a freshly pinned tag never appeared, and only a brand-new tab showed
/// current values.
///
/// Everything that can invalidate drawer content bumps [tick]: opening a
/// drawer, returning from a page opened out of one, and any doujin-store
/// write. Sections listen with `DrawerRefresh.tick.addListener(...)` and
/// reload. Sources that ARE observable (the doujin store's lists) stay
/// reactive on their own — this only covers the ones that aren't.
///
/// A plain [ValueNotifier] rather than an Rx value on purpose: its listeners
/// are independent of any GetX worker/stream lifecycle, so a section that
/// subscribes after an earlier one was torn down still receives every bump.
class DrawerRefresh {
  const DrawerRefresh._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void request() => tick.value++;
}
