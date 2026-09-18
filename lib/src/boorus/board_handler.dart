import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/board_query.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tag_alias_resolver.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The board feed (r73): a virtual booru behind a `board:<id>` tab.
///
/// Reads the board, turns its description and reference image into tags
/// ([BoardQueryBuilder], [ReverseImageSearch]), asks each of the board's
/// sources for the must-have tags in that site's own spelling plus one
/// derived tag at a time (rotating, deepening per page like For You), keeps
/// only posts that carry every must-have tag and none of the excluded ones,
/// and ranks a page by how close each post reads to the description (the
/// downloaded encoder) and how many derived tags it carries. Exact matches
/// of the reference image are pinned first.
class BoardHandler extends BooruHandler {
  BoardHandler(super.booru, super.limit);

  static const String surface = 'board';
  static const int maxSources = 8;
  static const int sourcesPerPage = 4;
  static const Duration resolveTimeout = Duration(seconds: 6);
  static const Duration searchTimeout = Duration(seconds: 12);
  static const Duration matchTimeout = Duration(seconds: 100);
  static const Duration embedTimeout = Duration(seconds: 20);

  // Seams: the sources, the alias resolver, the image matcher and the
  // encoder, replaced in tests.
  static ({BooruHandler handler, int startingPage}) Function(Booru booru, int limit) sourceFactory = _defaultSourceFactory;
  static List<Booru> Function() allSources = _defaultAllSources;
  static Board? Function(String id) boardLookup = _defaultBoardLookup;
  static Future<String?> Function(String tag, Booru booru) resolveTag = TagAliasResolver.resolve;
  static Future<List<ReverseMatch>> Function(Board board, List<Booru> sources) imageMatcher = defaultImageMatcher;
  static Future<Float32List?> Function(String text)? embedText = _defaultEmbedText;
  static Future<List<Float32List?>> Function(List<BooruItem> items, BooruHandler handler)? embedItems = _defaultEmbedItems;

  static void resetForTests() {
    sourceFactory = _defaultSourceFactory;
    allSources = _defaultAllSources;
    boardLookup = _defaultBoardLookup;
    resolveTag = TagAliasResolver.resolve;
    imageMatcher = defaultImageMatcher;
    embedText = _defaultEmbedText;
    embedItems = _defaultEmbedItems;
  }

  static ({BooruHandler handler, int startingPage}) _defaultSourceFactory(Booru booru, int limit) {
    final res = BooruHandlerFactory().getBooruHandler([booru], limit);
    return (handler: res.booruHandler, startingPage: res.startingPage);
  }

  static List<Booru> _defaultAllSources() => SettingsHandler.instance.booruList.toList();

  static Board? _defaultBoardLookup(String id) => BoardsHandler.instance.byId(id);

  static Future<Float32List?> _defaultEmbedText(String text) async {
    final EncoderHandler? e = EncoderHandler.maybe;
    if (e == null || !e.enabled) return null;
    return e.embedText(text);
  }

  static Future<List<Float32List?>> _defaultEmbedItems(List<BooruItem> items, BooruHandler handler) async {
    final EncoderHandler? e = EncoderHandler.maybe;
    if (e == null || !e.enabled) return List<Float32List?>.filled(items.length, null);
    return e.embedItems(items, handler: handler);
  }

  /// A source a board can ask: a real booru with an address, not a local
  /// view, a feed, a merge, the webview or a doujin site.
  static bool eligible(Booru b) {
    final BooruType? t = b.type;
    if (t == null) return false;
    if (t.isLocalDb || t.isMerge || t.isWebView || t.isRecommendationFeed) return false;
    if (DoujinDataHandler.isDoujinBooru(b)) return false;
    if ((b.baseURL ?? '').isEmpty && !t.isRedGifs && !t.isRule34Dev) return false;
    return true;
  }

  static String _nameOf(Booru b) => b.name ?? '';

  static String? boardIdOf(String tags) {
    final String t = tags.trim();
    if (!t.toLowerCase().startsWith('board:') || t.length <= 'board:'.length) return null;
    return t.substring('board:'.length);
  }

  Board? board;
  final List<Booru> _sources = [];
  final List<BooruHandler> _handlers = [];
  final List<int> _startPages = [];
  List<WeightedTag> _derived = [];
  List<ReverseMatch> _matches = [];

  /// Per source: the must-have tags in that site's spelling; a source that
  /// lacks one is not here (see [skippedSources]).
  final Map<String, Map<String, String>> _mustBySource = {};
  final Map<String, Map<String, String>> _derivedBySource = {};
  final List<String> skippedSources = [];

  /// The last image search failure, for the page to show.
  String imageError = '';
  Float32List? _descVec;
  int _feedPage = 0;
  int _emptyStreak = 0;
  final Map<String, int> _asked = {};
  String? _initedTags;
  Future<void>? _initFuture;
  Future<dynamic>? _pageInFlight;
  final Random _rand = Random();

  List<Booru> get sources => List<Booru>.unmodifiable(_sources);
  List<WeightedTag> get derivedTags => List<WeightedTag>.unmodifiable(_derived);
  List<ReverseMatch> get matches => List<ReverseMatch>.unmodifiable(_matches);

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

  Future<T?> _bounded<T>(Future<T> Function() future, Duration timeout) async {
    try {
      return await future().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// One init per query, shared by concurrent callers (review: a tab
  /// switch during the first load searched again, found nothing set up
  /// and locked the feed).
  Future<void> _ensureInit(String tags) {
    if (_initFuture == null || _initedTags != tags) {
      _initedTags = tags;
      _initFuture = _init(tags);
    }
    return _initFuture!;
  }

  Future<void> _init(String tags) async {
    _feedPage = 0;
    _emptyStreak = 0;
    _asked.clear();
    locked = false;
    errorString = '';
    imageError = '';
    skippedSources.clear();
    _sources.clear();
    _handlers.clear();
    _startPages.clear();
    _mustBySource.clear();
    _derivedBySource.clear();
    _derived = [];
    _matches = [];
    _descVec = null;
    storeTagsGlobally = false;

    // A restored tab may be the first thing to touch the boards.
    try {
      await BoardsHandler.instance.load();
    } catch (_) {}
    final String? id = boardIdOf(tags);
    board = id == null ? null : boardLookup(id);
    if (board == null) {
      errorString = 'This board no longer exists (or the tab holds no board).';
      locked = true;
      return;
    }
    final Board b = board!;
    final List<Booru> all = allSources().where(eligible).toList();
    final List<Booru> chosen = b.sourceNames.isEmpty ? all : all.where((s) => b.sourceNames.contains(s.name)).toList();
    for (final Booru s in chosen.take(maxSources)) {
      final res = sourceFactory(s, limit);
      res.handler.storeTagsGlobally = false;
      _sources.add(s);
      _handlers.add(res.handler);
      _startPages.add(res.startingPage);
    }
    if (_sources.isEmpty) {
      errorString = "None of this board's sources is set up. Add a booru, or edit the board.";
      locked = true;
      return;
    }
    if (b.hasImage) {
      if (b.hasFreshMatches) {
        // Cached on the board: a re-opened tab costs SauceNAO nothing.
        _matches = [...b.matches!];
      } else {
        try {
          _matches = await imageMatcher(b, _sources).timeout(matchTimeout);
          try {
            // Saved for the next open; this handler keeps working on [b].
            final Board fresh = boardLookup(b.id) ?? b;
            await BoardsHandler.instance.save(fresh.copyWith(matches: _matches, matchedAt: DateTime.now(), matchedImage: fresh.imageKey));
          } catch (e) {
            Logger.Inst().log('board matches could not be cached: $e', 'BoardHandler', '_init', LogTypes.booruHandlerInfo);
          }
        } catch (e, s) {
          imageError = e.toString();
          Logger.Inst().log('board image search failed: $e', 'BoardHandler', '_init', LogTypes.exception, s: s);
          _matches = [];
        }
      }
    }
    final List<String> seeds = [for (final ReverseMatch m in _matches) ...m.tags];
    _derived = await BoardQueryBuilder.deriveTags(
      b.description,
      sources: _sources,
      handlers: _handlers,
      seedTags: seeds,
      exclude: {...b.mustTags, ...b.excludeTags},
      limit: 8,
    );
    // The must-have tags in each site's own spelling; a confirmed miss
    // (the resolver's null) means the site cannot answer at all.
    for (int i = 0; i < _sources.length; i++) {
      final Map<String, String> spelled = {};
      bool ok = true;
      for (final String tag in b.mustTags) {
        String? r;
        try {
          r = await resolveTag(tag, _sources[i]).timeout(resolveTimeout);
        } catch (_) {
          r = tag;
        }
        if (r == null || r.isEmpty) {
          ok = false;
          break;
        }
        spelled[tag] = r;
      }
      if (ok) {
        _mustBySource[_nameOf(_sources[i])] = spelled;
      } else {
        skippedSources.add(_nameOf(_sources[i]));
      }
    }
    if (_mustBySource.isEmpty) {
      errorString = 'No source of this board knows the must-have tag${b.mustTags.length == 1 ? '' : 's'}: ${b.mustTags.join(', ')}.';
      locked = true;
      return;
    }
    if (_derived.isEmpty && b.mustTags.isEmpty && _matches.isEmpty) {
      errorString = 'There is nothing to ask the sources for: the description gave no known tags, there are no must-have tags and no image match.';
      locked = true;
      return;
    }
    if (b.description.trim().isNotEmpty && embedText != null) {
      _descVec = await _bounded<Float32List?>(() => embedText!(b.description), embedTimeout);
    }
  }

  /// Which of the board's sources a match's site is, by host only: a
  /// gelbooru id means nothing on rule34.xxx though both run the same
  /// engine (review). Only sites whose `id:` search is verified: danbooru,
  /// gelbooru, yande.re / konachan, e621 (e926 shares its ids).
  int? _sourceIndexForHost(String site) {
    const Map<String, List<String>> hosts = {
      'danbooru': ['donmai.us'],
      'gelbooru': ['gelbooru.com'],
      'yandere': ['yande.re'],
      'konachan': ['konachan.com', 'konachan.net'],
      'e621': ['e621.net', 'e926.net'],
    };
    final List<String>? wanted = hosts[site];
    if (wanted == null) return null;
    for (int i = 0; i < _sources.length; i++) {
      final String host = Uri.tryParse(_sources[i].baseURL ?? '')?.host ?? '';
      if (wanted.any((String h) => host == h || host.endsWith('.$h'))) return i;
    }
    return null;
  }

  Future<String> _spelled(int i, String tag) async {
    final Map<String, String> cache = _derivedBySource.putIfAbsent(_nameOf(_sources[i]), () => {});
    if (cache.containsKey(tag)) return cache[tag]!;
    String? r;
    try {
      r = await resolveTag(tag, _sources[i]).timeout(resolveTimeout);
    } catch (_) {
      r = tag;
    }
    final String spelled = r ?? '';
    cache[tag] = spelled;
    return spelled;
  }

  Future<List<BooruItem>> _ask(int i, String query) async {
    final BooruHandler h = _handlers[i];
    final String key = '${_sources[i].name}|$query';
    final int times = _asked[key] ?? 0;
    _asked[key] = times + 1;
    h.pageNum = _startPages[i] + 1 + times;
    h.locked = false;
    final List<BooruItem>? got = await _bounded(() async => (await h.search(query, null)) as List<BooruItem>? ?? <BooruItem>[], searchTimeout);
    if (got == null) {
      Logger.Inst().log('board source ${_sources[i].name} timed out or failed for "$query"', 'BoardHandler', '_ask', LogTypes.booruHandlerInfo);
      return const [];
    }
    // Sub-handlers accumulate across pages; only this round's tail is new.
    return got.length > limit ? got.sublist(got.length - limit) : [...got];
  }

  bool _seen(BooruItem item) {
    if (!GetIt.instance.isRegistered<SearchHandler>()) return false;
    try {
      return SearchHandler.instance.isPostSeen(item);
    } catch (_) {
      return false;
    }
  }

  bool _isDuplicate(BooruItem item) {
    for (final BooruItem existing in fetched) {
      if (existing.fileURL == item.fileURL ||
          existing.postURL == item.postURL ||
          (existing.md5String != null && existing.md5String == item.md5String)) {
        return true;
      }
    }
    return false;
  }

  /// How well a post answers the board: the description (encoder), the
  /// derived tags it carries, a little jitter so ties vary.
  double scoreItem(BooruItem item, Float32List? vec, {bool exact = false}) {
    double score = exact ? 100 : 0;
    if (vec != null && _descVec != null) score += 10 * max(0, BoardQueryBuilder.dot(_descVec!, vec));
    final Set<String> tags = {for (final t in item.tagsList) t.fullString.toLowerCase()};
    for (final WeightedTag d in _derived) {
      if (tags.contains(d.tag)) score += d.weight;
    }
    return score + _rand.nextDouble() * 0.01;
  }

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }
    // Concurrent callers (a tab switch during a load) share the page in flight.
    final Future<dynamic>? running = _pageInFlight;
    if (running != null) return running;
    final Future<dynamic> page = _searchPage(tags, withCaptchaCheck: withCaptchaCheck);
    _pageInFlight = page;
    try {
      return await page;
    } finally {
      _pageInFlight = null;
    }
  }

  Future<dynamic> _searchPage(String tags, {bool withCaptchaCheck = true}) async {
    try {
      await _ensureInit(tags);
    } catch (e, s) {
      Logger.Inst().log('board init failed: $e', 'BoardHandler', 'search', LogTypes.exception, s: s);
      errorString = 'The board could not be read: $e';
      locked = true;
    }
    if (locked || board == null) return fetched;
    final Board b = board!;
    final int before = fetched.length;
    final List<int> active = [
      for (int i = 0; i < _sources.length; i++)
        if (_mustBySource.containsKey(_sources[i].name)) i,
    ];
    // A source handler's search is not re-entrant, so the exact matches of
    // the reference image (first page only) are asked in their own wave,
    // before the derived queries that may hit the same sources.
    final List<({int source, bool exact, List<BooruItem> items})> answers = [];
    if (_feedPage == 0) {
      final Map<int, List<String>> exactBySource = {};
      for (final ReverseMatch m in _matches) {
        // The match's own site and the other sites it names the picture on.
        final Map<String, String> ids = {if (m.postId != null) m.site: m.postId!, ...m.alsoOn};
        for (final MapEntry<String, String> e in ids.entries) {
          final int? i = _sourceIndexForHost(e.key);
          if (i == null || !active.contains(i)) continue;
          final List<String> list = exactBySource.putIfAbsent(i, () => []);
          if (!list.contains(e.value)) list.add(e.value);
        }
      }
      answers.addAll(
        await Future.wait([
          for (final MapEntry<int, List<String>> e in exactBySource.entries)
            () async {
              final List<BooruItem> items = [];
              for (final String id in e.value.take(4)) {
                items.addAll(await _ask(e.key, 'id:$id'));
              }
              return (source: e.key, exact: true, items: items);
            }(),
        ]),
      );
    }
    final List<Future<({int source, bool exact, List<BooruItem> items})>> requests = [];
    final int take = min(active.length, sourcesPerPage);
    final Set<int> usedThisPage = {};
    for (int k = 0; k < take; k++) {
      final int i = active[(_feedPage * sourcesPerPage + k) % active.length];
      if (!usedThisPage.add(i)) continue;
      requests.add(() async {
        final List<String> parts = [for (final String m in b.mustTags) _mustBySource[_sources[i].name]![m]!];
        if (_derived.isNotEmpty) {
          final WeightedTag d = _derived[(_feedPage + k) % _derived.length];
          final String spelled = await _spelled(i, d.tag);
          if (spelled.isNotEmpty) parts.add(spelled);
        }
        if (parts.isEmpty) return (source: i, exact: false, items: <BooruItem>[]);
        return (source: i, exact: false, items: await _ask(i, parts.join(' ')));
      }());
    }
    answers.addAll(await Future.wait(requests));
    final List<BooruItem> pageItems = [];
    final Set<BooruItem> exactItems = {};
    for (final ({int source, bool exact, List<BooruItem> items}) got in answers) {
      final Map<String, String> aliases = _mustBySource[_sources[got.source].name] ?? const {};
      for (final BooruItem item in got.items) {
        if (!got.exact && !BoardQueryBuilder.accepts(item, must: b.mustTags, exclude: b.excludeTags, aliases: aliases)) continue;
        if (got.exact && !BoardQueryBuilder.accepts(item, must: const [], exclude: b.excludeTags, aliases: aliases)) continue;
        // The picture the board was made from may well have been viewed.
        if ((!got.exact && _seen(item)) || _isDuplicate(item)) continue;
        if (pageItems.any((e) => e.fileURL == item.fileURL || e.postURL == item.postURL)) continue;
        pageItems.add(item);
        if (got.exact) exactItems.add(item);
      }
    }
    if (pageItems.isEmpty) {
      _feedPage++;
      _emptyStreak++;
      if (_emptyStreak <= 2 && active.isNotEmpty) {
        return _searchPage(tags, withCaptchaCheck: withCaptchaCheck);
      }
      _emptyStreak = 0;
      locked = true;
      if (fetched.isEmpty && errorString.isEmpty) {
        errorString = 'Nothing found for this board yet: the sources answered nothing that carries every must-have tag.';
      }
      return fetched;
    }
    List<Float32List?> vecs = List<Float32List?>.filled(pageItems.length, null);
    if (_descVec != null && embedItems != null) {
      final List<Float32List?>? got = await _bounded(() => embedItems!(pageItems, this), embedTimeout);
      if (got != null && got.length == pageItems.length) vecs = got;
    }
    final Map<BooruItem, double> scores = {
      for (int i = 0; i < pageItems.length; i++) pageItems[i]: scoreItem(pageItems[i], vecs[i], exact: exactItems.contains(pageItems[i])),
    };
    pageItems.sort((x, y) => scores[y]!.compareTo(scores[x]!));
    final List<BooruItem> wanted = await (RecommenderHandler.maybe?.withoutDismissed(pageItems) ?? Future.value(pageItems));
    _feedPage++;
    _emptyStreak = 0;
    unawaited(RecommenderHandler.maybe?.onExposed(wanted, surface) ?? Future<void>.value());
    await afterParseResponse(wanted);
    if (fetched.length == before) {
      locked = true;
    }
    return fetched;
  }

  /// The reference image through SauceNAO (the user's key) and, when e621
  /// is among the sources, e621's own iqdb. A board created from a post
  /// keeps the post's url; a picked file lives under boards/.
  static Future<List<ReverseMatch>> defaultImageMatcher(Board board, List<Booru> sources) async {
    List<int>? bytes;
    if (board.imagePath.isNotEmpty && File(board.imagePath).existsSync()) {
      bytes = File(board.imagePath).readAsBytesSync();
    } else if (board.imageUrl.isNotEmpty) {
      try {
        // The address of a post's image: fetched with its booru's own headers.
        Map<String, String> headers = {'User-Agent': Tools.browserUserAgent};
        if (board.imageBooru.isNotEmpty) {
          final Booru? source = SettingsHandler.instance.booruList.where((s) => s.name == board.imageBooru).firstOrNull;
          if (source != null) headers = await Tools.getFileCustomHeaders(source, checkForReferer: true);
        }
        final Response<dynamic> res = await DioNetwork.get(
          board.imageUrl,
          headers: headers,
          options: Options(responseType: ResponseType.bytes),
        ).timeout(const Duration(seconds: 20));
        if (res.data is List<int>) bytes = res.data as List<int>;
      } catch (e) {
        Logger.Inst().log('board image download failed: $e', 'BoardHandler', 'defaultImageMatcher', LogTypes.booruHandlerInfo);
      }
    }
    final List<ReverseMatch> out = [];
    final List<String> errors = [];
    final String key = BoardsHandler.instance.sauceNaoApiKey;
    if (key.isNotEmpty) {
      try {
        out.addAll(await ReverseImageSearch.sauceNao(apiKey: key, imageBytes: bytes, imageUrl: bytes == null ? board.imageUrl : null));
      } catch (e) {
        errors.add(e.toString());
      }
    }
    final Booru? e621 = sources.where((s) => s.type == BooruType.e621).firstOrNull;
    if (e621 != null && bytes != null) {
      try {
        out.addAll(await ReverseImageSearch.e621Iqdb(imageBytes: bytes, baseUrl: e621.baseURL ?? 'https://e621.net'));
      } catch (e) {
        errors.add(e.toString());
      }
    }
    if (out.isEmpty && errors.isNotEmpty) throw Exception(errors.join(' / '));
    if (key.isEmpty && e621 == null) {
      throw StateError('No reverse image search available: add your SauceNAO API key in Settings → Recommendations → Boards.');
    }
    return out;
  }
}
