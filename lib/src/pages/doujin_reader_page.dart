import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';
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
/// LAYOUT CONTRACT — this page has shipped broken twice, so the rules its
/// structure follows are spelled out:
///
///  * It is pushed as an ordinary OPAQUE [MaterialPageRoute] — the same
///    route type the comments page uses from the same drawer — never a
///    transparent PageRouteBuilder. Field recordings of the transparent
///    version showed the page's chrome half-height with other routes' UI
///    interleaved; opaque removes the entire class.
///  * NO Scaffold slots. The chrome is a [Stack]: the page view fills the
///    stack, the top bar is Positioned(top: 0), the bottom bar is
///    Positioned(bottom: 0). Nothing (keyboard insets, sheet extents,
///    Scaffold slot behaviour) can float them mid-screen, and
///    resizeToAvoidBottomInset is false so view insets are ignored outright.
///  * The page view is wrapped in [ClipRect]. PhotoView paints — and hit
///    tests — outside its bounds when unclipped, which is how the previous
///    build's images covered the whole screen while its buttons went dead.
///  * Tap zones live on their OWN transparent layer above the page view and
///    below the chrome, so they keep working while a page is still loading
///    or failed — PhotoView keeps pinch/pan/double-tap-zoom only.
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

  /// Test hook: lets widget tests substitute a working in-memory image so a
  /// LIVE zoomable page is on screen while chrome/input is exercised —
  /// otherwise every slide settles into its error state under test and the
  /// clipping/zoom layers guard nothing.
  static ImageProvider Function(BooruItem item)? testImageProviderBuilder;

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
    // Both directions on purpose: the gallery below disables sleep for its
    // own lifetime, so honouring keepScreenOn=false here means actively
    // re-enabling, and restoring the disable on dispose.
    try {
      if (sourceSettings.keepScreenOn(widget.booru)) {
        ServiceHandler.disableSleep();
      } else {
        ServiceHandler.enableSleep();
      }
    } catch (_) {}
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
    _pendingTapTimer?.cancel();
    _controller.dispose();
    try {
      // The gallery viewer below expects sleep disabled while it is open.
      ServiceHandler.disableSleep();
    } catch (_) {}
    super.dispose();
  }

  /// Where a page-turn in flight is headed. Rapid tap-tap paging arrives
  /// FASTER than onPageChanged, so chaining turns off [_current] alone
  /// swallows every second tap — turns chain off this instead.
  int? _turnTarget;

  void _onPageChanged(int page) {
    setState(() => _current = page);
    if (_turnTarget == page) _turnTarget = null;
    ReaderHandler.instance.saveProgress(widget.booru, widget.galleryId, page, widget.pages.length);
  }

  int get _effectivePage => _turnTarget ?? _current;

  void _goTo(int page) {
    final int target = page.clamp(0, widget.pages.length - 1);
    if (target == _effectivePage) return;
    _turnTarget = target;
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

  // ── raw-pointer tap zones ──────────────────────────────────────────────
  // A GestureDetector tap loses the arena to the PageView's scrollable the
  // moment a page-turn animation is in flight (the scrollable claims the
  // pointer to interrupt the animation) — which drops every second tap of
  // rapid tap-tap paging. Raw pointer events are not arena-gated, so taps
  // are detected manually: single pointer, short, and no movement.
  Offset? _tapDownPosition;
  int _tapDownTime = 0;
  int _activePointers = 0;
  Timer? _pendingTapTimer;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _tapDownPosition = event.position;
      _tapDownTime = DateTime.now().millisecondsSinceEpoch;
    } else {
      // Second finger = pinch, not a tap.
      _tapDownPosition = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    final Offset? down = _tapDownPosition;
    _tapDownPosition = null;
    if (down == null) return;
    final int elapsed = DateTime.now().millisecondsSinceEpoch - _tapDownTime;
    if (elapsed > 260 || (event.position - down).distance > 18) return;

    if (sourceSettings.doubleTapZoom(widget.booru)) {
      // Double-tap zoom is on: hold single taps for the double-tap window
      // so a double-tap zooms instead of turning two pages.
      if (_pendingTapTimer?.isActive ?? false) {
        _pendingTapTimer!.cancel();
        return; // second tap of a double-tap — the slide's zoom handles it
      }
      final Offset position = event.position;
      _pendingTapTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted) _handleTap(position);
      });
      return;
    }
    _handleTap(event.position);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    _tapDownPosition = null;
  }

  /// Edge taps turn pages (respecting reading direction), middle taps toggle
  /// the chrome. Works regardless of whether the page under it is showing,
  /// loading, failed, or mid page-turn animation.
  void _handleTap(Offset position) {
    final Size size = MediaQuery.sizeOf(context);
    if (!sourceSettings.tapZones(widget.booru)) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    if (_vertical) {
      final double dy = position.dy / size.height;
      if (dy < 0.25) {
        _goTo(_effectivePage - 1);
      } else if (dy > 0.75) {
        _goTo(_effectivePage + 1);
      } else {
        setState(() => _chromeVisible = !_chromeVisible);
      }
      return;
    }
    final double dx = position.dx / size.width;
    if (dx < 0.3) {
      _goTo(_rtl ? _effectivePage + 1 : _effectivePage - 1);
    } else if (dx > 0.7) {
      _goTo(_rtl ? _effectivePage - 1 : _effectivePage + 1);
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

  Widget _topBar(BuildContext context) {
    final (IconData dirIcon, String dirLabel) = _directionIconLabel;
    return GestureDetector(
      // Absorb taps anywhere on the bar (including spacer gaps and the
      // status-bar strip) so they never fall through to the tap zones.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Material(
      key: const ValueKey('reader-top-bar'),
      color: Colors.black.withValues(alpha: 0.62),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Symbols.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  widget.title.isNotEmpty ? widget.title : 'Reader',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const ValueKey('reader-direction-button'),
                tooltip: dirLabel,
                icon: Icon(dirIcon, color: Colors.white),
                onPressed: _cycleDirection,
              ),
              PopupMenuButton<String>(
                key: const ValueKey('reader-menu-button'),
                icon: const Icon(Symbols.more_vert_rounded, color: Colors.white),
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
                key: const ValueKey('reader-close-button'),
                tooltip: 'Close',
                icon: const Icon(Symbols.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final int count = widget.pages.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Material(
      key: const ValueKey('reader-bottom-bar'),
      color: Colors.black.withValues(alpha: 0.62),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Insets must never move the chrome — the bars are Positioned, and the
      // body ignores the keyboard/IME area entirely.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Pages. Clipped: PhotoView paints and hit-tests outside its
          // bounds when left unclipped.
          ClipRect(
            child: PreloadPageView.builder(
              controller: _controller,
              reverse: _rtl,
              scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
              preloadPagesCount: sourceSettings.preloadPages(widget.booru),
              itemCount: widget.pages.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                return _ReaderPageSlide(
                  key: ValueKey('reader-page-${widget.galleryId}-$index'),
                  item: widget.pages[index],
                  booru: widget.booru,
                  pageNumber: index + 1,
                  doubleTapZoom: sourceSettings.doubleTapZoom(widget.booru),
                );
              },
            ),
          ),
          // Tap zones: raw pointer events (see _onPointerDown) — never in
          // any gesture arena, so pinch/pan/swipe pass through untouched
          // and taps still land mid page-turn animation.
          Positioned.fill(
            child: Listener(
              key: const ValueKey('reader-tap-zones'),
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
            ),
          ),
          if (_chromeVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _topBar(context),
            ),
          if (_chromeVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _bottomBar(context),
            ),
        ],
      ),
    );
  }
}

/// One page: zoomable image with explicit loading progress and an on-page
/// error message + retry.
///
/// Zoom is a stock [InteractiveViewer] — no photo_view: its fork
/// unconditionally registers a double-tap zoom recognizer, which delays
/// every single tap by the double-tap window and turns rapid tap-tap paging
/// into a zoom. Double-tap zoom here is opt-in per source; pinch always
/// works. The viewer claims drags only while zoomed in, so page swipes
/// reach the PageView at rest.
class _ReaderPageSlide extends StatefulWidget {
  const _ReaderPageSlide({
    required this.item,
    required this.booru,
    required this.pageNumber,
    required this.doubleTapZoom,
    super.key,
  });

  final BooruItem item;
  final Booru booru;
  final int pageNumber;
  final bool doubleTapZoom;

  @override
  State<_ReaderPageSlide> createState() => _ReaderPageSlideState();
}

class _ReaderPageSlideState extends State<_ReaderPageSlide> {
  ImageProvider? _provider;
  CancelToken? _cancelToken;
  Object? _error;

  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  TapDownDetails? _lastDoubleTapDown;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    _initProvider();
  }

  void _onTransformChanged() {
    final bool zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      // panEnabled flips with this: at rest the viewer must not claim drags
      // or the PageView never receives swipes.
      setState(() => _zoomed = zoomed);
    }
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
      _provider =
          DoujinReaderPage.testImageProviderBuilder?.call(widget.item) ??
          CustomNetworkImage(
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
    await _initProvider();
  }

  void _toggleDoubleTapZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    final Offset position = _lastDoubleTapDown?.localPosition ?? Offset.zero;
    const double scale = 2.5;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-position.dx * (scale - 1), -position.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
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

    Widget viewer = InteractiveViewer(
      transformationController: _transform,
      maxScale: 8,
      // Claim drags only while zoomed; at rest the PageView owns them.
      panEnabled: _zoomed,
      clipBehavior: Clip.hardEdge,
      child: Center(
        child: Image(
          image: _provider!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            final double? value = (progress.expectedTotalBytes ?? 0) == 0
                ? null
                : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 42, height: 42, child: CircularProgressIndicator(value: value)),
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _error == null) setState(() => _error = error);
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    if (widget.doubleTapZoom) {
      // Opt-in: this recognizer is exactly what delays single taps, so it
      // only exists when the user asked for it.
      viewer = GestureDetector(
        onDoubleTapDown: (details) => _lastDoubleTapDown = details,
        onDoubleTap: _toggleDoubleTapZoom,
        child: viewer,
      );
    }

    return ClipRect(child: viewer);
  }
}

/// Opens the reader for [item]'s registered book, resuming saved progress.
///
/// Pushed as an ordinary opaque [MaterialPageRoute] — see the layout
/// contract on [DoujinReaderPage]. Registered with [ViewerHandler] as a
/// nested viewer so the parent viewer's player stays paused
/// (maxActiveViewers doubles as the pause mechanism). Re-entrancy guarded:
/// a double-tap on a Read button must not stack two readers.
bool _readerOpening = false;

Future<void> openDoujinReader(
  BuildContext context, {
  required BooruItem item,
  required Booru booru,
  // Jump straight to this page (Pages grid), ignoring saved progress.
  int? startAt,
}) async {
  if (_readerOpening) return;
  _readerOpening = true;
  try {
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
        MaterialPageRoute(
          builder: (_) => DoujinReaderPage(
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
  } finally {
    _readerOpening = false;
  }
}
