/// r85: why `BooruHandler.filterFetched` left a loaded post out of a feed.
enum HiddenReason { hiddenTags, doujinBlacklist, marked, ai, mediaType, favourited, snatched, duplicate }

/// The words for what the filters hid, for the feed's banner and the log.
class HiddenByFilters {
  const HiddenByFilters._();

  static String label(HiddenReason reason, int count) => switch (reason) {
    HiddenReason.hiddenTags => '$count with hidden tags',
    HiddenReason.doujinBlacklist => '$count with blacklisted tags',
    HiddenReason.marked => '$count marked',
    HiddenReason.ai => '$count AI',
    HiddenReason.mediaType => '$count of another type',
    HiddenReason.favourited => '$count favourited',
    HiddenReason.snatched => '$count downloaded',
    HiddenReason.duplicate => '$count duplicates',
  };

  /// "14 favourited, 6 with hidden tags" - the biggest first; '' for none.
  static String summary(Map<HiddenReason, int> counts) {
    final List<MapEntry<HiddenReason, int>> entries = [
      for (final MapEntry<HiddenReason, int> e in counts.entries)
        if (e.value > 0) e,
    ]..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.index.compareTo(b.key.index));
    return entries.map((e) => label(e.key, e.value)).join(', ');
  }

  static String title(int loaded) => 'Everything loaded ($loaded) is hidden by your filters';
}
