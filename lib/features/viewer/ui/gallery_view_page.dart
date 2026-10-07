import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:photo_view/photo_view.dart';
import 'package:preload_page_view/preload_page_view.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/logging/navigation_trace.dart';
import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/features/viewer/ui/media/flash_play_viewer.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/idol_sankaku_handler.dart';
import 'package:lolisnatcher/sources/booru/sankaku_handler.dart';
import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/features/feed/logic/floating_preview_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/sources/framework/post_files_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/ui/buttons/close_dialog_button.dart';
import 'package:lolisnatcher/core/ui/long_press_repeater.dart';
import 'package:lolisnatcher/features/viewer/ui/chrome/gallery_buttons.dart';
import 'package:lolisnatcher/features/viewer/ui/chrome/hideable_appbar.dart';
import 'package:lolisnatcher/features/viewer/ui/info/item_info_bottom_sheet.dart';
import 'package:lolisnatcher/features/viewer/ui/notes_renderer.dart';
import 'package:lolisnatcher/features/viewer/ui/info/tag_view.dart';
import 'package:lolisnatcher/features/viewer/ui/viewer_tutorial.dart';
import 'package:lolisnatcher/features/viewer/ui/media/gif_viewer.dart';
import 'package:lolisnatcher/features/viewer/ui/media/image_viewer.dart';
import 'package:lolisnatcher/features/viewer/ui/media/guess_extension_viewer.dart';
import 'package:lolisnatcher/features/viewer/ui/media/load_item_viewer.dart';
import 'package:lolisnatcher/features/video/ui/better_player_view.dart';
import 'package:lolisnatcher/features/video/ui/media_kit_player_view.dart';
import 'package:lolisnatcher/features/video/ui/video_viewer_placeholder.dart';
import 'package:lolisnatcher/features/video/ui/video_viewer.dart';

part 'gallery_view_page/swipe_up_listener.dart';
part 'gallery_view_page/info_peek_bar.dart';
part 'gallery_view_page/item_info_drawer.dart';
part 'gallery_view_page/page_physics.dart';

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

class _GalleryViewPageState extends State<GalleryViewPage> with RouteAware, TraceLifecycle {
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

  // Dwell tracking for the taste profile: which item is currently on screen
  // and since when. Flushed to InterestsHandler when the item changes / closes.
  BooruItem? _dwellItem;
  DateTime _dwellSince = DateTime.now();

  void _flushDwell() {
    final item = _dwellItem;
    // Doujin items (however they reached the classic viewer) must not feed
    // the booru taste profile — per item, so merge tabs are covered too.
    if (item != null && !widget.tab.booruHandler.hasReader && !DoujinDataHandler.isDoujinItem(item)) {
      InterestsHandler.instance.onItemViewed(item, DateTime.now().difference(_dwellSince));
    }
    _dwellItem = null;
  }

  /// Sites where a post can hold several files only reveal the list on the
  /// post's own page, so it is fetched HERE — when a post is actually opened,
  /// never while the grid loads — and cached. The toolbar action appears by
  /// itself once the list arrives and turns out to hold more than one file.
  void _loadPostFiles(BooruItem item) {
    final booru = widget.tab.booruHandler.booru;
    if (!PostFilesHandler.instance.supports(booru)) return;
    unawaited(PostFilesHandler.instance.ensureLoaded(item, booru));
  }

  void _startDwell(BooruItem item) {
    if (identical(item, _dwellItem)) return;
    _flushDwell();
    _dwellItem = item;
    _dwellSince = DateTime.now();
  }

  final ValueNotifier<bool> isActive = ValueNotifier(true);
  final ValueNotifier<bool> drawerVisibility = ValueNotifier(true);

  // Boorusama-style bottom info sheet (alternative to the side endDrawer).
  final DraggableScrollableController infoSheetController = DraggableScrollableController();
  final ValueNotifier<double> infoSheetExtent = ValueNotifier(0);
  bool get useBottomInfoSheet => settingsHandler.useBottomInfoSheet;
  // Sheet open height as a fraction of the screen. The user setting is "in
  // thirds": 1 => 1/3, 2 => 2/3, 3 => full. fraction = N/3.
  double get infoSheetOpenSize => (settingsHandler.bottomSheetSizeMultiplier / 3).clamp(0.2, 0.98);

  void _mirrorSheetExtent() {
    viewerHandler.infoSheetExtent.value = infoSheetExtent.value;
  }

  @override
  void initState() {
    super.initState();
    // r68: a post opened from the feed. 'viewer.swipe' is a swipe to the next
    // post inside the viewer - the two used to be one and got misread.
    PerfTrace.instance.event('viewer.open', '${widget.initialIndex}');

    // Mirror the sheet extent into ViewerHandler so video-control overlays
    // know whether the peek bar is actually visible.
    viewerHandler.infoSheetExtent.value = 0;
    infoSheetExtent.addListener(_mirrorSheetExtent);

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
      _startDwell(item);
      _loadPostFiles(item);
      if (settingsHandler.dimSeenPosts) {
        unawaited(searchHandler.markPostSeen(item, tab: widget.tab));
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
    viewerHandler.releaseScreen(this);
  }

  @override
  void didPush() {
    isActive.value = true;
    viewerHandler.claimScreen(this);
  }

  // r77: frames are read only while a viewer is really on screen; a closing
  // viewer stops that the moment its route pops, not after its animation.
  @override
  void didPop() {
    viewerHandler.releaseScreen(this);
  }

  @override
  void didPopNext() {
    isActive.value = true;
    viewerHandler.claimScreen(this);

    // A nested viewer (e.g. opened from a tag preview strip) shares the
    // global sheet-extent mirror and resets it to 0 in its own initState —
    // re-assert THIS viewer's actual sheet position so video controls don't
    // lift for a peek bar that isn't there (sheet open ⇒ no peek bar).
    viewerHandler.infoSheetExtent.value = infoSheetExtent.value;

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
    viewerHandler.releaseScreen(this);
    _flushDwell();
    if (widget.key is GlobalKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewerHandler.removeViewer(widget.key! as GlobalKey);
      });
    }
    NavigationHandler.instance.routeObserver.unsubscribe(this);
    infoSheetController.dispose();
    infoSheetExtent.removeListener(_mirrorSheetExtent);
    // NOTE: deliberately NOT resetting viewerHandler.infoSheetExtent here — a
    // nested viewer disposing after the outer one's didPopNext would clobber
    // the outer viewer's just-restored sheet position. The next viewer's
    // initState sets its own value.
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
          onDismissed: (_) => NavigationTrace.closing('swipe down', () => Navigator.of(context).pop()),
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
                        NavigationTrace.closing('Escape key', () => Navigator.of(context).pop());
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
                                  widget.tab.booruHandler.booru.type?.isLocalDb == true ||
                                  widget.tab.booruHandler.booru.type?.isRecommendationFeed == true;
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
                                if (possibleBooru?.type?.isLocalDb == true || possibleBooru?.type?.isRecommendationFeed == true) {
                                  possibleBooru = null;
                                }
                              }

                              return ValueListenableBuilder(
                                valueListenable: item.mediaType,
                                builder: (context, mediaType, _) {
                                  final bool isVideo = mediaType.isVideo;
                                  final bool isImage = mediaType.isImageOrAnimation;
                                  final bool isNeedToGuess = mediaType.isNeedToGuess;
                                  final bool isNeedToLoadItem =
                                      mediaType.isNeedToLoadItem && widget.tab.booruHandler.hasLoadItemSupport;

                                  // GIFs get the extended_image renderer when the
                                  // fast-GIF option is on (decodes at display res
                                  // + own cache — fixes the slow stock Image path).
                                  final bool useGifViewer = mediaType.isAnimation && settingsHandler.fastGifPlayback;

                                  late Widget itemWidget;
                                  // r48: a Flash post is its thumbnail and a Play button, never
                                  // the loading card and the type guessing that end on
                                  // "Failed to guess the file extension".
                                  if (FlashPlayViewer.shouldShow(item)) {
                                    itemWidget = FlashPlayViewer(
                                      item: item,
                                      handler: widget.tab.booruHandler,
                                      key: item.key,
                                    );
                                  } else if (useGifViewer) {
                                    itemWidget = ValueListenableBuilder(
                                      valueListenable: page,
                                      builder: (_, pageVal, _) {
                                        return GifViewer(
                                          item,
                                          booru: possibleBooru ?? widget.tab.booruHandler.booru,
                                          isViewed: pageVal == index,
                                          key: item.key,
                                        );
                                      },
                                    );
                                  } else if (isImage) {
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
                              PerfTrace.instance.event('viewer.swipe', '$index');
                              page.value = index;
                              widget.onPageChanged?.call(index);
                              ServiceHandler.disableSleep();

                              kbFocusNode.requestFocus();

                              try {
                                final item = widget.tab.booruHandler.filteredFetched[index];
                                if (mounted) {
                                  viewerHandler.setCurrent(item);
                                  _startDwell(item);
                                  if (settingsHandler.dimSeenPosts) {
                                    unawaited(searchHandler.markPostSeen(item, tab: widget.tab));
                                  }
                                  {
                                    _loadPostFiles(item);
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
                    ViewerTutorial(
                      shown: settingsHandler.showViewerTutorial,
                      onDismiss: () {
                        settingsHandler.showViewerTutorial = false;
                        setState(() {});
                        Logger.Inst().log(
                          'viewer hint closed',
                          'GalleryViewPage',
                          'viewerTutorial',
                          LogTypes.settingsLoad,
                        );
                        unawaited(settingsHandler.saveSettings(restate: false));
                      },
                    ),
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
            // Persistent peek bar: artist + tag-count chips + swipe-up hint,
            // shown while the sheet is collapsed and the chrome is visible.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Obx(() {
                // Only while the viewer chrome is showing, so it never covers
                // hidden-UI immersive viewing.
                if (!viewerHandler.displayAppbar.value) return const SizedBox.shrink();
                return ValueListenableBuilder<double>(
                  valueListenable: infoSheetExtent,
                  builder: (context, extent, _) {
                    final double t = (1 - (extent / 0.06)).clamp(0.0, 1.0);
                    if (t <= 0.01) return const SizedBox.shrink();
                    return Opacity(
                      opacity: t,
                      child: IgnorePointer(
                        ignoring: t < 0.5,
                        child: _InfoPeekBar(
                          tab: widget.tab,
                          page: page,
                          onTap: openInfoPanel,
                        ),
                      ),
                    );
                  },
                );
              }),
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
                  // r77: a preview window shown on this page takes this Back
                  // (it closes first; the sheet closes on the next one).
                  // (The top page is this viewer when its Back runs; asking
                  // ModalRoute.of here would rebuild on every route change.)
                  final FloatingPreviewHandler previews = FloatingPreviewHandler.instance;
                  if (!didPop && !previews.hasWindowFor(previews.topPageRoute)) closeInfoSheet();
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

/// The tag the viewer's peek bar names as [item]'s artist. The app-wide tag
/// store is a booru store: a doujin item's tags carry their own site's type
/// and the store is never consulted for them (HANDOVER 6.2).
@visibleForTesting
String? infoPeekBarArtistOf(BooruItem item) {
  final th = TagHandler.instance;
  final bool isDoujin = DoujinDataHandler.isDoujinItem(item);
  for (final t in item.tagsList) {
    final TagType type = isDoujin ? t.tagType : th.getTag(t.fullString).tagType;
    if (type.isArtist) return t.fullString;
  }
  return null;
}
