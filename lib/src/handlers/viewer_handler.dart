import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer.dart';

// TODO media actions, video pause/mute... global controller

class ViewerHandler {
  static ViewerHandler get instance => GetIt.instance<ViewerHandler>();

  static ViewerHandler register() {
    if (!GetIt.instance.isRegistered<ViewerHandler>()) {
      GetIt.instance.registerSingleton(ViewerHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<ViewerHandler>();

  // Keys to get states of all currently built viewers
  final RxList<GlobalKey?> activeKeys = RxList([]);
  // Key of the currently viewed media widget
  final Rxn<BooruItem> current = Rxn(null);

  final RxList<GlobalKey> activeViewers = RxList([]);

  /// How deep viewers may stack before the covered one stops rendering its
  /// media (gallery_view_page's isViewerTooDeep).
  ///
  /// 2, not 1: a post's file carousel opens ON TOP of the viewer that launched
  /// it, and at 1 the parent unmounted the moment the overlay appeared —
  /// tearing down its player (the saved-position hand-off exists because of
  /// exactly that). The tag-preview and waterfall nested viewers read the same
  /// constant and simply keep their parent alive too. Kept low deliberately:
  /// each extra level is another live player against a media_kit pool that
  /// defaults to 4.
  static const int maxActiveViewers = 2;

  void addViewer(GlobalKey key) {
    if (activeViewers.contains(key)) {
      return;
    }

    activeViewers.add(key);
  }

  void removeViewer(GlobalKey key) {
    activeViewers.remove(key);
    if (activeViewers.isEmpty) {
      // Whole viewer stack closed — parked video positions and manual-pause
      // marks are only meant to live within one viewing session (nested
      // round-trips, swiping between posts). A fresh open starts clean:
      // position 0, autoplay back to normal.
      _savedVideoPositions.clear();
      _manuallyPaused.clear();
    }
  }

  int indexOfViewer(GlobalKey key) {
    return activeViewers.indexOf(key);
  }

  void addViewed(Key? key) {
    if (key == null || activeKeys.contains(key)) {
      return;
    }

    if (key is GlobalKey) {
      activeKeys.add(key);
    }
  }

  void removeViewed(Key? key) {
    if (key == null || !activeKeys.contains(key)) {
      return;
    }

    if (key is GlobalKey) {
      activeKeys.remove(key);
    }
  }

  void setCurrent(BooruItem? item) {
    if (item == null || current.value?.key == item.key) {
      return;
    }

    current.value = item;
    setNewState(item.key);
  }

  // Drop the key of viewed widget and reset the handler state
  // (used when user exits the viewer page)
  void dropCurrent() {
    current.value = null;
    resetState();
  }

  final RxBool displayAppbar = true.obs; // is viewer toolbar visible

  // Current extent of the bottom info sheet (0 = closed). Mirrored from the
  // gallery page so overlays (e.g. video controls) can tell whether the Flow
  // peek bar is actually on screen: it only shows while the chrome is visible
  // AND the sheet is closed.
  final RxDouble infoSheetExtent = 0.0.obs;

  bool get isPeekBarVisible => displayAppbar.value && infoSheetExtent.value < 0.06;

  // ── manual pause tracking ────────────────────────────────────────────────
  // URLs of videos the USER paused via the controls. While the
  // "don't auto-resume manually paused videos" setting is on, the players'
  // auto-play paths skip these (e.g. returning from a nested viewer /
  // preview window won't restart a video you paused). Pressing play clears
  // the mark, and the whole set is wiped when the viewer stack closes (see
  // removeViewer) — reopening a post later autoplays as normal.
  final Set<String> _manuallyPaused = {};

  void markManualPause(String? url) {
    if (url != null && url.isNotEmpty) _manuallyPaused.add(url);
  }

  void clearManualPause(String? url) {
    if (url != null) _manuallyPaused.remove(url);
  }

  bool isManuallyPaused(String? url) => url != null && _manuallyPaused.contains(url);

  // ── nested-viewer position hand-off ──────────────────────────────────────
  // Opening a nested viewer unmounts the covered viewer's media widget
  // entirely (maxActiveViewers guard), destroying its player and with it the
  // playback position. The disposing player parks its position here; the
  // widget re-created on return picks it up and seeks back, so the video is
  // exactly where it was left. Entries are consumed on take and the whole map
  // is wiped when the viewer stack closes, so a later fresh open of the same
  // video still starts at the beginning.
  final Map<String, Duration> _savedVideoPositions = {};

  void saveVideoPosition(String? url, Duration? position) {
    if (url == null || url.isEmpty || position == null || position <= Duration.zero) {
      return;
    }
    _savedVideoPositions[url] = position;
  }

  Duration? takeVideoPosition(String? url) {
    if (url == null) return null;
    return _savedVideoPositions.remove(url);
  }

  // Bumped by the soft-refresh button and by the 403-probe after a captcha
  // solve; failed thumbnails listen and retry themselves with the fresh
  // session instead of staying stuck on their error tile.
  final RxInt mediaRefreshEpoch = 0.obs;
  final RxBool isZoomed = false.obs; // is current item zoomed in
  final RxBool isLoaded = false.obs; // is current item loaded
  final RxBool isStopped = false.obs; // is current item stopped
  final Rx<PhotoViewControllerValue?> viewState = Rx(null); // current view controller value (used by notes renderer)
  final RxBool isFullscreen = false.obs; // is viewing video in fullscreen (mobile app mode)
  final RxBool isDesktopFullscreen = false.obs; // is viewing video in fullscreen (desktop app mode)

  final RxBool showNotes = true.obs;

  void resetState() {
    displayAppbar.value = true;
    isZoomed.value = false;
    isLoaded.value = false;
    isStopped.value = false;
    setFullScreenState(false);
    isDesktopFullscreen.value = false;
    viewState.value = null;
  }

  void setNewState(Key? key) {
    if (key == null || current.value?.key != key || key is! GlobalKey) {
      return;
    }

    // addPostFrameCallback waits until widget is built to avoid calling setState in it while other setState is active
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = key.currentState;
      switch (state?.widget) {
        case ImageViewer():
          final widgetState = state! as ImageViewerState;
          isZoomed.value = widgetState.isZoomed.value;
          isLoaded.value = widgetState.isLoaded.value;
          isStopped.value = widgetState.isStopped.value;
          setFullScreenState(false);
          viewState.value = widgetState.viewController.value;
          break;
        case VideoViewer():
          final widgetState = state! as VideoViewerState;
          isZoomed.value = widgetState.isZoomed.value;
          isLoaded.value = widgetState.isVideoInited;
          isStopped.value = widgetState.isStopped.value;
          setFullScreenState(widgetState.chewieController.value?.isFullScreen ?? false);
          viewState.value = widgetState.viewController.value;
          break;
        default:
          isZoomed.value = false;
          isLoaded.value = true;
          isStopped.value = false;
          setFullScreenState(false);
          viewState.value = null;
          break;
      }
    });
  }

  void setZoomed(Key? key, bool isZoom) {
    if (key == null || current.value?.key != key) {
      return;
    }

    isZoomed.value = isZoom;
  }

  void toggleZoom() {
    isZoomed.value ? resetZoom() : doubleTapZoom();
  }

  void resetZoom() {
    final state = (current.value?.key as GlobalKey?)?.currentState;
    switch (state?.widget) {
      case ImageViewer():
        (state as ImageViewerState?)?.resetZoom();
        break;
      case VideoViewer():
        (state as VideoViewerState?)?.resetZoom();
        break;
      default:
        break;
    }
  }

  void doubleTapZoom() {
    final state = (current.value?.key as GlobalKey?)?.currentState;
    switch (state?.widget) {
      case ImageViewer():
        (state as ImageViewerState?)?.doubleTapZoom();
        break;
      case VideoViewer():
        (state as VideoViewerState?)?.doubleTapZoom();
        break;
      default:
        break;
    }
  }

  void toggleMuteAllVideos({bool mute = true}) {
    for (final key in activeKeys) {
      final state = key?.currentState;
      switch (state?.widget) {
        case VideoViewer():
          (state as VideoViewerState?)?.videoController.value?.setVolume(mute ? 0 : 1);
          break;
        default:
          break;
      }
    }
  }

  void pauseAllVideos() {
    for (final key in activeKeys) {
      final state = key?.currentState;
      switch (state?.widget) {
        case VideoViewer():
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => (state as VideoViewerState?)?.videoController.value?.pause(),
          );
          break;
        default:
          break;
      }
    }
  }

  void forceLoadCurrentItem() {
    final state = (current.value?.key as GlobalKey?)?.currentState;
    switch (state?.widget) {
      case ImageViewer():
        (state as ImageViewerState?)?.forceLoad();
        break;
      case VideoViewer():
        (state as VideoViewerState?)?.forceLoad();
        break;
      default:
        break;
    }
  }

  void setFullScreenState(bool value) {
    isFullscreen.value = value;
  }

  void hideExtraUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final key in activeKeys) {
        final state = key?.currentState;
        switch (state?.widget) {
          case ImageViewer():
            (state as ImageViewerState?)?.showLoading.value = false;
            break;
          case VideoViewer():
            (state as VideoViewerState?)?.showControls.value = false;
            break;
          default:
            break;
        }
      }
    });
  }

  void showExtraUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final key in activeKeys) {
        final state = key?.currentState;
        switch (state?.widget) {
          case ImageViewer():
            (state as ImageViewerState?)?.showLoading.value = true;
            break;
          case VideoViewer():
            (state as VideoViewerState?)?.showControls.value = true;
            break;
          default:
            break;
        }
      }
    });
  }

  void setViewValue(Key? key, PhotoViewControllerValue value) {
    if (key == null || current.value?.key != key) {
      return;
    }

    viewState.value = value;
  }

  void setLoaded(Key? key, bool value) {
    if (key == null || current.value?.key != key || isLoaded.value == value) {
      return;
    }

    isLoaded.value = value;

    if (value) {
      setStopped(key, false);
    }
  }

  void setStopped(Key? key, bool value) {
    if (key == null || current.value?.key != key || isStopped.value == value) {
      return;
    }

    isStopped.value = value;
  }

  void toggleToolbar(
    bool isLongTap, {
    bool? forcedNewValue,
  }) {
    final bool newAppbarVisibility = forcedNewValue ?? !displayAppbar.value;
    displayAppbar.value = newAppbarVisibility;

    if (isLongTap) {
      ServiceHandler.vibrate();
    }

    final settingsHandler = SettingsHandler.instance;

    // enable volume buttons if current page is a video AND appbar is set to visible
    final bool isVolumeAllowed = !settingsHandler.useVolumeButtonsForScroll || newAppbarVisibility;
    ServiceHandler.setVolumeButtons(isVolumeAllowed);
  }

  bool videoAutoMute = kDebugMode
      ? Constants.blurImagesDefaultDev
      : false; // hold volume button in VideoViewer to mute videos globally

  //
  // Tag previews history
  // Keeps track of the viewed tag previews stack for each tab

  Map<String, List<MapEntry<String, String>>> tagPreviews = {};
  Map<String, List<List<MapEntry<String, String>>>> tagPreviewsHistory = {};

  void addTagPreview(
    String? tabId,
    String previewId,
    String tag,
  ) {
    if (tabId == null) return;

    if (tagPreviews[tabId] == null) {
      tagPreviews[tabId] = [];
    }
    tagPreviews[tabId]?.add(MapEntry(previewId, tag));
    updateTagPreviewHistory(tabId);
  }

  void removeTagPreview(
    String? tabId,
    String previewId,
  ) {
    if (tabId == null) return;

    tagPreviews[tabId]?.removeWhere((e) => e.key == previewId);
    updateTagPreviewHistory(tabId);
  }

  List<MapEntry<String, String>> currentTagPreviewState(
    String? tabId,
  ) {
    if (tabId == null) return [];

    return tagPreviews[tabId] ?? [];
  }

  void updateTagPreviewHistory(
    String? tabId,
  ) {
    if (tabId == null) return;

    // debounce to ignore multiple page pops affecting history more than needed
    Debounce.debounce(
      tag: 'tag_previews_history_update',
      duration: const Duration(milliseconds: 600),
      callback: () {
        if (tagPreviewsHistory[tabId] == null) {
          tagPreviewsHistory[tabId] = [];
        }
        tagPreviewsHistory[tabId]?.add([...tagPreviews[tabId] ?? []]);

        if ((tagPreviewsHistory[tabId]?.length ?? 0) > 100) {
          tagPreviewsHistory[tabId]?.removeRange(0, 1);
        }
      },
    );
  }
}
