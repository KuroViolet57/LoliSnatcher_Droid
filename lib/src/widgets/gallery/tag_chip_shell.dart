import 'dart:async';

import 'package:flutter/material.dart';

/// r77: a tag chip's frame - its stadium, its own gestures on the body
/// (tap = menu, double tap = tag editor, hold = new tab) and the preview zone
/// at its right end laid OVER the body as a button of its own.
///
/// The preview icon used to sit inside the body's gesture area, which also
/// listens for double taps, so it only reacted about 0.3 s after the finger
/// left (Flutter holds a lone tap until the double-tap time is up). On 19 Sep
/// the viewer closed in that gap and the preview then opened over the main
/// feed. Laid over the body, the zone is hit first and alone: no double-tap
/// wait. The icon itself is still drawn by [child], so the chip looks and
/// measures the same.
class TagChipShell extends StatefulWidget {
  const TagChipShell({
    required this.color,
    required this.shape,
    required this.child,
    required this.previewZoneWidth,
    required this.onPreview,
    this.onPreviewLongPress,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.previewLabel,
    this.guardRepeats = true,
    super.key,
  });

  final Color color;
  final ShapeBorder shape;
  final Widget child;

  /// How much of the chip's right end is the preview zone.
  final double previewZoneWidth;
  final VoidCallback onPreview;
  final VoidCallback? onPreviewLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  /// The zone's label for accessibility (`Preview red_hair`).
  final String? previewLabel;

  /// A second tap on the zone within [repeatGuard] is dropped (one window,
  /// not two). Off while tags are being selected, where each tap toggles.
  final bool guardRepeats;

  static const Duration repeatGuard = Duration(milliseconds: 500);

  /// The preview zone as the chip draws it: the icon's padded box (11 left,
  /// 8 right) plus the chip's own right padding (2).
  static double previewZoneWidthFor({double iconSize = 16}) => 11 + iconSize + 8 + 2;

  @override
  State<TagChipShell> createState() => _TagChipShellState();
}

class _TagChipShellState extends State<TagChipShell> {
  Timer? _guard;

  void _preview() {
    if (widget.guardRepeats) {
      if (_guard != null) return;
      _guard = Timer(TagChipShell.repeatGuard, () => _guard = null);
    }
    widget.onPreview();
  }

  @override
  void dispose() {
    _guard?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.color,
      shape: widget.shape,
      child: Stack(
        children: [
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            onLongPress: widget.onLongPress,
            child: widget.child,
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: widget.previewZoneWidth,
            child: Semantics(
              button: true,
              label: widget.previewLabel,
              // r77: TalkBack's double tap and hold act on the zone too.
              onTap: _preview,
              onLongPress: widget.onPreviewLongPress,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _preview,
                onLongPress: widget.onPreviewLongPress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
