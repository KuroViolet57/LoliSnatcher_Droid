import 'package:flutter/widgets.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';

/// Wraps one page tile (the detail page's grid, the reader's filmstrip) and
/// asks the source for the page's own thumbnail when the tile appears.
///
/// e-hentai serves page thumbnails a block at a time, as sprite strips, so a
/// page past the first block shows its gallery's cover until its block is
/// read. When the answer changes what the page shows, the tile rebuilds;
/// leaving the screen withdraws the request before it is sent. Sources with
/// nothing to add answer at once and nothing happens.
class PageThumbnailLoader extends StatefulWidget {
  const PageThumbnailLoader({
    required this.page,
    required this.handler,
    required this.builder,
    super.key,
  });

  final BooruItem page;
  final BooruHandler? handler;
  final WidgetBuilder builder;

  @override
  State<PageThumbnailLoader> createState() => _PageThumbnailLoaderState();
}

class _PageThumbnailLoaderState extends State<PageThumbnailLoader> {
  CancelToken? _interest;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(PageThumbnailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A list cell reused for another page asks for that page instead.
    if (!identical(oldWidget.page, widget.page) || oldWidget.handler != widget.handler) {
      _interest?.cancel();
      _ask();
    }
  }

  void _ask() {
    final BooruHandler? handler = widget.handler;
    if (handler == null) return;
    final BooruItem page = widget.page;
    final String before = page.displayThumbnailURL;
    final CancelToken interest = CancelToken();
    _interest = interest;
    handler.ensurePageThumbnail(page, cancelToken: interest).then((_) {
      if (!mounted || interest.isCancelled || !identical(widget.page, page)) return;
      if (page.displayThumbnailURL != before) setState(() {});
    });
  }

  @override
  void dispose() {
    _interest?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
