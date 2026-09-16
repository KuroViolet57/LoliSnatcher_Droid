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

/// One thing the app did while a trace was running.
class TraceEvent {
  const TraceEvent({required this.atMs, required this.kind, this.detail});

  /// Milliseconds since the recording started.
  final int atMs;

  /// 'video.create', 'video.rebind', 'viewer.page', ...
  final String kind;
  final String? detail;
}

/// Records how smoothly the app ran and what it was doing, from inside the app
/// (r65).
///
/// Written so a slow moment can be looked at without a cable, a profile build
/// and the Dart VM service - that machinery measured the recorder as much as
/// the app. Frame timings come from the engine in any build (`build` is the
/// app's own work for a frame, `raster` is drawing it), and the app drops a
/// line on the same timeline when it builds or re-points a video player, or
/// opens another post.
class PerfTrace {
  PerfTrace._();
  static final PerfTrace instance = PerfTrace._();

  /// The timeline keeps this many events; the oldest drop off. The counts
  /// keep seeing everything.
  static const int maxEvents = 600;

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

  bool _listening = false;

  int get frameCount => _buildMs.length;
  List<TraceEvent> get events => List.unmodifiable(_events);
  Map<String, int> get counts => Map.unmodifiable(_counts);

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

    b.writeln('WHAT HAPPENED');
    if (_counts.isEmpty) {
      b.writeln('  nothing the app reports was recorded');
    } else {
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
