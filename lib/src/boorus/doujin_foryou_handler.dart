import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The doujin For You (r33): a virtual doujin source that asks the
/// configured doujin sites for what the reading history and the learner
/// point at, and hands each card to the source it came from for everything
/// else (the detail page, the reader, the strips, page thumbnails).
///
/// The booru For You's shape, for the other world: galleries you read
/// contribute facets (their parody, character, artist, two act tags), each
/// facet is asked on a rotating source in the sites' shared namespace
/// grammar (`parody:x`, `female:y` — the handlers translate to their own
/// spelling), the answers are blended under per-artist / per-character
/// caps, what you already read is left out, and the recommender reranks the
/// page and is told what was shown. The dominant reading language becomes
/// a constraint on the sites that understand one.
///
/// Config travels in the tab's search string, as for the booru feed:
///   ''                            -> history mode
///   'seed:parody:x seed:artist:y' -> seed mode (plain namespaced terms too)
///   '-female:z' / 'filter:…'      -> constraints on every query
class DoujinForYouHandler extends BooruHandler {
  DoujinForYouHandler(super.booru, super.limit);

  static const String surface = 'foryou-doujin';

  /// Test seam: builds a source's handler in place of the factory.
  @visibleForTesting
  static BooruHandler Function(Booru booru, int limit)? sourceHandlerFactory;

  /// Sources whose search grammar takes a `language:` term.
  static bool understandsLanguage(Booru booru) => switch (booru.type) {
    BooruType.NHentai || BooruType.EHentai || BooruType.Hitomi => true,
    _ => false,
  };

  static const int maxSources = 8;
  static const int _sourcesPerPage = 3;
  static const int _entriesPerPage = 3;
  static const int _facetsPerEntry = 3;
  static const int _historyDepth = 60;
  static const Duration defaultSearchTimeout = Duration(seconds: 15);

  /// How long a page waits for one source's answer. The request itself is
  /// not cut short: its lane stays taken until it really finishes, so the
  /// next question to that source never re-enters the handler.
  @visibleForTesting
  static Duration searchTimeout = defaultSearchTimeout;

  final Random _rand = Random();

  /// The configured doujin sources this feed draws from — refreshed on every
  /// page, so a source added while the tab is open joins in.
  final List<Booru> sources = [];
  final Map<String, BooruHandler> _handlers = {};

  bool _inited = false;
  String? _initedTags;
  int _feedPage = 0;
  int _rotation = 0;
  int _emptyStreak = 0;
  final Set<String> _servedKeys = {};

  /// What the history holds, refreshed per page.
  Set<String> _readKeys = const {};

  List<String> seeds = [];
  String extraFilter = '';

  /// The reading language most of the history is in ('' when there is no
  /// clear one).
  String language = '';

  List<DoujinEntry> _history = [];

  @override
  bool get hasReader => true;

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

  // ── the cards belong to their sources ──

  BooruHandler _handlerFor(Booru source) {
    final String key = DoujinDataHandler.hostOf(source);
    return _handlers[key] ??= (sourceHandlerFactory?.call(source, limit) ?? BooruHandlerFactory().getBooruHandler([source], limit).booruHandler)
      ..storeTagsGlobally = false;
  }

  @override
  BooruHandler handlerForItem(BooruItem item) {
    final String? host = Uri.tryParse(item.postURL)?.host;
    if (host == null || host.isEmpty) return this;
    for (final Booru source in sources) {
      if (DoujinDataHandler.hostOf(source) == host) return _handlerFor(source);
    }
    final Booru? configured = DoujinDataHandler.doujinBooruForItem(item);
    return configured == null ? this : _handlerFor(configured);
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) {
    final BooruHandler owner = handlerForItem(item);
    if (identical(owner, this)) {
      return Future.value((item: null, failed: true, error: 'no configured source for ${item.postURL}'));
    }
    return owner.loadItem(item: item, cancelToken: cancelToken, withCapcthaCheck: withCapcthaCheck);
  }

  @override
  String? relatedVersionsQuery(BooruItem item) {
    final BooruHandler owner = handlerForItem(item);
    return identical(owner, this) ? null : owner.relatedVersionsQuery(item);
  }

  @override
  Future<void> ensurePageThumbnail(BooruItem page, {CancelToken? cancelToken}) {
    final BooruHandler owner = handlerForItem(page);
    return identical(owner, this) ? Future.value() : owner.ensurePageThumbnail(page, cancelToken: cancelToken);
  }

  @override
  void forgetPageThumbnail(BooruItem page) {
    final BooruHandler owner = handlerForItem(page);
    if (!identical(owner, this)) owner.forgetPageThumbnail(page);
  }

  // ── what to ask for ──

  static const Set<String> _characterNamespaces = {'character'};
  static const Set<String> _parodyNamespaces = {'parody', 'series'};
  static const Set<String> _artistNamespaces = {'artist', 'group', 'circle', 'cosplayer'};
  static const Set<String> _skippedNamespaces = {'language', 'category', 'type', 'magazine', 'publisher', 'uploader'};

  /// The facets one remembered gallery contributes: its character(s), its
  /// parody, its artist (a small quota — the artist's shelf is one tap away),
  /// two of its act tags. [seed] rotates which character and acts are used
  /// across pages.
  static List<SuggestionFacet> facetsForEntry(DoujinEntry entry, {int seed = 0}) {
    final List<String> characters = [];
    final List<String> parodies = [];
    final List<String> artists = [];
    final List<String> acts = [];
    for (final String raw in entry.tags) {
      final int colon = raw.indexOf(':');
      final String ns = colon > 0 ? raw.substring(0, colon).toLowerCase() : '';
      if (_skippedNamespaces.contains(ns)) continue;
      if (_characterNamespaces.contains(ns)) {
        characters.add(raw);
      } else if (_parodyNamespaces.contains(ns)) {
        parodies.add(raw);
      } else if (_artistNamespaces.contains(ns)) {
        artists.add(raw);
      } else {
        acts.add(raw);
      }
    }
    String rotate(List<String> list, int offset) => list[(seed + offset) % list.length];
    final List<SuggestionFacet> facets = [];
    if (characters.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.character, query: rotate(characters, 0), quota: 6));
    }
    if (parodies.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.franchise, query: rotate(parodies, 0), quota: 5));
    }
    // An act before the artist: a page takes the first three facets, and
    // the artist's shelf is one tap away already.
    if (acts.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.act, query: acts[seed % acts.length], quota: 4));
    }
    if (artists.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.artist, query: rotate(artists, 0), quota: 3));
    }
    if (acts.length > 1) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.act, query: acts[(seed + 1) % acts.length], quota: 4));
    }
    return facets;
  }

  /// The language most of [history] carries, when it is a clear majority
  /// (at least 60 % of the entries that name one); '' otherwise.
  static String dominantLanguage(List<DoujinEntry> history) {
    final Map<String, int> counts = {};
    int named = 0;
    for (final DoujinEntry e in history) {
      String? language;
      for (final String tag in e.tags) {
        if (tag.startsWith('language:')) {
          language = tag.substring('language:'.length);
          break;
        }
      }
      if (language == null || language.isEmpty || language == 'translated') continue;
      named++;
      counts[language] = (counts[language] ?? 0) + 1;
    }
    if (named == 0) return '';
    final MapEntry<String, int> top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return top.value / named >= 0.6 ? top.key : '';
  }

  @visibleForTesting
  static String parseFilter(String input) {
    final List<String> parts = [];
    for (final String term in input.split(' ').where((t) => t.trim().isNotEmpty)) {
      final String t = term.trim();
      if (t.startsWith('-') && t.length > 1) {
        parts.add(t);
      } else if (t.toLowerCase().startsWith('filter:') && t.length > 'filter:'.length) {
        parts.add(t.substring('filter:'.length));
      }
    }
    return parts.join(' ');
  }

  static List<String> parseSeeds(String input) {
    final List<String> out = [];
    for (final String term in input.split(' ').where((t) => t.trim().isNotEmpty)) {
      String t = term.trim().toLowerCase();
      if (t.startsWith('-') || t.startsWith('filter:')) continue;
      if (t.startsWith('seed:')) t = t.substring('seed:'.length);
      if (t.isEmpty || t.startsWith('sort:') || t.startsWith('pages:')) continue;
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  /// One source's query: the facet, the user's constraints, and the reading
  /// language on the sites that take one.
  String queryFor(Booru source, String facet) {
    final List<String> parts = [facet.trim()];
    if (extraFilter.trim().isNotEmpty) parts.add(extraFilter.trim());
    if (language.isNotEmpty && understandsLanguage(source)) parts.add('language:$language');
    return parts.where((p) => p.isNotEmpty).join(' ');
  }

  /// The configured doujin sources as of now.
  void _refreshSources() {
    sources.clear();
    for (final Booru b in DoujinDataHandler.doujinSources()) {
      if ((b.baseURL ?? '').isEmpty) continue;
      sources.add(b);
      if (sources.length >= maxSources) break;
    }
  }

  Future<void> _init(String tags) async {
    if (_inited && _initedTags == tags) return;
    final bool firstInit = !_inited;
    _inited = true;
    _initedTags = tags;
    if (firstInit) {
      storeTagsGlobally = false;
    } else {
      _feedPage = 0;
      _emptyStreak = 0;
      locked = false;
    }
    seeds = parseSeeds(tags);
    extraFilter = parseFilter(tags);
    final DoujinDataHandler data = DoujinDataHandler.instance..ensureLoaded();
    _history = data.history.where((e) => e.tags.isNotEmpty).take(_historyDepth).toList();
    language = dominantLanguage(_history);
    // The learner's view of what was read leads: galleries it scores high
    // contribute their facets first.
    final RecommenderHandler? recommender = RecommenderHandler.maybe;
    if (recommender != null && recommender.recommendationsEnabled && _history.length > 1) {
      final List<double> scores = await Future.wait([
        for (final DoujinEntry e in _history)
          recommender.scoreDoujinParts(namespacedTags: e.tags, title: e.title, host: e.booruHost, pages: e.pages),
      ]);
      final List<int> order = List.generate(_history.length, (i) => i)
        ..sort((a, b) => scores[b].compareTo(scores[a]));
      _history = [for (final int i in order) _history[i]];
    }
    _rotation = sources.length <= 1 ? 0 : _rand.nextInt(sources.length);
  }

  bool _isRead(BooruItem item) => _readKeys.contains(item.postURL);

  bool _isDuplicate(BooruItem item) => _servedKeys.contains(item.postURL);

  /// What the last page asked each source and what came back, for the live
  /// report and the log.
  @visibleForTesting
  final List<({String source, String query, int got, int kept, String error})> lastRequests = [];

  /// One request at a time per source: a handler's search is not
  /// re-entrant (query, cursor and result state are shared), so three
  /// facets fired at one site at once came back empty. Sources still run in
  /// parallel with each other.
  final Map<String, Future<void>> _lanes = {};

  Future<List<BooruItem>> _ask(Booru source, String query) {
    final String lane = DoujinDataHandler.hostOf(source);
    final Completer<List<BooruItem>> answer = Completer();
    final Future<void> run = (_lanes[lane] ?? Future<void>.value()).then((_) async {
      final Future<List<BooruItem>> real = _askNow(source, query);
      // The page waits for the answer for [searchTimeout], counted from the
      // moment the question was really asked (not from when it was queued
      // behind the source's previous one); the lane waits for the real
      // answer, so the next question never re-enters the handler.
      unawaited(
        real.timeout(searchTimeout).then(
          (got) {
            if (!answer.isCompleted) answer.complete(got);
          },
          onError: (Object _) {
            if (answer.isCompleted) return;
            lastRequests.add((source: source.name ?? '', query: query, got: 0, kept: 0, error: 'timed out'));
            Logger.Inst().log('doujin For You: ${source.name} timed out for "$query"', 'DoujinForYouHandler', '_ask', LogTypes.booruHandlerInfo);
            answer.complete(const []);
          },
        ),
      );
      await real;
    });
    _lanes[lane] = run.then<void>((_) {}, onError: (Object _) {});
    return answer.future;
  }

  /// How many times each source was asked each query: the page to ask for
  /// next. A cursor-paged site (e-hentai) can only serve page 0 of a query
  /// it has not seen — a running per-handler counter asked it for page 3 of
  /// a brand-new query and got an empty, locked answer.
  final Map<String, Map<String, int>> _pagesAsked = {};

  Future<List<BooruItem>> _askNow(Booru source, String query) async {
    final BooruHandler handler = _handlerFor(source);
    final Map<String, int> asked = _pagesAsked[DoujinDataHandler.hostOf(source)] ??= {};
    handler.pageNum = asked[query] ?? 0;
    asked[query] = handler.pageNum + 1;
    handler.locked = false;
    // A source handler returns everything it holds for its current query
    // and empties that on a new one; starting each question from nothing
    // makes the answer exactly this round's rows (a "what was added" guess
    // dropped rows whenever the previous query had answered fewer).
    handler.fetched.value = [];
    List<BooruItem> got;
    try {
      got = (await handler.search(query, null)) as List<BooruItem>? ?? <BooruItem>[];
    } catch (e) {
      lastRequests.add((source: source.name ?? '', query: query, got: 0, kept: 0, error: '$e'));
      Logger.Inst().log('doujin For You: ${source.name} failed for "$query": $e', 'DoujinForYouHandler', '_askNow', LogTypes.booruHandlerInfo);
      return const [];
    }
    final List<BooruItem> rows = [...got];
    final List<BooruItem> kept = rows.where((i) => !_isRead(i) && !_isDuplicate(i)).toList();
    lastRequests.add((source: source.name ?? '', query: query, got: rows.length, kept: kept.length, error: handler.errorString));
    return kept;
  }

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) pageNum = pageNumCustom;
    try {
      await _init(tags);
    } catch (e, s) {
      Logger.Inst().log('doujin For You init failed: $e', 'DoujinForYouHandler', 'search', LogTypes.exception, s: s);
    }
    _refreshSources();
    if (sources.isEmpty) {
      errorString = 'Add at least one doujin source to get recommendations.';
      locked = true;
      return fetched;
    }
    if (seeds.isEmpty && _history.isEmpty) {
      errorString = 'Nothing to go on yet: read or favourite a few galleries, or seed this feed with a tag from the ⋮ menu.';
      locked = true;
      return fetched;
    }
    errorString = '';
    _readKeys = {for (final DoujinEntry e in DoujinDataHandler.instance.history) e.postURL};
    final int before = fetched.length;
    lastRequests.clear();
    final List<BooruItem> pageItems = seeds.isNotEmpty ? await _seedPage() : await _historyPage();
    for (final BooruItem item in pageItems) {
      _servedKeys.add(item.postURL);
    }
    _feedPage++;
    if (pageItems.isEmpty) {
      // One more round only, and only when the sources did answer (every
      // row was read or served already): sources that came back empty are
      // out of pages or rate-limited, and asking again would be a burst.
      final bool answered = lastRequests.any((r) => r.got > 0);
      _emptyStreak++;
      if (answered && _emptyStreak <= 1) return search(tags, null, withCaptchaCheck: withCaptchaCheck);
      _emptyStreak = 0;
      locked = true;
      if (fetched.isEmpty && !answered) {
        final Set<String> errors = {for (final r in lastRequests) if (r.error.isNotEmpty) '${r.source}: ${r.error}'};
        errorString = errors.isEmpty ? 'No source had anything for this yet.' : 'No source answered — ${errors.join('; ')}';
      }
      return fetched;
    }
    _emptyStreak = 0;
    final RecommenderHandler? recommender = RecommenderHandler.maybe;
    final List<BooruItem> ordered = await (RecommenderHandler.maybe?.rerank(pageItems, world: RecommenderWorld.doujin) ?? Future.value(pageItems));
    unawaited(recommender?.onExposed(ordered, surface) ?? Future<void>.value());
    await afterParseResponse(ordered);
    if (fetched.length == before) locked = true;
    return fetched;
  }

  /// Seed mode: a rotating subset of sources, each asked a rotating seed.
  Future<List<BooruItem>> _seedPage() async {
    final int take = min(sources.length, _sourcesPerPage);
    final List<Future<List<BooruItem>>> requests = [];
    for (int k = 0; k < take; k++) {
      final Booru source = sources[(_feedPage * _sourcesPerPage + _rotation + k) % sources.length];
      final String seed = seeds[(_feedPage + _rotation + k) % seeds.length];
      requests.add(_ask(source, queryFor(source, seed)));
    }
    // One from each source in turn, so a site with a full page of answers
    // does not push the others off the page.
    final List<List<BooruItem>> answers = await Future.wait(requests);
    final List<BooruItem> out = [];
    final Set<String> seen = {};
    bool progressed = true;
    for (int i = 0; progressed && out.length < limit; i++) {
      progressed = false;
      for (final List<BooruItem> got in answers) {
        if (i >= got.length) continue;
        progressed = true;
        final BooruItem item = got[i];
        if (_servedKeys.contains(item.postURL) || !seen.add(item.postURL)) continue;
        out.add(item);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// History mode: a rotating handful of remembered galleries, each of their
  /// facets asked on a rotating source, blended under the engine's caps.
  Future<List<BooruItem>> _historyPage() async {
    final List<Future<MapEntry<SuggestionFacet, List<BooruItem>>>> requests = [];
    int facetIndex = 0;
    for (int p = 0; p < min(_entriesPerPage, _history.length); p++) {
      final DoujinEntry entry = _history[(_feedPage * _entriesPerPage + p + _rotation) % _history.length];
      for (final SuggestionFacet facet in facetsForEntry(entry, seed: _feedPage).take(_facetsPerEntry)) {
        final Booru source = sources[(facetIndex + _feedPage + _rotation) % sources.length];
        facetIndex++;
        requests.add(_ask(source, queryFor(source, facet.query)).then((got) => MapEntry(facet, got)));
      }
    }
    final Map<SuggestionFacet, List<BooruItem>> byFacet = {};
    for (final MapEntry<SuggestionFacet, List<BooruItem>> entry in await Future.wait(requests)) {
      byFacet.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }
    return SuggestionEngine.blend(byFacet, source: null, exclude: _servedKeys, limit: limit);
  }

  @override
  Future<void> searchCount(String input) async {
    totalCount.value = 0;
  }
}
