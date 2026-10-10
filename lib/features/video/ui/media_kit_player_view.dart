import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/features/video/logic/player_pool_planner.dart';
import 'package:lolisnatcher/features/video/logic/media_kit_engine_options.dart';
import 'package:lolisnatcher/features/video/logic/video_completion_tracker.dart';
import 'package:lolisnatcher/features/video/logic/video_surface_cap.dart';
import 'package:lolisnatcher/features/video/logic/video_frame_players.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_zoom_target.dart';
import 'package:lolisnatcher/core/network/dio_network.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/utils/tools.dart';

part 'media_kit_player_view/player_pool.dart';
part 'media_kit_player_view/controls.dart';

/// Experimental video engine backed by media_kit (libmpv) rather than
/// ExoPlayer/MediaCodec. libmpv manages its own decoders (with software
/// fallback), so it sidesteps the hardware-decoder-exhaustion crashes that
/// plague rapid create/destroy of ExoPlayer instances.
///
/// Players are kept warm in a URL-keyed LRU pool ([_MediaKitPlayerPool]) so
/// scrolling back to a recently-watched video resumes with its buffer intact
/// instead of restarting the download.
class MediaKitPlayerView extends StatefulWidget {
  const MediaKitPlayerView(
    this.booruItem, {
    required this.booru,
    required this.isViewed,
    super.key,
  });

  final BooruItem booruItem;
  final Booru booru;
  final bool isViewed;

  /// Soft-refresh hook: drops idle pooled players and flags live ones so
  /// every video reloads with freshly-read cookies (e.g. after re-solving a
  /// Cloudflare challenge).
  static void resetPool() => _MediaKitPlayerPool.instance.reset();

  /// r77: a pooled player in use is playing right now (background model work
  /// holds the image tagger while one does).
  static bool anyPlaying() {
    for (final _PooledPlayer e in _MediaKitPlayerPool.instance._slots) {
      if (e.refCount > 0 && e.player.state.playing) return true;
    }
    return false;
  }

  /// r77: how long after a frame grab mpv's screenshot messages are taken as
  /// its answer rather than as a player error. Generous: mpv may run a queued
  /// screenshot after the frame service stopped waiting (3 s), and only
  /// screenshots produce these two messages anyway.
  static const Duration screenshotWindow = Duration(seconds: 15);

  static final Stopwatch _mono = Stopwatch()..start();

  /// A monotonic clock for grab times (a wall-clock correction must not move
  /// them).
  static Duration monoNow() => _mono.elapsed;

  /// r77: [message] is mpv's answer to a frame grab on this player - exactly
  /// "Taking screenshot failed." (nothing drawn yet) or "Error writing
  /// screenshot!" - within [screenshotWindow] of [lastGrabAt]. Nothing else
  /// is, even a message that mentions a screenshot.
  static bool isScreenshotNoise(String message, {required Duration? lastGrabAt, required Duration now}) {
    if (lastGrabAt == null) return false;
    final Duration since = now - lastGrabAt;
    if (since.isNegative || since > screenshotWindow) return false;
    final String m = message.trim();
    return m == 'Taking screenshot failed.' || m == 'Error writing screenshot!';
  }

  /// r77: the log line for a video left with dropped frames, from mpv's
  /// `frame-drop-count` (the output skipped them) and
  /// `decoder-frame-drop-count` (the decoder fell behind); null when none
  /// were dropped or mpv did not say.
  static String? droppedLine(String output, String decoder, String url) {
    final int o = int.tryParse(output.trim()) ?? 0;
    final int d = int.tryParse(decoder.trim()) ?? 0;
    if (o <= 0 && d <= 0) return null;
    return 'video: $o frames dropped by the output, $d by the decoder ($url)';
  }

  @override
  State<MediaKitPlayerView> createState() => MediaKitPlayerViewState();
}

class MediaKitPlayerViewState extends State<MediaKitPlayerView> with TraceLifecycle implements ViewerZoomTarget {
  final PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  @override
  final PhotoViewController viewController = PhotoViewController();
  @override
  final ValueNotifier<bool> isZoomed = ValueNotifier(false);
  late final StreamSubscription<PhotoViewControllerValue> _viewSub;
  late final StreamSubscription<PhotoViewScaleState> _scaleSub;
  bool get hasPlayer => _entry != null;
  @override
  bool get isZoomTargetLoaded => hasPlayer;
  _PooledPlayer? _entry;
  String? _acquiredUrl;

  Timer? _initDebounce;
  bool _initInProgress = false;

  // Error-recovery probe: mpv does its own networking, so an expired
  // Cloudflare session just makes the video silently fail — no captcha
  // screen ever triggers. On a player error we probe the URL through Dio
  // WITH the captcha interceptor (which pops the solve webview when the
  // host is challenging), then rebuild the player with the fresh cookies.
  StreamSubscription<String>? _errorProbeSub;
  StreamSubscription<Duration>? _positionSub;
  final VideoCompletionTracker _completion = VideoCompletionTracker();
  // r77: logs what mpv was doing when a video shows no picture 8 s in.
  Timer? _pictureCheck;
  // Per-URL cooldown so a genuinely broken file can't loop probe/retry.
  static final Map<String, int> _lastProbeAt = {};
  static const Duration _probeCooldown = Duration(minutes: 2);

  bool get _wantsPlayer => widget.isViewed || SettingsHandler.instance.preloadVideos;

  @override
  void initState() {
    super.initState();
    _viewSub = viewController.outputStateStream.listen((PhotoViewControllerValue value) {
      ViewerHandler.instance.setViewValue(widget.key, value);
    });
    _scaleSub = scaleController.outputScaleStateStream.listen(_onScaleStateChanged);
    if (_wantsPlayer) {
      _scheduleInit();
    }
  }

  void _onScaleStateChanged(PhotoViewScaleState scaleState) {
    isZoomed.value =
        scaleState == PhotoViewScaleState.zoomedIn ||
        scaleState == PhotoViewScaleState.covering ||
        scaleState == PhotoViewScaleState.originalSize;
    ViewerHandler.instance.setZoomed(widget.key, isZoomed.value);
  }

  /// Same cover the still-image zoom button uses. The controls stay put.
  @override
  void doubleTapZoom() {
    if (_entry == null) return;
    scaleController.scaleState = PhotoViewScaleState.covering;
  }

  @override
  void resetZoom() {
    scaleController.scaleState = PhotoViewScaleState.initial;
    ViewerHandler.instance.setZoomed(widget.key, false);
  }

  @override
  void didUpdateWidget(covariant MediaKitPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool itemChanged = oldWidget.booruItem != widget.booruItem;
    if (itemChanged) {
      resetZoom();
      _release();
      if (_wantsPlayer) {
        _scheduleInit();
      }
    } else if (oldWidget.isViewed != widget.isViewed) {
      if (widget.isViewed) {
        if (_entry == null) {
          _scheduleInit();
        } else {
          // Always restart from the beginning when a video becomes the
          // active page — user expectation from the previous engine.
          // The restart is not a loop of the previous watch.
          _completion.markResumed();
          _entry!.player.seek(Duration.zero);
          // r77: a preloaded player becoming the viewed one is watched too.
          _watchForPicture(_entry!, widget.booruItem.fileURL);
          if (SettingsHandler.instance.autoPlayEnabled &&
              !(SettingsHandler.instance.respectManualPause &&
                  ViewerHandler.instance.isManuallyPaused(widget.booruItem.fileURL))) {
            _entry!.player.play();
          }
        }
      } else {
        // Off-screen: pause but keep the player + its buffer warm in the
        // pool. Releasing the slot happens only on widget dispose.
        resetZoom();
        _entry?.player.pause();
      }
    }
  }

  void _scheduleInit() {
    _initDebounce?.cancel();
    _initDebounce = Timer(MediaKitEngineOptions.startDelay(SettingsHandler.instance), () {
      if (!mounted || !_wantsPlayer || _entry != null) return;
      _init();
    });
  }

  Future<void> _init() async {
    if (_initInProgress) return;
    _initInProgress = true;
    try {
      final settings = SettingsHandler.instance;
      final headers = await Tools.getFileCustomHeaders(
        widget.booru,
        item: widget.booruItem,
        checkForReferer: true,
      );
      if (!mounted || !_wantsPlayer) return;

      final url = widget.booruItem.fileURL;
      final entry = await _MediaKitPlayerPool.instance.acquire(
        url: url,
        headers: headers,
      );

      if (!mounted || !_wantsPlayer) {
        _MediaKitPlayerPool.instance.release(entry);
        return;
      }

      // Restart from beginning whenever this widget becomes the active view —
      // unless a previous incarnation parked its position (nested-viewer
      // cover), in which case resume exactly there.
      if (widget.isViewed) {
        final Duration? savedPosition = ViewerHandler.instance.takeVideoPosition(url);
        await entry.player.seek(savedPosition ?? Duration.zero);
      }
      if (settings.startVideosMuted) {
        await entry.player.setVolume(0);
      }
      if (widget.isViewed &&
          settings.autoPlayEnabled &&
          !(settings.respectManualPause && ViewerHandler.instance.isManuallyPaused(url))) {
        await entry.player.play();
      }

      if (!mounted) {
        _MediaKitPlayerPool.instance.release(entry);
        return;
      }

      setState(() {
        _entry = entry;
        _acquiredUrl = url;
      });

      await _errorProbeSub?.cancel();
      _errorProbeSub = entry.player.stream.error.listen(_onPlayerError);
      await _positionSub?.cancel();
      _positionSub = entry.player.stream.position.listen(_onPlaybackPosition);

      Logger.Inst().log(
        'media_kit acquired ${entry.wasReused ? "(reused)" : (entry.replaced ? "(new, replacing a broken player)" : "(new)")} for $url',
        'MediaKitPlayerView',
        '_init',
        LogTypes.booruItemLoad,
      );
      _watchForPicture(entry, url);
    } catch (e, s) {
      Logger.Inst().log(
        'media_kit init threw for ${widget.booruItem.fileURL}: $e',
        'MediaKitPlayerView',
        '_init',
        LogTypes.exception,
        s: s,
      );
    } finally {
      _initInProgress = false;
    }
  }

  /// r77: a video with no picture size 8 s after its player was handed out
  /// is logged with mpv's state - idle, output, codec, cache - so a stalled
  /// video says why in the user's log.
  void _watchForPicture(_PooledPlayer entry, String url) {
    _pictureCheck?.cancel();
    _pictureCheck = Timer(const Duration(seconds: 8), () async {
      if (!mounted || !identical(_entry, entry) || !widget.isViewed) return;
      if ((entry.player.state.width ?? 0) > 0) return;
      final platform = entry.player.platform;
      if (platform is! NativePlayer) return;
      Future<String> read(String name) async {
        try {
          return await platform.getProperty(name);
        } catch (_) {
          return '?';
        }
      }

      final String line =
          'video: no picture 8 s after start (idle ${await read('idle-active')}, output ${await read('current-vo')}, codec ${await read('video-codec')}, '
          'waiting for cache ${await read('paused-for-cache')}, cached ${await read('demuxer-cache-duration')} s) ($url)';
      PerfTrace.instance.event('video.nopicture', url);
      Logger.Inst().log(line, 'MediaKitPlayerView', 'picture', LogTypes.booruItemLoad);
    });
  }

  void _onPlaybackPosition(Duration position) {
    final Duration duration = _entry?.player.state.duration ?? Duration.zero;
    if (_completion.noteIfViewed(
      isViewed: widget.isViewed,
      key: widget.booruItem.fileURL,
      position: position,
      duration: duration,
    )) {
      InterestsHandler.instance.onVideoCompleted(widget.booruItem);
    }
  }

  Future<void> _onPlayerError(String message) async {
    // Only recover for the video the user is actually looking at.
    if (!mounted || !widget.isViewed) return;

    // r77: mpv's answer to a frame grab that came too early is not a playback
    // problem - and it must not use up this video's recovery window below.
    if (MediaKitPlayerView.isScreenshotNoise(message, lastGrabAt: _entry?.lastGrabAt, now: MediaKitPlayerView.monoNow())) return;
    // r77: fullscreen shows this very player; rebuilding it underneath would
    // leave fullscreen on a disposed player.
    if ((_entry?.fullscreenHolds ?? 0) > 0) return;

    // Decoder-level hiccups ('Could not open codec.' on some webm tracks)
    // are NOT session/network problems — mpv usually plays the file anyway.
    // Rebuilding on them swapped the player out from under the controls for
    // nothing.
    if (message.toLowerCase().contains('codec')) return;

    final String url = widget.booruItem.fileURL;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastProbeAt[url] ?? 0) < _probeCooldown.inMilliseconds) return;
    _lastProbeAt[url] = now;

    // Give playback a moment — if the stream starts anyway, the error was
    // transient/partial and there is nothing to recover from.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !widget.isViewed) return;
    final st = _entry?.player.state;
    if (st != null && (st.playing || st.position > Duration.zero)) return;

    Logger.Inst().log(
      'probing after player error for $url ($message)',
      'MediaKitPlayerView',
      '_onPlayerError',
      LogTypes.booruItemLoad,
    );

    // The probe request runs through the captcha interceptor: if the host is
    // serving a Cloudflare challenge, the solve webview opens here and the
    // request is replayed with the fresh cookies once it's done.
    try {
      final headers = await Tools.getFileCustomHeaders(
        widget.booru,
        item: widget.booruItem,
        checkForReferer: true,
      );
      await DioNetwork.get(
        url,
        headers: {...headers, 'Range': 'bytes=0-0'},
        customInterceptor: (dio) => DioNetwork.captchaInterceptor(
          dio,
          customUserAgent: Tools.browserUserAgent,
        ),
      );
    } catch (_) {
      // Probe failed outright — nothing more to do, keep the error state.
      return;
    }
    if (!mounted) return;

    // Probe succeeded (challenge solved or transient hiccup) — rebuild this
    // player with freshly-read cookies.
    _MediaKitPlayerPool.instance.markErrored(url);
    _release();
    _scheduleInit();
  }

  void _release() {
    _errorProbeSub?.cancel();
    _errorProbeSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _initDebounce?.cancel();
    _initDebounce = null;
    final url = _acquiredUrl;
    final _PooledPlayer? entry = _entry;
    // Released while still the viewed page = unmounted under the user
    // (nested viewer cover), not swiped away — park the position so the
    // re-created widget resumes instead of restarting.
    if (entry != null && widget.isViewed) {
      ViewerHandler.instance.saveVideoPosition(url, entry.player.state.position);
    }
    _pictureCheck?.cancel();
    _pictureCheck = null;
    _entry = null;
    _acquiredUrl = null;
    // r77: by identity - during a replace two slots can hold the same address.
    if (entry != null) {
      _MediaKitPlayerPool.instance.release(entry);
    }
  }

  @override
  void dispose() {
    _release();
    _viewSub.cancel();
    _scaleSub.cancel();
    scaleController.dispose();
    viewController.dispose();
    isZoomed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) {
      return const Material(color: Colors.black, child: SizedBox.expand());
    }
    return Material(
      color: Colors.black,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoView.customChild(
              childSize: MediaQuery.sizeOf(context),
              customSize: MediaQuery.sizeOf(context),
              backgroundDecoration: const BoxDecoration(color: Colors.transparent),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 8,
              initialScale: PhotoViewComputedScale.contained,
              basePosition: Alignment.center,
              controller: viewController,
              scaleStateController: scaleController,
              enableRotation: SettingsHandler.instance.allowRotation,
              child: Video(
                // r77: a replaced player comes with its own controller; the
                // video surface is rebuilt for it (media_kit_video's state does
                // not rebind to a new controller).
                key: ObjectKey(entry.controller),
                controller: entry.controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),
            ),
            _MediaKitControls(
              player: entry.player,
              controller: entry.controller,
              url: widget.booruItem.fileURL,
            ),
          ],
        ),
      ),
    );
  }
}
