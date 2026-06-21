import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:photo_view/photo_view.dart';
import 'package:preload_page_view/preload_page_view.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/long_press_repeater.dart';
import 'package:lolisnatcher/src/widgets/gallery/gallery_buttons.dart';
import 'package:lolisnatcher/src/widgets/gallery/hideable_appbar.dart';
import 'package:lolisnatcher/src/widgets/gallery/item_info_bottom_sheet.dart';
import 'package:lolisnatcher/src/widgets/gallery/notes_renderer.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/widgets/gallery/viewer_tutorial.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/guess_extension_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/load_item_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/better_player_view.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer_placeholder.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer.dart';

class GalleryViewPage extends StatefulWidget {
  const GalleryViewPage({
    required this.tab,
    required this.initialIndex,
    required super.key, // key required to allow disabling rendering viewer items when there are too many active viewers at the same time
    this.canSelect = true,
    this.readOnly = false,
    this.onPageChanged,
  });

  final SearchTab tab;
  final int initialIndex;
  final bool canSelect;
  final bool readOnly;
  final ValueChanged<int>? onPageChanged;

  @override
  State<GalleryViewPage> createState() => _GalleryViewPageState();
}

class _GalleryViewPageState extends State<GalleryViewPage> with RouteAware {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final SnatchHandler snatchHandler = SnatchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  late final PreloadPageController controller;

  final ValueNotifier<int> page = ValueNotifier(0);

  final FocusNode kbFocusNode = FocusNode();
  StreamSubscription? volumeListener;
  final GlobalKey<ScaffoldState> viewerScaffoldKey = GlobalKey<ScaffoldState>();

  bool isOpeningAnimation = true;
  final ValueNotifier<double> dismissProgress = ValueNotifier(1);
  final ValueNotifier<bool> drawerOpen = ValueNotifier(false);

  final ValueNotifier<bool> isActive = ValueNotifier(true);
  final ValueNotifier<bool> drawerVisibility = ValueNotifier(true);

  // Boorusama-style bottom info sheet (alternative to the side endDrawer).
  final DraggableScrollableController infoSheetController = DraggableScrollableController();
  final ValueNotifier<double> infoSheetExtent = ValueNotifier(0);
  bool get useBottomInfoSheet => settingsHandler.useBottomInfoSheet;
  // Sheet open height as a fraction of the screen. The user setting is "in
  // thirds": 1 => 1/3, 2 => 2/3, 3 => full. fraction = N/3.
  double get infoSheetOpenSize => (settingsHandler.bottomSheetSizeMultiplier / 3).clamp(0.2, 0.98);

  @override
  void initState() {
    super.initState();

    // pause all active videos to avoid performance and sound overlay issues
    viewerHandler.pauseAllVideos();

    controller = PreloadPageController(initialPage: widget.initialIndex);
    page.value = widget.initialIndex;

    ServiceHandler.disableSleep();
    kbFocusNode.requestFocus();

    final bool isVolumeAllowed = !settingsHandler.useVolumeButtonsForScroll || viewerHandler.displayAppbar.value;
    ServiceHandler.setVolumeButtons(isVolumeAllowed);
    volumeListener = searchHandler.volumeStream?.listen(volumeCallback);

    try {
      final item = widget.tab.booruHandler.filteredFetched[widget.initialIndex];
      viewerHandler.setCurrent(item);
      if (settingsHandler.dimSeenPosts) {
        unawaited(searchHandler.markPostSeen(item));
      }
    } catch (e) {
      viewerHandler.dropCurrent();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      dismissProgress.value = 0;
      await Future.delayed(const Duration(milliseconds: 420));
      isOpeningAnimation = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    NavigationHandler.instance.routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute,
    );
  }

  @override
  void didPushNext() {
    isActive.value = false;
  }

  @override
  void didPush() {
    isActive.value = true;
  }

  @override
  void didPopNext() {
    isActive.value = true;

    try {
      final item = widget.tab.booruHandler.filteredFetched[page.value];
      if (mounted) {
        viewerHandler.setCurrent(item);
      }
    } catch (_) {
      // attempt to recover from broken out of array bounds state (i.e. when adding tag to hidden removes all items from the tab)
      if (widget.tab.booruHandler.filteredFetched.isEmpty) {
        page.value = 0;
        controller.jumpToPage(page.value);
      } else if (page.value >= widget.tab.booruHandler.filteredFetched.length - 1) {
        page.value = widget.tab.booruHandler.filteredFetched.length - 1;
        controller.jumpToPage(page.value);
      }

      viewerHandler.dropCurrent();
    }

    // reset full screen state in case user leaves the fulscreen route through system back button/gesture
    viewerHandler.setFullScreenState(false);
  }

  @override
  void dispose() {
    if (widget.key is GlobalKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewerHandler.removeViewer(widget.key! as GlobalKey);
      });
    }
    NavigationHandler.instance.routeObserver.unsubscribe(this);
    infoSheetController.dispose();
    infoSheetExtent.dispose();
    volumeListener?.cancel();
    ServiceHandler.setVolumeButtons(!settingsHandler.useVolumeButtonsForScroll);
    kbFocusNode.dispose();
    ServiceHandler.enableSleep();
    super.dispose();
  }

  void drawerVisibilityChanged(bool visible) => drawerVisibility.value = visible;

  void openInfoPanel() {
    if (useBottomInfoSheet) {
      // Animate even on the first call. The controller attaches as soon as the
      // sheet's first frame runs, which has happened by the time the user can
      // tap a button or swipe. If somehow not attached, retry next frame.
      if (infoSheetController.isAttached) {
        infoSheetController.animateTo(
          infoSheetOpenSize,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (infoSheetController.isAttached) {
            infoSheetController.animateTo(
              infoSheetOpenSize,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    } else {
      viewerScaffoldKey.currentState?.openEndDrawer();
    }
  }

  void closeInfoSheet() {
    if (infoSheetController.isAttached) {
      infoSheetController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void volumeCallback(String event) {
    // print('in gallery $event');
    int dir = 0;
    if (event == 'up') {
      dir = -1;
    } else if (event == 'down') {
      dir = 1;
    }

    if (kbFocusNode.hasFocus && isActive.value && dir != 0) {
      // disable volume scrolling when not in focus
      // lastScrolledTo = math.max(math.min(lastScrolledTo + dir, widget.handler.filteredFetched.length), 0);
      final int toPage = page.value + dir; // lastScrolledTo;
      // controller.animateToPage(toPage, duration: Duration(milliseconds: 30), curve: Curves.easeInOut);
      if (toPage >= 0 && toPage < widget.tab.booruHandler.filteredFetched.length) {
        controller.jumpToPage(toPage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBar = HideableAppBar(
      tab: widget.tab,
      pageController: controller,
      canSelect: widget.canSelect,
      readOnly: widget.readOnly,
      onOpenDrawer: openInfoPanel,
    );

    final scaffold = Scaffold(
      key: viewerScaffoldKey,
      extendBodyBehindAppBar: true,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      appBar: settingsHandler.galleryBarPosition.isTop ? appBar : null,
      bottomNavigationBar: settingsHandler.galleryBarPosition.isBottom ? appBar : null,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The viewer. With the bottom info sheet on, it shrinks and anchors
          // to the top as the sheet rises (Boorusama split): at the sheet's
          // peek the player occupies the top ~1/3, the sheet the bottom ~2/3.
          // The heavy viewer subtree is passed as `child` so it is NOT rebuilt
          // on extent change — only re-parented into a shorter SizedBox.
          ValueListenableBuilder<double>(
            valueListenable: infoSheetExtent,
            builder: (context, extent, child) {
              if (!useBottomInfoSheet) return child!;
              // Use MediaQuery (not LayoutBuilder) because LayoutBuilder
              // defers its build until the LAYOUT phase, which causes the
              // bottom sheet + appbar (mounted earlier in the same frame) to
              // read pageController.page before the PreloadPageView attaches
              // its position → "Bad state: No element" crash on first frame.
              // extendBody* are both true on this Scaffold, so the body fills
              // MediaQuery.size — no off-by-pixels at the seam.
              final double screenH = MediaQuery.sizeOf(context).height;
              final double viewerH = screenH * (1 - extent).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(height: viewerH, child: child),
              );
            },
            child: PhotoViewGestureDetectorScope(
        // vertical to prevent swipe-to-dismiss when zoomed
        // axis: Axis.vertical, // photo_view doesn't support locking both axises, so we use custom fork to fix this
        axis: Axis.values,
        child: Dismissible(
          direction: settingsHandler.galleryScrollDirection.isVertical
              ? DismissDirection.horizontal
              // In horizontal-scroll mode vertical swipes normally dismiss
              // both ways. With the bottom info sheet on, reserve swipe-up for
              // opening the sheet — only swipe-down dismisses the viewer.
              : (useBottomInfoSheet ? DismissDirection.down : DismissDirection.vertical),
          // background: Container(color: Colors.black.withValues(alpha: 0.3)),
          key: const Key('imagePageDismissibleKey'),
          resizeDuration: null, // Duration(milliseconds: 100),
          dismissThresholds: const {
            DismissDirection.up: 0.2,
            DismissDirection.down: 0.2,
            DismissDirection.startToEnd: 0.3,
            DismissDirection.endToStart: 0.3,
          }, // Amount of swiped away which triggers dismiss
          onUpdate: (dismissUpdateDetails) {
            final prevValue = dismissProgress.value;
            dismissProgress.value =
                (dismissUpdateDetails.progress * (1 / (settingsHandler.galleryScrollDirection.isVertical ? 0.3 : 0.2)))
                    .clamp(0, 1);

            if (prevValue != dismissProgress.value && dismissProgress.value == 1) {
              ServiceHandler.vibrate();
            }
          },
          onDismissed: (_) => Navigator.of(context).pop(),
          child: ValueListenableBuilder(
            valueListenable: dismissProgress,
            builder: (context, dismissProgress, child) {
              if (dismissProgress == 0) {
                viewerHandler.showExtraUi();
              } else {
                viewerHandler.hideExtraUi();
              }

              return Transform.scale(
                scale: isOpeningAnimation
                    ? 1
                    : lerpDouble(
                        1,
                        0.75,
                        dismissProgress,
                      ),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: isOpeningAnimation ? 400 : 10),
                  decoration: BoxDecoration(
                    color: settingsHandler.shitDevice
                        ? Colors.black
                        : Color.lerp(
                            Colors.black,
                            Colors.transparent,
                            dismissProgress,
                          ),
                    borderRadius: (settingsHandler.shitDevice || isOpeningAnimation)
                        ? null
                        : BorderRadius.lerp(
                            BorderRadius.zero,
                            BorderRadius.circular(16),
                            dismissProgress,
                          ),
                  ),
                  child: child,
                ),
              );
            },
            child: Center(
              child: KeyboardListener(
                autofocus: false,
                focusNode: kbFocusNode,
                onKeyEvent: (KeyEvent event) async {
                  // detect only key DOWN events
                  if (event.runtimeType == KeyDownEvent) {
                    if (event.physicalKey == PhysicalKeyboardKey.arrowLeft ||
                        event.physicalKey == PhysicalKeyboardKey.keyH) {
                      // prev page on Left Arrow or H
                      if (page.value > 0) {
                        controller.jumpToPage(page.value - 1);
                      }
                    } else if (event.physicalKey == PhysicalKeyboardKey.arrowRight ||
                        event.physicalKey == PhysicalKeyboardKey.keyL) {
                      // next page on Right Arrow or L
                      if (page.value < widget.tab.booruHandler.filteredFetched.length - 1) {
                        controller.jumpToPage(page.value + 1);
                      }
                    } else if (event.physicalKey == PhysicalKeyboardKey.keyS) {
                      if (widget.readOnly) return;

                      // save on S
                      snatchHandler.queue(
                        [widget.tab.booruHandler.filteredFetched[page.value]],
                        widget.tab.booruHandler.booru,
                        settingsHandler.snatchCooldown,
                        false,
                      );
                      if (settingsHandler.favouriteOnSnatch) {
                        await widget.tab.toggleItemFavourite(
                          page.value,
                          forcedValue: true,
                          skipSnatching: true,
                        );
                      }
                    } else if (event.physicalKey == PhysicalKeyboardKey.keyF) {
                      if (widget.readOnly) return;

                      // favorite on F
                      if (settingsHandler.dbEnabled) {
                        await widget.tab.toggleItemFavourite(
                          page.value,
                        );
                      }
                    } else if (event.physicalKey == PhysicalKeyboardKey.keyR) {
                      // force load on R
                      viewerHandler.forceLoadCurrentItem();
                    } else if (event.physicalKey == PhysicalKeyboardKey.escape) {
                      // exit on escape if in focus
                      if (kbFocusNode.hasFocus) {
                        Navigator.of(context).pop();
                      }
                    }
                  }
                },
                child: Stack(
                  children: [
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: ValueListenableBuilder(
                        valueListenable: widget.tab.booruHandler.filteredFetched,
                        builder: (context, filteredFetched, child) {
                          if (filteredFetched.isEmpty) {
                            return Center(
                              child: Text(context.loc.galleryView.noItems, style: const TextStyle(color: Colors.white)),
                            );
                          }

                          final int preloadCount = settingsHandler.preloadCount;
                          final bool isSankaku = [
                            BooruType.Sankaku,
                            BooruType.IdolSankaku,
                          ].any((t) => t == widget.tab.booruHandler.booru.type);

                          return PreloadPageView.builder(
                            controller: controller,
                            preloadPagesCount: preloadCount,
                            // allowImplicitScrolling: true,
                            scrollDirection: settingsHandler.galleryScrollDirection.isVertical
                                ? Axis.vertical
                                : Axis.horizontal,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: _SnappyPageSpringPhysics(parent: ClampingScrollPhysics()),
                            ),
                            itemCount: filteredFetched.length,
                            itemBuilder: (context, index) {
                              final BooruItem item = widget.tab.booruHandler.filteredFetched[index];

                              final bool isFavsOrDls =
                                  widget.tab.booruHandler.booru.type?.isFavouritesOrDownloads == true;
                              Booru? possibleBooru;
                              if (isFavsOrDls) {
                                final itemFileHost = Uri.tryParse(item.fileURL)?.host;
                                final itemPostHost = Uri.tryParse(item.postURL)?.host;
                                possibleBooru = SettingsHandler.instance.booruList.firstWhereOrNull((e) {
                                  final booruHost = Uri.tryParse(e.baseURL ?? '')?.host;

                                  return (itemPostHost?.isNotEmpty == true &&
                                          booruHost?.isNotEmpty == true &&
                                          (itemPostHost! == booruHost! ||
                                              switch (e.type) {
                                                BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(
                                                  itemPostHost,
                                                ),
                                                BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(
                                                  itemPostHost,
                                                ),
                                                _ => false,
                                              })) ||
                                      (itemFileHost?.isNotEmpty == true &&
                                          booruHost?.isNotEmpty == true &&
                                          itemFileHost! == booruHost!);
                                });
                                if (possibleBooru?.type?.isFavouritesOrDownloads == true) {
                                  possibleBooru = null;
                                }
                              }

                              return ValueListenableBuilder(
                                valueListenable: item.mediaType,
                                builder: (context, mediaType, _) {
                                  // Flutter's built-in GIF decoder runs on the
                                  // UI isolate and drops to single-digit FPS on
                                  // anything past a few hundred KB. With the
                                  // setting on, route .gif files through the
                                  // active video backend (libmpv / fvp /
                                  // better_player) which decode natively and
                                  // play smoothly.
                                  final bool reroutedAsVideo =
                                      settingsHandler.useVideoBackendForGifs && mediaType.isAnimation;
                                  final bool isVideo = mediaType.isVideo || reroutedAsVideo;
                                  final bool isImage = mediaType.isImageOrAnimation && !reroutedAsVideo;
                                  final bool isNeedToGuess = mediaType.isNeedToGuess;
                                  final bool isNeedToLoadItem =
                                      mediaType.isNeedToLoadItem && widget.tab.booruHandler.hasLoadItemSupport;

                                  late Widget itemWidget;
                                  if (isImage) {
                                    itemWidget = ValueListenableBuilder(
                                      valueListenable: page,
                                      builder: (_, pageVal, _) {
                                        return ImageViewer(
                                          item,
                                          booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                          isViewed: pageVal == index,
                                          key: item.key,
                                        );
                                      },
                                    );
                                  } else if (isVideo) {
                                    if (!settingsHandler.disableVideo &&
                                        (Platform.isAndroid ||
                                            Platform.isIOS ||
                                            Platform.isWindows ||
                                            Platform.isLinux)) {
                                      itemWidget = ValueListenableBuilder(
                                        valueListenable: page,
                                        builder: (_, pageVal, _) {
                                          final usedBooru = possibleBooru ?? widget.tab.booruHandler.booru;
                                          // Experimental media_kit (libmpv) path takes precedence.
                                          if (settingsHandler.useMediaKitPlayer && Platform.isAndroid) {
                                            return MediaKitPlayerView(
                                              item,
                                              booru: usedBooru,
                                              isViewed: pageVal == index,
                                              key: item.key,
                                            );
                                          }
                                          // Experimental better_player_plus path; behind a setting.
                                          if (settingsHandler.useBetterPlayer && Platform.isAndroid) {
                                            return BetterPlayerView(
                                              item,
                                              booru: usedBooru,
                                              isViewed: pageVal == index,
                                              key: item.key,
                                            );
                                          }
                                          return VideoViewer(
                                            item,
                                            booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                            isViewed: pageVal == index,
                                            enableFullscreen: true,
                                            key: item.key,
                                          );
                                        },
                                      );
                                    } else {
                                      itemWidget = VideoViewerPlaceholder(
                                        item: item,
                                        booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                        key: item.key,
                                      );
                                    }
                                  } else if (isNeedToGuess) {
                                    itemWidget = GuessExtensionViewer(
                                      item: item,
                                      booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                      onMediaTypeGuessed: (MediaType newMediaType) {
                                        item.mediaType.value = newMediaType;
                                        item.possibleMediaType.value = newMediaType.isUnknown
                                            ? item.possibleMediaType.value
                                            : null;
                                      },
                                      key: item.key,
                                    );
                                  } else if (isNeedToLoadItem) {
                                    itemWidget = LoadItemViewer(
                                      item: item,
                                      handler: widget.tab.booruHandler,
                                      onItemLoaded: (newItem) {
                                        widget.tab.booruHandler.filteredFetched[index] = newItem;
                                        // ignore: invalid_use_of_protected_member
                                        newItem.mediaType.refresh();
                                      },
                                      key: item.key,
                                    );
                                  } else {
                                    itemWidget = GuessExtensionViewer(
                                      item: item,
                                      booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                      onMediaTypeGuessed: (MediaType newMediaType) {
                                        item.mediaType.value = newMediaType;
                                        item.possibleMediaType.value = newMediaType.isUnknown
                                            ? item.possibleMediaType.value
                                            : null;
                                      },
                                      key: item.key,
                                    );
                                  }

                                  final child = ListenableBuilder(
                                    listenable: Listenable.merge([viewerHandler.activeViewers, page]),
                                    builder: (context, child) {
                                      final activeViewers = viewerHandler.activeViewers.value;
                                      final pageVal = page.value;
                                      final viewerIndex = widget.key is GlobalKey
                                          ? viewerHandler.indexOfViewer(widget.key! as GlobalKey)
                                          : -1;
                                      final int viewerDepth = viewerIndex == -1
                                          ? 0
                                          : (activeViewers.length - 1 - viewerIndex);
                                      final bool isViewerTooDeep = viewerDepth >= ViewerHandler.maxActiveViewers;

                                      final bool isViewedVal = index == pageVal;
                                      final int distanceFromCurrent = (pageVal - index).abs();
                                      // don't render more than 3 videos at once, chance to crash is too high otherwise
                                      // disabled video preload for sankaku because their videos cause crashes if loading/rendering(?) more than one at a time
                                      final bool isNear =
                                          viewerDepth < ViewerHandler.maxActiveViewers &&
                                          (distanceFromCurrent <=
                                              (isVideo ? (isSankaku ? 0 : min(preloadCount, 1)) : preloadCount));

                                      return AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 100),
                                        child: (isViewerTooDeep || (!isViewedVal && !isNear))
                                            ? Center(child: Container(color: Colors.black))
                                            : child,
                                      );
                                    },
                                    child: ClipRect(
                                      // Stack/Buttons Temp fix for desktop pageview only scrollable on like 2px at edges of screen. Think its a windows only bug
                                      child: GestureDetector(
                                        onTap: () => viewerHandler.toggleToolbar(false),
                                        onLongPress: () => viewerHandler.toggleToolbar(true),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 100),
                                          child: itemWidget,
                                        ),
                                      ),
                                    ),
                                  );

                                  if (settingsHandler.disableCustomPageTransitions) {
                                    return child;
                                  }

                                  return AnimatedBuilder(
                                    animation: controller,
                                    builder: (context, child) {
                                      return slidePageTransition(
                                        context,
                                        controller,
                                        settingsHandler.galleryScrollDirection.isVertical
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                        index,
                                        child,
                                      );
                                    },
                                    child: child,
                                  );
                                },
                              );
                            },
                            onPageChanged: (int index) {
                              page.value = index;
                              widget.onPageChanged?.call(index);
                              ServiceHandler.disableSleep();

                              kbFocusNode.requestFocus();

                              try {
                                final item = widget.tab.booruHandler.filteredFetched[index];
                                if (mounted) {
                                  viewerHandler.setCurrent(item);
                                  if (settingsHandler.dimSeenPosts) {
                                    unawaited(searchHandler.markPostSeen(item));
                                  }
                                }
                              } catch (e) {
                                // attempt to recover from broken out of array bounds state (i.e. when adding tag to hidden removes all items from the tab)
                                if (widget.tab.booruHandler.filteredFetched.isEmpty) {
                                  page.value = 0;
                                  controller.jumpToPage(page.value);
                                } else if (page.value >= widget.tab.booruHandler.filteredFetched.length - 1) {
                                  page.value = widget.tab.booruHandler.filteredFetched.length - 1;
                                  controller.jumpToPage(page.value);
                                }

                                viewerHandler.dropCurrent();
                              }

                              final bool isVolumeAllowed =
                                  !settingsHandler.useVolumeButtonsForScroll || viewerHandler.displayAppbar.value;
                              ServiceHandler.setVolumeButtons(isVolumeAllowed);
                            },
                          );
                        },
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: dismissProgress,
                      builder: (context, dismissProgress, child) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: dismissProgress == 0 ? child : const SizedBox.shrink(),
                        );
                      },
                      child: ValueListenableBuilder(
                        valueListenable: page,
                        builder: (context, page, child) {
                          if (widget.tab.booruHandler.filteredFetched.isEmpty ||
                              page >= widget.tab.booruHandler.filteredFetched.length) {
                            return const SizedBox.shrink();
                          }

                          return NotesRenderer(
                            item: widget.tab.booruHandler.filteredFetched[page],
                            handler: widget.tab.booruHandler,
                            pageController: controller,
                          );
                        },
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: drawerOpen,
                      builder: (context, drawerOpen, child) {
                        return ValueListenableBuilder(
                          valueListenable: dismissProgress,
                          builder: (context, dismissProgress, _) {
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: (dismissProgress == 0 && !drawerOpen) ? child : const SizedBox.shrink(),
                            );
                          },
                        );
                      },
                      child: GalleryButtons(pageController: controller),
                    ),
                    const ViewerTutorial(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
          ),
          // Boorusama-style bottom info sheet. Only present when the setting is
          // on; otherwise the classic right-side endDrawer (below) handles the
          // info panel.
          if (useBottomInfoSheet) ...[
            ItemInfoBottomSheet(
              tab: widget.tab,
              currentPage: page,
              sheetController: infoSheetController,
              extentNotifier: infoSheetExtent,
              openSize: infoSheetOpenSize,
            ),
            // Full-screen passive listener: observes pointer events without
            // claiming them in the gesture arena (so paging, dismiss, pan,
            // and tap-to-toggle-controls all still work). While the sheet is
            // closed it drives the sheet's extent directly from the finger's
            // displacement (1:1, native refresh rate) on an upward swipe. Once
            // the sheet is open it stands down and the sheet's own drag takes
            // over. Always mounted so it never unmounts mid-gesture.
            Positioned.fill(
              child: _SwipeUpListener(
                controller: infoSheetController,
                openSize: infoSheetOpenSize,
              ),
            ),
          ],
        ],
      ),
      endDrawerEnableOpenDragGesture: false,
      onEndDrawerChanged: (isOpened) {
        drawerOpen.value = isOpened;
        drawerVisibilityChanged(isOpened);
      },
      endDrawer: useBottomInfoSheet
          ? null
          : ItemInfoDrawer(
              tab: widget.tab,
              pageController: controller,
              onVisibilityChanged: drawerVisibilityChanged,
            ),
    );

    //

    // When the bottom info sheet is open, intercept the system back button to
    // close the sheet instead of leaving the viewer.
    final Widget maybeBackHandled = useBottomInfoSheet
        ? ValueListenableBuilder<double>(
            valueListenable: infoSheetExtent,
            builder: (context, extent, child) {
              return PopScope(
                canPop: extent <= 0.001,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) closeInfoSheet();
                },
                child: child!,
              );
            },
            child: scaffold,
          )
        : scaffold;

    return ValueListenableBuilder(
      valueListenable: drawerVisibility,
      builder: (context, drawerVisibility, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            drawerTheme: Theme.of(context).drawerTheme.copyWith(
              scrimColor: drawerVisibility ? null : Colors.transparent,
            ),
          ),
          child: child!,
        );
      },
      child: maybeBackHandled,
    );
  }
}

/// Full-screen passive pointer observer that drives the bottom info sheet's
/// extent directly as the user swipes — Boorusama-style. Once it detects a
/// clear upward swipe (≥24px up, vertical dominating horizontal by 1.5×,
/// single touch) it switches into a "drag" phase and uses jumpTo on each
/// pointer move so the sheet is glued to the finger at native refresh rate
/// instead of running a separate animateTo. On release it snaps to the
/// nearest of {closed, peek, expanded} biased by fling velocity.
///
/// Uses [Listener] (not [GestureDetector]) so it never enters the gesture
/// arena while idle — paging, dismiss, photo_view pan and tap-to-toggle all
/// continue to work normally.
class _SwipeUpListener extends StatefulWidget {
  const _SwipeUpListener({
    required this.controller,
    required this.openSize,
  });

  final DraggableScrollableController controller;
  final double openSize;

  @override
  State<_SwipeUpListener> createState() => _SwipeUpListenerState();
}

class _SwipeUpListenerState extends State<_SwipeUpListener> {
  int? _pointerId;
  Offset _startPos = Offset.zero;
  Offset _lastPos = Offset.zero;
  int _lastTimeUs = 0;
  // Velocity along Y in logical pixels per second (negative = upward).
  double _velocityYPxPerSec = 0;
  bool _engaged = false;
  bool _multiTouch = false;
  // True only when the gesture began while the sheet was (near) closed. When
  // the sheet is already open we leave dragging to its own physics.
  bool _eligible = false;

  static const double _engagePx = 12;
  static const double _flingPxPerSec = 600;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointerId != null) {
          _multiTouch = true;
          return;
        }
        _pointerId = event.pointer;
        _startPos = event.position;
        _lastPos = event.position;
        _lastTimeUs = event.timeStamp.inMicroseconds;
        _engaged = false;
        _multiTouch = false;
        _velocityYPxPerSec = 0;
        double current = 0;
        if (widget.controller.isAttached) current = widget.controller.size;
        _eligible = current <= 0.02;
      },
      onPointerMove: (event) {
        if (_multiTouch || !_eligible) return;
        if (event.pointer != _pointerId) return;

        final dtUs = (event.timeStamp.inMicroseconds - _lastTimeUs).clamp(1, 1 << 31);
        _velocityYPxPerSec = (event.position.dy - _lastPos.dy) / (dtUs / 1e6);
        _lastPos = event.position;
        _lastTimeUs = event.timeStamp.inMicroseconds;

        // Displacement from where the finger went DOWN — positive = moved up.
        final double dyUp = _startPos.dy - event.position.dy;
        final double dxAbs = (event.position.dx - _startPos.dx).abs();

        if (!_engaged) {
          if (dyUp < _engagePx) return;
          // Vertical must dominate horizontal so we don't hijack page swipes.
          if (dxAbs > dyUp) return;
          _engaged = true;
        }

        if (!widget.controller.isAttached) return;

        // Extent grows 1:1 with how far the finger has moved up, regardless of
        // where on screen the swipe started — so it begins from 0 and tracks
        // the finger smoothly instead of snapping to an absolute position.
        final double screenHeight = MediaQuery.sizeOf(context).height;
        final double newExtent = (dyUp / screenHeight).clamp(0.0, widget.openSize);
        widget.controller.jumpTo(newExtent);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointerId) return;
        _pointerId = null;
        if (!_engaged) return;
        _settle();
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointerId) return;
        _pointerId = null;
        if (!_engaged) return;
        _settle();
      },
    );
  }

  void _settle() {
    if (!widget.controller.isAttached) return;
    final current = widget.controller.size;
    final upPxPerSec = -_velocityYPxPerSec;

    // Single open stop now (the sheet locks at openSize). Fling up => open,
    // fling down => close, otherwise snap to whichever is nearer.
    double target;
    if (upPxPerSec > _flingPxPerSec) {
      target = widget.openSize;
    } else if (upPxPerSec < -_flingPxPerSec) {
      target = 0;
    } else {
      target = current >= widget.openSize / 2 ? widget.openSize : 0;
    }

    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

Widget slidePageTransition(
  BuildContext context,
  PreloadPageController pageController,
  Axis direction,
  int index,
  Widget? child,
) {
  double delta = 0;
  if (pageController.hasClients && pageController.position.haveDimensions) {
    final position = (pageController.page! - index).clamp(-1.0, 1.0);
    final viewport = pageController.position.viewportDimension;
    delta = position * viewport / 2;
  }
  return ClipRect(
    child: Transform.translate(
      offset: Offset(
        direction == Axis.horizontal ? delta : 0,
        direction == Axis.vertical ? delta : 0,
      ),
      child: child,
    ),
  );
}

class ItemInfoDrawer extends StatefulWidget {
  const ItemInfoDrawer({
    required this.tab,
    required this.pageController,
    required this.onVisibilityChanged,
    super.key,
  });

  final SearchTab tab;
  final PreloadPageController pageController;
  final ValueChanged<bool> onVisibilityChanged;

  @override
  State<ItemInfoDrawer> createState() => _ItemInfoDrawerState();
}

class _ItemInfoDrawerState extends State<ItemInfoDrawer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  final ValueNotifier<bool> isVisible = ValueNotifier(true);

  final ValueNotifier<int> page = ValueNotifier(0);

  @override
  void initState() {
    super.initState();

    page.value = widget.pageController.page?.round() ?? 0;
    widget.pageController.addListener(pageListener);
  }

  void pageListener() {
    page.value = widget.pageController.page?.round() ?? 0;
    print('page: ${page.value}/${widget.pageController.page}');
  }

  void toggleVisibility() {
    isVisible.value = !isVisible.value;
    widget.onVisibilityChanged(isVisible.value);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(pageListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxDrawerWidth = MediaQuery.sizeOf(context).shortestSide * 0.8;

    final List<Widget> buttons = [
      // TODO fav/dl buttons?
      Expanded(
        child: ValueListenableBuilder(
          valueListenable: viewerHandler.isStopped,
          builder: (context, isStopped, child) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isStopped
                  ? SizedBox.expand(
                      child: OutlinedButton(
                        onPressed: viewerHandler.forceLoadCurrentItem,
                        child: const Icon(Icons.refresh),
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
      Expanded(
        child: ValueListenableBuilder(
          valueListenable: isVisible,
          builder: (context, _, _) {
            return GestureDetector(
              onLongPressDown: (_) => toggleVisibility(),
              onLongPressUp: toggleVisibility,
              onLongPressCancel: toggleVisibility,
              child: OutlinedButton(
                onPressed: toggleVisibility,
                child: isVisible.value ? const Icon(Icons.remove_red_eye) : const Icon(Icons.remove_red_eye_outlined),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: LongPressRepeater(
          onStart: () async {
            widget.pageController.jumpToPage(page.value - 1);
            await Future.delayed(const Duration(milliseconds: 100));
          },
          fasterAfter: 20,
          child: OutlinedButton(
            onPressed: () => widget.pageController.jumpToPage(page.value - 1),
            child: settingsHandler.galleryScrollDirection.isVertical
                ? const Icon(Icons.arrow_upward)
                : const Icon(Icons.arrow_back),
          ),
        ),
      ),
      Expanded(
        child: LongPressRepeater(
          onStart: () async {
            widget.pageController.jumpToPage(page.value + 1);
            await Future.delayed(const Duration(milliseconds: 100));
          },
          fasterAfter: 20,
          child: OutlinedButton(
            onPressed: () => widget.pageController.jumpToPage(page.value + 1),
            child: settingsHandler.galleryScrollDirection.isVertical
                ? const Icon(Icons.arrow_downward)
                : const Icon(Icons.arrow_forward),
          ),
        ),
      ),
    ];

    return RepaintBoundary(
      child: Theme(
        data: Theme.of(context).copyWith(
          // copy existing main app theme, but make background semitransparent
          drawerTheme: Theme.of(context).drawerTheme.copyWith(
            backgroundColor: Theme.of(context).canvasColor.withValues(alpha: 0.66),
          ),
        ),
        child: SizedBox(
          width: maxDrawerWidth + 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SafeArea(
                child: Container(
                  alignment: Alignment.bottomCenter,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  height: (50 * buttons.length) + (12 * (buttons.length - 1)),
                  width: 50,
                  child: ValueListenableBuilder(
                    valueListenable: isVisible,
                    builder: (context, isVisible, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          outlinedButtonTheme: OutlinedButtonThemeData(
                            style: OutlinedButtonTheme.of(context).style?.copyWith(
                              backgroundColor: WidgetStatePropertyAll(
                                Theme.of(context).canvasColor.withValues(alpha: isVisible ? 0.66 : 0.1),
                              ),
                              side: WidgetStatePropertyAll(
                                BorderSide(
                                  width: isVisible ? 1.5 : 0.5,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: Opacity(
                          opacity: isVisible ? 0.9 : 0.3,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      spacing: 12,
                      children: buttons,
                    ),
                  ),
                ),
              ),

              ValueListenableBuilder(
                valueListenable: isVisible,
                builder: (context, isVisible, child) {
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !isVisible,
                      child: child,
                    ),
                  );
                },
                child: Drawer(
                  width: maxDrawerWidth,
                  child: SafeArea(
                    child: ValueListenableBuilder(
                      valueListenable: page,
                      builder: (context, page, _) {
                        if (widget.tab.booruHandler.filteredFetched.isEmpty ||
                            page >= widget.tab.booruHandler.filteredFetched.length) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 16,
                              children: [
                                Text(context.loc.galleryView.noItemSelected),
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: CloseDialogButton(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return TagView(
                          item: widget.tab.booruHandler.filteredFetched[page],
                          handler: widget.tab.booruHandler,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stiffer page-snap spring so swiping between posts settles quickly instead
/// of the default "buttery"/floaty glide. PreloadPageView resolves its
/// page-snap [spring] through the physics parent chain, so overriding [spring]
/// here is enough — we don't need to reimplement the ballistic simulation.
class _SnappyPageSpringPhysics extends ScrollPhysics {
  const _SnappyPageSpringPhysics({super.parent});

  @override
  _SnappyPageSpringPhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPageSpringPhysics(parent: buildParent(ancestor));
  }

  // Default page spring is roughly mass 0.5 / stiffness 100 / ratio 1.1.
  // Lighter + stiffer = a faster, snappier settle with no overshoot.
  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.32,
    stiffness: 230,
    ratio: 1.1,
  );
}
