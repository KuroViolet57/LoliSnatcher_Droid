import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Puts screens on the trace's timeline: added to the app's
/// `navigatorObservers`, it costs nothing while no trace is running.
class PerfTraceRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    PerfTrace.instance.event('route.push', _name(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    PerfTrace.instance.event('route.pop', _name(route));
  }

  static String _name(Route<dynamic> route) =>
      route.settings.name ?? route.settings.arguments?.toString() ?? route.runtimeType.toString();
}

/// A widget's state reports its own life to the trace (r67): `widget.init`
/// when it is created, `widget.dispose` when it goes. Mixed into the heavy
/// widgets - player views, the details panel, the viewer, the feed - so a
/// trace shows what was built when, and what never went away.
mixin TraceLifecycle<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    PerfTrace.instance.lifecycle(runtimeType.toString(), alive: true);
  }

  @override
  void dispose() {
    PerfTrace.instance.lifecycle(runtimeType.toString(), alive: false);
    super.dispose();
  }
}

/// Records what the user did, at the root of the app (r67): every tap
/// (`ui.tap`), every swipe with its direction (`ui.swipe left|right|up|down`),
/// and every scroll once, with its axis and how deeply nested the scrollable
/// is (`ui.scroll vertical, depth 0`). A sideways scroll at depth 1 next to a
/// search on the timeline is the kind of thing this exists to catch.
class PerfTraceGestureLayer extends StatefulWidget {
  const PerfTraceGestureLayer({required this.child, super.key});

  final Widget child;

  /// A finger that travels less than this is a tap, not a swipe.
  static const double tapSlop = 24;

  @override
  State<PerfTraceGestureLayer> createState() => _PerfTraceGestureLayerState();
}

class _PerfTraceGestureLayerState extends State<PerfTraceGestureLayer> {
  Offset? _down;

  void _onDown(PointerDownEvent e) {
    if (!PerfTrace.instance.isRecording.value) return;
    _down = e.position;
  }

  void _onUp(PointerUpEvent e) {
    final Offset? down = _down;
    _down = null;
    if (down == null || !PerfTrace.instance.isRecording.value) return;
    final Offset d = e.position - down;
    if (d.distance < PerfTraceGestureLayer.tapSlop) {
      PerfTrace.instance.event('ui.tap', '${down.dx.round()},${down.dy.round()}');
      return;
    }
    final String direction = d.dx.abs() >= d.dy.abs() ? (d.dx > 0 ? 'right' : 'left') : (d.dy > 0 ? 'down' : 'up');
    PerfTrace.instance.event('ui.swipe', direction);
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && PerfTrace.instance.isRecording.value) {
      final String axis = n.metrics.axis == Axis.vertical ? 'vertical' : 'horizontal';
      PerfTrace.instance.event('ui.scroll', '$axis, depth ${n.depth}');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _down = null,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
    );
  }
}

/// One thing the app did while a trace was running.
class TraceEvent {
  const TraceEvent({required this.atMs, required this.kind, this.detail});

  /// Milliseconds since the recording started.
  final int atMs;

  /// 'video.create', 'video.rebind', 'viewer.page', 'ui.tap', 'widget.init', ...
  final String kind;
  final String? detail;
}

/// Records how smoothly the app ran and what it was doing, from inside the app
/// (r65; widened in r67).
///
/// Written so a slow moment can be looked at without a cable, a profile build
/// and the Dart VM service - that machinery measured the recorder as much as
/// the app. Frame timings come from the engine in any build (`build` is the
/// app's own work for a frame, `raster` is drawing it), and the app drops a
/// line on the same timeline for what it did: players built or re-pointed,
/// posts and screens opened, widgets created and disposed, taps, swipes and
/// scrolls. Builds are only counted, never timelined - there are too many.
class PerfTrace {
  PerfTrace._();
  static final PerfTrace instance = PerfTrace._();

  /// The timeline keeps this many events; the oldest drop off. The counts
  /// keep seeing everything.
  static const int maxEvents = 2000;

  final ValueNotifier<bool> isRecording = ValueNotifier(false);

  /// Bumped as frames and events arrive, for a UI that shows progress live.
  final ValueNotifier<int> revision = ValueNotifier(0);

  DateTime? startedAt;
  DateTime? stoppedAt;

  final List<double> _buildMs = [];
  final List<double> _rasterMs = [];
  final List<({int atMs, double buildMs, double rasterMs})> _slowest = [];
  final List<TraceEvent> _events = [];
  final Map<String, int> _counts = {};
  final Map<String, int> _builds = {};
  final Map<String, ({int created, int disposed})> _lifecycles = {};

  bool _listening = false;

  int get frameCount => _buildMs.length;
  List<TraceEvent> get events => List.unmodifiable(_events);
  Map<String, int> get counts => Map.unmodifiable(_counts);

  /// How many times each widget rebuilt while recording.
  Map<String, int> get builds => Map.unmodifiable(_builds);

  double get medianBuildMs => _percentile(_buildMs, 0.5);
  double get medianRasterMs => _percentile(_rasterMs, 0.5);
  double get p95BuildMs => _percentile(_buildMs, 0.95);
  double get p95RasterMs => _percentile(_rasterMs, 0.95);
  double get worstBuildMs => _buildMs.isEmpty ? 0 : _buildMs.reduce((a, b) => a > b ? a : b);
  double get worstRasterMs => _rasterMs.isEmpty ? 0 : _rasterMs.reduce((a, b) => a > b ? a : b);

  int buildOver(double ms) => _buildMs.where((v) => v > ms).length;
  int rasterOver(double ms) => _rasterMs.where((v) => v > ms).length;

  Duration get elapsed => (stoppedAt ?? DateTime.now()).difference(startedAt ?? DateTime.now());

  void start() {
    _reset();
    startedAt = DateTime.now();
    stoppedAt = null;
    isRecording.value = true;
    if (!_listening) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _listening = true;
    }
    revision.value++;
  }

  void stop() {
    if (!isRecording.value) return;
    stoppedAt = DateTime.now();
    isRecording.value = false;
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
    revision.value++;
  }

  void _onTimings(List<FrameTiming> timings) {
    final DateTime? start = startedAt;
    if (!isRecording.value || start == null) return;
    for (final FrameTiming t in timings) {
      addFrame(
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
        atMs: DateTime.now().difference(start).inMilliseconds,
      );
    }
  }

  /// One frame the engine finished. [atMs] is milliseconds into the recording.
  void addFrame({required int buildUs, required int rasterUs, required int atMs}) {
    if (!isRecording.value) return;
    final double build = buildUs / 1000;
    final double raster = rasterUs / 1000;
    _buildMs.add(build);
    _rasterMs.add(raster);

    if (build > 16.7 || raster > 16.7) {
      _slowest.add((atMs: atMs, buildMs: build, rasterMs: raster));
      _slowest.sort((a, b) {
        final double wa = a.buildMs > a.rasterMs ? a.buildMs : a.rasterMs;
        final double wb = b.buildMs > b.rasterMs ? b.buildMs : b.rasterMs;
        return wb.compareTo(wa);
      });
      if (_slowest.length > 12) _slowest.removeRange(12, _slowest.length);
    }
    revision.value++;
  }

  /// Something the app did, on the same timeline as the frames.
  void event(String kind, [String? detail]) {
    if (!isRecording.value) return;
    _counts[kind] = (_counts[kind] ?? 0) + 1;
    _events.add(
      TraceEvent(
        atMs: DateTime.now().difference(startedAt ?? DateTime.now()).inMilliseconds,
        kind: kind,
        detail: detail,
      ),
    );
    if (_events.length > maxEvents) _events.removeRange(0, _events.length - maxEvents);
    revision.value++;
  }

  /// A widget rebuilt. Counted, not timelined: a scroll rebuilds hundreds.
  void built(String widget) {
    if (!isRecording.value) return;
    _builds[widget] = (_builds[widget] ?? 0) + 1;
  }

  /// A widget's state was created ([alive] true) or disposed (false).
  void lifecycle(String widget, {required bool alive}) {
    if (!isRecording.value) return;
    final ({int created, int disposed}) c = _lifecycles[widget] ?? (created: 0, disposed: 0);
    _lifecycles[widget] = alive
        ? (created: c.created + 1, disposed: c.disposed)
        : (created: c.created, disposed: c.disposed + 1);
    event(alive ? 'widget.init' : 'widget.dispose', widget);
  }

  /// The whole thing as text: short enough to read, complete enough to act on.
  String report() {
    final StringBuffer b = StringBuffer();
    final DateTime start = startedAt ?? DateTime.now();
    b.writeln('LoliSnatcher trace');
    b.writeln('${start.toIso8601String()} · ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s');
    b.writeln();

    b.writeln('FRAMES');
    b.writeln('  $frameCount frames');
    if (frameCount > 0) {
      b.writeln(
        '  app work: median ${_fmt(medianBuildMs)} ms, 95th ${_fmt(p95BuildMs)} ms, worst ${_fmt(worstBuildMs)} ms',
      );
      b.writeln(
        '  drawing:  median ${_fmt(medianRasterMs)} ms, 95th ${_fmt(p95RasterMs)} ms, worst ${_fmt(worstRasterMs)} ms',
      );
      b.writeln('  over 8.3 ms (120 Hz): ${buildOver(8.3)} app / ${rasterOver(8.3)} drawing');
      b.writeln('  over 16.7 ms (60 Hz): ${buildOver(16.7)} app / ${rasterOver(16.7)} drawing');
      b.writeln('  over 33.3 ms (a visible hitch): ${buildOver(33.3)} app / ${rasterOver(33.3)} drawing');
      b.writeln('  over 100 ms: ${buildOver(100)} app / ${rasterOver(100)} drawing');
    }
    b.writeln();

    if (_slowest.isNotEmpty) {
      b.writeln('SLOWEST FRAMES');
      for (final s in _slowest) {
        b.writeln(
          '  +${(s.atMs / 1000).toStringAsFixed(1)} s  app ${_fmt(s.buildMs)} ms  drawing ${_fmt(s.rasterMs)} ms',
        );
      }
      b.writeln();
    }

    if (_builds.isNotEmpty) {
      b.writeln('WIDGET BUILDS');
      final List<String> names = _builds.keys.toList()..sort((a, b) => _builds[b]!.compareTo(_builds[a]!));
      for (final String n in names) {
        b.writeln('  $n × ${_builds[n]}');
      }
      b.writeln();
    }

    if (_lifecycles.isNotEmpty) {
      b.writeln('WIDGETS ALIVE');
      final List<String> names = _lifecycles.keys.toList()..sort();
      for (final String n in names) {
        final ({int created, int disposed}) c = _lifecycles[n]!;
        b.writeln('  $n: ${c.created} created, ${c.disposed} disposed, ${c.created - c.disposed} alive');
      }
      b.writeln();
    }

    b.writeln('WHAT HAPPENED');
    if (_counts.isEmpty) {
      b.writeln('  nothing the app reports was recorded');
    } else {
      final int opened = _counts['viewer.open'] ?? 0;
      final int swipes = _counts['viewer.swipe'] ?? 0;
      if (opened > 0 || swipes > 0) {
        // Spelled out: "viewer.page x 6" was once read as six posts opened.
        b.writeln('  posts opened $opened · swipes between posts $swipes');
      }
      final List<String> kinds = _counts.keys.toList()..sort();
      for (final String k in kinds) {
        b.writeln('  $k × ${_counts[k]}');
      }
    }
    b.writeln();

    b.writeln('TIMELINE');
    if (_events.isEmpty) {
      b.writeln('  (empty)');
    } else {
      for (final TraceEvent e in _events) {
        b.writeln(
          '  +${(e.atMs / 1000).toStringAsFixed(1)} s  ${e.kind}${e.detail == null ? '' : '  ${e.detail}'}',
        );
      }
    }
    return b.toString();
  }

  void _reset() {
    _buildMs.clear();
    _rasterMs.clear();
    _slowest.clear();
    _events.clear();
    _counts.clear();
    _builds.clear();
    _lifecycles.clear();
  }

  @visibleForTesting
  void clearForTests() {
    if (isRecording.value) stop();
    _reset();
    startedAt = null;
    stoppedAt = null;
  }

  static String _fmt(double ms) => ms.toStringAsFixed(ms >= 10 ? 0 : 1);

  static double _percentile(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final List<double> sorted = [...values]..sort();
    final int i = ((sorted.length - 1) * q).round();
    return sorted[i];
  }
}
