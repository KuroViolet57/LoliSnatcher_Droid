import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/data/settings/preview_display_mode.dart';

/// The size a thumbnail is decoded at (r69).
///
/// Thumbnails used to be decoded for the app-wide preview SHAPE - square by
/// default - whatever box they were drawn in. A 450x629 doujin cover in a
/// 116x176 list column (406x616 px on a 3.5x screen) was decoded to fit a
/// 406x406 box, so 290x406, and then drawn 1.4x larger than that: blur the
/// app added itself. A cover in a bounded box now decodes for that box, with
/// slack for the difference between the cover's shape and the box's; nothing
/// else changes.
class ThumbnailDecodeBox {
  const ThumbnailDecodeBox._();

  /// How much larger than the box a cover may decode. A cover drawn cover-fit
  /// is scaled by the LARGER of the two ratios box/image, and a 0.7 cover in
  /// a square cell needs 1.43x the box's width for that; the decode never
  /// upscales, so a small source stays at its own size.
  static const double coverSlack = 1.5;

  static ({double? width, double? height}) of({
    required BoxConstraints constraints,
    required double devicePixelRatio,
    required PreviewDisplayMode mode,
    required bool isStandalone,
    required bool isCover,
    double? aspectRatio,
  }) {
    final double widthLimit = constraints.maxWidth * devicePixelRatio;
    if (!isStandalone) return (width: widthLimit, height: null);

    if (isCover && constraints.hasBoundedWidth && constraints.hasBoundedHeight && constraints.maxHeight > 0) {
      return (
        width: widthLimit * coverSlack,
        height: constraints.maxHeight * devicePixelRatio * coverSlack,
      );
    }

    switch (mode) {
      case PreviewDisplayMode.rectangle:
        return (width: widthLimit, height: widthLimit * 16 / 9);
      case PreviewDisplayMode.staggered:
        if (aspectRatio != null) {
          // vertical image - resize to width; horizontal - to height
          if (aspectRatio < 1) return (width: widthLimit, height: null);
          return (width: null, height: widthLimit * aspectRatio);
        }
        return (width: widthLimit, height: widthLimit * 16 / 9);
      case PreviewDisplayMode.square:
        return (width: widthLimit, height: widthLimit);
    }
  }
}
