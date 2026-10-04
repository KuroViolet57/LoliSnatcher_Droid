import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/utils/logger.dart';

/// How long each step of a cold start took (1.0).
///
/// [start] is called first thing in `main`, [mark] after each startup step,
/// and [finish] once the home screen has drawn its first frame. [finish]
/// writes one line to the app log (Settings -> Debug -> Logger) and to
/// logcat:
///
///     startup: binding 12 ms · settings 128 ms · tabs 760 ms · total 900 ms
///
/// Each step shows its own time (since the previous mark); `total` is the
/// time from [start]. Marks after [finish] are ignored, so a later re-entry
/// (a restart of the home widget) cannot add noise.
class StartupTimeline {
  StartupTimeline._();

  static final Stopwatch _clock = Stopwatch();
  static int Function()? _testClock;
  static final List<(String, int)> _marks = [];
  static bool _finished = false;

  static int get _elapsed => _testClock?.call() ?? _clock.elapsedMilliseconds;

  static void start() {
    _clock
      ..reset()
      ..start();
    _marks.clear();
    _finished = false;
  }

  static void mark(String step) {
    if (_finished) {
      return;
    }
    _marks.add((step, _elapsed));
  }

  static List<(String, int)> get marks => List.unmodifiable(_marks);

  static bool get isFinished => _finished;

  static String summary() {
    if (_marks.isEmpty) {
      return 'startup: no steps recorded';
    }
    final List<String> parts = [];
    int previous = 0;
    for (final (String step, int at) in _marks) {
      parts.add('$step ${at - previous} ms');
      previous = at;
    }
    parts.add('total ${_marks.last.$2} ms');
    return 'startup: ${parts.join(' · ')}';
  }

  /// Records [step], logs the summary once and returns it; null when the
  /// timeline was already finished.
  static String? finish(String step) {
    if (_finished) {
      return null;
    }
    mark(step);
    _finished = true;
    final String line = summary();
    Logger.Inst().log(line, 'StartupTimeline', 'finish', LogTypes.settingsLoad);
    debugPrint(line);
    return line;
  }

  @visibleForTesting
  static void debugUseClock(int Function()? now) => _testClock = now;
}
