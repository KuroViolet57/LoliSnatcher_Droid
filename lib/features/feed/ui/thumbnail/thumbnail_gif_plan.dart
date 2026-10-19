/// Largest GIF file the grid will download when the sample is not its own
/// smaller GIF. Checked against danbooru.donmai.us on 2026-10-07: a GIF's
/// sample address is often the file itself, and those files were 260 KB,
/// 840 KB, 1.6 MB, 7.9 MB, and 31 MB. Two mebibytes keeps the first three
/// and leaves the last two as still thumbnails.
const int gifGridFileBytes = 2 * 1024 * 1024;

/// Which address a grid cell loads, and whether that picture may animate.
///
/// GIF thumbnails need Don't scale images as well. ResizeImage keeps a single
/// frame, so an allowed GIF sample is not resized. A hidden post, a video, and
/// a post that still needs its file address stay on the static thumbnail.
/// A GIF file plays in the cell only when its size is known and within
/// [gifGridFileBytes]. An unknown size stays still.
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

  /// False when the cell plays a GIF. A normal sample still decodes down to
  /// the cell.
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
  int? fileSize,
}) {
  final bool sampleIsGif = sampleUrl.contains('.gif');
  final bool gifToggle = disableImageScaling && gifsAsThumbnails;
  final bool sameFileAndSample = !standalone && fileUrl == sampleUrl;
  final bool allowed =
      isAnimation && gifToggle && !isHidden && !isVideo && !needsGuess && !needsLoadItem;
  final bool animate = allowed && sampleIsGif && !sameFileAndSample;
  if (animate) {
    return ThumbnailLoadPlan(
      url: sampleUrl,
      folder: 'samples',
      thumbQuality: false,
      animate: true,
      resize: false,
    );
  }

  // The sample is the file, or it is a still picture of a GIF file. Download
  // that file only when the site told us the size and it is small enough.
  final bool smallGifFile =
      fileSize != null && fileSize > 0 && fileSize <= gifGridFileBytes && _pathEndsWithGif(fileUrl);
  if (allowed && !previewIsThumbnail && smallGifFile && (sameFileAndSample || !sampleIsGif)) {
    return ThumbnailLoadPlan(
      url: fileUrl,
      folder: 'media',
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

bool _pathEndsWithGif(String url) {
  final String path = url.split('?').first.split('#').first.toLowerCase();
  return path.endsWith('.gif');
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
