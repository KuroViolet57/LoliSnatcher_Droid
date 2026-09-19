import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/utils/logger.dart';

/// r77: what closed the viewer. Twice on 19 Sep the viewer closed right after
/// a tap on a tag's preview icon and the log could not say why. Every viewer
/// close now logs the app's own code that closed it ([ViewerCloseObserver]),
/// and every system Back and Back gesture is logged ([BackGestureLogger]).
class NavigationTrace {
  const NavigationTrace._();

  /// Where the lines go; replaced in tests.
  static void Function(String line) log = _defaultLog;

  static void _defaultLog(String line) => Logger.Inst().log(line, 'NavigationTrace', 'route', LogTypes.booruHandlerInfo);

  static void resetForTests() => log = _defaultLog;

  /// The app's own frames of [trace], newest first, joined on one line -
  /// Flutter's and Dart's frames are left out; "the system" when no app code
  /// was involved (a system Back handled by the framework).
  static String callerOf(StackTrace trace, {int max = 6}) {
    final List<String> frames = trace
        .toString()
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .where((String l) => !l.contains('package:flutter/') && !l.contains('(dart:') && !l.contains('navigation_trace.dart'))
        // Async gaps and elided runs say nothing about who closed it.
        .where((String l) => !l.contains('<asynchronous suspension>') && !l.startsWith('(elided'))
        .take(max)
        .map((String l) => l.replaceFirst(RegExp(r'^#\d+\s+'), ''))
        .toList();
    return frames.isEmpty ? 'the system (no app code in the path)' : frames.join(' <- ');
  }
}

/// Logs how every viewer page closed.
class ViewerCloseObserver extends NavigatorObserver {
  /// The route name every viewer push uses (the feed's, the strips', the
  /// preview windows' and linked media's).
  static const String viewerRoute = 'viewer';

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _note(route, 'closed');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _note(route, 'removed');

  void _note(Route<dynamic> route, String how) {
    if (route.settings.name != viewerRoute) return;
    NavigationTrace.log('viewer $how by: ${NavigationTrace.callerOf(StackTrace.current)}');
  }
}

/// Logs the system Back and the start of a predictive Back gesture; never
/// handles them. Flutter asks observers about a system Back one by one, in
/// the order they were added, and stops at the first that handles it - so
/// this one is added before the app starts (ahead of the app's navigator).
/// A gesture's start reaches every observer.
class BackGestureLogger with WidgetsBindingObserver {
  static bool _attached = false;

  static void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(BackGestureLogger());
  }

  @override
  Future<bool> didPopRoute() async {
    NavigationTrace.log('Back pressed (system)');
    return false;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    NavigationTrace.log('Back gesture started (${backEvent.swipeEdge.name} edge)');
    return false;
  }
}
