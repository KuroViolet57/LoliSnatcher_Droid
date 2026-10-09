import 'package:flutter/foundation.dart';

import 'package:photo_view/photo_view.dart';

/// A viewer page the zoom button can drive (the fast GIF and the media_kit
/// video). The page's State implements it, so ViewerHandler reaches the page
/// through its GlobalKey without importing the ui layer.
abstract interface class ViewerZoomTarget {
  ValueNotifier<bool> get isZoomed;

  PhotoViewController get viewController;

  /// What the viewer reports as loaded while this page is current.
  bool get isZoomTargetLoaded;

  void doubleTapZoom();

  void resetZoom();
}
