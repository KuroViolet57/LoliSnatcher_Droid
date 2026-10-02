import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// r77: what closed the viewer. Twice on 19 Sep the viewer closed right after
/// a tap on a tag's preview icon and the log could not say why. Every viewer
/// close is logged ([ViewerCloseObserver]) with its reason (r79: [closing]),
/// and every system Back and Back gesture is logged ([BackGestureLogger]).
class NavigationTrace {
  const NavigationTrace._();

  /// Where the lines go; replaced in tests.
  static void Function(String line) log = _defaultLog;

  static void _defaultLog(String line) => Logger.Inst().log(line, 'NavigationTrace', 'route', LogTypes.booruHandlerInfo);

  /// Why the page closing right now is closing - set only for the length of
  /// the app's own close (see [closing]).
  static String? _reason;

  /// When the last system Back and the last Back gesture started. Replaced in
  /// tests through [now].
  static DateTime? _systemBackAt;
  static DateTime? _gestureAt;
  static DateTime Function() now = DateTime.now;

  /// How long after a system Back a close is put down to it, and after the
  /// start of a Back gesture (the swipe takes a moment before it commits).
  static Duration systemBackWindow = const Duration(seconds: 1);
  static Duration gestureWindow = const Duration(seconds: 5);

  static void resetForTests() {
    log = _defaultLog;
    now = DateTime.now;
    _reason = null;
    _systemBackAt = null;
    _gestureAt = null;
    systemBackWindow = const Duration(seconds: 1);
    gestureWindow = const Duration(seconds: 5);
  }

  /// r79: the app's own code closes a page and says why. The reason holds
  /// only while [close] runs, which covers a pop and a popUntil: the
  /// navigator tells its observers inside the call.
  ///
  /// r77 read the closer off the stack instead. In a release build that
  /// names the wrong function - identical little closures share one copy of
  /// machine code - so on 20 Sep all 34 closes named the Google Drive dialog's
  /// OK button, back-arrow taps included.
  static T closing<T>(String reason, T Function() close) {
    final String? outer = _reason;
    _reason = reason;
    try {
      return close();
    } finally {
      _reason = outer;
    }
  }

  static void noteSystemBack() => _systemBackAt = now();
  static void noteBackGesture() => _gestureAt = now();

  /// Why a viewer is closing now: the app's own reason, else a system Back or
  /// Back gesture that just happened, else "unmarked".
  static String reasonNow() {
    final String? reason = _reason;
    if (reason != null) return reason;
    final DateTime t = now();
    final DateTime? gesture = _gestureAt;
    if (gesture != null && t.difference(gesture) <= gestureWindow) return 'Back gesture (system)';
    final DateTime? back = _systemBackAt;
    if (back != null && t.difference(back) <= systemBackWindow) return 'Back button (system)';
    return "unmarked - not one of the app's own closes, and no system Back just before";
  }

  /// r79: the tag previews' breadcrumb closes the dialogs down to [tag]'s -
  /// and stops at the viewer. r77 stopped only at that tag's dialog or the
  /// feed; the dialogs of a chain are closed as it goes on, so when the
  /// tag's own dialog was already gone it fell through and closed the viewer.
  static bool tagDialogOrViewer(Route<dynamic> route, String tag) =>
      route.settings.name == 'tagDialog/$tag' || route.settings.name == ViewerCloseObserver.viewerRoute || route.isFirst;

  /// r79: closes the dialog [dialogContext] belongs to - only if that dialog
  /// is still the top page. A dialog's action that closes it after an await
  /// (a download started, an item saved) otherwise closed whatever was on top
  /// by then: the viewer, when the dialog had been dismissed meanwhile.
  static bool popIfOnTop(BuildContext dialogContext, String what) {
    final ModalRoute<dynamic>? route = dialogContext.mounted ? ModalRoute.of(dialogContext) : null;
    if (route == null || !route.isCurrent) {
      log('$what was already closed; nothing else is closed in its place');
      return false;
    }
    Navigator.of(dialogContext).pop();
    return true;
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
    final String why = NavigationTrace.reasonNow();
    NavigationTrace.log('viewer $how by: $why');
    PerfTrace.instance.event('viewer.close', why);
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
    NavigationTrace.noteSystemBack();
    NavigationTrace.log('Back pressed (system)');
    return false;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // r79: the app's own predictive-back detector commits the gesture with a
    // plain pop that never passes [didPopRoute], so its start is remembered.
    NavigationTrace.noteBackGesture();
    NavigationTrace.log('Back gesture started (${backEvent.swipeEdge.name} edge)');
    return false;
  }
}
