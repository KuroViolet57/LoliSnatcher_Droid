import 'dart:async';
import 'dart:math';

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
/// Renders with a full-screen-filling video surface and a custom controls
/// overlay that mirrors the native LoliControls UX: tap to toggle controls,
/// double-tap left/right to seek, double-tap centre to play/pause, a bottom
/// bar with play/pause + position/duration + scrubber + mute + fullscreen.
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
  double? _windowedRatio;
  bool _wasFullScreen = false;

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
      // Use our own overlay rather than better_player's material controls.
      playerTheme: BetterPlayerTheme.custom,
      customControlsBuilder: (controller, onVisibilityChanged, cfg) {
        return _BetterControls(
          controller: controller,
          onVisibilityChanged: onVisibilityChanged,
        );
      },
    );

    final config = BetterPlayerConfiguration(
      autoPlay: widget.isViewed && settings.autoPlayEnabled,
      looping: true,
      allowedScreenSleep: false,
      // Letterbox the video inside whatever box we're given (we make the box
      // fill the screen below via setOverriddenAspectRatio).
      fit: BoxFit.contain,
      expandToFill: true,
      handleLifecycle: true,
      autoDispose: false,
      // In fullscreen, size the player to the actual video aspect ratio so it
      // fills the rotated screen.
      autoDetectFullscreenAspectRatio: true,
      autoDetectFullscreenDeviceOrientation: true,
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

    // Apply the screen-filling box ratio BEFORE the first build so the loading
    // surface already covers the screen — no "small black box then snap to
    // full res" when the first frame arrives.
    final size = MediaQuery.sizeOf(context);
    _windowedRatio = size.height == 0 ? 16 / 9 : size.width / size.height;
    controller.setOverriddenAspectRatio(_windowedRatio!);

    // Re-assert the windowed box ratio when returning from fullscreen —
    // otherwise the player snaps back to its default tiny 16:9 box.
    controller.addEventsListener(_onPlayerEvent);

    setState(() {
      _controller = controller;
    });
    if (settings.startVideosMuted) {
      await controller.setVolume(0);
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (event.betterPlayerEventType == BetterPlayerEventType.hideFullscreen) {
      final controller = _controller;
      final ratio = _windowedRatio;
      if (controller != null && ratio != null) {
        // Defer one frame so the windowed route is back in the tree.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !controller.isFullScreen) {
            controller.setOverriddenAspectRatio(ratio);
          }
        });
      }
    }
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    _windowedRatio = null;
    _wasFullScreen = false;
    c?.removeEventsListener(_onPlayerEvent);
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
    if (controller == null) {
      return const Material(color: Colors.black, child: SizedBox.expand());
    }

    // Keep the windowed box ratio matched to the screen (handles orientation
    // changes and re-asserts after a fullscreen round-trip). better_player
    // lays its surface out inside an AspectRatio sized by getAspectRatio();
    // overriding it to the screen ratio + fit:contain is what fills the
    // screen — exactly like the native player.
    final bool isFs = controller.isFullScreen;
    if (!isFs) {
      final size = MediaQuery.sizeOf(context);
      final double screenRatio = size.height == 0 ? 16 / 9 : size.width / size.height;
      final bool justExitedFs = _wasFullScreen;
      if (_windowedRatio == null ||
          (_windowedRatio! - screenRatio).abs() > 0.001 ||
          justExitedFs) {
        _windowedRatio = screenRatio;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !controller.isFullScreen) {
            controller.setOverriddenAspectRatio(screenRatio);
          }
        });
      }
    }
    _wasFullScreen = isFs;

    return Material(
      color: Colors.black,
      child: SizedBox.expand(
        child: BetterPlayer(controller: controller),
      ),
    );
  }
}

/// Native-LoliControls-style overlay rendered on top of the better_player
/// surface (in both windowed and fullscreen modes via customControlsBuilder).
class _BetterControls extends StatefulWidget {
  const _BetterControls({
    required this.controller,
    required this.onVisibilityChanged,
  });

  final BetterPlayerController controller;
  final void Function(bool visible) onVisibilityChanged;

  @override
  State<_BetterControls> createState() => _BetterControlsState();
}

class _BetterControlsState extends State<_BetterControls> {
  BetterPlayerController get _bpc => widget.controller;

  bool _hidden = false;
  bool _dragging = false;

  // Double-tap seek feedback.
  TapDownDetails? _doubleTapInfo;
  int _lastSide = 0; // -1 left, 1 right
  int _lastSkipSeconds = 0;
  bool _showSeekFeedback = false;
  Timer? _hideTimer;
  Timer? _seekFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _bpc.videoPlayerController?.addListener(_onValue);
    _startHideTimer();
  }

  @override
  void didUpdateWidget(covariant _BetterControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.videoPlayerController?.removeListener(_onValue);
      _bpc.videoPlayerController?.addListener(_onValue);
    }
  }

  @override
  void dispose() {
    _bpc.videoPlayerController?.removeListener(_onValue);
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    super.dispose();
  }

  void _onValue() {
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _hidden = true);
      widget.onVisibilityChanged(false);
    });
  }

  void _toggleControls() {
    setState(() => _hidden = !_hidden);
    widget.onVisibilityChanged(!_hidden);
    if (!_hidden) _startHideTimer();
  }

  void _wake() {
    if (_hidden) {
      setState(() => _hidden = false);
      widget.onVisibilityChanged(true);
    }
    _startHideTimer();
  }

  bool get _isInitialized => _bpc.videoPlayerController?.value.initialized ?? false;
  bool get _isPlaying => _bpc.videoPlayerController?.value.isPlaying ?? false;
  bool get _isBuffering => _bpc.videoPlayerController?.value.isBuffering ?? false;
  Duration get _position => _bpc.videoPlayerController?.value.position ?? Duration.zero;
  Duration get _duration => _bpc.videoPlayerController?.value.duration ?? Duration.zero;

  double get _bufferedFraction {
    final v = _bpc.videoPlayerController?.value;
    if (v == null || v.duration == null || v.duration!.inMilliseconds == 0) return 0;
    if (v.buffered.isEmpty) return 0;
    final end = v.buffered.last.end.inMilliseconds;
    return (end / v.duration!.inMilliseconds).clamp(0.0, 1.0);
  }

  void _playPause() {
    if (_isPlaying) {
      _bpc.pause();
    } else {
      _bpc.play();
    }
    _wake();
  }

  // Skip amount scales with length so short clips don't jump too far.
  // Always >= 5 s for anything longer than a few seconds (per request).
  int _skipSecondsFor(int durationSec) {
    if (durationSec <= 5) return 0;
    if (durationSec <= 30) return 5;
    return 10;
  }

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapInfo = d;

  void _onDoubleTap() {
    if (!_isInitialized || _doubleTapInfo == null) return;
    final double width = MediaQuery.sizeOf(context).width;
    final double mid = width / 2;
    final double sideZone = width / 6;
    final double dx = _doubleTapInfo!.localPosition.dx;

    int side;
    if (dx > mid + sideZone) {
      side = 1;
    } else if (dx < mid - sideZone) {
      side = -1;
    } else {
      side = 0;
    }

    if (side == 0) {
      _playPause();
      return;
    }

    final int durSec = _duration.inSeconds;
    final int skip = _skipSecondsFor(durSec);
    if (skip == 0) {
      _playPause();
      return;
    }

    final int posMs = _position.inMilliseconds;
    final int durMs = _duration.inMilliseconds;
    final int target = min(max(0, posMs + skip * 1000 * side), durMs);
    _bpc.seekTo(Duration(milliseconds: target));

    setState(() {
      _lastSide = side;
      _lastSkipSeconds = skip;
      _showSeekFeedback = true;
    });
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showSeekFeedback = false);
    });
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.secondary;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gesture layer covering the whole surface.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
        ),

        // Buffering spinner.
        if (_isBuffering && !_dragging)
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
          ),

        // Double-tap seek feedback.
        if (_showSeekFeedback)
          Align(
            alignment: _lastSide < 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: _SeekFeedback(side: _lastSide, seconds: _lastSkipSeconds),
            ),
          ),

        // Center play/pause indicator when controls visible.
        if (!_hidden)
          Center(
            child: AnimatedOpacity(
              opacity: _isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _playPause,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
                ),
              ),
            ),
          ),

        // Bottom control bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _hidden ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: _hidden,
              child: _buildBottomBar(accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(Color accent) {
    final double volume = _bpc.videoPlayerController?.value.volume ?? 1.0;
    final bool muted = volume == 0;

    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _ProgressBar(
                position: _position,
                duration: _duration,
                bufferedFraction: _bufferedFraction,
                accent: accent,
                onDragStart: () => setState(() => _dragging = true),
                onDragUpdate: (frac) {
                  final ms = (_duration.inMilliseconds * frac).round();
                  _bpc.seekTo(Duration(milliseconds: ms));
                  _wake();
                },
                onDragEnd: () => setState(() => _dragging = false),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: _playPause,
                ),
                Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                  onPressed: () {
                    _bpc.setVolume(muted ? 1.0 : 0.0);
                    _wake();
                  },
                ),
                IconButton(
                  icon: Icon(
                    _bpc.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _bpc.toggleFullScreen();
                    _wake();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}

class _SeekFeedback extends StatelessWidget {
  const _SeekFeedback({required this.side, required this.seconds});

  final int side;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.black45,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              side < 0 ? Icons.fast_rewind : Icons.fast_forward,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              '${seconds}s',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple draggable progress bar: background track, buffered range, played
/// range and a draggable handle. Reports drag fraction back to the parent.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.bufferedFraction,
    required this.accent,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Duration position;
  final Duration duration;
  final double bufferedFraction;
  final Color accent;
  final VoidCallback onDragStart;
  final void Function(double fraction) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragFraction;

  double get _playedFraction {
    if (_dragFraction != null) return _dragFraction!;
    final durMs = widget.duration.inMilliseconds;
    if (durMs == 0) return 0;
    return (widget.position.inMilliseconds / durMs).clamp(0.0, 1.0);
  }

  void _seekToLocal(double dx, double width) {
    final frac = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragFraction = frac);
    widget.onDragUpdate(frac);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            widget.onDragStart();
            _seekToLocal(d.localPosition.dx, width);
          },
          onHorizontalDragUpdate: (d) => _seekToLocal(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) {
            widget.onDragEnd();
            setState(() => _dragFraction = null);
          },
          onTapDown: (d) {
            widget.onDragStart();
            _seekToLocal(d.localPosition.dx, width);
          },
          onTapUp: (_) {
            widget.onDragEnd();
            setState(() => _dragFraction = null);
          },
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track.
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Buffered.
                FractionallySizedBox(
                  widthFactor: widget.bufferedFraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Played.
                FractionallySizedBox(
                  widthFactor: _playedFraction,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Handle.
                Align(
                  alignment: Alignment(_playedFraction * 2 - 1, 0),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
