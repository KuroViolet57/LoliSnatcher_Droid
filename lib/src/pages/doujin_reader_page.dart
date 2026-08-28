import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:photo_view/photo_view.dart';
import 'package:preload_page_view/preload_page_view.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// The doujin reader: ordered pages of one gallery, read like a book.
///
/// Pages render through their own self-contained image path (a PhotoView on
/// a CustomNetworkImage) rather than the main viewer's ImageViewer. The
/// first shipped reader reused ImageViewer and came back from the field as a
/// black screen on every page — ImageViewer is welded to the gallery
/// machinery (hero tags, viewer-handler state, notes, tiling) and none of
/// its failure modes are visible. This path owes nothing to that machinery,
/// shows real progress while loading, and prints the URL + error ON the page
/// with a retry button when loading fails, so a broken page can be diagnosed
/// from a screenshot alone.
///
/// Reading behaviour comes from the per-source settings (reading direction
/// including vertical, tap zones, instant/animated turns, preload depth,
/// keep screen on) — see [SourceSettingsHandler].
class DoujinReaderPage extends StatefulWidget {
  const DoujinReaderPage({
    required this.pages,
    required this.booru,
    required this.galleryId,
    this.title = '',
    this.initialPage = 0,
    super.key,
  });

  final List<BooruItem> pages;
  final Booru booru;
  final String galleryId;
  final String title;
  final int initialPage;

  @override
  State<DoujinReaderPage> createState() => _DoujinReaderPageState();
}

class _DoujinReaderPageState extends State<DoujinReaderPage> {
  final settingsHandler = SettingsHandler.instance;
  final sourceSettings = SourceSettingsHandler.instance;

  late final PreloadPageController _controller;
  late int _current;
  late String _direction;
  bool _chromeVisible = true;

  bool get _rtl => _direction == 'rtl';
  bool get _vertical => _direction == 'vertical';

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage.clamp(0, widget.pages.length - 1);
    _controller = PreloadPageController(initialPage: _current);
    _direction = sourceSettings.readingDirection(widget.booru);
    if (sourceSettings.keepScreenOn(widget.booru)) {
      ServiceHandler.disableSleep();
    }
    Logger.Inst().log(
      'reader open: gallery=${widget.galleryId} pages=${widget.pages.length} '
      'start=${_current + 1} first=${widget.pages.first.fileURL}',
      'DoujinReaderPage',
      'initState',
      LogTypes.booruItemLoad,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _current = page);
    ReaderHandler.instance.saveProgress(widget.booru, widget.galleryId, page, widget.pages.length);
  }

  void _goTo(int page) {
    final int target = page.clamp(0, widget.pages.length - 1);
    if (sourceSettings.instantPageTurns(widget.booru)) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  /// PhotoView's own tap callback — no competing gesture recognizers.
  /// Edges turn pages (respecting reading direction), the middle toggles
  /// the chrome.
  void _onTapUp(BuildContext context, TapUpDetails details, PhotoViewControllerValue value) {
    if (!sourceSettings.tapZones(widget.booru)) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    if (_vertical) {
      final double dy = details.globalPosition.dy / MediaQuery.sizeOf(context).height;
      if (dy < 0.25) {
        _goTo(_current - 1);
      } else if (dy > 0.75) {
        _goTo(_current + 1);
      } else {
        setState(() => _chromeVisible = !_chromeVisible);
      }
      return;
    }
    final double dx = details.globalPosition.dx / MediaQuery.sizeOf(context).width;
    if (dx < 0.3) {
      _goTo(_rtl ? _current + 1 : _current - 1);
    } else if (dx > 0.7) {
      _goTo(_rtl ? _current - 1 : _current + 1);
    } else {
      setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  void _cycleDirection() {
    final String next = switch (_direction) {
      'ltr' => 'rtl',
      'rtl' => 'vertical',
      _ => 'ltr',
    };
    setState(() => _direction = next);
    // The toggle IS the per-source preference — no separate save step.
    sourceSettings.update(widget.booru, (s) => s.readingDirection = next);
  }

  void _snatch(List<BooruItem> items) {
    SnatchHandler.instance.queue(items, widget.booru, settingsHandler.snatchCooldown, false);
    FlashElements.showSnackbar(
      context: context,
      title: Text(items.length == 1 ? 'Saving page ${_current + 1}...' : 'Saving all ${items.length} pages...'),
      duration: const Duration(seconds: 2),
      sideColor: Colors.green,
    );
  }

  (IconData, String) get _directionIconLabel => switch (_direction) {
    'rtl' => (Symbols.format_textdirection_r_to_l_rounded, 'Right-to-left (manga) — tap to change'),
    'vertical' => (Symbols.swap_vert_rounded, 'Vertical — tap to change'),
    _ => (Symbols.format_textdirection_l_to_r_rounded, 'Left-to-right — tap to change'),
  };

  @override
  Widget build(BuildContext context) {
    final int count = widget.pages.length;
    final (IconData dirIcon, String dirLabel) = _directionIconLabel;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: Colors.black38,
              elevation: 0,
              titleSpacing: 0,
              title: Text(
                widget.title.isNotEmpty ? widget.title : 'Reader',
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: dirLabel,
                  icon: Icon(dirIcon),
                  onPressed: _cycleDirection,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Symbols.more_vert_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'save-page':
                        _snatch([widget.pages[_current]]);
                      case 'save-all':
                        _snatch(widget.pages);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'save-page', child: Text('Save this page')),
                    PopupMenuItem(value: 'save-all', child: Text('Save all pages')),
                  ],
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Symbols.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            )
          : null,
      // Same scope wrapper as the main viewer: lets PhotoView's pan (while
      // zoomed) and the PageView's swipe negotiate instead of fighting.
      body: PhotoViewGestureDetectorScope(
        axis: Axis.values,
        child: PreloadPageView.builder(
          controller: _controller,
          reverse: _rtl,
          scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
          preloadPagesCount: sourceSettings.preloadPages(widget.booru),
          itemCount: count,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            return _ReaderPageSlide(
              key: ValueKey('reader-page-${widget.galleryId}-$index'),
              item: widget.pages[index],
              booru: widget.booru,
              pageNumber: index + 1,
              onTapUp: _onTapUp,
            );
          },
        ),
      ),
      bottomNavigationBar: !_chromeVisible
          ? null
          : ColoredBox(
              color: Colors.black38,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Text(
                      '${_current + 1} / $count',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Expanded(
                      child: count > 1
                          ? Directionality(
                              // The slider runs in reading order too.
                              textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                              child: Slider(
                                value: (_current + 1).toDouble(),
                                min: 1,
                                max: count.toDouble(),
                                divisions: count - 1,
                                label: '${_current + 1}',
                                onChanged: (value) => _controller.jumpToPage(value.round() - 1),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One page: zoomable image with explicit loading progress and an on-page
/// error message + retry. Headers match what the grid thumbnails send, so a
/// page can never fail for header reasons the thumbs don't share.
class _ReaderPageSlide extends StatefulWidget {
  const _ReaderPageSlide({
    required this.item,
    required this.booru,
    required this.pageNumber,
    required this.onTapUp,
    super.key,
  });

  final BooruItem item;
  final Booru booru;
  final int pageNumber;
  final void Function(BuildContext, TapUpDetails, PhotoViewControllerValue) onTapUp;

  @override
  State<_ReaderPageSlide> createState() => _ReaderPageSlideState();
}

class _ReaderPageSlideState extends State<_ReaderPageSlide> {
  CustomNetworkImage? _provider;
  CancelToken? _cancelToken;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _initProvider();
  }

  Future<void> _initProvider() async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final headers = await Tools.getFileCustomHeaders(
      widget.booru,
      item: widget.item,
      checkForReferer: true,
    );
    if (!mounted) return;
    setState(() {
      _error = null;
      _provider = CustomNetworkImage(
        widget.item.fileURL,
        headers: headers,
        cancelToken: _cancelToken,
        withCache: SettingsHandler.instance.mediaCache,
        cacheFolder: 'media',
        fileNameExtras: widget.item.fileNameExtras,
        onError: (e) {
          Logger.Inst().log(
            'reader page ${widget.pageNumber} failed: $e url=${widget.item.fileURL}',
            '_ReaderPageSlide',
            'onError',
            LogTypes.imageLoadingError,
          );
          if (mounted) setState(() => _error = e);
        },
      );
    });
  }

  Future<void> _retry() async {
    final provider = _provider;
    if (provider != null) await provider.evict();
    _epoch++;
    await _initProvider();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page ${widget.pageNumber} failed to load',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.item.fileURL}\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Symbols.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return PhotoView(
      key: ValueKey('reader-photo-$_epoch'),
      imageProvider: _provider,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 8,
      initialScale: PhotoViewComputedScale.contained,
      basePosition: Alignment.center,
      onTapUp: widget.onTapUp,
      loadingBuilder: (context, event) {
        final double? progress = (event == null || (event.expectedTotalBytes ?? 0) == 0)
            ? null
            : event.cumulativeBytesLoaded / event.expectedTotalBytes!;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(value: progress),
              ),
              const SizedBox(height: 10),
              Text(
                'Page ${widget.pageNumber}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // PhotoView's own decode-level failures land here (provider-level
        // ones go through onError above) — same presentation.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _error == null) setState(() => _error = error);
        });
        return const SizedBox.shrink();
      },
    );
  }
}

/// Opens the reader for [item]'s registered book, resuming saved progress.
///
/// Registered with [ViewerHandler] as a nested viewer, exactly like the
/// tag-preview and post-files overlays — that keeps the parent viewer's
/// player paused (maxActiveViewers doubles as the pause mechanism).
Future<void> openDoujinReader(
  BuildContext context, {
  required BooruItem item,
  required Booru booru,
  // Jump straight to this page (Pages grid), ignoring saved progress.
  int? startAt,
}) async {
  final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
  if (pages == null || pages.isEmpty) return;

  final String galleryId = item.serverId ?? item.postURL;
  final ReaderProgress? progress = await ReaderHandler.instance.loadProgress(booru, galleryId);
  // A finished book starts over; an unfinished one resumes.
  final int initialPage = startAt ?? ((progress != null && !progress.isFinished) ? progress.page : 0);

  final String title = (item.description ?? '').split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');

  if (!context.mounted) return;
  final GlobalKey viewerKey = GlobalKey(debugLabel: 'viewer-doujin-reader');
  ViewerHandler.instance.addViewer(viewerKey);
  try {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => DoujinReaderPage(
          key: viewerKey,
          pages: pages,
          booru: booru,
          galleryId: galleryId,
          title: title,
          initialPage: initialPage,
        ),
      ),
    );
  } finally {
    ViewerHandler.instance.removeViewer(viewerKey);
  }
}
