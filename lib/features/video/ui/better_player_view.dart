import 'dart:async';
import 'dart:math';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/video/logic/video_completion_tracker.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/utils/tools.dart';

part 'better_player_view/player_pool.dart';
part 'better_player_view/controls.dart';

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

  /// Soft-refresh hook for the appbar reload button.
  static void resetPool() => _BetterPlayerPool.resetAll();

  final Booru booru;
  final bool isViewed;

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView> {
  BetterPlayerController? _controller;
  double? _windowedRatio;
  bool _wasFullScreen = false;

  // Android can only run a handful of hardware video decoders (MediaCodec)
  // at once. Each better_player controller holds one ExoPlayer decoder.
  // Without a global cap, fast scrolling spins up new decoders faster than
  // they release → MediaCodec exhaustion → the next video fails to load or
  // the app hard-crashes natively.
  //
  // Strategy:
  //   - Hard cap (`_BetterPlayerPool._maxAlive`) controllers alive across
  //     the whole app via `_BetterPlayerPool` (LRU-evicting force-dispose).
  //   - Pause-on-offscreen (not full dispose) so scrolling back to a recently
  //     viewed page is instant — the controller stays alive in the pool.
  //   - Debounce creation so pages the user is just swiping past don't each
  //     spin up a controller mid-flight.
  Timer? _initDebounce;
  static const Duration _initDelay = Duration(milliseconds: 250);

  // Position parked by a previous incarnation of this video (nested-viewer
  // cover) — applied once the fresh controller reports initialized.
  Duration? _pendingResumePosition;
  // The fileURL the live controller was created for — the key for the
  // position hand-off (widget.booruItem may already point at a different
  // item by the time the controller is torn down).
  String? _controllerUrl;

  bool get _wantsPlayer => widget.isViewed || SettingsHandler.instance.preloadVideos;

  @override
  void initState() {
    super.initState();
    if (_wantsPlayer) {
      _scheduleInit();
    }
  }

  @override
  void didUpdateWidget(covariant BetterPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool itemChanged = oldWidget.booruItem != widget.booruItem;
    if (itemChanged) {
      _disposeController();
      if (_wantsPlayer) {
        _scheduleInit();
      }
    } else if (oldWidget.isViewed != widget.isViewed) {
      if (widget.isViewed) {
        if (_controller == null) {
          _scheduleInit();
        } else {
          // Already-alive controller is back on-screen — make sure the pool
          // knows it's the most-recently-used so it isn't the next to evict.
          _BetterPlayerPool.touch(this);
          if (SettingsHandler.instance.autoPlayEnabled &&
              !(SettingsHandler.instance.respectManualPause &&
                  ViewerHandler.instance.isManuallyPaused(widget.booruItem.fileURL))) {
            _controller?.play();
          }
        }
      } else {
        // Page scrolled off-screen: pause (don't dispose). The pool will
        // force-dispose the least-recently-used controller when the cap is
        // hit, so the decoder count stays bounded but recent ones survive
        // for instant scroll-back.
        _controller?.pause();
      }
    }
  }

  void _scheduleInit() {
    _initDebounce?.cancel();
    _initDebounce = Timer(_initDelay, () {
      if (!mounted || !_wantsPlayer || _controller != null) return;
      _init();
    });
  }

  /// Called by [_BetterPlayerPool] when it needs to evict this view's
  /// controller to free a decoder slot. Tears down the controller without
  /// killing the widget itself; the widget will be allowed to re-init if it
  /// later becomes the active page again.
  void _forceDisposeFromPool() {
    if (!mounted) return;
    Logger.Inst().log(
      'pool-evicted, force-disposing controller for ${widget.booruItem.fileURL}',
      'BetterPlayerView',
      '_forceDisposeFromPool',
      LogTypes.booruItemLoad,
    );
    _disposeControllerInternal(unregister: false);
    setState(() {});
  }

  Future<void> _init() async {
    Logger.Inst().log(
      'init for ${widget.booruItem.fileURL} '
      '(isViewed=${widget.isViewed}, pool=${_BetterPlayerPool._lru.length}/${_BetterPlayerPool._maxAlive})',
      'BetterPlayerView',
      '_init',
      LogTypes.booruItemLoad,
    );
    // Serialize the whole create sequence (evict old + settle + allocate new)
    // through the global decoder gate so it can never overlap another view's
    // teardown/creation. This is the actual fix for the native abort.
    await _DecoderGate.run(() async {
      try {
        await _initInner();
      } catch (e, s) {
        Logger.Inst().log(
          'init threw for ${widget.booruItem.fileURL}: $e',
          'BetterPlayerView',
          '_init',
          LogTypes.exception,
          s: s,
        );
      }
    });
  }

  Future<void> _initInner() async {
    final settings = SettingsHandler.instance;

    // Free a decoder slot BEFORE we allocate ours, so the live hardware
    // decoder count never exceeds the cap even momentarily. Then wait for the
    // evicted ExoPlayer's native release to actually settle — allocating a new
    // MediaCodec while the old one is mid-release is a common abort trigger.
    // (We're inside the gate, so nothing else is creating/disposing meanwhile.)
    //
    // A neighbour being preloaded never takes the decoder from the video on
    // screen: with one slot that would black it out, and an evicted page only
    // re-inits when its isViewed flips. It inits once it is swiped to.
    if (!widget.isViewed && _BetterPlayerPool.holdsViewedOtherThan(this)) return;
    _BetterPlayerPool.makeRoomFor(this);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || !_wantsPlayer || _controller != null) return;

    final headers = await Tools.getFileCustomHeaders(
      widget.booru,
      item: widget.booruItem,
      checkForReferer: true,
    );
    if (!mounted || !_wantsPlayer || _controller != null) return;

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
    // so a partial re-watch / scrub doesn't re-hit the CDN. Size is
    // user-configurable via Settings -> Video.
    final int totalCacheBytes = settings.betterPlayerCacheMb * 1024 * 1024;
    final int perFileCacheBytes = settings.betterPlayerPerFileMb * 1024 * 1024;
    final bool cacheEnabled = settings.mediaCache && totalCacheBytes > 0;
    final cache = BetterPlayerCacheConfiguration(
      useCache: cacheEnabled,
      maxCacheSize: totalCacheBytes,
      maxCacheFileSize: perFileCacheBytes,
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
          url: widget.booruItem.fileURL,
        );
      },
    );

    final config = BetterPlayerConfiguration(
      autoPlay: widget.isViewed &&
          settings.autoPlayEnabled &&
          !(settings.respectManualPause && ViewerHandler.instance.isManuallyPaused(widget.booruItem.fileURL)),
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
      errorBuilder: (context, errorMessage) {
        Logger.Inst().log(
          'errorBuilder fired for ${widget.booruItem.fileURL}: $errorMessage',
          'BetterPlayerView',
          'errorBuilder',
          LogTypes.exception,
        );
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              errorMessage ?? 'Playback error',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );

    // Claim any parked position now (take = consume) so the initialized
    // event can seek back to it.
    _pendingResumePosition = ViewerHandler.instance.takeVideoPosition(widget.booruItem.fileURL);
    _controllerUrl = widget.booruItem.fileURL;

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
    // Register with the global pool so we (or whoever scrolls in next) can
    // evict the oldest live controller if we'd otherwise exceed the cap.
    _BetterPlayerPool.register(this);
    if (settings.startVideosMuted) {
      await controller.setVolume(0);
    }
  }

  /// r34: a video watched through is a signal, once per item.
  final VideoCompletionTracker _completion = VideoCompletionTracker();

  void _onPlayerEvent(BetterPlayerEvent event) {
    final type = event.betterPlayerEventType;

    if (widget.isViewed && (type == BetterPlayerEventType.progress || type == BetterPlayerEventType.finished)) {
      final Duration? duration = event.parameters?['duration'] as Duration? ?? _controller?.videoPlayerController?.value.duration;
      final Duration? position = type == BetterPlayerEventType.finished ? duration : event.parameters?['progress'] as Duration?;
      if (position != null &&
          duration != null &&
          _completion.update(key: widget.booruItem.fileURL, position: position, duration: duration)) {
        InterestsHandler.instance.onVideoCompleted(widget.booruItem);
      }
    }

    // Surface noteworthy events into the in-app talker log so users can
    // share a full event trail when reporting a playback hang/crash via
    // Settings → Debug → Share logs. Skip the spammy ones (progress, etc.).
    switch (type) {
      case BetterPlayerEventType.exception:
      case BetterPlayerEventType.openFullscreen:
      case BetterPlayerEventType.hideFullscreen:
      case BetterPlayerEventType.bufferingStart:
      case BetterPlayerEventType.bufferingEnd:
      case BetterPlayerEventType.initialized:
      case BetterPlayerEventType.finished:
      case BetterPlayerEventType.setupDataSource:
        final isError = type == BetterPlayerEventType.exception;
        Logger.Inst().log(
          'better_player event ${type.name} '
          '(url=${widget.booruItem.fileURL}, params=${event.parameters})',
          'BetterPlayerView',
          '_onPlayerEvent',
          isError ? LogTypes.exception : LogTypes.booruItemLoad,
        );
        break;
      default:
        break;
    }

    if (type == BetterPlayerEventType.initialized) {
      // A re-created controller starts over: not a loop having wrapped.
      _completion.markResumed();
      final Duration? resume = _pendingResumePosition;
      _pendingResumePosition = null;
      if (resume != null && resume > Duration.zero) {
        _controller?.seekTo(resume);
      }
    }

    if (type == BetterPlayerEventType.hideFullscreen) {
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

  void _disposeController() => _disposeControllerInternal(unregister: true);

  void _disposeControllerInternal({required bool unregister}) {
    _initDebounce?.cancel();
    _initDebounce = null;
    final c = _controller;
    _controller = null;
    _windowedRatio = null;
    _wasFullScreen = false;
    if (c != null) {
      Logger.Inst().log(
        'dispose controller for ${widget.booruItem.fileURL} '
        '(unregister=$unregister, pool=${_BetterPlayerPool._lru.length})',
        'BetterPlayerView',
        '_disposeControllerInternal',
        LogTypes.booruItemLoad,
      );
    }
    if (unregister) {
      _BetterPlayerPool.unregister(this);
    }
    // Torn down while still the viewed page = unmounted under the user
    // (nested viewer cover / pool eviction), not swiped away — park the
    // position so the next incarnation resumes instead of restarting.
    if (c != null && widget.isViewed) {
      ViewerHandler.instance.saveVideoPosition(
        _controllerUrl,
        c.videoPlayerController?.value.position,
      );
    }
    _controllerUrl = null;
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
