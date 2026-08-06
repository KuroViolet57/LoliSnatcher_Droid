import 'dart:async';
import 'dart:math';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tag_alias_resolver.dart';

/// "For You" recommender: a virtual booru that surfaces posts from the user's
/// real boorus based on their taste profile (see [InterestsHandler]) or an
/// explicit seed (a tag, or the characteristic tags of a favourited post).
///
/// It fans a rotating set of seed tags across the configured source boorus,
/// resolving each seed to that booru's own spelling first (via
/// [TagAliasResolver], so `burnice_white` still finds
/// `burnice_white_(zenless_zone_zero)` on a booru that qualifies it), merges
/// and de-duplicates the results, and ranks each page by how strongly it
/// matches the profile.
///
/// Config travels in the tab's search string:
///   ''                       -> profile mode (uses the behaviour profile)
///   'seed:tagA seed:tagB'    -> seed mode (recommend around these tags)
///   'tagA tagB'              -> plain tags work as seeds too
class ForYouHandler extends BooruHandler {
  ForYouHandler(super.booru, super.limit);

  bool _inited = false;
  // The query the seed set was built for — a changed query re-derives seeds
  // instead of silently serving the old feed.
  String? _initedTags;

  final Random _rand = Random();

  final List<Booru> _sources = [];
  final List<BooruHandler> _sourceHandlers = [];
  final List<int> _sourceStartPages = [];

  List<String> _seeds = [];
  Map<String, double> _profile = {};

  // Advances every page so seeds rotate and each source deepens over time.
  int _feedPage = 0;

  // Randomized once per session so the source/seed pairing starts somewhere
  // different every time — otherwise the first page of the feed was fully
  // deterministic and looked identical on every open.
  int _rotationOffset = 0;

  // Bounds how many empty rounds we auto-retry within a single scroll before
  // declaring the feed exhausted (each round fans out to every source).
  int _emptyStreak = 0;

  // Max source boorus tracked (keeps request fan-out bounded).
  static const int _maxSources = 8;

  // Sources actually queried per page — a rotating subset of the tracked
  // sources so one page doesn't wait on every booru at once.
  static const int _sourcesPerPage = 4;

  // Per-request budgets so one slow / captcha-looping booru can't stall the
  // whole feed (which showed up as "For You loads forever").
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

  List<String> _parseSeeds(String input) {
    final List<String> seeds = [];
    for (final term in input.split(' ').where((t) => t.trim().isNotEmpty)) {
      String raw = term;
      if (raw.toLowerCase().startsWith('seed:')) {
        raw = raw.substring('seed:'.length);
      } else if (raw.startsWith('-')) {
        // Exclusions aren't seeds.
        continue;
      }
      // Plain tags count as seeds too — searching `girl` should steer the
      // feed just like `seed:girl` (previously non-seed: terms were silently
      // ignored and the old feed kept rendering).
      final v = _sanitizeSeed(raw);
      if (v.isNotEmpty && !seeds.contains(v)) seeds.add(v);
    }
    return seeds;
  }

  // Booru-specific prefixes (creator:, artist:, niche:, source:, sort:, …) and
  // meta filters don't port across sites, so strip them to the bare term for
  // cross-booru fanning — a plain name the alias resolver can actually match.
  static const List<String> _dropPrefixes = [
    'creator:',
    'artist:',
    'niche:',
    'source:',
    'sort:',
    'order:',
    'rating:',
    'status:',
    'score:',
  ];

  String _sanitizeSeed(String raw) {
    String s = raw.trim().toLowerCase();
    for (final p in _dropPrefixes) {
      if (s.startsWith(p)) {
        // sort:/order:/rating:/etc. carry no reusable term — drop entirely.
        if (p == 'sort:' || p == 'order:' || p == 'rating:' || p == 'status:' || p == 'score:') {
          return '';
        }
        s = s.substring(p.length).trim();
        break;
      }
    }
    // Keep the meaningful prefix forms out; also skip empties and lone digits.
    if (s.isEmpty || RegExp(r'^\d+$').hasMatch(s)) return '';
    return s;
  }

  /// Runs [future] but gives up (returns null) after [timeout] or on error, so
  /// a single misbehaving source can never block the feed.
  Future<T?> _bounded<T>(Future<T> Function() future, Duration timeout) async {
    try {
      return await future().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _init(String tags) async {
    // Re-derive the seed set when the query changes (same handler instance) —
    // otherwise editing the search did nothing and the old feed kept coming.
    if (_inited && _initedTags == tags) return;
    final bool firstInit = !_inited;
    _inited = true;
    _initedTags = tags;

    if (firstInit) {
      // This virtual booru has no API of its own; don't let afterParseResponse
      // try to fetch tag types through it (items already carry their tags).
      storeTagsGlobally = false;

      // Source boorus: real, tag-searchable sites the user has configured.
      final all = SettingsHandler.instance.booruList;
      for (final b in all) {
        final t = b.type;
        if (t == null) continue;
        if (t.isLocalDb || t.isMerge || t.isWebView || t.isForYou) continue;
        if ((b.baseURL ?? '').isEmpty && !t.isRedGifs && !t.isRule34Dev) continue;
        _sources.add(b);
        if (_sources.length >= _maxSources) break;
      }
      for (final b in _sources) {
        final res = BooruHandlerFactory().getBooruHandler([b], limit);
        res.booruHandler.storeTagsGlobally = false;
        _sourceHandlers.add(res.booruHandler);
        _sourceStartPages.add(res.startingPage);
      }
    } else {
      // Query changed: restart the feed walk for the new seed set.
      _feedPage = 0;
      _emptyStreak = 0;
      locked = false;
    }

    // Session variety: start the source/seed rotation somewhere random.
    _rotationOffset = _rand.nextInt(1 << 16);

    // Seeds: explicit if given, else the strongest profile tags.
    _seeds = _parseSeeds(tags);
    _profile = {
      for (final e in await InterestsHandler.instance.topTags(limit: 60)) e.key: e.value,
    };
    if (_seeds.isEmpty) {
      // Sanitize profile tags into portable, cross-booru seeds and de-dupe.
      final List<String> pool = [];
      for (final e in _profile.entries) {
        if (e.value <= 0) continue;
        final String s = _sanitizeSeed(e.key);
        if (s.isNotEmpty && !pool.contains(s)) pool.add(s);
        if (pool.length >= 24) break;
      }
      // Shuffle so the profile feed doesn't open on the exact same seed
      // (and thus the exact same posts) every session.
      pool.shuffle(_rand);
      _seeds = pool;
    } else {
      // Seed mode still benefits from profile ranking; make sure seeds appear.
      for (final s in _seeds) {
        _profile.putIfAbsent(s, () => 5);
      }
    }
  }

  double _scoreItem(BooruItem item) {
    double score = 0;
    for (final t in item.tagsList) {
      score += _profile[t.fullString.toLowerCase()] ?? 0;
    }
    // Light popularity nudge so ties resolve toward well-liked posts.
    final int? s = int.tryParse(item.score ?? '');
    if (s != null) score += (s / 500).clamp(0, 2);
    // Small jitter so equally-ranked posts don't line up identically on
    // every open.
    return score + _rand.nextDouble() * 0.5;
  }

  bool _isDuplicate(BooruItem item) {
    for (final existing in fetched) {
      if (existing.fileURL == item.fileURL ||
          existing.postURL == item.postURL ||
          (existing.md5String != null && existing.md5String == item.md5String)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    try {
      await _init(tags);
    } catch (e, s) {
      Logger.Inst().log('For You init failed: $e', 'ForYouHandler', 'search', LogTypes.exception, s: s);
    }

    if (_sources.isEmpty) {
      errorString = 'Add at least one booru to get recommendations.';
      locked = true;
      return fetched;
    }
    if (_seeds.isEmpty) {
      errorString =
          'Not enough history yet. Browse, favourite or preview some tags — or seed this with a tag / favourite from the ⋮ menu.';
      locked = true;
      return fetched;
    }

    final int before = fetched.length;
    final List<BooruItem> pageItems = [];

    // Query a rotating subset of sources per page (not all at once), each for a
    // rotating seed, deepening as the feed scrolls. Every network step is time-
    // bounded so a slow/captcha booru can't hang the feed. The subset rotates
    // by page so all sources get used across a few scrolls.
    final int take = _sources.length < _sourcesPerPage ? _sources.length : _sourcesPerPage;
    for (int k = 0; k < take; k++) {
      // _rotationOffset varies the pairing per session; _feedPage still
      // drives the page depth so rare seeds aren't asked for deep pages.
      final int j = ((_feedPage + _rotationOffset) * _sourcesPerPage + k) % _sources.length;
      final Booru booru = _sources[j];
      final BooruHandler handler = _sourceHandlers[j];
      final String seed = _seeds[(_feedPage + _rotationOffset + k) % _seeds.length];

      String resolved = seed;
      final String? aliased = await _bounded<String?>(
        () => TagAliasResolver.resolve(seed, booru),
        _resolveTimeout,
      );
      if (aliased != null && aliased.isNotEmpty) resolved = aliased;
      if (resolved.isEmpty) continue;

      handler.pageNum = _sourceStartPages[j] + 1 + _feedPage;
      handler.locked = false;
      final List<BooruItem>? got = await _bounded(
        () async => (await handler.search(resolved, null)) as List<BooruItem>? ?? <BooruItem>[],
        _searchTimeout,
      );
      if (got == null) {
        Logger.Inst().log(
          'For You source ${booru.name} timed out/failed for "$resolved"',
          'ForYouHandler',
          'search',
          LogTypes.booruHandlerInfo,
        );
        continue;
      }
      for (final item in got) {
        if (SearchHandler.instance.isPostSeen(item)) continue;
        if (_isDuplicate(item)) continue;
        if (pageItems.any((e) => e.fileURL == item.fileURL || e.postURL == item.postURL)) continue;
        pageItems.add(item);
      }
    }

    // Rank this page by profile affinity (best matches first). Scores are
    // precomputed — _scoreItem carries random jitter, and a comparator that
    // re-rolls per comparison isn't a consistent ordering.
    final Map<BooruItem, double> scores = {
      for (final item in pageItems) item: _scoreItem(item),
    };
    pageItems.sort((a, b) => scores[b]!.compareTo(scores[a]!));

    _feedPage++;

    if (pageItems.isEmpty) {
      // Nothing new this round; try a few more rotations before giving up so a
      // single dry seed/booru doesn't end the feed. Bounded to keep the
      // network fan-out per scroll in check.
      _emptyStreak++;
      if (_emptyStreak <= 2) {
        return search(tags, null, withCaptchaCheck: withCaptchaCheck);
      }
      _emptyStreak = 0;
      locked = true;
      return fetched;
    }
    _emptyStreak = 0;

    await afterParseResponse(pageItems);

    if (fetched.length == before) {
      locked = true;
    }
    return fetched;
  }

  @override
  Future<void> searchCount(String input) async {
    // Endless discovery feed — no meaningful total.
    totalCount.value = 0;
  }
}
