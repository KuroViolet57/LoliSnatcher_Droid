import 'dart:async';

import 'package:flutter/foundation.dart';

/// A call that runs only once its owner has stayed around for [delay] (r54).
///
/// Each post's details panel used to fetch the post page as soon as it was
/// built, even for posts swiped straight past: with instant swipes that tripped
/// rule34.xxx's rate limit (429 and its CAPTCHA page). The panel schedules its
/// first load with this and cancels it on dispose, so a post swiped past
/// before [delay] sends nothing.
class SettledCall {
  SettledCall(this.delay);

  /// How long a post stays on screen before its details panel loads its data.
  static const Duration itemDataDelay = Duration(milliseconds: 800);

  final Duration delay;
  Timer? _timer;

  /// Runs [run] after [delay]; a call still pending is replaced.
  void schedule(VoidCallback run) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      run();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isPending => _timer?.isActive ?? false;
}
