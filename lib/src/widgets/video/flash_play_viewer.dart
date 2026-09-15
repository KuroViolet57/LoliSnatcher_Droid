import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/pages/flash_player_page.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

/// A Flash post in the viewer (r48): its thumbnail and a Play button that
/// opens the in-app Flash player (Ruffle). Before, the viewer loaded the post
/// behind a loading card and then tried to guess a video or image type,
/// ending on "Failed to guess the file extension", although the top bar
/// already knew it was Flash. The post page is still read in the background
/// (tags for the details page, the real file for a download); the viewer's
/// details stay one swipe away.
class FlashPlayViewer extends StatefulWidget {
  const FlashPlayViewer({
    required this.item,
    required this.handler,
    this.loadInBackground = true,
    this.background,
    super.key,
  });

  final BooruItem item;
  final BooruHandler handler;

  /// Read the post page quietly when the file is not known yet.
  final bool loadInBackground;

  /// Behind the button; the item's thumbnail when null.
  final Widget? background;

  /// The viewer shows this instead of loading and guessing: a Flash post (its
  /// listing or its file says so) that is not already a picture or a video.
  static bool shouldShow(BooruItem item) {
    final MediaType type = item.mediaType.value;
    if (type.isImageOrAnimation || type.isVideo) return false;
    return FlashPlayerPage.isFlash(item);
  }

  @override
  State<FlashPlayViewer> createState() => _FlashPlayViewerState();
}

class _FlashPlayViewerState extends State<FlashPlayViewer> {
  CancelToken? _cancel;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadInBackground && widget.handler.hasLoadItemSupport && !FlashPlayerPage.isFlashUrl(widget.item.fileURL)) {
      _cancel = CancelToken();
      widget.handler.loadItem(item: widget.item, cancelToken: _cancel).ignore();
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await FlashPlayerPage.openFor(context, widget.handler, widget.item);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.background ?? Thumbnail(item: widget.item, booru: widget.handler.booru, isStandalone: false),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.extension_rounded, size: 28, color: Colors.white70),
                const SizedBox(height: 4),
                const Text(
                  'Flash',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('flash-play'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _opening ? null : _play,
                  icon: _opening
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Symbols.play_arrow_rounded, size: 30, fill: 1),
                  label: const Text('Play'),
                ),
                const SizedBox(height: 8),
                Text('Plays in the app through Ruffle', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                TextButton.icon(
                  onPressed: () => launchUrlString(widget.item.postURL, mode: LaunchMode.externalApplication),
                  icon: const Icon(Symbols.public_rounded, size: 18),
                  label: const Text('Open post in browser'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
