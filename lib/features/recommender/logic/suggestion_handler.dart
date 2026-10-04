import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/meta_tag.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/features/recommender/logic/item_features.dart';
import 'package:lolisnatcher/features/recommender/logic/recommender_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/suggestion_engine.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
// The handlers/ resolver translates a whole space-separated query term by
// term, which the two-term style facets ("3d mating_press") need.
import 'package:lolisnatcher/features/tags/logic/query_alias_resolver.dart';

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

  // ── r76: a tab's query that carries the post ──

  /// The first term of a suggestion tab's query.
  static const String queryMarker = 'suggest:';

  /// How many distinctive tags the query keeps (rounds rotate through them).
  static const int maxActs = 12;

  /// A tab query that starts with [queryMarker] and names a `post:`.
  static bool isQuery(String query) {
    final List<String> terms = query.trim().split(RegExp(r'\s+'));
    return terms.length >= 2 && terms.first.toLowerCase() == queryMarker && terms.skip(1).any((t) => t.startsWith('post:') && t.length > 'post:'.length);
  }

  static String _esc(String s) => s.replaceAll('%', '%25').replaceAll(' ', '%20');

  static String _unesc(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// What the strip's loader needs from [item], as a tab query:
  /// `suggest: c:<character> f:<series> a:<artist> t:<tag> s:<style>
  /// [with:<filter>] [on:<source>] post:<address>`, in the order the
  /// suggestion engine reads them, spaces and `%` escaped.
  static String queryFor(BooruItem item, {String filter = '', List<Booru>? boorus}) {
    final List<String> terms = [queryMarker];
    for (final String c in SuggestionEngine.tagsOfType(item, TagType.character)) {
      terms.add('c:${_esc(c)}');
    }
    for (final String f in SuggestionEngine.tagsOfType(item, TagType.copyright)) {
      terms.add('f:${_esc(f)}');
    }
    for (final String a in SuggestionEngine.tagsOfType(item, TagType.artist)) {
      terms.add('a:${_esc(a)}');
    }
    final List<Tag> acts = SuggestionEngine.actTags(item).take(maxActs).toList();
    for (final Tag t in acts) {
      terms.add('t:${_esc(t.fullString)}');
    }
    final String? style = SuggestionEngine.styleTag(item);
    if (style != null && !acts.any((t) => t.fullString.trim().toLowerCase().replaceAll(' ', '_') == style)) {
      terms.add('s:${_esc(style)}');
    }
    if (filter.trim().isNotEmpty) terms.add('with:${_esc(filter.trim())}');
    for (final Booru b in boorus ?? const <Booru>[]) {
      if ((b.name ?? '').isNotEmpty) terms.add('on:${_esc(b.name!)}');
    }
    terms.add('post:${_esc(item.postURL.isNotEmpty ? item.postURL : item.fileURL)}');
    return terms.join(' ');
  }

  /// The loader for a tab whose query came from [queryFor]: the post is
  /// rebuilt with the same typed tags (distinctive tags in the same order),
  /// the sources named by `on:` (else the tab's own [booru]), the filter.
  static SuggestionHandler? fromQuery(Booru booru, int limit, String query) {
    if (!isQuery(query)) return null;
    final List<Tag> tags = [];
    final List<Booru> targets = [];
    String post = '';
    String filter = '';
    int acts = 0;
    for (final String term in query.trim().split(RegExp(r'\s+')).skip(1)) {
      final int i = term.indexOf(':');
      if (i <= 0) continue;
      final String key = term.substring(0, i);
      final String value = _unesc(term.substring(i + 1));
      if (value.isEmpty) continue;
      switch (key) {
        case 'c':
          tags.add(Tag(value, tagType: TagType.character));
        case 'f':
          tags.add(Tag(value, tagType: TagType.copyright));
        case 'a':
          tags.add(Tag(value, tagType: TagType.artist));
        case 't':
          // Ascending counts keep the engine's rarest-first order.
          tags.add(Tag(value, count: ++acts));
        case 's':
          if (!tags.any((t) => t.fullString == value)) tags.add(Tag(value));
        case 'with':
          filter = value;
        case 'on':
          for (final Booru b in SettingsHandler.instance.booruList) {
            if (b.name == value) {
              targets.add(b);
              break;
            }
          }
        case 'post':
          post = value;
      }
    }
    if (post.isEmpty) return null;
    final BooruItem source = BooruItem(fileURL: post, sampleURL: '', thumbnailURL: '', tagsList: tags, postURL: post);
    return SuggestionHandler(booru, limit, sourceItem: source, targetBoorus: targets.isEmpty ? null : targets, extraFilter: filter);
  }

  /// The name the recommender logs this strip's exposures under.
  static const String surface = 'suggested';

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

  /// How a target's handler is made; replaced in tests.
  @visibleForTesting
  static BooruHandler Function(Booru booru, int limit)? handlerFactory;

  BooruHandler _handlerFor(Booru b) {
    final String key = _handlerKey(b);
    final BooruHandler? known = _handlers[key];
    if (known != null) return known;
    final BooruHandler made = (handlerFactory?.call(b, limit) ?? BooruHandlerFactory().getBooruHandler([b], limit).booruHandler)
      ..storeTagsGlobally = false;
    _firstPages[key] = made.pageNum;
    return _handlers[key] = made;
  }

  /// The page each target's handler started at, and the last page asked of
  /// each (target, query): every facet query is paged on its own. One
  /// running page per handler made the facets of a round ask pages 1, 2, 3...
  /// of different queries (page 7 of a small character tag is empty).
  final Map<String, int> _firstPages = {};
  final Map<String, int> _pagesAsked = {};

  /// One search at a time per sub-handler: a handler's search is not
  /// re-entrant (its page, query and results are shared), so the facets
  /// that land on one target take turns; targets still run in parallel.
  final Map<BooruHandler, Future<void>> _lanes = {};

  /// Runs [ask] in [handler]'s lane. The answer is given up (null) after
  /// [timeout] counted from now, waiting included, so a round never waits
  /// longer than before; a turn that comes after that is skipped, and the
  /// lane always waits for a running search to end before the next starts.
  Future<List<BooruItem>?> _inLane(BooruHandler handler, Future<List<BooruItem>> Function() ask, Duration timeout) {
    final Completer<List<BooruItem>?> answer = Completer();
    final Timer timer = Timer(timeout, () {
      if (!answer.isCompleted) answer.complete(null);
    });
    final Future<void> turn = (_lanes[handler] ?? Future<void>.value()).then((_) async {
      if (answer.isCompleted) return;
      try {
        final List<BooruItem> got = await ask();
        if (!answer.isCompleted) answer.complete(got);
      } catch (_) {
        if (!answer.isCompleted) answer.complete(null);
      } finally {
        timer.cancel();
      }
    });
    _lanes[handler] = turn.catchError((Object _) {});
    return answer.future;
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
        final String finalQuery = withFilter(query);
        final List<BooruItem>? got = await _inLane(handler, () async {
          final String pageKey = '${_handlerKey(target)}|$finalQuery';
          final int page = (_pagesAsked[pageKey] ?? _firstPages[_handlerKey(target)] ?? handler.pageNum) + 1;
          _pagesAsked[pageKey] = page;
          handler.pageNum = page;
          handler.locked = false;
          final List<BooruItem> all = (await handler.search(finalQuery, null)) as List<BooruItem>? ?? <BooruItem>[];
          // Each sub-handler accumulates across pages; only the newly added
          // tail belongs to this round (taken before the lane moves on).
          return all.length > limit ? all.sublist(all.length - limit) : [...all];
        }, _searchTimeout);
        if (got == null) {
          Logger.Inst().log(
            'suggestion facet $facet timed out on ${target.name}',
            'SuggestionHandler',
            'search',
            LogTypes.booruHandlerInfo,
          );
          return MapEntry(facet, <BooruItem>[]);
        }
        return MapEntry(facet, got);
      }());
    }

    final Map<SuggestionFacet, List<BooruItem>> byFacet = {};
    for (final entry in await Future.wait(requests)) {
      byFacet.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }

    // r35: what the user marked "Not interested" leaves the candidates
    // before the blend, so it is neither re-proposed nor a hole in the page.
    final RecommenderHandler? recommender = RecommenderHandler.maybe;
    if (recommender != null) {
      for (final SuggestionFacet facet in byFacet.keys.toList()) {
        byFacet[facet] = await recommender.withoutDismissed(byFacet[facet]!);
      }
    }
    final List<BooruItem> raw = SuggestionEngine.blend(
      byFacet,
      source: sourceItem,
      exclude: _servedKeys,
      limit: limit,
    );
    // r33: the user's taste orders the strip within the blend's own caps —
    // half taste, half the facet order, so the mix stays varied.
    final List<BooruItem> blended = await (RecommenderHandler.maybe?.rerank(raw, world: ItemFeatures.worldOfBooru(booru), mix: 0.5) ?? Future.value(raw));
    unawaited(RecommenderHandler.maybe?.onExposed(blended, surface) ?? Future<void>.value());
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
