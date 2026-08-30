import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// For doujin sources whose listing endpoint returns covers and titles but no
/// tags — niyaniya, asmhentai and eahentai all do this; nhentai, hentalk and
/// hitomi hand tags over with the listing.
///
/// Without this the gap is not cosmetic. Grid cards would show an empty tag
/// strip, and — because the per-source blacklist, the doujin favourite-tag
/// stars and the "hidden"/"marked" checks all read `tagsList` — none of them
/// could act on a card until it had been opened once. So tags are backfilled
/// from each gallery's own page after the grid has already painted: the page
/// appears at full speed, then fills in.
///
/// The fetches are deliberately throttled and best-effort. A source that rate
/// limits, or a page that fails to parse, costs an empty strip on that one
/// card and nothing else.
mixin DoujinListingTagBackfill on BooruHandler {
  /// Fetches the tags for one listing item. Return an empty list when they
  /// cannot be had; never throw.
  Future<List<Tag>> tagsForListingItem(BooruItem item);

  /// How many gallery pages are in flight at once.
  int get tagBackfillConcurrency => 3;

  /// Tags already fetched this session, keyed by post URL, so paging back and
  /// forth does not refetch them.
  final Map<String, List<Tag>> _tagCache = {};

  /// Incremented on every new fetch so a backfill left over from a previous
  /// query stops writing into the list the user is now looking at.
  int _generation = 0;

  @override
  Future<void> afterParseResponse(List<BooruItem> newItems) async {
    await super.afterParseResponse(newItems);
    unawaited(_backfill(newItems, ++_generation));
  }

  /// Runs one backfill pass directly, so the caching, cancellation and
  /// failure behaviour can be exercised without the database work the base
  /// class's [afterParseResponse] does.
  @visibleForTesting
  Future<void> backfillForTests(List<BooruItem> items) => _backfill(items, ++_generation);

  Future<void> _backfill(List<BooruItem> items, int generation) async {
    final List<BooruItem> pending = [
      for (final item in items)
        if (item.tagsList.isEmpty && item.postURL.isNotEmpty) item,
    ];
    if (pending.isEmpty) return;

    // Anything already known is filled in immediately and for free.
    final List<BooruItem> toFetch = [];
    for (final item in pending) {
      final List<Tag>? cached = _tagCache[item.postURL];
      if (cached != null) {
        item.tagsList = cached;
      } else {
        toFetch.add(item);
      }
    }
    if (toFetch.isNotEmpty) {
      int next = 0;
      Future<void> worker() async {
        while (true) {
          if (generation != _generation) return;
          final int index = next++;
          if (index >= toFetch.length) return;
          final BooruItem item = toFetch[index];
          try {
            final List<Tag> tags = await tagsForListingItem(item);
            if (generation != _generation) return;
            if (tags.isEmpty) continue;
            _tagCache[item.postURL] = tags;
            item.tagsList = tags;
          } catch (e, s) {
            Logger.Inst().log(
              'tag backfill failed for ${item.postURL}: $e',
              className,
              'tagBackfill',
              LogTypes.booruHandlerRawFetched,
              s: s,
            );
          }
        }
      }

      await Future.wait([
        for (int i = 0; i < tagBackfillConcurrency; i++) worker(),
      ]);
    }

    if (generation != _generation) return;
    // Now that tags exist, the blacklist and the hidden/marked checks finally
    // have something to run against.
    filterFetched();
    // The items were mutated in place, so the filtered list is unchanged by
    // identity and filterFetched's own equality guard suppressed the
    // notification. Hand out a fresh list so the grid repaints with the tag
    // strips it now has.
    filteredFetched.value = [...filteredFetched];
  }
}
