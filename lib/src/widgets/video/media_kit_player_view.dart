import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
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

  @override
  State<MediaKitPlayerView> createState() => _MediaKitPlayerViewState();
}

class _MediaKitPlayerViewState extends State<MediaKitPlayerView> {
  _PooledPlayer? _entry;
  String? _acquiredUrl;

  Timer? _initDebounce;
  static const Duration _initDelay = Duration(milliseconds: 200);
  bool _initInProgress = false;

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
          if (SettingsHandler.instance.autoPlayEnabled) {
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

      // Restart from beginning whenever this widget becomes the active view.
      if (widget.isViewed) {
        await entry.player.seek(Duration.zero);
      }
      if (settings.startVideosMuted) {
        await entry.player.setVolume(0);
      }
      if (widget.isViewed && settings.autoPlayEnabled) {
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

  void _release() {
    _initDebounce?.cancel();
    _initDebounce = null;
    final url = _acquiredUrl;
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
            _MediaKitControls(player: entry.player),
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
      existing.refCount++;
      existing.lastUsedTick = ++_tick;
      existing.wasReused = true;
      return existing;
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
    _entries[url] = entry;
    return entry;
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
        e.player.dispose();
      } catch (_) {}
      toEvict--;
    }
  }
}

/// LoliControls-style overlay driven by a media_kit [Player]'s streams.
class _MediaKitControls extends StatefulWidget {
  const _MediaKitControls({required this.player});

  final Player player;

  @override
  State<_MediaKitControls> createState() => _MediaKitControlsState();
}

class _MediaKitControlsState extends State<_MediaKitControls> {
  Player get _p => widget.player;

  bool _hidden = false;
  bool _dragging = false;

  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double _volume = 100;

  bool _fullscreen = false;

  final List<StreamSubscription> _subs = [];

  TapDownDetails? _doubleTapInfo;
  int _lastSide = 0;
  int _lastSkipSeconds = 0;
  bool _showSeekFeedback = false;
  Timer? _hideTimer;
  Timer? _seekFeedbackTimer;

  @override
  void initState() {
    super.initState();
    final s = _p.state;
    _playing = s.playing;
    _buffering = s.buffering;
    _position = s.position;
    _duration = s.duration;
    _buffer = s.buffer;
    _volume = s.volume;

    _subs.addAll([
      _p.stream.playing.listen((v) => _safe(() => _playing = v)),
      _p.stream.buffering.listen((v) => _safe(() => _buffering = v)),
      _p.stream.position.listen((v) => _safe(() {
            if (!_dragging) _position = v;
          })),
      _p.stream.duration.listen((v) => _safe(() => _duration = v)),
      _p.stream.buffer.listen((v) => _safe(() => _buffer = v)),
      _p.stream.volume.listen((v) => _safe(() => _volume = v)),
    ]);
    _startHideTimer();
  }

  void _safe(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
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
    _p.playOrPause();
    _wake();
  }

  int _skipSecondsFor(int durationSec) {
    if (durationSec <= 5) return 0;
    if (durationSec <= 30) return 5;
    return 10;
  }

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapInfo = d;

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
        ),
        if (_buffering && !_dragging)
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
              opacity: _playing ? 0 : 1,
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
                  icon: Icon(_playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded, color: Colors.white),
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
                    _p.setVolume(muted ? 100 : 0);
                    _wake();
                  },
                ),
                IconButton(
                  icon: Icon(_fullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded, color: Colors.white),
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
    if (_fullscreen) {
      await Navigator.of(context).maybePop();
      return;
    }
    setState(() => _fullscreen = true);
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => _FullscreenMediaKit(player: _p),
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

/// Fullscreen route — shares the SAME player (no new decoder) and reuses the
/// same controls overlay, so playback continues seamlessly and double-tap /
/// scrubber all work in landscape.
class _FullscreenMediaKit extends StatefulWidget {
  const _FullscreenMediaKit({required this.player});

  final Player player;

  @override
  State<_FullscreenMediaKit> createState() => _FullscreenMediaKitState();
}

class _FullscreenMediaKitState extends State<_FullscreenMediaKit> {
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.player);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
            // A second controls instance bound to the same player; fullscreen
            // button here pops back.
            _MediaKitControls(player: widget.player),
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
