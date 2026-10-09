import 'package:flutter/foundation.dart';

/// Below this extent the sheet counts as shut: the peek bar shows and the
/// video controls lift above it.
const double infoSheetPeekExtent = 0.06;

/// Whether the info peek bar's zone is showing (the sheet is shut or nearly).
bool infoSheetInPeekZone(double extent) => extent < infoSheetPeekExtent;

/// Decides when the bottom info sheet builds the tag view.
///
/// The tag view loads the post as soon as it is created, so a shut sheet
/// does not build it for every post the user swipes past. Once the user
/// opens the sheet on a post, the tag view stays for that post.
///
/// The swap from the placeholder list to the tag view must happen BEFORE an
/// open animation starts: the SDK's DraggableScrollableController disposes
/// its running animations when the sheet's scroll position detaches, which
/// the swap does (that is what left the sheet half open on the first tap).
class InfoSheetContentGate {
  /// True while the sheet shows the tag view.
  final ValueNotifier<bool> live = ValueNotifier(false);

  /// The user asked for the sheet (info button, peek bar, or swipe up).
  void requestOpen() => live.value = true;

  /// The sheet moved on its own (a drag); any extent above 0 needs content.
  void onExtent(double extent) {
    if (extent > 0) live.value = true;
  }

  /// The viewer moved to another post. A shut sheet drops the tag view so
  /// the next post is not loaded until asked for; an open one keeps it.
  void onPageChanged(double extent) {
    if (extent <= 0) live.value = false;
  }

  void dispose() => live.dispose();
}
