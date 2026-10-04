import 'package:lolisnatcher/gen/strings.g.dart';

/// Enum representing the available gallery toolbar buttons.
enum GalleryButton {
  snatch,
  favourite,
  info,
  share,

  /// r61: opens the sheet of media links found in the post's description. It
  /// used to borrow the share button's place, so switching share off took it
  /// away too.
  linkedMedia,
  select,
  open,
  autoscroll,
  reloadnoscale,
  toggleQuality,
  externalPlayer,
  imageSearch,

  /// r34: "Not interested" on a recommendation feed — a loud no the learner
  /// keeps, and the item leaves the feed.
  notInterested,
  ;

  /// Returns the string value used for JSON serialization.
  /// Maintains backwards compatibility with old string values.
  String toJson() {
    switch (this) {
      case GalleryButton.toggleQuality:
        return 'toggle_quality';
      case GalleryButton.externalPlayer:
        return 'external_player';
      case GalleryButton.imageSearch:
        return 'image_search';
      case GalleryButton.notInterested:
        return 'not_interested';
      case GalleryButton.linkedMedia:
        return 'linked_media';
      default:
        return name;
    }
  }

  /// Creates a GalleryButton from a string value.
  static GalleryButton? fromString(String value) {
    switch (value) {
      case 'snatch':
        return GalleryButton.snatch;
      case 'favourite':
        return GalleryButton.favourite;
      case 'info':
        return GalleryButton.info;
      case 'share':
        return GalleryButton.share;
      case 'select':
        return GalleryButton.select;
      case 'open':
        return GalleryButton.open;
      case 'autoscroll':
        return GalleryButton.autoscroll;
      case 'reloadnoscale':
        return GalleryButton.reloadnoscale;
      case 'toggle_quality':
        return GalleryButton.toggleQuality;
      case 'external_player':
        return GalleryButton.externalPlayer;
      case 'image_search':
        return GalleryButton.imageSearch;
      case 'not_interested':
        return GalleryButton.notInterested;
      case 'linked_media':
        return GalleryButton.linkedMedia;
      default:
        return null;
    }
  }

  /// List of buttons that can be disabled (all except 'info').
  static List<GalleryButton> get disableable => values.where((e) => e != GalleryButton.info).toList();

  /// Whether this button can be disabled by the user.
  bool get canBeDisabled => this != GalleryButton.info;

  bool get isSnatch => this == GalleryButton.snatch;
  bool get isFavourite => this == GalleryButton.favourite;
  bool get isInfo => this == GalleryButton.info;
  bool get isShare => this == GalleryButton.share;
  bool get isLinkedMedia => this == GalleryButton.linkedMedia;
  bool get isSelect => this == GalleryButton.select;
  bool get isOpen => this == GalleryButton.open;
  bool get isAutoscroll => this == GalleryButton.autoscroll;
  bool get isReloadNoScale => this == GalleryButton.reloadnoscale;
  bool get isToggleQuality => this == GalleryButton.toggleQuality;
  bool get isExternalPlayer => this == GalleryButton.externalPlayer;
  bool get isImageSearch => this == GalleryButton.imageSearch;
  bool get isNotInterested => this == GalleryButton.notInterested;

  /// Returns the localized display name for this button.
  String get locName {
    switch (this) {
      case GalleryButton.snatch:
        return loc.galleryButtons.snatch;
      case GalleryButton.favourite:
        return loc.galleryButtons.favourite;
      case GalleryButton.info:
        return loc.galleryButtons.info;
      case GalleryButton.share:
        return loc.galleryButtons.share;
      case GalleryButton.select:
        return loc.galleryButtons.select;
      case GalleryButton.open:
        return loc.galleryButtons.open;
      case GalleryButton.autoscroll:
        return loc.galleryButtons.slideshow;
      case GalleryButton.reloadnoscale:
        return loc.galleryButtons.reloadNoScale;
      case GalleryButton.toggleQuality:
        return loc.galleryButtons.toggleQuality;
      case GalleryButton.externalPlayer:
        return loc.galleryButtons.externalPlayer;
      case GalleryButton.imageSearch:
        return loc.galleryButtons.imageSearch;
      case GalleryButton.notInterested:
        return 'Not interested';
      case GalleryButton.linkedMedia:
        return 'Linked media';
    }
  }
}
