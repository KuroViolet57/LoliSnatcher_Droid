import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The top inset the app lays out with while the status bar is hidden (r50).
class StatusBarInset {
  const StatusBarInset._();

  /// A hidden status bar still leaves the edge where Android watches for the
  /// swipe that brings it back; a top bar drawn there loses taps. So its
  /// space is kept: `padding.top` becomes the reported top view inset.
  /// [drawUnder] is the old full-height layout (Modular UI).
  static MediaQueryData apply(MediaQueryData mq, {required bool hideStatusBar, required bool drawUnder}) {
    if (!hideStatusBar) return mq;
    if (drawUnder) {
      return mq.copyWith(
        padding: mq.padding.copyWith(top: 0),
        viewPadding: mq.viewPadding.copyWith(top: 0),
      );
    }
    return mq.copyWith(padding: mq.padding.copyWith(top: math.max(mq.padding.top, mq.viewPadding.top)));
  }
}
