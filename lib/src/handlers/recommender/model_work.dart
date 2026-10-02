import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// r77: when the user last touched the screen, scrolled or changed page.
///
/// Fed by a global pointer route (every touch, wherever it lands), the root
/// scroll listener in [PerfTraceGestureLayer] (a fling keeps scrolling after
/// the finger is gone) and [PerfTraceRouteObserver] (system Back sends no
/// touch). Background model work waits for a quiet moment ([ModelWork]).
class ActivityClock {
  ActivityClock._();
  static final ActivityClock instance = ActivityClock._();

  /// A monotonic clock (a wall-clock correction must not stall the queue).
  /// Replaced in tests.
  DateTime Function() now = monotonicNow;

  static final Stopwatch _mono = Stopwatch()..start();

  static DateTime monotonicNow() => DateTime.fromMicrosecondsSinceEpoch(_mono.elapsedMicroseconds);

  DateTime? _last;
  bool _attached = false;

  /// The last touch, scroll or page change; null when there was none yet.
  DateTime? get last => _last;

  void mark() => _last = now();

  /// Nothing happened for at least [quiet].
  bool quietFor(Duration quiet) {
    final DateTime? l = _last;
    return l == null || now().difference(l) >= quiet;
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(onPointer);
  }

  void onPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent || e is PointerUpEvent || e is PointerScrollEvent || e is PointerPanZoomUpdateEvent) {
      mark();
    }
  }

  void resetForTests() {
    now = monotonicNow;
    _last = null;
  }
}

/// A background step: `lite` is true when the app is leaving the screen - the
/// step then does its bookkeeping without running any model.
typedef ModelStep = Future<void> Function(bool lite);

class _Pending {
  _Pending(this.label, this.step, this.heavy, this.queuedAt, this.defer);

  final String label;
  final ModelStep step;
  final bool heavy;
  final DateTime queuedAt;

  /// r78: what to do instead when the app leaves before this step ran.
  final void Function()? defer;
  final Completer<void> done = Completer<void>();
}

/// r77: the on-device models' background work, kept away from the moments
/// the user is using the app.
///
/// A learning step (after a view, a favourite, a snatch, exposures) and a
/// video frame's looks run here, one at a time, only after [quiet] without a
/// touch, scroll or page change ([ActivityClock]). A heavy step (the image
/// tagger) also waits while a video plays, up to [maxVideoWait]. When the app
/// leaves the screen, what is waiting runs at once in lite mode - learned
/// without the models - so nothing is lost if Android then ends the process.
/// Work the user asked for (Try it, boards, Posts like this, For You) never
/// comes here; it can still wait for the step that is running, since the
/// ONNX plugin runs one call at a time.
class ModelWork with WidgetsBindingObserver {
  ModelWork._();
  static final ModelWork instance = ModelWork._();

  static const String className = 'ModelWork';

  // Knobs and seams, replaced in tests.
  Duration quiet = const Duration(milliseconds: 1500);

  /// r78: how long a step may wait for a quiet moment before it runs anyway.
  /// Without this a person who never stops for [quiet] never learned with the
  /// models at all: the queue only drained when the app left the screen, and
  /// that drain runs lite.
  Duration maxWait = const Duration(seconds: 20);

  /// r78: was 60 s. Measured on the 19 Sep phone log: a video was on screen
  /// 56 % of the session and every tagger run came from a favourite, so the
  /// video hold - not the quiet gate - was the real brake.
  Duration maxVideoWait = const Duration(seconds: 10);
  Duration poll = const Duration(milliseconds: 250);

  /// A step that waited this long says so in the log.
  Duration logWait = const Duration(seconds: 3);

  /// A step running longer than this no longer holds up the queue (its work
  /// goes on; the next step starts).
  Duration stepTimeout = const Duration(seconds: 60);
  bool Function() videoPlaying = _noVideo;

  /// The app is away (paused, hidden): steps run lite. Not while merely
  /// inactive - the notification shade or a system dialog over the app.
  bool Function() away = defaultAway;

  /// Called when steps ran lite and the queue is empty (the recommender
  /// writes its models to disk then, since the app may be ended soon).
  void Function()? onDrainedAway;

  final ListQueue<_Pending> _pending = ListQueue();
  bool _running = false;
  bool _ranLite = false;
  Timer? _timer;
  bool _attached = false;

  /// Steps waiting for their turn.
  int get waiting => _pending.length;

  final List<Completer<void>> _drainWaiters = [];

  /// Completes once no step waits or runs (tests, and callers that must see
  /// what was learned).
  Future<void> drained() {
    if (!_running && _pending.isEmpty) return Future<void>.value();
    final Completer<void> c = Completer<void>();
    _drainWaiters.add(c);
    return c.future;
  }

  static bool _noVideo() => false;

  static bool defaultAway() {
    final AppLifecycleState? s = WidgetsBinding.instance.lifecycleState;
    return s == AppLifecycleState.paused || s == AppLifecycleState.hidden || s == AppLifecycleState.detached;
  }

  static void resetForTests() {
    final ModelWork w = instance;
    w._timer?.cancel();
    w._timer = null;
    for (final _Pending p in w._pending) {
      if (!p.done.isCompleted) p.done.complete();
    }
    w._pending.clear();
    w._running = false;
    w._ranLite = false;
    for (final Completer<void> c in w._drainWaiters) {
      if (!c.isCompleted) c.complete();
    }
    w._drainWaiters.clear();
    w
      ..quiet = const Duration(milliseconds: 1500)
      ..maxWait = const Duration(seconds: 20)
      ..maxVideoWait = const Duration(seconds: 10)
      ..poll = const Duration(milliseconds: 250)
      ..logWait = const Duration(seconds: 3)
      ..stepTimeout = const Duration(seconds: 60)
      ..videoPlaying = _noVideo
      ..away = defaultAway
      ..onDrainedAway = null;
    ActivityClock.instance.resetForTests();
  }

  /// Starts following touches and the app's lifecycle; [videoPlaying] tells
  /// whether a video plays on screen.
  void attach({bool Function()? videoPlaying}) {
    if (videoPlaying != null) this.videoPlaying = videoPlaying;
    ActivityClock.instance.attach();
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _pump();
    }
  }

  /// Runs [step] at the next quiet moment; the future completes when it has
  /// run. A step that throws is logged, never rethrown - callers do not wait.
  ///
  /// r78: [defer] is what to do instead when the app leaves the screen before
  /// the step ran - keep it for later, rather than learn it lite and lose the
  /// models' half for good. A step without [defer] still runs lite.
  Future<void> run(String label, ModelStep step, {bool heavy = false, void Function()? defer}) {
    final _Pending p = _Pending(label, step, heavy, ActivityClock.instance.now(), defer);
    _pending.add(p);
    _pump();
    return p.done.future;
  }

  void _pump() {
    if (_running) return;
    if (_pending.isEmpty) {
      _stopTimer();
      if (_ranLite) {
        _ranLite = false;
        onDrainedAway?.call();
      }
      if (_drainWaiters.isNotEmpty) {
        final List<Completer<void>> waiters = List<Completer<void>>.of(_drainWaiters);
        _drainWaiters.clear();
        for (final Completer<void> c in waiters) {
          c.complete();
        }
      }
      return;
    }
    final bool lite = away();
    _Pending? next;
    if (lite) {
      next = _pending.first;
    } else {
      // r78: quiet, or waited long enough. Each gate has its own deadline, so
      // a person who never stops still gets their learning done.
      final bool quietNow = ActivityClock.instance.quietFor(quiet);
      final bool video = videoPlaying();
      final DateTime t = ActivityClock.instance.now();
      for (final _Pending p in _pending) {
        final Duration waited = t.difference(p.queuedAt);
        if (p.heavy && video && waited < maxVideoWait) continue;
        if (!quietNow && waited < maxWait) continue;
        next = p;
        break;
      }
    }
    if (next == null) {
      _timer ??= Timer.periodic(poll, (_) => _pump());
      return;
    }
    _stopTimer();
    _pending.remove(next);
    _running = true;
    unawaited(_runOne(next, lite: lite));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runOne(_Pending p, {required bool lite}) async {
    final Duration waited = ActivityClock.instance.now().difference(p.queuedAt);
    if (lite && p.defer != null) {
      // r78: the app is leaving with this step still waiting. Keeping it is
      // better than learning it without the models, which cannot be undone.
      Logger.Inst().log('model: ${p.label} kept for later (the app is leaving)', className, 'run', LogTypes.booruHandlerInfo);
      PerfTrace.instance.event('model.kept', p.label);
      try {
        p.defer!.call();
      } catch (e, s) {
        Logger.Inst().log('model: ${p.label} could not be kept: $e', className, 'run', LogTypes.exception, s: s);
      }
      if (!p.done.isCompleted) p.done.complete();
      _running = false;
      _pump();
      return;
    }
    if (waited >= logWait) {
      Logger.Inst().log(
        'model: ${p.label} waited ${(waited.inMilliseconds / 1000).toStringAsFixed(1)} s for a quiet moment (${_pending.length} more waiting)',
        className,
        'run',
        LogTypes.booruHandlerInfo,
      );
    }
    // r78: it ran although the screen was still busy - the deadline. The log
    // and the trace say so, so a phone log shows how often that happens.
    final bool pastDeadline = !lite && !ActivityClock.instance.quietFor(quiet);
    if (pastDeadline) {
      Logger.Inst().log(
        'model: ${p.label} ran after waiting ${(waited.inMilliseconds / 1000).toStringAsFixed(1)} s (the screen never went quiet)',
        className,
        'run',
        LogTypes.booruHandlerInfo,
      );
      PerfTrace.instance.event('model.deadline', p.label);
    }
    final Stopwatch sw = Stopwatch()..start();
    PerfTrace.instance.event('model.start', p.label);
    if (lite) _ranLite = true;
    try {
      await p.step(lite).timeout(stepTimeout);
    } on TimeoutException {
      Logger.Inst().log('model: ${p.label} took over ${stepTimeout.inSeconds} s; the next step starts', className, 'run', LogTypes.booruHandlerInfo);
    } catch (e, s) {
      Logger.Inst().log('model: ${p.label} failed: $e', className, 'run', LogTypes.exception, s: s);
    } finally {
      PerfTrace.instance.event('model.end', '${p.label} ${sw.elapsedMilliseconds} ms${lite ? ' (lite)' : ''}');
      if (!p.done.isCompleted) p.done.complete();
      _running = false;
      _pump();
    }
  }
}
