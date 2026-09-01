import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
// The handlers/ resolver translates a whole space-separated query term by
// term, which the two-term style facets ("3d mating_press") need.
import 'package:lolisnatcher/src/handlers/tag_alias_resolver.dart';

/// Virtual handler that serves the blended suggestions for one post.
///
/// Each "page" fires every facet query (see [SuggestionEngine]) in parallel on
/// the target booru(s), then blends the results round-robin under per-facet
/// quotas and per-artist / per-character caps. Scrolling deepens each facet's
/// page and rotates which character/act tags are used, so the strip keeps
/// producing new material instead of repeating the first blend.
class SuggestionHandler extends BooruHandler {
  SuggestionHandler(
    super.booru,
    super.limit, {
    required this.sourceItem,
    List<Booru>? targetBoorus,
    this.extraFilter = '',
  }) : targetBoorus = (targetBoorus == null || targetBoorus.isEmpty) ? [booru] : targetBoorus;

  /// A constraint every facet query must also satisfy — the strip header's
  /// videos/GIFs toggle, for instance.
  ///
  /// [search]'s `tags` argument is NOT this: the strip passes a placeholder
  /// ('suggestions') as its tag, because the query is built from the source
  /// post rather than from a tag. That is why the toggle appeared to do
  /// nothing — the filter was assembled into a string this handler never read,
  /// and every facet went out unconstrained.
  final String extraFilter;

  /// Applies [extraFilter] to one facet query.
  @visibleForTesting
  String withFilter(String query) {
    final String filter = extraFilter.trim();
    if (filter.isEmpty) return query;
    if (query.trim().isEmpty) return filter;
    return '$query $filter';
  }

  /// The post the suggestions are built around.
  final BooruItem sourceItem;

  /// Boorus to query. One entry = the post's own booru (post view); several =
  /// cross-booru discovery ("find elsewhere"), where each facet tag is first
  /// translated to that booru's own spelling.
  final List<Booru> targetBoorus;

  bool get isCrossBooru => targetBoorus.length > 1;

  final Map<String, BooruHandler> _handlers = {};
  final Set<String> _servedKeys = {};

  int _round = 0;
  int _emptyStreak = 0;

  static const Duration _resolveTimeout = Duration(seconds: 6);
  static const Duration _searchTimeout = Duration(seconds: 12);

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String validateTags(String tags) => tags;

  @override
  List<MetaTag> availableMetaTags() => [];

  String _handlerKey(Booru b) => '${b.type?.name}|${b.name}|${b.baseURL}';

  BooruHandler _handlerFor(Booru b) {
    return _handlers[_handlerKey(b)] ??= (BooruHandlerFactory().getBooruHandler([b], limit).booruHandler
      ..storeTagsGlobally = false);
  }

  Future<T?> _bounded<T>(Future<T> Function() run, Duration timeout) async {
    try {
      return await run().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<dynamic> search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    // Rotate the facet seed per round so later pages lean on different
    // characters / act tags rather than paging deeper into the same ones.
    final List<SuggestionFacet> facets = SuggestionEngine.facetsForItem(sourceItem, seed: _round);
    if (facets.isEmpty) {
      errorString = 'This post has no tags to build suggestions from.';
      locked = true;
      return fetched;
    }

    final int before = fetched.length;
    final List<Future<MapEntry<SuggestionFacet, List<BooruItem>>>> requests = [];

    for (int i = 0; i < facets.length; i++) {
      final SuggestionFacet facet = facets[i];
      // Cross-booru mode spreads facets over the configured boorus so one
      // page shows several sites at once instead of hammering one.
      final Booru target = targetBoorus[(i + _round) % targetBoorus.length];

      requests.add(() async {
        String query = facet.query;
        if (isCrossBooru) {
          final String? aliased = await _bounded(
            () => TagAliasResolver.resolveQuery(query, target).then((r) => r.query),
            _resolveTimeout,
          );
          if (aliased != null && aliased.trim().isNotEmpty) query = aliased;
        }

        final BooruHandler handler = _handlerFor(target);
        handler.pageNum = handler.pageNum + 1;
        handler.locked = false;
        final String finalQuery = withFilter(query);
        final List<BooruItem>? got = await _bounded(
          () async => (await handler.search(finalQuery, null)) as List<BooruItem>? ?? <BooruItem>[],
          _searchTimeout,
        );
        if (got == null) {
          Logger.Inst().log(
            'suggestion facet $facet timed out on ${target.name}',
            'SuggestionHandler',
            'search',
            LogTypes.booruHandlerInfo,
          );
          return MapEntry(facet, <BooruItem>[]);
        }
        // Each sub-handler accumulates across pages; only the newly added
        // tail belongs to this round.
        return MapEntry(facet, got.length > limit ? got.sublist(got.length - limit) : [...got]);
      }());
    }

    final Map<SuggestionFacet, List<BooruItem>> byFacet = {};
    for (final entry in await Future.wait(requests)) {
      byFacet.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }

    final List<BooruItem> blended = SuggestionEngine.blend(
      byFacet,
      source: sourceItem,
      exclude: _servedKeys,
      limit: limit,
    );
    for (final item in blended) {
      _servedKeys.add(item.postURL.isNotEmpty ? item.postURL : item.fileURL);
    }

    _round++;

    if (blended.isEmpty) {
      // A dry round doesn't mean the well is dry — the next round rotates to
      // different facet tags. Bounded so scrolling can't loop forever.
      _emptyStreak++;
      if (_emptyStreak <= 2) {
        return search(tags, null, withCaptchaCheck: withCaptchaCheck);
      }
      _emptyStreak = 0;
      locked = true;
      return fetched;
    }
    _emptyStreak = 0;

    await afterParseResponse(blended);
    if (fetched.length == before) {
      locked = true;
    }
    return fetched;
  }

  @override
  Future<void> searchCount(String input) async {
    // Endless blended feed — no meaningful total.
    totalCount.value = 0;
  }
}
