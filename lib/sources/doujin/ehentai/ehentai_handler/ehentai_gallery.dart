part of '../ehentai_handler.dart';

/// What a gallery page says about a gallery.
class EHentaiGallery {
  const EHentaiGallery({
    required this.gid,
    required this.token,
    required this.title,
    required this.titleJpn,
    required this.category,
    required this.uploader,
    required this.posted,
    required this.language,
    required this.pages,
    required this.favorited,
    required this.rating,
    required this.tags,
    required this.pageKeys,
    required this.pageThumbs,
    required this.blockSize,
    required this.newerVersions,
    required this.parentGid,
    required this.parentToken,
    required this.cover,
  });

  final String gid;
  final String token;
  final String title;
  final String titleJpn;
  final String category;
  final String uploader;
  final String posted;
  final String language;
  final int pages;
  final int favorited;
  final String rating;
  final List<Tag> tags;

  /// Page number -> image key, for the pages the fetched block showed.
  final Map<int, String> pageKeys;

  /// Page number -> thumbnail for the same pages: a tile of the block's
  /// sprite strip (`strip.webp#xywh=x,y,w,h`), or an image URL in an
  /// account's individual-image mode. Strip links expire within days, so
  /// these are session data (`BooruItem.transientThumbnailURL`).
  final Map<int, String> pageThumbs;

  /// Pages per gallery page (20, or 40 with the account setting).
  final int blockSize;
  final List<(String gid, String token)> newerVersions;
  final String? parentGid;
  final String? parentToken;
  final String cover;
}
