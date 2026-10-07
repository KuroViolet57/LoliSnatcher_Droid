import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:extended_image/extended_image.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/gif_decode_width.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';

/// Dedicated GIF renderer using extended_image (the same engine Boorusama
/// uses). The win over the default Image path: extended_image decodes the
/// animated frames at display resolution via cacheWidth instead of full res —
/// the stock viewer deliberately skips downscaling for animations, which is
/// what drags large GIFs down to a few FPS. extended_image also keeps its own
/// disk + memory cache, so re-opening a GIF doesn't re-download or re-decode.
class GifViewer extends StatefulWidget {
  const GifViewer(
    this.booruItem, {
    required this.booru,
    required this.isViewed,
    super.key,
  });

  final BooruItem booruItem;
  final Booru booru;
  final bool isViewed;

  @override
  State<GifViewer> createState() => GifViewerState();
}

class GifViewerState extends State<GifViewer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;
  final PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  final PhotoViewController viewController = PhotoViewController();
  final ValueNotifier<bool> isZoomed = ValueNotifier(false);
  late final StreamSubscription<PhotoViewControllerValue> _viewSub;
  late final StreamSubscription<PhotoViewScaleState> _scaleSub;

  Map<String, String>? _headers;
  bool _failedHeaders = false;

  // Bumped to force a fresh ExtendedImage (new decode) when the gif should
  // restart from frame 0.
  int _restartToken = 0;
  // Whether we've already reset the animation for the current "viewed" spell,
  // so we don't evict repeatedly on every rebuild while viewed.
  bool _didResetForView = false;

  @override
  void initState() {
    super.initState();
    _viewSub = viewController.outputStateStream.listen((PhotoViewControllerValue value) {
      viewerHandler.setViewValue(widget.key, value);
    });
    _scaleSub = scaleController.outputScaleStateStream.listen(_onScaleStateChanged);
    _loadHeaders();
  }

  void _onScaleStateChanged(PhotoViewScaleState scaleState) {
    final bool zoomed =
        scaleState == PhotoViewScaleState.zoomedIn ||
        scaleState == PhotoViewScaleState.covering ||
        scaleState == PhotoViewScaleState.originalSize;
    final bool changed = isZoomed.value != zoomed;
    final bool opened = zoomed && !isZoomed.value;
    isZoomed.value = zoomed;
    viewerHandler.setZoomed(widget.key, zoomed);
    // A width change needs a new decode. Full-file mode already uses every
    // pixel, so a zoom there does not rebuild.
    if (!changed || !mounted) return;
    if (settingsHandler.disableImageScaling || widget.booruItem.isNoScale.value) return;
    if (opened) {
      Logger.Inst().log(
        'GIF decode widened for a zoom',
        'GifViewer',
        '_onScaleStateChanged',
        LogTypes.imageInfo,
      );
    }
    // The scale stream can notify during the gesture that built this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  /// Same cover the still-image zoom button uses.
  void doubleTapZoom() {
    scaleController.scaleState = PhotoViewScaleState.covering;
  }

  void resetZoom() {
    scaleController.scaleState = PhotoViewScaleState.initial;
    viewerHandler.setZoomed(widget.key, false);
  }

  @override
  void didUpdateWidget(GifViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isViewed && !widget.isViewed) {
      resetZoom();
    }
    // PreloadPageView builds adjacent pages ahead of time, so their gifs decode
    // and animate off-screen. Without a reset, swiping to one shows it already
    // mid-animation. When a page scrolls into view, restart it from frame 0.
    if (widget.isViewed && !oldWidget.isViewed) {
      _restartAnimation();
    } else if (!widget.isViewed && oldWidget.isViewed) {
      _didResetForView = false;
    }
  }

  @override
  void dispose() {
    _viewSub.cancel();
    _scaleSub.cancel();
    scaleController.dispose();
    viewController.dispose();
    isZoomed.dispose();
    super.dispose();
  }

  Future<void> _loadHeaders() async {
    try {
      final headers = await Tools.getFileCustomHeaders(
        widget.booru,
        item: widget.booruItem,
        checkForReferer: true,
      );
      if (!mounted) return;
      setState(() => _headers = headers);
      // If this page is already the viewed one at mount (e.g. opened straight
      // from the grid), start its animation cleanly too.
      if (widget.isViewed) unawaited(_restartAnimation());
    } catch (_) {
      if (!mounted) return;
      setState(() => _failedHeaders = true);
    }
  }

  // Evicts the gif's cached (and live) image stream so the next build decodes a
  // fresh completer starting at frame 0, then rebuilds with a new key. Disk
  // cache is untouched, so this doesn't re-download — only re-decodes.
  Future<void> _restartAnimation() async {
    if (_didResetForView || _headers == null || !mounted) return;
    _didResetForView = true;
    try {
      await _buildProvider(context).evict();
    } catch (_) {
      // eviction is best-effort; a failure just means the gif may resume
      // mid-frame rather than crash.
    }
    if (mounted) setState(() => _restartToken++);
  }

  // Builds the same provider ExtendedImage.network would, so evicting this
  // instance targets the exact cache entry the widget renders.
  ImageProvider _buildProvider(BuildContext context) {
    final base = ExtendedNetworkImageProvider(
      widget.booruItem.fileURL,
      cache: settingsHandler.mediaCache,
      headers: _headers,
    );
    final int? cacheWidth = _cacheWidthFor(context);
    return cacheWidth == null
        ? base
        : ExtendedResizeImage.resizeIfNeeded(provider: base, cacheWidth: cacheWidth);
  }

  // Screen width at rest. Twice that after a zoom, capped to the file so we
  // never upscale. Full-file frames stay behind Don't scale images: they are
  // what choke the UI isolate.
  int? _cacheWidthFor(BuildContext context) {
    return gifDecodeWidth(
      disableImageScaling: settingsHandler.disableImageScaling,
      noScale: widget.booruItem.isNoScale.value,
      zoomed: isZoomed.value,
      screenWidthCss: MediaQuery.sizeOf(context).width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      fileWidth: widget.booruItem.fileWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failedHeaders) {
      return const Center(child: Icon(Symbols.broken_image_rounded, size: 48));
    }
    if (_headers == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Size screen = MediaQuery.sizeOf(context);
    return PhotoView.customChild(
      childSize: screen,
      customSize: screen,
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 8,
      initialScale: PhotoViewComputedScale.contained,
      basePosition: Alignment.center,
      controller: viewController,
      scaleStateController: scaleController,
      enableRotation: settingsHandler.allowRotation,
      child: ExtendedImage(
      // Key on the restart token and the decode width so becoming-viewed, or
      // a zoom, forces a fresh decode rather than resuming the old completer.
      key: ValueKey('gif-${widget.booruItem.fileURL}-$_restartToken-${_cacheWidthFor(context)}'),
      image: _buildProvider(context),
      fit: BoxFit.contain,
      // Pinch and the zoom button belong to the PhotoView wrapper, the same
      // one a still image uses. Two gesture detectors fight the page swipe.
      mode: ExtendedImageMode.none,
      enableLoadState: true,
      loadStateChanged: (ExtendedImageState state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(child: CircularProgressIndicator());
          case LoadState.failed:
            return GestureDetector(
              onTap: state.reLoadImage,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.broken_image_rounded, size: 48),
                    SizedBox(height: 8),
                    Text('Tap to retry'),
                  ],
                ),
              ),
            );
          case LoadState.completed:
            return null; // let extended_image render (and animate) the gif
        }
      },
      ),
    );
  }
}
