import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

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

/// [StatusBarInset] for the app's page tree (r52). The tree lives in an
/// Overlay entry that is built once, so a MediaQuery made in the app builder
/// kept the first frame's insets: the keyboard never reached a page while the
/// status bar was hidden, and it covered bottom sheets. This reads the insets
/// where it is built, so it follows the keyboard on its own.
class HiddenStatusBarInsets extends StatelessWidget {
  const HiddenStatusBarInsets({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ModularUi.revision,
      builder: (context, _, _) => MediaQuery(
        data: StatusBarInset.apply(
          MediaQuery.of(context),
          hideStatusBar: SettingsHandler.instance.hideStatusBar,
          drawUnder: ModularUi.isOn(ModularUi.appDrawUnderHiddenStatusBar),
        ),
        child: child,
      ),
    );
  }
}
