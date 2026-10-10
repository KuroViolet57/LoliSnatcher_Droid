import 'package:flutter/cupertino.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/core/ui/bottom_bar_visibility.dart';
import 'package:lolisnatcher/core/ui/sliver/custom_sliver_persistent_header.dart';

class NavigationHandler {
  static NavigationHandler get instance => GetIt.instance<NavigationHandler>();

  static NavigationHandler register() {
    if (!GetIt.instance.isRegistered<NavigationHandler>()) {
      GetIt.instance.registerSingleton(NavigationHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<NavigationHandler>();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  BuildContext get navContext => navigatorKey.currentContext!;

  final RouteObserver<ModalRoute> routeObserver = RouteObserver<ModalRoute>();

  final GlobalKey<CustomFloatingHeaderState> floatingHeaderKey = GlobalKey<CustomFloatingHeaderState>();
  /// The feed's bottom bar (WaterfallBottomBar); drive it through [bottomBar].
  final GlobalKey bottomBarKey = GlobalKey();

  BottomBarVisibility? get bottomBar => bottomBarKey.currentState as BottomBarVisibility?;
}
