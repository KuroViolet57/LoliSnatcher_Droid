import 'dart:async';

import 'package:flutter/widgets.dart';

/// How a pick ended.
enum PickOutcome {
  /// A picture came back.
  picture,

  /// The picker answered, with nothing (a cancel looks like this).
  nothing,

  /// No answer ever came: the picker closed without one, or nothing opened.
  lost,

  /// The picker threw.
  failed,
}

/// What came back from a picture picker, and how long it was open.
class PickResult<T> {
  const PickResult(this.value, this.outcome, this.openMs, {this.error, this.reason = ''});

  final T? value;
  final PickOutcome outcome;
  final int openMs;
  final Object? error;

  /// Why we gave up, for [PickOutcome.lost].
  final String reason;

  String get openFor => '${(openMs / 1000).toStringAsFixed(1)} s';
}

/// r78: a picture pick that cannot hang for good.
///
/// On 19 Sep "Try it on a picture" did nothing and logged nothing. A pick
/// whose answer never arrives - which the app's old result handling could
/// cause, by answering the picker's return on a reply that was already used -
/// left the caller waiting for ever: the button stayed on "Reading…" and
/// every later tap did nothing at all.
///
/// So a pick is watched. While the picker is in front the app is away, and we
/// wait however long the person takes. When the app comes back the answer is
/// due within [afterResume]; if it does not arrive, the pick is given up on
/// and the caller can say so. [hardLimit] covers the case where nothing ever
/// opened. An answer that arrives after that is still handed to the caller's
/// `onLate` rather than thrown away.
class PickerWatch {
  const PickerWatch._();

  /// How long an answer may take after the app comes back to the screen.
  static Duration afterResume = const Duration(seconds: 6);

  /// The backstop when the app never left (no picker ever opened).
  static Duration hardLimit = const Duration(minutes: 5);

  static void resetForTests() {
    afterResume = const Duration(seconds: 6);
    hardLimit = const Duration(minutes: 5);
  }

  static Future<PickResult<T>> run<T>(Future<T?> Function() pick, {void Function(T value)? onLate}) => _Watch<T>(onLate).start(pick);
}

class _Watch<T> with WidgetsBindingObserver {
  _Watch(this.onLate);

  final void Function(T value)? onLate;
  final Completer<PickResult<T>> _done = Completer<PickResult<T>>();
  final Stopwatch _clock = Stopwatch();
  Timer? _back;
  Timer? _hard;
  bool _left = false;
  bool _settled = false;

  Future<PickResult<T>> start(Future<T?> Function() pick) {
    _clock.start();
    WidgetsBinding.instance.addObserver(this);
    _hard = Timer(PickerWatch.hardLimit, () => _giveUp('no answer from the picker'));
    unawaited(Future<T?>.sync(pick).then(_answer, onError: _failed));
    return _done.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_settled) return;
    if (state != AppLifecycleState.resumed) {
      // The picker is in front. However long it takes is the person's own time.
      _left = true;
      _back?.cancel();
      _back = null;
      return;
    }
    if (_left) _back ??= Timer(PickerWatch.afterResume, () => _giveUp('the picker closed without an answer'));
  }

  void _answer(T? value) {
    if (_settled) {
      if (value != null) onLate?.call(value);
      return;
    }
    _settle(PickResult<T>(value, value == null ? PickOutcome.nothing : PickOutcome.picture, _clock.elapsedMilliseconds));
  }

  void _failed(Object error, StackTrace stack) {
    if (_settled) return;
    _settle(PickResult<T>(null, PickOutcome.failed, _clock.elapsedMilliseconds, error: error));
  }

  void _giveUp(String reason) {
    if (_settled) return;
    _settle(PickResult<T>(null, PickOutcome.lost, _clock.elapsedMilliseconds, reason: reason));
  }

  void _settle(PickResult<T> result) {
    _settled = true;
    _clock.stop();
    _back?.cancel();
    _hard?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _done.complete(result);
  }
}
