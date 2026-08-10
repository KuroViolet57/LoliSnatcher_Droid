import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/video/better_player_view.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer_placeholder.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';

/// Carousel of every file belonging to one post.
///
/// Opened on top of the main viewer for sites where a post is a gallery (see
/// [PostFilesHandler]). It is a NESTED viewer, not a lightweight carousel:
/// its key is registered with [ViewerHandler] exactly like the tag-preview and
/// waterfall paths do, so pinch zoom, double-tap zoom, mute state, appbar
/// visibility and the video players' saved-position / manual-pause behaviour
/// all work here unchanged.
class PostFilesPage extends StatefulWidget {
  const PostFilesPage({
    required this.items,
    required this.booru,
    this.initialIndex = 0,
    super.key,
  });

  /// One item per file, built by PostFilesHandler.itemsFor.
  final List<BooruItem> items;
  final Booru booru;
  final int initialIndex;

  @override
  State<PostFilesPage> createState() => _PostFilesPageState();
}

class _PostFilesPageState extends State<PostFilesPage> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black38,
        elevation: 0,
        title: Text(
          '${_current + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Symbols.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (page) => setState(() => _current = page),
        itemBuilder: (context, index) {
          final BooruItem item = widget.items[index];
          // Only the visible slide is "viewed": the players key their
          // acquire/release on this, so preloading is deliberately NOT done
          // here — the parent viewer already holds a player and the media_kit
          // pool defaults to 4. One live player in the overlay keeps us well
          // inside it instead of thrashing the pool.
          return _PostFileSlide(
            item: item,
            booru: widget.booru,
            isViewed: index == _current,
          );
        },
      ),
    );
  }
}

/// Picks the same widget the main viewer would for this item.
///
/// Deliberately mirrors gallery_view_page's selection (media_kit first when
/// enabled, then better_player, then chewie, image otherwise) so a video slide
/// runs through the very same player implementation, with its pool, saved
/// positions and pause behaviour.
class _PostFileSlide extends StatelessWidget {
  const _PostFileSlide({
    required this.item,
    required this.booru,
    required this.isViewed,
  });

  final BooruItem item;
  final Booru booru;
  final bool isViewed;

  @override
  Widget build(BuildContext context) {
    final settingsHandler = SettingsHandler.instance;

    if (item.mediaType.value.isVideo) {
      final bool canPlay = !settingsHandler.disableVideo &&
          (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux);
      if (!canPlay) {
        return VideoViewerPlaceholder(item: item, booru: booru, key: item.key);
      }
      if (settingsHandler.useMediaKitPlayer && Platform.isAndroid) {
        return MediaKitPlayerView(item, booru: booru, isViewed: isViewed, key: item.key);
      }
      if (settingsHandler.useBetterPlayer && Platform.isAndroid) {
        return BetterPlayerView(item, booru: booru, isViewed: isViewed, key: item.key);
      }
      return VideoViewer(
        item,
        booru: booru,
        isViewed: isViewed,
        enableFullscreen: true,
        key: item.key,
      );
    }

    return ImageViewer(item, booru: booru, isViewed: isViewed, key: item.key);
  }
}

/// Opens the overlay for [items], registering it as a nested viewer.
Future<void> openPostFilesOverlay(
  BuildContext context, {
  required List<BooruItem> items,
  required Booru booru,
}) async {
  final GlobalKey viewerKey = GlobalKey(debugLabel: 'viewer-post-files');
  ViewerHandler.instance.addViewer(viewerKey);
  try {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => PostFilesPage(
          key: viewerKey,
          items: items,
          booru: booru,
        ),
      ),
    );
  } finally {
    ViewerHandler.instance.removeViewer(viewerKey);
  }
}
