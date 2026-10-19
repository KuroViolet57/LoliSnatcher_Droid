part of '../better_player_view.dart';

/// Native-LoliControls-style overlay rendered on top of the better_player
/// surface (in both windowed and fullscreen modes via customControlsBuilder).
class _BetterControls extends StatefulWidget {
  const _BetterControls({
    required this.controller,
    required this.onVisibilityChanged,
    this.url,
  });

  final BetterPlayerController controller;
  final void Function(bool visible) onVisibilityChanged;
  final String? url;

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
      // User-initiated pause: keep this video paused across auto-play paths.
      ViewerHandler.instance.markManualPause(widget.url);
    } else {
      ViewerHandler.instance.clearManualPause(widget.url);
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
                  child: const Icon(Symbols.play_arrow_rounded, color: Colors.white, size: 48),
                ),
              ),
            ),
          ),

        // Bottom control bar. While the viewer chrome is visible the Flow
        // info peek bar overlays the bottom of the screen — lift the
        // seek/controls above it.
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
                  icon: Icon(_isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded, color: Colors.white),
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
                    _bpc.setVolume(muted ? 1.0 : 0.0);
                    _wake();
                  },
                ),
                IconButton(
                  icon: Icon(
                    _bpc.isFullScreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
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
              side < 0 ? Symbols.fast_rewind_rounded : Symbols.fast_forward_rounded,
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
