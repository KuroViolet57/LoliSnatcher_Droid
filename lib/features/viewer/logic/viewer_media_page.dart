import 'package:flutter/foundation.dart';

import 'package:photo_view/photo_view.dart';

/// The image page and the ExoPlayer video page as ViewerHandler drives them.
/// The page's State implements it (like ViewerZoomTarget for the fast GIF
/// and media_kit), so the handler reaches the page through its GlobalKey
/// without importing the ui layer.
abstract interface class ViewerMediaPage {
  ValueNotifier<bool> get isZoomed;

  ValueNotifier<bool> get isStopped;

  PhotoViewController get viewController;

  /// What the viewer reports as loaded while this page is current.
  bool get isMediaLoaded;

  /// Whether the page itself is in its own fullscreen (the ExoPlayer controls).
  bool get isMediaFullScreen;

  /// The page's own overlay the viewer hides with its UI: the image's loading
  /// bar, the video's controls.
  ValueNotifier<bool> get extraUi;

  void resetZoom();

  void doubleTapZoom();

  void forceLoad();
}

/// A video page the viewer mutes and pauses (only the ExoPlayer one).
abstract interface class ViewerVideoPage {
  void setVolume(double volume);

  void pause();
}
