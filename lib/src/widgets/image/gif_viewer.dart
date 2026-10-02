import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:extended_image/extended_image.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

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
  State<GifViewer> createState() => _GifViewerState();
}

class _GifViewerState extends State<GifViewer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

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
    _loadHeaders();
  }

  @override
  void didUpdateWidget(GifViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // PreloadPageView builds adjacent pages ahead of time, so their gifs decode
    // and animate off-screen. Without a reset, swiping to one shows it already
    // mid-animation. When a page scrolls into view, restart it from frame 0.
    if (widget.isViewed && !oldWidget.isViewed) {
      _restartAnimation();
    } else if (!widget.isViewed && oldWidget.isViewed) {
      _didResetForView = false;
    }
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

  // Decode the GIF at the screen's pixel width (capped to its own width so we
  // never upscale). This is the actual speed lever — full-res GIF frames are
  // what choke the UI isolate.
  int? _cacheWidthFor(BuildContext context) {
    if (settingsHandler.disableImageScaling || widget.booruItem.isNoScale.value) {
      return null;
    }
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double screenW = MediaQuery.sizeOf(context).width * dpr;
    final double? srcW = widget.booruItem.fileWidth;
    int target = screenW.round();
    if (srcW != null && srcW > 0 && srcW < target) {
      target = srcW.round();
    }
    // sane floor so a tiny viewport never decodes a 1px-wide GIF
    return target < 64 ? 64 : target;
  }

  @override
  Widget build(BuildContext context) {
    if (_failedHeaders) {
      return const Center(child: Icon(Symbols.broken_image_rounded, size: 48));
    }
    if (_headers == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ExtendedImage(
      // Key on the restart token so becoming-viewed forces a fresh decode
      // (frame 0) rather than resuming the cached mid-animation completer.
      key: ValueKey('gif-${widget.booruItem.fileURL}-$_restartToken'),
      image: _buildProvider(context),
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      // animate immediately and loop, like a GIF should
      enableLoadState: true,
      initGestureConfigHandler: (state) => GestureConfig(
        minScale: 0.9,
        maxScale: 4,
        animationMinScale: 0.7,
        animationMaxScale: 4.5,
        speed: 1,
        inertialSpeed: 100,
        initialScale: 1,
        cacheGesture: false,
        inPageView: true,
      ),
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
    );
  }
}
