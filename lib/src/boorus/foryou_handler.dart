import 'dart:async';

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
class ForYouHandler extends BooruHandler {
  ForYouHandler(super.booru, super.limit);

  bool _inited = false;

  final List<Booru> _sources = [];
  final List<BooruHandler> _sourceHandlers = [];
  final List<int> _sourceStartPages = [];

  List<String> _seeds = [];
  Map<String, double> _profile = {};

  // Advances every page so seeds rotate and each source deepens over time.
  int _feedPage = 0;

  // Bounds how many empty rounds we auto-retry within a single scroll before
  // declaring the feed exhausted (each round fans out to every source).
  int _emptyStreak = 0;

  // Max source boorus queried per page (keeps request fan-out bounded).
  static const int _maxSources = 8;

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
      if (term.toLowerCase().startsWith('seed:')) {
        final v = term.substring('seed:'.length).trim().toLowerCase();
        if (v.isNotEmpty) seeds.add(v);
      }
    }
    return seeds;
  }

  Future<void> _init(String tags) async {
    if (_inited) return;
    _inited = true;

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

    // Seeds: explicit if given, else the strongest profile tags.
    _seeds = _parseSeeds(tags);
    _profile = {
      for (final e in await InterestsHandler.instance.topTags(limit: 60)) e.key: e.value,
    };
    if (_seeds.isEmpty) {
      _seeds = _profile.entries.where((e) => e.value > 0).take(24).map((e) => e.key).toList();
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
    return score;
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

    // Pull one page from each source, each for a rotating seed, deepening as
    // the feed scrolls. Alias-resolve every seed onto the source's spelling.
    for (int j = 0; j < _sources.length; j++) {
      final Booru booru = _sources[j];
      final BooruHandler handler = _sourceHandlers[j];
      final String seed = _seeds[(_feedPage + j) % _seeds.length];

      String? resolved;
      try {
        resolved = await TagAliasResolver.resolve(seed, booru);
      } catch (_) {
        resolved = seed;
      }
      if (resolved == null || resolved.isEmpty) continue;

      try {
        handler.pageNum = _sourceStartPages[j] + 1 + _feedPage;
        final List<BooruItem> got = (await handler.search(resolved, null)) ?? [];
        for (final item in got) {
          if (SearchHandler.instance.isPostSeen(item)) continue;
          if (_isDuplicate(item)) continue;
          if (pageItems.any((e) => e.fileURL == item.fileURL || e.postURL == item.postURL)) continue;
          pageItems.add(item);
        }
      } catch (e, s) {
        Logger.Inst().log(
          'For You source ${booru.name} failed: $e',
          'ForYouHandler',
          'search',
          LogTypes.booruHandlerInfo,
          s: s,
        );
      }
    }

    // Rank this page by profile affinity (best matches first).
    pageItems.sort((a, b) => _scoreItem(b).compareTo(_scoreItem(a)));

    _feedPage++;

    if (pageItems.isEmpty) {
      // Nothing new this round; try a few more rotations before giving up so a
      // single dry seed/booru doesn't end the feed. Bounded to keep the
      // network fan-out per scroll in check.
      _emptyStreak++;
      if (_emptyStreak <= 3) {
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
