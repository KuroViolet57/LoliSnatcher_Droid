import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:preload_page_view/preload_page_view.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';

/// The doujin reader: ordered pages of one gallery, read like a book.
///
/// This is NOT the multi-file carousel (PostFilesPage) — a book needs a
/// position you can come back to, a way to jump, and a reading direction.
/// Each page runs through the same [ImageViewer] as the main viewer, so
/// pinch/double-tap zoom and the media cache behave identically, and the
/// page slot is a [PreloadPageView] with the user's own preload setting so
/// the next pages are already loading while the current one is read.
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

  /// Right-to-left reading, the native direction for most manga. Remembered
  /// for the app session — flipping it once per book would get old fast.
  static bool rtl = false;

  late final PreloadPageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage.clamp(0, widget.pages.length - 1);
    _controller = PreloadPageController(initialPage: _current);
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

  void _jumpTo(int page) {
    _controller.jumpToPage(page.clamp(0, widget.pages.length - 1));
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

  @override
  Widget build(BuildContext context) {
    final int count = widget.pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
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
            tooltip: rtl ? 'Right-to-left (manga) — tap for left-to-right' : 'Left-to-right — tap for right-to-left (manga)',
            icon: Icon(rtl ? Symbols.format_textdirection_r_to_l_rounded : Symbols.format_textdirection_l_to_r_rounded),
            onPressed: () => setState(() => rtl = !rtl),
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
      ),
      body: PreloadPageView.builder(
        controller: _controller,
        // reverse flips swipe direction AND page order together — exactly
        // what right-to-left reading is.
        reverse: rtl,
        preloadPagesCount: settingsHandler.preloadCount,
        itemCount: count,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final BooruItem item = widget.pages[index];
          return ImageViewer(
            item,
            booru: widget.booru,
            isViewed: index == _current,
            key: item.key,
          );
        },
      ),
      bottomNavigationBar: ColoredBox(
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
                        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                        child: Slider(
                          value: (_current + 1).toDouble(),
                          min: 1,
                          max: count.toDouble(),
                          divisions: count - 1,
                          label: '${_current + 1}',
                          onChanged: (value) => _jumpTo(value.round() - 1),
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

/// Opens the reader for [item]'s registered book, resuming saved progress.
///
/// Registered with [ViewerHandler] as a nested viewer, exactly like the
/// tag-preview and post-files overlays — that keeps the parent viewer's
/// player paused (maxActiveViewers doubles as the pause mechanism) and gives
/// this page normal zoom/appbar behaviour.
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
