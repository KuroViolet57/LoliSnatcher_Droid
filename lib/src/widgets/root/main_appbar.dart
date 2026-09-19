import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/inner_drawer.dart';
import 'package:lolisnatcher/src/widgets/preview/flow_tab_carousel.dart';
import 'package:lolisnatcher/src/widgets/root/custom_sliver_app_bar.dart';
import 'package:lolisnatcher/src/widgets/video/better_player_view.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';

class MainAppBar extends StatefulWidget implements PreferredSizeWidget {
  const MainAppBar({
    super.key,
  });

  static double get height => 64;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<MainAppBar> createState() => _MainAppBarState();
}

class _MainAppBarState extends State<MainAppBar> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final SnatchHandler snatchHandler = SnatchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  void _toggleDrawer(InnerDrawerDirection? dir) {
    final state = searchHandler.mainDrawerKey.currentState;
    if (state is! InnerDrawerState) {
      return;
    }

    state.toggle(direction: dir);
  }

  void _onMenuLongTap() {
    ServiceHandler.vibrate();
    // scroll to start on long press of menu buttons
    searchHandler.gridScrollController.jumpTo(0);
  }

  Widget menuButton(InnerDrawerDirection direction) {
    return Builder(
      builder: (context) {
        // All three gestures on one InkResponse: an IconButton nested inside
        // a GestureDetector builds its own ink tap recognizer, which is
        // innermost in the gesture arena and beats the ancestor's long press.
        return InkResponse(
          onTap: () => _toggleDrawer(direction),
          onLongPress: _onMenuLongTap,
          onSecondaryTap: _onMenuLongTap,
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Symbols.menu_rounded,
              color: Theme.of(context).appBarTheme.iconTheme?.color,
            ),
          ),
        );
      },
    );
  }

  Widget snatcherButton(InnerDrawerDirection direction) {
    return Builder(
      builder: (context) {
        return Obx(() {
          if (searchHandler.tabs.isNotEmpty) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Obx(() {
                  if (snatchHandler.active.value == false || snatchHandler.current.value == null) {
                    return const SizedBox.shrink();
                  }

                  final double singleToTotalProgress = 1 / snatchHandler.current.value!.booruItems.length;
                  final double currentCompleteProgress = snatchHandler.queueProgress.value * singleToTotalProgress;

                  final double downloadProgress = snatchHandler.currentProgress;
                  final double downloadToTotalProgress = singleToTotalProgress * downloadProgress;

                  return CircularProgressIndicator(
                    value: currentCompleteProgress + downloadToTotalProgress,
                  );
                }),
                // Flow: this drawer is the Pinned tags / quick access sidebar
                // now, so a single pin glyph replaces the old floppy+arrows.
                IconButton(
                  onPressed: () async {
                    _toggleDrawer(direction);
                  },
                  icon: Icon(
                    Symbols.push_pin_rounded,
                    color: Theme.of(context).appBarTheme.iconTheme?.color,
                  ),
                ),
                if (searchHandler.currentSelected.isNotEmpty)
                  Positioned(
                    right: -6,
                    top: 8,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        height: 20,
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Text(
                              searchHandler.currentSelected.length.toFormattedString(),
                              style: TextStyle(color: Theme.of(context).colorScheme.onSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          } else {
            return const SizedBox.shrink();
          }
        });
      },
    );
  }

  // Soft media refresh: drops the image memory cache and the video player
  // pools so everything reloads with freshly-read cookies — WITHOUT touching
  // the tab itself (no re-search, page and scroll position stay). The fix-up
  // step after re-solving a Cloudflare/session challenge in the webview.
  void _softRefreshMedia() {
    Tools.forceClearMemoryCache(withLive: true);
    MediaKitPlayerView.resetPool();
    BetterPlayerView.resetPool();
    // Failed thumbnails listen for this and retry with the fresh session.
    viewerHandler.mediaRefreshEpoch.value++;
    // Re-emit the item list so grid cells rebuild and re-request their media.
    searchHandler.filterCurrentFetched();

    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'soft_refresh',
      duration: const Duration(seconds: 2),
      title: const Text('Reloading media', style: TextStyle(fontSize: 20)),
      content: const Text('Fresh session, same page — posts will re-request as you view them.'),
      leadingIcon: Symbols.mop_rounded,
      sideColor: Colors.green,
    );
  }

  Widget refreshMediaButton() {
    return Builder(
      builder: (context) {
        return IconButton(
          tooltip: 'Reload media (keeps your place)',
          icon: Icon(
            Symbols.mop_rounded,
            color: Theme.of(context).appBarTheme.iconTheme?.color,
          ),
          onPressed: _softRefreshMedia,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).brightness.isLight ? Colors.white : Colors.black;
    final foregroundColor = Theme.of(context).brightness.isLight ? Colors.black : Colors.white;

    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme.of(context).copyWith(
          backgroundColor: backgroundColor.withValues(alpha: settingsHandler.shitDevice ? 1 : 0.66),
          foregroundColor: foregroundColor,
          iconTheme: AppBarTheme.of(context).iconTheme?.copyWith(color: foregroundColor),
          actionsIconTheme: AppBarTheme.of(context).actionsIconTheme?.copyWith(color: foregroundColor),
          titleTextStyle: AppBarTheme.of(context).titleTextStyle?.copyWith(color: foregroundColor),
          toolbarTextStyle: AppBarTheme.of(context).toolbarTextStyle?.copyWith(color: foregroundColor),
          // elevation: 0,
          // scrolledUnderElevation: 0,
        ),
      ),
      child: CustomSliverAppBar(
        floating: true,
        snap: true,
        automaticallyImplyLeading: false,
        headerKey: NavigationHandler.instance.floatingHeaderKey,
        onHeaderVisiblityChanged: (visible) {
          if (visible) {
            NavigationHandler.instance.bottomBarKey.currentState?.show();
          } else {
            NavigationHandler.instance.bottomBarKey.currentState?.hide();
          }
        },
        leading: settingsHandler.handSide.value.isLeft
            ? menuButton(InnerDrawerDirection.start)
            : snatcherButton(InnerDrawerDirection.start),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabsCountPill(),
            SizedBox(width: 8),
            PageIndicatorPill(),
          ],
        ),
        toolbarHeight: MainAppBar.height,
        flexibleSpace: settingsHandler.shitDevice
            ? null
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: const SizedBox.expand(
                    child: ColoredBox(
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
        actions: [
          const NewTabButton(),
          if (settingsHandler.handSide.value.isRight)
            menuButton(InnerDrawerDirection.end)
          else
            snatcherButton(InnerDrawerDirection.end),
          // Rightmost: soft media refresh (fresh session, keeps tab state).
          refreshMediaButton(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
