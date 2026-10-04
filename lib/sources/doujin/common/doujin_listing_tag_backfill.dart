import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';

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

  /// Pause between one worker's fetches. Sources that publish a request budget
  /// need this: niyaniya's API answers `x-ratelimit-limit: 5`, and a backfill
  /// that ignores it spends the whole budget and then 429s every request the
  /// person actually made.
  Duration get tagBackfillDelay => Duration.zero;

  /// Tags already fetched this session, keyed by post URL, so paging back and
  /// forth does not refetch them.
  final Map<String, List<Tag>> _tagCache = {};

  /// Incremented on every new query so a backfill left over from a previous
  /// query stops writing into the list the user is now looking at.
  int _generation = 0;

  /// The pass of the current generation, which the next page's pass waits
  /// for: the earlier page's cards still get their tags, and a rate-limited
  /// source still sees one pass at its own pace.
  Future<void> _lastPass = Future<void>.value();
  int _lastPassGeneration = -1;

  @override
  Future<void> afterParseResponse(List<BooruItem> newItems) async {
    await super.afterParseResponse(newItems);
    // The base search empties the list exactly when prevTags != currentTags,
    // and records the query only after this returns: that is a new query.
    // Another page of the same query joins the running pass instead of
    // abandoning it.
    if (prevTags != currentTags) ++_generation;
    final int generation = _generation;
    final Future<void> before = _lastPassGeneration == generation ? _lastPass : Future<void>.value();
    final Future<void> pass = () async {
      // Never throws: every pass catches its own failure below.
      await before;
      try {
        await _backfill(newItems, generation);
      } catch (e, s) {
        Logger.Inst().log('tag backfill pass failed: $e', className, 'tagBackfill', LogTypes.booruHandlerRawFetched, s: s);
      }
    }();
    _lastPass = pass;
    _lastPassGeneration = generation;
    unawaited(pass);
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
          if (index > 0 && tagBackfillDelay > Duration.zero) {
            await Future.delayed(tagBackfillDelay);
            if (generation != _generation) return;
          }
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
