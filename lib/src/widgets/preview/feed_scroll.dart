import 'package:flutter/widgets.dart';

/// Which scroll notifications the feed may act on (r66).
///
/// The feed fetches its next page when its scrolling nears the bottom, and it
/// hides its bars while scrolling. Both listened to every notification that
/// bubbled up - including a horizontal scroll inside a card (the list card's
/// tag rows and title, the tab cards), and one sitting at its own end looks
/// exactly like the feed near its bottom. So pages were fetched while the user
/// only read tags. Only the feed's own vertical scrolling counts.
class FeedScroll {
  const FeedScroll._();

  static bool isFeedScroll(ScrollNotification notification) =>
      accepts(depth: notification.depth, metrics: notification.metrics);

  /// Depth 0 is the feed itself; anything deeper is a scrollable inside it.
  static bool accepts({required int depth, required ScrollMetrics metrics}) =>
      depth == 0 && metrics.axis == Axis.vertical;
}
