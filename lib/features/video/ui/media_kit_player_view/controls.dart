part of '../media_kit_player_view.dart';

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
    // r77: the video is still what the user watches - frames go on reading it.
    // The viewer under fullscreen gives the screen up when this route covers
    // it and takes it back when it pops; this claim only lasts in between.
    final Object fullscreenClaim = Object();
    ViewerHandler.instance.claimScreen(fullscreenClaim);
    // r77: the pool must not replace or dispose this player under fullscreen.
    final Player held = _p;
    _MediaKitPlayerPool.instance.holdForFullscreen(held);
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
    ViewerHandler.instance.releaseScreen(fullscreenClaim);
    _MediaKitPlayerPool.instance.endFullscreenHold(held);
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
