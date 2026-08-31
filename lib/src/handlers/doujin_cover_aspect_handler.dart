import 'package:flutter/foundation.dart';

/// Cover aspect ratios, learned from the image the source actually served.
///
/// The "adapt" cover-display mode is supposed to size the card to the cover.
/// It was built on `BooruItem.fileWidth/fileHeight`, which only nhentai and
/// niyaniya fill in — on EAHentai, hentalk, hitomi and ASMHentai the listing
/// carries no dimensions at all, so adapt silently fell back to a fixed grid
/// and letterboxed every cover. That is the dead space in the recording.
///
/// A cover's real aspect is knowable without the API's help: it is in the
/// decoded image. Every thumbnail that decodes reports its size here, keyed by
/// its own URL, and the one cell showing that cover re-lays itself out. Cells
/// whose cover has not decoded yet use [provisional] so the grid is stable and
/// close before anything loads.
class DoujinCoverAspects {
  DoujinCoverAspects._();

  static final DoujinCoverAspects instance = DoujinCoverAspects._();

  /// Doujin covers are overwhelmingly B5-ish portrait. Used only until the
  /// real cover decodes, so a wrong guess costs one relayout, never dead space.
  static const double provisional = 0.7;

  /// Nothing outside this range is a cover — a 1px tracking pixel or a broken
  /// response must not be allowed to size a card.
  static const double minAspect = 0.2;
  static const double maxAspect = 5;

  /// A long feed can hold thousands of items, so the map is bounded. Evicted
  /// entries are dropped, never disposed: a cell still listening to one keeps
  /// working off its own reference, and a cell rebuilt later simply relearns
  /// its aspect from the next decode.
  static const int maxEntries = 2000;

  final Map<String, ValueNotifier<double?>> _byKey = {};

  ValueNotifier<double?> notifierFor(String key) {
    final ValueNotifier<double?>? existing = _byKey[key];
    if (existing != null) return existing;
    if (_byKey.length >= maxEntries) {
      _byKey.remove(_byKey.keys.first);
    }
    return _byKey[key] = ValueNotifier<double?>(null);
  }

  double? aspectFor(String key) => _byKey[key]?.value;

  /// Records what actually decoded. Ignores sizes that cannot be a cover.
  void record(String key, int width, int height) {
    if (key.isEmpty || width <= 0 || height <= 0) return;
    final double aspect = width / height;
    if (aspect < minAspect || aspect > maxAspect) return;
    final ValueNotifier<double?> notifier = notifierFor(key);
    if (notifier.value == aspect) return;
    notifier.value = aspect;
  }

  /// The aspect a cell should lay out at right now.
  double effectiveAspect(String key) => aspectFor(key) ?? provisional;

  @visibleForTesting
  void resetForTests() {
    for (final n in _byKey.values) {
      n.dispose();
    }
    _byKey.clear();
  }
}
