import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Experimental alternative to `VideoViewer` backed by `better_player_plus`,
/// which exposes the ExoPlayer buffer/cache tuning that the stock Flutter
/// `video_player` plugin hides. Selected via SettingsHandler.useBetterPlayer.
///
/// Intentionally self-contained — does not register with ViewerHandler, so a
/// few power-user features (external zoom commands, long-tap fast-forward,
/// MPV fallback) don't apply here. That's the trade for an isolated, safe
/// engine swap behind a flag.
class BetterPlayerView extends StatefulWidget {
  const BetterPlayerView(
    this.booruItem, {
    required this.booru,
    required this.isViewed,
    super.key,
  });

  final BooruItem booruItem;
  final Booru booru;
  final bool isViewed;

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView> {
  BetterPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isViewed || SettingsHandler.instance.preloadVideos) {
      _init();
    }
  }

  @override
  void didUpdateWidget(covariant BetterPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool itemChanged = oldWidget.booruItem != widget.booruItem;
    if (itemChanged) {
      _disposeController();
      if (widget.isViewed || SettingsHandler.instance.preloadVideos) {
        _init();
      }
    } else if (oldWidget.isViewed != widget.isViewed) {
      if (widget.isViewed) {
        if (_controller == null) {
          _init();
        } else if (SettingsHandler.instance.autoPlayEnabled) {
          _controller?.play();
        }
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _init() async {
    final settings = SettingsHandler.instance;
    final headers = await Tools.getFileCustomHeaders(
      widget.booru,
      item: widget.booruItem,
      checkForReferer: true,
    );

    // Tuned for jittery mobile networks: start sooner (1.5 s buffered is
    // enough to begin), keep more in the buffer once we're going (60 s) so
    // a stall is rare, and require a beefy refill after a rebuffer (8 s) so
    // we don't enter a stall-buffer-stall ping-pong.
    const buffering = BetterPlayerBufferingConfiguration(
      minBufferMs: 30000,
      maxBufferMs: 60000,
      bufferForPlaybackMs: 1500,
      bufferForPlaybackAfterRebufferMs: 8000,
    );

    // Use ExoPlayer's built-in HTTP cache — same cache lives across the app,
    // so a partial re-watch / scrub doesn't re-hit the CDN.
    final cache = BetterPlayerCacheConfiguration(
      useCache: settings.mediaCache,
      maxCacheSize: 500 * 1024 * 1024,
      maxCacheFileSize: 100 * 1024 * 1024,
      preCacheSize: 3 * 1024 * 1024,
      key: widget.booruItem.fileURL,
    );

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.booruItem.fileURL,
      headers: headers,
      bufferingConfiguration: buffering,
      cacheConfiguration: cache,
    );

    final controlsConfig = BetterPlayerControlsConfiguration(
      enableSubtitles: false,
      enableQualities: false,
      enableAudioTracks: false,
      enablePip: false,
      enableRetry: true,
      enableFullscreen: true,
      enableMute: true,
      progressBarPlayedColor: Theme.of(context).colorScheme.secondary,
      progressBarHandleColor: Theme.of(context).colorScheme.secondary,
    );

    final config = BetterPlayerConfiguration(
      autoPlay: widget.isViewed && settings.autoPlayEnabled,
      looping: true,
      allowedScreenSleep: false,
      fit: BoxFit.contain,
      expandToFill: true,
      handleLifecycle: true,
      autoDispose: false,
      controlsConfiguration: controlsConfig,
      errorBuilder: (context, errorMessage) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            errorMessage ?? 'Playback error',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    final controller = BetterPlayerController(config, betterPlayerDataSource: dataSource);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
    });
    if (settings.startVideosMuted) {
      await controller.setVolume(0);
    }
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    c?.pause();
    c?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Material(
      color: Colors.black,
      child: Center(
        child: controller == null
            ? const SizedBox.expand()
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: BetterPlayer(controller: controller),
              ),
      ),
    );
  }
}
