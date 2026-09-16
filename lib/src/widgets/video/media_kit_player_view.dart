import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

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

  @override
  State<MediaKitPlayerView> createState() => _MediaKitPlayerViewState();
}

class _MediaKitPlayerViewState extends State<MediaKitPlayerView> {
  _PooledPlayer? _entry;
  String? _acquiredUrl;

  Timer? _initDebounce;
  static const Duration _initDelay = Duration(milliseconds: 200);
  bool _initInProgress = false;

  // Error-recovery probe: mpv does its own networking, so an expired
  // Cloudflare session just makes the video silently fail — no captcha
  // screen ever triggers. On a player error we probe the URL through Dio
  // WITH the captcha interceptor (which pops the solve webview when the
  // host is challenging), then rebuild the player with the fresh cookies.
  StreamSubscription<String>? _errorProbeSub;
  // Per-URL cooldown so a genuinely broken file can't loop probe/retry.
  static final Map<String, int> _lastProbeAt = {};
  static const Duration _probeCooldown = Duration(minutes: 2);

  bool get _wantsPlayer => widget.isViewed || SettingsHandler.instance.preloadVideos;

  @override
  void initState() {
    super.initState();
    if (_wantsPlayer) {
      _scheduleInit();
    }
  }

  @override
  void didUpdateWidget(covariant MediaKitPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool itemChanged = oldWidget.booruItem != widget.booruItem;
    if (itemChanged) {
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
          _entry!.player.seek(Duration.zero);
          if (SettingsHandler.instance.autoPlayEnabled &&
              !(SettingsHandler.instance.respectManualPause &&
                  ViewerHandler.instance.isManuallyPaused(widget.booruItem.fileURL))) {
            _entry!.player.play();
          }
        }
      } else {
        // Off-screen: pause but keep the player + its buffer warm in the
        // pool. Releasing the slot happens only on widget dispose.
        _entry?.player.pause();
      }
    }
  }

  void _scheduleInit() {
    _initDebounce?.cancel();
    _initDebounce = Timer(_initDelay, () {
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
        _MediaKitPlayerPool.instance.release(url);
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
        _MediaKitPlayerPool.instance.release(url);
        return;
      }

      setState(() {
        _entry = entry;
        _acquiredUrl = url;
      });

      await _errorProbeSub?.cancel();
      _errorProbeSub = entry.player.stream.error.listen(_onPlayerError);

      Logger.Inst().log(
        'media_kit acquired ${entry.wasReused ? "(reused)" : "(new)"} for $url',
        'MediaKitPlayerView',
        '_init',
        LogTypes.booruItemLoad,
      );
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

  Future<void> _onPlayerError(String message) async {
    // Only recover for the video the user is actually looking at.
    if (!mounted || !widget.isViewed) return;

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
    _initDebounce?.cancel();
    _initDebounce = null;
    final url = _acquiredUrl;
    // Released while still the viewed page = unmounted under the user
    // (nested viewer cover), not swiped away — park the position so the
    // re-created widget resumes instead of restarting.
    if (_entry != null && widget.isViewed) {
      ViewerHandler.instance.saveVideoPosition(url, _entry!.player.state.position);
    }
    _entry = null;
    _acquiredUrl = null;
    if (url != null) {
      _MediaKitPlayerPool.instance.release(url);
    }
  }

  @override
  void dispose() {
    _release();
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
            Video(
              controller: entry.controller,
              fit: BoxFit.contain,
              controls: NoVideoControls,
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

/// Per-URL pooled player. Refcounted: many widgets *could* share the same URL,
/// though in practice the PageView gives each item a unique URL.
class _PooledPlayer {
  _PooledPlayer({
    required this.url,
    required this.player,
    required this.controller,
  });

  final String url;
  final Player player;
  final VideoController controller;
  int refCount = 0;
  int lastUsedTick = 0;
  // Set per acquire() call so callers know whether they got a warm buffer.
  bool wasReused = false;
  // Set when the player reported an error (network block, expired session
  // cookie, ...). An errored entry is rebuilt with fresh headers on the next
  // acquire instead of being reused broken.
  bool hasError = false;
  // Cancelled on evict/reset/dispose — the pool owns the lifecycle.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? errorSub;
}

/// Global URL-keyed LRU pool. Survives widget disposal so scrolling back to a
/// neighbour video resumes with its buffer intact instead of restarting the
/// download. Capacity = [SettingsHandler.mediaKitMaxPlayers]. Idle (refCount==0)
/// entries are evicted oldest-first when capacity is exceeded.
class _MediaKitPlayerPool {
  _MediaKitPlayerPool._();
  static final _MediaKitPlayerPool instance = _MediaKitPlayerPool._();

  final Map<String, _PooledPlayer> _entries = {};
  int _tick = 0;
  bool _initialized = false;

  Future<_PooledPlayer> acquire({
    required String url,
    required Map<String, String> headers,
  }) async {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      _initialized = true;
    }

    final existing = _entries[url];
    if (existing != null) {
      // A pooled player that errored (e.g. its baked-in session cookie
      // expired) must NOT be reused — drop it and build a fresh one with the
      // headers we were just given.
      if (existing.hasError && existing.refCount <= 0) {
        _entries.remove(url);
        try {
          await existing.errorSub?.cancel();
          await existing.player.dispose();
        } catch (_) {}
      } else {
        existing.refCount++;
        existing.lastUsedTick = ++_tick;
        existing.wasReused = true;
        return existing;
      }
    }

    // Make room for the new entry up-front.
    _evictIfNeeded(needSlot: true);

    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    final controller = VideoController(player);

    await player.open(Media(url, httpHeaders: headers), play: false);
    // PlaylistMode.single => mpv loop-file=yes: loops THIS file in place
    // without re-running the playlist. PlaylistMode.loop (loop-playlist=yes)
    // re-inits the demuxer at the loop point, which showed up as a 1-2s
    // buffering spinner and an occasional cache reset on every loop.
    await player.setPlaylistMode(PlaylistMode.single);

    // Tune libmpv cache so we don't underrun mid-clip on jittery CDNs and so
    // we keep enough back-buffer to seek-back without re-downloading.
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-secs', '30');
        await platform.setProperty('demuxer-readahead-secs', '20');
        await platform.setProperty('demuxer-max-bytes', '67108864');
        await platform.setProperty('demuxer-max-back-bytes', '33554432');
        // Belt-and-suspenders: gapless in-place file loop at the mpv level.
        await platform.setProperty('loop-file', 'inf');
      }
    } catch (e, s) {
      Logger.Inst().log(
        'mpv setProperty failed: $e',
        '_MediaKitPlayerPool',
        'acquire',
        LogTypes.exception,
        s: s,
      );
    }

    final entry = _PooledPlayer(url: url, player: player, controller: controller)
      ..refCount = 1
      ..lastUsedTick = ++_tick
      ..wasReused = false;
    // Cancelled on evict/reset/dispose — the pool owns the lifecycle.
    // ignore: cancel_subscriptions
    entry.errorSub = player.stream.error.listen((message) {
      // Codec grumbles aren't fatal (playback usually continues) — don't
      // condemn the entry to a rebuild over them.
      if (!message.toLowerCase().contains('codec')) {
        entry.hasError = true;
      }
      Logger.Inst().log(
        'media_kit player error for $url: $message',
        '_MediaKitPlayerPool',
        'errorStream',
        LogTypes.booruItemLoad,
      );
    });
    _entries[url] = entry;
    return entry;
  }

  void markErrored(String url) {
    _entries[url]?.hasError = true;
  }

  /// Drops every idle player and flags the in-use ones as errored, so all
  /// videos rebuild with freshly-read cookies on their next acquire. Used by
  /// the soft-refresh button after e.g. re-solving a Cloudflare challenge.
  void reset() {
    final idle = _entries.values.where((e) => e.refCount <= 0).toList();
    for (final e in idle) {
      _entries.remove(e.url);
      try {
        e.errorSub?.cancel();
        e.player.dispose();
      } catch (_) {}
    }
    for (final e in _entries.values) {
      e.hasError = true;
    }
  }

  void release(String url) {
    final entry = _entries[url];
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount--;
    entry.lastUsedTick = ++_tick;
    if (entry.refCount == 0) {
      // Idle but kept warm in the pool. Pause to free decode CPU; the buffer
      // is preserved by libmpv until we evict.
      try {
        entry.player.pause();
      } catch (_) {}
    }
    _evictIfNeeded();
  }

  void _evictIfNeeded({bool needSlot = false}) {
    final int max = SettingsHandler.instance.mediaKitMaxPlayers;
    // When making room for a new entry, target capacity is `max - 1`.
    final int target = needSlot ? max - 1 : max;
    if (_entries.length <= target) return;

    final evictable = _entries.values.where((e) => e.refCount == 0).toList()
      ..sort((a, b) => a.lastUsedTick.compareTo(b.lastUsedTick));
    int toEvict = _entries.length - target;
    for (final e in evictable) {
      if (toEvict <= 0) break;
      _entries.remove(e.url);
      try {
        e.errorSub?.cancel();
        e.player.dispose();
      } catch (_) {}
      toEvict--;
    }
  }
}

/// LoliControls-style overlay driven by a media_kit [Player]'s streams.
class _MediaKitControls extends StatefulWidget {
  const _MediaKitControls({
    required this.player,
    required this.controller,
    required this.url,
    this.isFullscreen = false,
  });

  final Player player;
  // Carried along so the fullscreen route can reuse the SAME VideoController
  // (= same platform texture) instead of allocating a new one per entry.
  final VideoController controller;
  final String url;
  final bool isFullscreen;

  @override
  State<_MediaKitControls> createState() => _MediaKitControlsState();
}

class _MediaKitControlsState extends State<_MediaKitControls> {
  Player get _p => widget.player;

  bool _hidden = false;
  bool _dragging = false;

  bool _playing = false;
  bool _buffering = false;
  // Debounced UI mirrors of the above: mpv pulses buffering=true and
  // playing=false for a few ms at every loop-file loop point, and reflecting
  // those raw pulses made loops visibly stutter (spinner + play icon flash).
  // The UI only reacts when a state persists past the debounce window;
  // user-initiated pauses stay instant via _userPaused.
  bool _showBuffering = false;
  bool _playingUi = false;
  bool _userPaused = false;
  Timer? _bufferingDebounce;
  Timer? _pauseIconDebounce;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double _volume = 100;
  // Last audible volume, so unmuting restores it instead of forcing 100
  // (matters when the video started muted or at a custom level).
  double _lastNonZeroVolume = 100;

  bool _fullscreen = false;

  final List<StreamSubscription> _subs = [];

  TapDownDetails? _doubleTapInfo;
  int _lastSide = 0;
  int _lastSkipSeconds = 0;
  bool _showSeekFeedback = false;
  Timer? _hideTimer;
  Timer? _seekFeedbackTimer;

  // Long-press 2× speed (hold anywhere to fast-forward, release to resume).
  // Rate is player-level state and pooled players stay warm, so every exit
  // path (release, player swap, dispose) must restore 1×.
  bool _speedBoosted = false;
  static const double _boostRate = 2;

  @override
  void initState() {
    super.initState();
    _bindPlayer();
    _startHideTimer();
  }

  // (Re)binds this overlay to the current widget.player. Split out of
  // initState because the hosting view can swap the underlying player in
  // place (pool rebuild after an error) — without rebinding, the overlay
  // kept dead subscriptions to the disposed player and froze (static seek
  // bar, wrong play/pause icon) while the new player actually played.
  void _bindPlayer() {
    final s = _p.state;
    _playing = s.playing;
    _playingUi = s.playing;
    _buffering = s.buffering;
    _showBuffering = false;
    _position = s.position;
    _duration = s.duration;
    _buffer = s.buffer;
    _volume = s.volume;
    if (_volume > 0) _lastNonZeroVolume = _volume;

    _subs.addAll([
      _p.stream.playing.listen((v) => _safe(() {
            _playing = v;
            if (v) {
              _pauseIconDebounce?.cancel();
              _playingUi = true;
              _userPaused = false;
            } else if (_userPaused) {
              _playingUi = false;
            } else {
              _pauseIconDebounce?.cancel();
              _pauseIconDebounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted && !_playing) setState(() => _playingUi = false);
              });
            }
          })),
      _p.stream.buffering.listen((v) => _safe(() {
            _buffering = v;
            if (v) {
              _bufferingDebounce?.cancel();
              _bufferingDebounce = Timer(const Duration(milliseconds: 350), () {
                if (mounted && _buffering) setState(() => _showBuffering = true);
              });
            } else {
              _bufferingDebounce?.cancel();
              _showBuffering = false;
            }
          })),
      _p.stream.position.listen((v) => _safe(() {
            if (!_dragging) _position = v;
          })),
      _p.stream.duration.listen((v) => _safe(() => _duration = v)),
      _p.stream.buffer.listen((v) => _safe(() => _buffer = v)),
      _p.stream.volume.listen((v) => _safe(() {
            _volume = v;
            if (v > 0) _lastNonZeroVolume = v;
          })),
    ]);
  }

  @override
  void didUpdateWidget(covariant _MediaKitControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      if (_speedBoosted) {
        _speedBoosted = false;
        try {
          oldWidget.player.setRate(1);
        } catch (_) {}
      }
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      _safe(_bindPlayer);
    }
  }

  void _safe(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    if (_speedBoosted) {
      try {
        widget.player.setRate(1);
      } catch (_) {}
    }
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _bufferingDebounce?.cancel();
    _pauseIconDebounce?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hidden = true);
    });
  }

  void _toggleControls() {
    setState(() => _hidden = !_hidden);
    if (!_hidden) _startHideTimer();
  }

  void _wake() {
    if (_hidden) setState(() => _hidden = false);
    _startHideTimer();
  }

  void _playPause() {
    // Track USER intent before toggling: pausing marks the video so
    // auto-play paths won't restart it; playing clears the mark. The pause
    // icon reflects a user pause instantly (no debounce).
    if (_playing) {
      ViewerHandler.instance.markManualPause(widget.url);
      _userPaused = true;
      _playingUi = false;
    } else {
      ViewerHandler.instance.clearManualPause(widget.url);
      _userPaused = false;
      _playingUi = true;
    }
    _p.playOrPause();
    _wake();
  }

  int _skipSecondsFor(int durationSec) {
    if (durationSec <= 5) return 0;
    if (durationSec <= 30) return 5;
    return 10;
  }

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapInfo = d;

  void _startSpeedBoost(LongPressStartDetails _) {
    // Only meaningful while playing (2× on a paused frame does nothing).
    if (!_playing || _speedBoosted) return;
    _speedBoosted = true;
    HapticFeedback.mediumImpact();
    _p.setRate(_boostRate);
    setState(() {});
  }

  void _endSpeedBoost() {
    if (!_speedBoosted) return;
    _speedBoosted = false;
    _p.setRate(1);
    if (mounted) setState(() {});
  }

  void _onDoubleTap() {
    if (_doubleTapInfo == null) return;
    final width = MediaQuery.sizeOf(context).width;
    final mid = width / 2;
    final sideZone = width / 6;
    final dx = _doubleTapInfo!.localPosition.dx;

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

    final skip = _skipSecondsFor(_duration.inSeconds);
    if (skip == 0) {
      _playPause();
      return;
    }

    final target = Duration(
      milliseconds: min(
        max(0, _position.inMilliseconds + skip * 1000 * side),
        _duration.inMilliseconds,
      ),
    );
    _p.seek(target);
    setState(() {
      _position = target;
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

  double get _bufferedFraction {
    if (_duration.inMilliseconds == 0) return 0;
    return (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onLongPressStart: _startSpeedBoost,
          onLongPressEnd: (_) => _endSpeedBoost(),
          onLongPressCancel: _endSpeedBoost,
        ),
        if (_speedBoosted)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.fast_forward_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 6),
                        Text('2×', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_showBuffering && !_dragging)
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
          ),
        if (_showSeekFeedback)
          Align(
            alignment: _lastSide < 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: _SeekFeedback(side: _lastSide, seconds: _lastSkipSeconds),
            ),
          ),
        if (!_hidden)
          Center(
            child: AnimatedOpacity(
              opacity: _playingUi ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _playPause,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Symbols.play_arrow_rounded, color: Colors.white, size: 48),
                ),
              ),
            ),
          ),
        // While the viewer chrome is visible the Flow info peek bar overlays
        // the bottom of the screen — lift the seek/controls above it.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Obx(
            () => Padding(
              padding: EdgeInsets.only(
                bottom: ViewerHandler.instance.isPeekBarVisible
                    ? 64 + MediaQuery.viewPaddingOf(context).bottom
                    : 0,
              ),
              child: AnimatedOpacity(
                opacity: _hidden ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: _hidden,
                  child: _buildBottomBar(accent),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(Color accent) {
    final muted = _volume == 0;
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
                  setState(() => _position = Duration(milliseconds: ms));
                  _p.seek(Duration(milliseconds: ms));
                  _wake();
                },
                onDragEnd: () => setState(() => _dragging = false),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_playingUi ? Symbols.pause_rounded : Symbols.play_arrow_rounded, color: Colors.white),
                  onPressed: _playPause,
                ),
                Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(muted ? Symbols.volume_off_rounded : Symbols.volume_up_rounded, color: Colors.white),
                  onPressed: () {
                    _p.setVolume(muted ? _lastNonZeroVolume : 0);
                    _wake();
                  },
                ),
                IconButton(
                  icon: Icon(
                    (widget.isFullscreen || _fullscreen) ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    _wake();
    // The controls instance living INSIDE the fullscreen route always pops —
    // its local _fullscreen flag starts false, so without this check the
    // button there stacked a second fullscreen route instead of leaving.
    if (widget.isFullscreen || _fullscreen) {
      await Navigator.of(context).maybePop();
      return;
    }
    setState(() => _fullscreen = true);
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => _FullscreenMediaKit(
          player: _p,
          controller: widget.controller,
          url: widget.url,
        ),
      ),
    );
    if (mounted) setState(() => _fullscreen = false);
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

/// Fullscreen route — shares the SAME player and VideoController (no new
/// decoder, no new platform texture) and reuses the same controls overlay,
/// so playback continues seamlessly and double-tap / scrubber all work in
/// landscape. Creating a fresh VideoController here used to leak one
/// texture per fullscreen entry (they only die with the pooled player).
class _FullscreenMediaKit extends StatelessWidget {
  const _FullscreenMediaKit({
    required this.player,
    required this.controller,
    required this.url,
  });

  final Player player;
  final VideoController controller;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: controller,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
            // A second controls instance bound to the same player; fullscreen
            // button here pops back (isFullscreen).
            _MediaKitControls(
              player: player,
              controller: controller,
              url: url,
              isFullscreen: true,
            ),
          ],
        ),
      ),
    );
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
            Icon(side < 0 ? Symbols.fast_rewind_rounded : Symbols.fast_forward_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            Text('${seconds}s', style: const TextStyle(color: Colors.white, fontSize: 20)),
          ],
        ),
      ),
    );
  }
}

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
        final width = constraints.maxWidth;
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
                Container(
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                FractionallySizedBox(
                  widthFactor: widget.bufferedFraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _playedFraction,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: widget.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Align(
                  alignment: Alignment(_playedFraction * 2 - 1, 0),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 2)],
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
