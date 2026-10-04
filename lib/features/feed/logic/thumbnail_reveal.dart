import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Grid thumbnails already shown this session appear at once (r56).
///
/// A grid thumbnail waited [loadDelay] before it started loading (so a fast
/// scroll does not start loads for thumbnails it flies past) and then faded
/// in, even when the picture was already in memory; in the profiling the slow
/// grid frames drew up to 32 fading thumbnails, each its own layer. With the
/// Modular UI switch on, a thumbnail whose URL was shown before this session
/// skips the wait, and one shown before or answered from the memory cache
/// appears without the fade. A thumbnail never shown keeps both.
class ThumbnailReveal {
  const ThumbnailReveal._();

  /// The wait before a grid thumbnail starts loading.
  static const Duration loadDelay = Duration(milliseconds: 200);

  /// How many thumbnail URLs are remembered; the one seen longest ago goes first.
  static const int maxRemembered = 4000;

  static final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  static bool seen(String url) => _seen.contains(url);

  static int get rememberedCount => _seen.length;

  /// Marks [url] as shown, as the newest entry.
  static void remember(String url) {
    _seen.remove(url);
    _seen.add(url);
    while (_seen.length > maxRemembered) {
      _seen.remove(_seen.first);
    }
  }

  /// The wait before loading: [loadDelay] for a grid thumbnail, none when
  /// [instant] is on and [url] was shown before, none outside the grid.
  static Duration delayFor({required bool isStandalone, required bool instant, required String url}) =>
      isStandalone && !(instant && seen(url)) ? loadDelay : Duration.zero;

  /// The fade-in: [normal], or none when [instant] is on and the picture was
  /// shown before or came from the memory cache ([syncCall]).
  static Duration fadeFor({
    required Duration normal,
    required bool instant,
    required bool seenBefore,
    required bool syncCall,
  }) => instant && (seenBefore || syncCall) ? Duration.zero : normal;

  @visibleForTesting
  static void resetForTests() => _seen.clear();
}
