part of '../gallery_view_page.dart';

/// Full-screen passive pointer observer that drives the bottom info sheet's
/// extent directly as the user swipes — Boorusama-style. Once it detects a
/// clear upward swipe (≥24px up, vertical dominating horizontal by 1.5×,
/// single touch) it switches into a "drag" phase and uses jumpTo on each
/// pointer move so the sheet is glued to the finger at native refresh rate
/// instead of running a separate animateTo. On release it snaps to the
/// nearest of {closed, peek, expanded} biased by fling velocity.
///
/// Uses [Listener] (not [GestureDetector]) so it never enters the gesture
/// arena while idle — paging, dismiss, photo_view pan and tap-to-toggle all
/// continue to work normally.
class _SwipeUpListener extends StatefulWidget {
  const _SwipeUpListener({
    required this.controller,
    required this.gate,
    required this.openSize,
  });

  final DraggableScrollableController controller;
  final InfoSheetContentGate gate;
  final double openSize;

  @override
  State<_SwipeUpListener> createState() => _SwipeUpListenerState();
}

class _SwipeUpListenerState extends State<_SwipeUpListener> {
  int? _pointerId;
  Offset _startPos = Offset.zero;
  Offset _lastPos = Offset.zero;
  int _lastTimeUs = 0;
  // Velocity along Y in logical pixels per second (negative = upward).
  double _velocityYPxPerSec = 0;
  bool _engaged = false;
  bool _multiTouch = false;
  // True only when the gesture began while the sheet was (near) closed. When
  // the sheet is already open we leave dragging to its own physics.
  bool _eligible = false;
  // False when this swipe made the sheet build its tag view. That swap lands
  // on the next frame and stops any sheet animation already running, so a
  // flick released before it waits a frame to settle.
  bool _contentWasLive = true;

  static const double _engagePx = 12;
  static const double _flingPxPerSec = 600;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointerId != null) {
          _multiTouch = true;
          return;
        }
        _pointerId = event.pointer;
        _startPos = event.position;
        _lastPos = event.position;
        _lastTimeUs = event.timeStamp.inMicroseconds;
        _engaged = false;
        _multiTouch = false;
        _velocityYPxPerSec = 0;
        double current = 0;
        if (widget.controller.isAttached) current = widget.controller.size;
        _eligible = current <= 0.02;
      },
      onPointerMove: (event) {
        if (_multiTouch || !_eligible) return;
        if (event.pointer != _pointerId) return;

        final dtUs = (event.timeStamp.inMicroseconds - _lastTimeUs).clamp(1, 1 << 31);
        _velocityYPxPerSec = (event.position.dy - _lastPos.dy) / (dtUs / 1e6);
        _lastPos = event.position;
        _lastTimeUs = event.timeStamp.inMicroseconds;

        // Displacement from where the finger went DOWN — positive = moved up.
        final double dyUp = _startPos.dy - event.position.dy;
        final double dxAbs = (event.position.dx - _startPos.dx).abs();

        if (!_engaged) {
          if (dyUp < _engagePx) return;
          // Vertical must dominate horizontal so we don't hijack page swipes.
          if (dxAbs > dyUp) return;
          _engaged = true;
          // Build the tag view now, so the sheet has its content as it rises.
          _contentWasLive = widget.gate.live.value;
          widget.gate.requestOpen();
          PerfTrace.instance.event('viewer.infoSheet.swipe', _contentWasLive ? 'ready' : 'build');
        }

        if (!widget.controller.isAttached) return;

        // Extent grows 1:1 with how far the finger has moved up, regardless of
        // where on screen the swipe started — so it begins from 0 and tracks
        // the finger smoothly instead of snapping to an absolute position.
        final double screenHeight = MediaQuery.sizeOf(context).height;
        final double newExtent = (dyUp / screenHeight).clamp(0.0, widget.openSize);
        widget.controller.jumpTo(newExtent);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointerId) return;
        _pointerId = null;
        if (!_engaged) return;
        _settle();
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointerId) return;
        _pointerId = null;
        if (!_engaged) return;
        _settle();
      },
    );
  }

  void _settle() {
    if (!widget.controller.isAttached) return;
    final current = widget.controller.size;
    final upPxPerSec = -_velocityYPxPerSec;

    // Single open stop now (the sheet locks at openSize). Fling up => open,
    // fling down => close, otherwise snap to whichever is nearer.
    double target;
    if (upPxPerSec > _flingPxPerSec) {
      target = widget.openSize;
    } else if (upPxPerSec < -_flingPxPerSec) {
      target = 0;
    } else {
      target = current >= widget.openSize / 2 ? widget.openSize : 0;
    }

    void animate() {
      if (!widget.controller.isAttached) return;
      widget.controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    if (_contentWasLive) {
      animate();
    } else {
      _contentWasLive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => animate());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }
}
