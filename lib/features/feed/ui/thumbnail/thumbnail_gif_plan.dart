/// Which address a grid cell loads, and whether that picture may animate.
///
/// GIF thumbnails need Don't scale images as well. ResizeImage keeps a single
/// frame, so an allowed GIF sample is not resized. A hidden post, a video, a
/// post that still needs its file address, and a sample that is the full file
/// stay on the static thumbnail.
class ThumbnailLoadPlan {
  const ThumbnailLoadPlan({
    required this.url,
    required this.folder,
    required this.thumbQuality,
    required this.animate,
    required this.resize,
  });

  final String url;
  final String folder;
  final bool thumbQuality;
  final bool animate;

  /// False only for the animated GIF sample. A normal sample still decodes
  /// down to the cell.
  final bool resize;
}

ThumbnailLoadPlan planThumbnailLoad({
  required bool previewIsThumbnail,
  required bool isAnimation,
  required bool disableImageScaling,
  required bool gifsAsThumbnails,
  required bool isHidden,
  required bool isVideo,
  required bool needsGuess,
  required bool needsLoadItem,
  required bool standalone,
  required String fileUrl,
  required String sampleUrl,
  required String thumbnailUrl,
}) {
  final bool sampleIsGif = sampleUrl.contains('.gif');
  final bool gifToggle = disableImageScaling && gifsAsThumbnails;
  final bool sameFileAndSample = !standalone && fileUrl == sampleUrl;
  final bool animate =
      isAnimation &&
      gifToggle &&
      !isHidden &&
      sampleIsGif &&
      !isVideo &&
      !needsGuess &&
      !needsLoadItem &&
      !sameFileAndSample;
  if (animate) {
    return ThumbnailLoadPlan(
      url: sampleUrl,
      folder: 'samples',
      thumbQuality: false,
      animate: true,
      resize: false,
    );
  }

  final bool gifBlocked = isAnimation && (gifToggle ? isHidden : true);
  final bool thumbQuality =
      previewIsThumbnail || gifBlocked || isVideo || needsGuess || needsLoadItem || sameFileAndSample;
  if (thumbQuality) {
    return _staticThumb(thumbnailUrl);
  }
  return ThumbnailLoadPlan(
    url: sampleUrl,
    folder: 'samples',
    thumbQuality: false,
    animate: false,
    resize: true,
  );
}

ThumbnailLoadPlan _staticThumb(String thumbnailUrl) {
  return ThumbnailLoadPlan(
    url: thumbnailUrl,
    folder: 'thumbnails',
    thumbQuality: true,
    animate: false,
    resize: true,
  );
}
