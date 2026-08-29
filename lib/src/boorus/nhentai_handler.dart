import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// nhentai.net — the first DOUJIN source: a post is a whole book, read
/// through [ReaderHandler] / DoujinReaderPage rather than viewed as one file.
///
/// Uses the official v2 REST API (the old unofficial endpoints are dead and
/// answer "Use new API"). Everything read-only worked WITHOUT auth when
/// verified live; an API key (Settings -> the booru's API key field, generated
/// at nhentai.net/user/settings#apikeys) is accepted and needed for favorites
/// and blacklists later. Full site search syntax passes through the `query`
/// param verbatim (`tag:"school swimsuit" -tag:netorare pages:>20`).
///
/// Layout of a gallery (verified against /api/v2 responses):
///   * list rows are lightweight: title, thumb path, page count and TAG IDS
///     only — names come from the open /tags/ids endpoint, session-cached;
///   * the detail call returns the whole book in one response: every page's
///     path + dimensions + its own thumbnail, typed tags, related, comments;
///   * images live on i1-i4.nhentai.net, thumbs AND covers on t1-t4 (the
///     i-servers 404 cover paths).
class NHentaiHandler extends BooruHandler {
  NHentaiHandler(super.booru, super.limit);

  String get _base {
    String url = booru.baseURL ?? 'https://nhentai.net';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  /// Session CDN config; /api/v2/cdn refreshes it once per app run, these
  /// are the values it returned in every live test.
  static List<String> _imageServers = ['https://i1.nhentai.net', 'https://i2.nhentai.net', 'https://i3.nhentai.net', 'https://i4.nhentai.net'];
  static List<String> _thumbServers = ['https://t1.nhentai.net', 'https://t2.nhentai.net', 'https://t3.nhentai.net', 'https://t4.nhentai.net'];
  static bool _cdnFetched = false;

  /// Server choice must be STABLE per path or image cache keys churn.
  static String _pick(List<String> servers, String path) => servers[path.hashCode.abs() % servers.length];

  static String imageUrl(String path) => '${_pick(_imageServers, path)}/$path';
  static String thumbUrl(String path) => '${_pick(_thumbServers, path)}/$path';

  Future<void> _ensureCdnConfig() async {
    if (_cdnFetched) return;
    _cdnFetched = true;
    try {
      final response = await DioNetwork.get('$_base/api/v2/cdn', headers: getHeaders());
      final data = _json(response.data);
      final List<String> images = List<String>.from(data['image_servers'] ?? []);
      final List<String> thumbs = List<String>.from(data['thumb_servers'] ?? []);
      if (images.isNotEmpty) _imageServers = images;
      if (thumbs.isNotEmpty) _thumbServers = thumbs;
    } catch (e) {
      Logger.Inst().log('cdn config fetch failed, using defaults: $e', className, '_ensureCdnConfig', LogTypes.booruHandlerInfo);
    }
  }

  /// Dio may hand the body over already decoded (json content-type) or as a
  /// string — normalize.
  static dynamic _json(dynamic data) => data is String ? jsonDecode(data) : data;

  // ─────────────────────────── capabilities ───────────────────────────

  /// Real per-item dimensions (the thumb's aspect ratio) come with every
  /// list row, so the staggered grid can adapt cells to the cover.
  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  bool get hasCommentsSupport => true;

  @override
  bool get hasReader => true;

  /// Image-only site.
  @override
  List<String> get animatedPreviewFilters => const [];

  /// The site has no OR groups.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String? get metatagsCheatSheetLink => 'https://nhentai.net/info/';

  /// Account favourites work through the API key ('Authorization: Key ...').
  @override
  bool get hasSiteFavourites => booru.apiKey?.isNotEmpty ?? false;

  @override
  Future<(bool, String)> setSiteFavourite(BooruItem item, bool value) async {
    final String? id = item.serverId;
    if (id == null || id.isEmpty) return (false, 'No gallery id');
    if (!hasSiteFavourites) {
      return (false, 'Local only — add your nhentai API key in the booru settings to sync');
    }
    try {
      final response = value
          ? await DioNetwork.post('$_base/api/v2/galleries/$id/favorite', headers: getHeaders())
          : await DioNetwork.delete('$_base/api/v2/galleries/$id/favorite', headers: getHeaders());
      final data = _json(response.data);
      final bool favorited = data is Map && data['favorited'] == true;
      if (favorited == value) {
        return (true, value ? 'Synced to your nhentai account' : 'Removed from your nhentai account');
      }
      return (false, 'The site did not accept the change');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return (false, 'nhentai rejected the API key — check it in the booru settings');
      }
      return (false, 'Sync failed: ${e.response?.statusCode ?? e.type.name}');
    } catch (e) {
      return (false, 'Sync failed: $e');
    }
  }

  @override
  Map<String, String> getHeaders() => {
    'Accept': 'application/json',
    'User-Agent': Tools.browserUserAgent,
    // Optional: unlocks favorites/blacklist and identifies the account.
    if (booru.apiKey?.isNotEmpty ?? false) 'Authorization': 'Key ${booru.apiKey}',
  };

  @override
  String validateTags(String tags) => tags.trim();

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        values: [
          MetaTagValue(name: 'Newest', value: 'date'),
          MetaTagValue(name: 'Popular (all time)', value: 'popular'),
          MetaTagValue(name: 'Popular today', value: 'popular-today'),
          MetaTagValue(name: 'Popular this week', value: 'popular-week'),
          MetaTagValue(name: 'Popular this month', value: 'popular-month'),
        ],
      ),
      MetaTagWithValues(
        name: 'Language',
        keyName: 'language',
        values: [
          MetaTagValue(name: 'English', value: 'english'),
          MetaTagValue(name: 'Japanese', value: 'japanese'),
          MetaTagValue(name: 'Chinese', value: 'chinese'),
          MetaTagValue(name: 'Translated', value: 'translated'),
        ],
      ),
      MetaTagWithValues(
        name: 'Category',
        keyName: 'category',
        values: [
          MetaTagValue(name: 'Doujinshi', value: 'doujinshi'),
          MetaTagValue(name: 'Manga', value: 'manga'),
          MetaTagValue(name: 'Artist CG', value: 'artistcg'),
          MetaTagValue(name: 'Game CG', value: 'gamecg'),
          MetaTagValue(name: 'Western', value: 'western'),
          MetaTagValue(name: 'Non-H', value: 'non-h'),
          MetaTagValue(name: 'Image set', value: 'imageset'),
          MetaTagValue(name: 'Cosplay', value: 'cosplay'),
        ],
      ),
    ];
  }

  // ─────────────────────────── query building ───────────────────────────

  static const List<String> _sorts = ['date', 'popular', 'popular-today', 'popular-week', 'popular-month'];

  static const Set<String> _namespaces = {'tag', 'artist', 'parody', 'character', 'group', 'language', 'category'};

  /// App term -> site query term. Underscores are the app's convention,
  /// nhentai's tags use spaces — and a spaced value must be quoted or the
  /// site splits it into free-text words.
  static String _siteTerm(String term) {
    final bool negated = term.startsWith('-');
    final String body = negated ? term.substring(1) : term;
    final int colon = body.indexOf(':');
    final String key = colon > 0 ? body.substring(0, colon).toLowerCase() : '';
    if (_namespaces.contains(key)) {
      final String value = body.substring(colon + 1).replaceAll('_', ' ');
      return '${negated ? '-' : ''}$key:"$value"';
    }
    // pages:>N, uploaded:, free text — pass through, underscores to spaces.
    return '${negated ? '-' : ''}${body.replaceAll('_', ' ')}';
  }

  ({String query, String? sort, String? relatedId, String? versionsId, String? recommendId, bool accountFavorites}) _parse(String input) {
    final List<String> terms = [];
    String? sort;
    String? relatedId;
    String? versionsId;
    String? recommendId;
    bool wantsAccountFavorites = false;

    for (final term in input.split(' ').where((t) => t.trim().isNotEmpty)) {
      final String lower = term.toLowerCase();
      if (lower.startsWith('sort:')) {
        final String value = lower.substring(5);
        if (_sorts.contains(value)) sort = value;
        continue;
      }
      if (lower.startsWith('related:')) {
        final String value = lower.substring(8);
        if (int.tryParse(value) != null) relatedId = value;
        continue;
      }
      // Chapters + other-language versions of a gallery: a quoted phrase
      // search on its base title (see _versionsBaseTitle). Resolved in
      // parseListFromResponse when the title isn't known yet — NEVER
      // degraded to a plain (firehose) query.
      if (lower.startsWith('versions:')) {
        final String value = lower.substring(9);
        if (int.tryParse(value) != null) versionsId = value;
        continue;
      }
      // Blended recommendations seeded from this gallery (see
      // _buildRecommendations).
      if (lower.startsWith('recommend:')) {
        final String value = lower.substring(10);
        if (int.tryParse(value) != null) recommendId = value;
        continue;
      }
      // The account's favourites feed (needs the API key).
      if (lower == 'favorites:me' || lower == 'favourites:me') {
        wantsAccountFavorites = true;
        continue;
      }
      terms.add(_siteTerm(term));
    }
    // Per-source default sort applies only when the query didn't pick one.
    sort ??= () {
      final String? def = SourceSettingsHandler.instance.defaultSort(booru);
      return (def != null && _sorts.contains(def) && def != 'date') ? def : null;
    }();
    return (
      query: terms.join(' '),
      sort: sort,
      relatedId: relatedId,
      versionsId: versionsId,
      recommendId: recommendId,
      accountFavorites: wantsAccountFavorites,
    );
  }

  /// Related feeds are a single fixed list — makeURL flags it so parsing can
  /// refuse to "paginate" the same five items forever.
  bool _relatedMode = false;

  /// Set when the current fetch must be post-processed by
  /// parseListFromResponse: 'versions'/'recommend' fetches bounce through
  /// the gallery-detail endpoint first when the needed signals are missing.
  String? _pendingVersionsId;
  String? _pendingRecommendId;

  @override
  String makeURL(String tags) {
    final parsed = _parse(tags);
    final int page = pageNum < 0 ? 1 : pageNum + 1;

    _relatedMode = parsed.relatedId != null;
    _pendingVersionsId = null;
    _pendingRecommendId = null;

    if (parsed.accountFavorites) {
      // Normal paginated GalleryListItem shape; the q param carries any
      // remaining free text.
      final String q = parsed.query.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(parsed.query)}';
      return '$_base/api/v2/favorites?page=$page$q';
    }
    if (parsed.relatedId != null) {
      return '$_base/api/v2/galleries/${parsed.relatedId}/related';
    }
    if (parsed.recommendId != null) {
      // Single blended page built in parseListFromResponse.
      _pendingRecommendId = parsed.recommendId;
      return '$_base/api/v2/galleries/${parsed.recommendId}';
    }
    if (parsed.versionsId != null) {
      final String? pretty = _prettyTitles[parsed.versionsId!];
      if (pretty == null) {
        // Title unknown (fresh session, restored tab): fetch the detail
        // first; parseListFromResponse runs the real search after.
        _pendingVersionsId = parsed.versionsId;
        return '$_base/api/v2/galleries/${parsed.versionsId}';
      }
      final String phrase = '"${_versionsBaseTitle(pretty)}"';
      return '$_base/api/v2/search?query=${Uri.encodeQueryComponent(phrase)}&page=$page';
    }
    if (parsed.query.isEmpty) {
      // The search endpoint rejects an empty query; the newest-first firehose
      // has its own endpoint. Its `sort` is fixed, so popular sorts go
      // through search with a match-everything pages filter instead.
      if (parsed.sort == null || parsed.sort == 'date') {
        return '$_base/api/v2/galleries?page=$page';
      }
      return '$_base/api/v2/search?query=${Uri.encodeQueryComponent('pages:>0')}&sort=${parsed.sort}&page=$page';
    }
    final String sortParam = parsed.sort != null ? '&sort=${parsed.sort}' : '';
    return '$_base/api/v2/search?query=${Uri.encodeQueryComponent(parsed.query)}$sortParam&page=$page';
  }

  @override
  String makePostURL(String id) => '$_base/g/$id/';

  // ─────────────────────────── tag id cache ───────────────────────────

  /// id -> (name, type). List rows carry tag IDS only; names resolve through
  /// the open /tags/ids endpoint once per unknown id per session.
  static final Map<int, ({String name, TagType type})> _tagCache = {};

  /// name -> the site's own namespace + gallery count, recorded from every
  /// API response that carries tag objects. Feeds the drawer's native
  /// sections, the chip counts, and the grid cards' language badges.
  static final Map<String, ({String namespace, int count})> _tagSiteInfo = {};

  /// gallery id -> "pretty" title (no bracket groups), from the detail call.
  /// Powers the versions/chapters search behind `versions:<id>`.
  static final Map<String, String> _prettyTitles = {};

  static void _recordSiteInfo(dynamic row) {
    final String name = _normalizeName(row['name']?.toString() ?? '');
    final String namespace = row['type']?.toString() ?? '';
    if (name.isEmpty || namespace.isEmpty) return;
    _tagSiteInfo[name] = (namespace: namespace, count: row['count'] as int? ?? 0);
  }

  static int tagSiteCount(String name) => _tagSiteInfo[name]?.count ?? 0;

  @override
  String? tagNamespace(String tag) => _tagSiteInfo[tag]?.namespace;

  @override
  List<(String, String)> get tagNamespaceSections => const [
    ('parody', 'Parodies'),
    ('character', 'Characters'),
    ('artist', 'Artists'),
    ('group', 'Groups'),
    ('category', 'Categories'),
    ('language', 'Languages'),
    ('tag', 'Tags'),
  ];

  @override
  String? relatedVersionsQuery(BooruItem item) {
    final String? id = item.serverId;
    if (id == null || _prettyTitles[id] == null) return null;
    return 'versions:$id';
  }

  /// Base title for finding other chapters and language versions: the pretty
  /// title with trailing subtitle blocks and volume markers stripped, so
  /// "Mesu no Ie III ~Oyako wa...~" searches as "Mesu no Ie" and returns
  /// every chapter in every language (verified live: 16 hits).
  static String _versionsBaseTitle(String pretty) {
    String base = pretty.trim();
    String previous;
    do {
      previous = base;
      base = base
          // trailing ~subtitle~ / (...) / [...] / 【...】 blocks
          .replaceFirst(RegExp(r'[~〜([【][^~〜)\]】]*[~〜)\]】]$'), '')
          // trailing volume/chapter markers
          .replaceFirst(
            RegExp(
              r'(?:[#♯]?\d+|[IVXivx]+|Ch\.?\s*\d+|Vol\.?\s*\d+|Part\s*\d+|前編|中編|後編|上|中|下|続)$',
              caseSensitive: false,
            ),
            '',
          )
          .replaceFirst(RegExp(r'[\s\-–—|:：・]+$'), '')
          .trim();
    } while (base != previous);
    return base.length >= 3 ? base : pretty.trim();
  }

  static TagType _mapType(String type) => switch (type) {
    'artist' => TagType.artist,
    // Circles publish the work; the closest booru concept is artist.
    'group' => TagType.artist,
    'parody' => TagType.copyright,
    'character' => TagType.character,
    'language' => TagType.meta,
    'category' => TagType.meta,
    _ => TagType.none,
  };

  static String _normalizeName(String name) => name.trim().replaceAll(' ', '_');

  Future<void> _resolveTagIds(Iterable<int> ids) async {
    final List<int> missing = ids.where((id) => !_tagCache.containsKey(id)).toSet().toList();
    // Chunked: hundreds of ids per grid page, keep URLs sane.
    for (int i = 0; i < missing.length; i += 100) {
      final chunk = missing.sublist(i, (i + 100).clamp(0, missing.length));
      try {
        final response = await DioNetwork.get(
          '$_base/api/v2/tags/ids?ids=${chunk.join(',')}',
          headers: getHeaders(),
        );
        for (final row in _json(response.data) as List) {
          _tagCache[row['id'] as int] = (name: _normalizeName(row['name'].toString()), type: _mapType(row['type'].toString()));
          _recordSiteInfo(row);
        }
      } catch (e) {
        // Names stay unresolved for this page; the grid still works and
        // loadItem fills real tags on open.
        Logger.Inst().log('tag id resolve failed: $e', className, '_resolveTagIds', LogTypes.booruHandlerInfo);
        return;
      }
    }
  }

  // ─────────────────────────── list parsing ───────────────────────────

  @override
  FutureOr<List> parseListFromResponse(dynamic response) async {
    await _ensureCdnConfig();
    dynamic data = _json(response.data);

    // Related / recommend feeds: one fixed list, no pagination — a second
    // "page" would return the same items forever.
    if ((_relatedMode || _pendingRecommendId != null) && pageNum > 0) return [];

    // versions:<id> with an unknown title bounced through the gallery detail
    // endpoint — record the title, then run the REAL phrase search. Never
    // silently degrades to a plain query.
    if (_pendingVersionsId != null && pageNum <= 0) {
      final String id = _pendingVersionsId!;
      _recordDetailSignals(id, data);
      final String? pretty = _prettyTitles[id];
      if (pretty == null) return [];
      final String phrase = '"${_versionsBaseTitle(pretty)}"';
      final versionsResponse = await DioNetwork.get(
        '$_base/api/v2/search?query=${Uri.encodeQueryComponent(phrase)}&page=1',
        headers: getHeaders(),
      );
      data = _json(versionsResponse.data);
    }

    // recommend:<id>: the detail response IS the seed — build the blended
    // recommendation list from it.
    if (_pendingRecommendId != null && pageNum <= 0) {
      final String id = _pendingRecommendId!;
      _recordDetailSignals(id, data);
      final List recommended = await _buildRecommendations(id, data);
      await _resolveTagIds([
        for (final row in recommended) ...List<int>.from(row['tag_ids'] as List? ?? []),
      ]);
      return recommended;
    }

    final List rows = (data is Map ? data['result'] : data) as List? ?? [];
    if (data is Map && data['total'] != null) {
      totalCount.value = data['total'] as int? ?? 0;
    }

    await _resolveTagIds([
      for (final row in rows) ...List<int>.from(row['tag_ids'] as List? ?? []),
    ]);
    return rows;
  }

  /// Pulls the reusable signals out of a gallery DETAIL response: pretty
  /// title and per-tag site info.
  void _recordDetailSignals(String id, dynamic detail) {
    if (detail is! Map) return;
    final String pretty = (detail['title'] as Map?)?['pretty']?.toString() ?? '';
    if (pretty.isNotEmpty) _prettyTitles[id] = pretty;
    for (final t in detail['tags'] as List? ?? []) {
      _recordSiteInfo(t);
    }
  }

  // ─────────────────────── recommendation engine ───────────────────────

  /// Real recommendations, reference-app style: "the source supplies a
  /// handful; the rest are found by matching this gallery's tags".
  ///
  /// Seeds = the API's own related list (hard-capped at 5 by the site),
  /// extended by searches on the gallery's signals — its artist/group and
  /// its most DISTINCTIVE tags (lowest site-wide count = most specific) —
  /// scored by tag overlap, deduplicated, self and other chapters/language
  /// versions of the same work excluded. All verified live: the artist
  /// search returns the author's other works, the two-distinctive-tag AND
  /// search returns thematically close galleries.
  Future<List> _buildRecommendations(String id, dynamic detail) async {
    if (detail is! Map) return [];
    final int limit = SourceSettingsHandler.instance.recommendedCount(booru);

    final Set<int> sourceTagIds = {
      for (final t in detail['tags'] as List? ?? []) t['id'] as int,
    };
    final String pretty = (detail['title'] as Map?)?['pretty']?.toString() ?? '';
    final String baseTitle = pretty.isEmpty ? '' : _versionsBaseTitle(pretty).toLowerCase();

    String? artist;
    final List<(String, int)> generalTags = [];
    for (final t in detail['tags'] as List? ?? []) {
      final String type = t['type'].toString();
      final String name = t['name'].toString();
      if (type == 'artist' || type == 'group') artist ??= name;
      if (type == 'tag') generalTags.add((name, t['count'] as int? ?? 0));
    }
    // Low count = specific. 'original' & co. are parodies, already skipped.
    generalTags.sort((a, b) => a.$2.compareTo(b.$2));
    final List<String> distinctive = [for (final t in generalTags.take(3)) t.$1];

    Future<List> search(String query, {String sort = 'popular'}) async {
      try {
        final response = await DioNetwork.get(
          '$_base/api/v2/search?query=${Uri.encodeQueryComponent(query)}&sort=$sort&page=1',
          headers: getHeaders(),
        );
        return (_json(response.data) as Map)['result'] as List? ?? [];
      } catch (_) {
        return [];
      }
    }

    Future<List> related() async {
      try {
        final response = await DioNetwork.get(
          '$_base/api/v2/galleries/$id/related',
          headers: getHeaders(),
        );
        return (_json(response.data) as Map)['result'] as List? ?? [];
      } catch (_) {
        return [];
      }
    }

    final results = await Future.wait([
      related(),
      if (artist != null) search('artist:"$artist"'),
      if (distinctive.length >= 2) search('tag:"${distinctive[0]}" tag:"${distinctive[1]}"'),
      if (distinctive.isNotEmpty) search('tag:"${distinctive[0]}"'),
    ]);

    final List seeds = results.first;
    final Set<int> seen = {int.parse(id)};
    bool isVersionOfSource(dynamic row) =>
        baseTitle.isNotEmpty && row['english_title'].toString().toLowerCase().contains(baseTitle);

    final List out = [];
    for (final row in seeds) {
      final int rowId = row['id'] as int;
      if (seen.add(rowId) && !isVersionOfSource(row)) out.add(row);
    }

    // Extension candidates, scored by tag overlap with the source gallery
    // (cosine-ish), same-artist results get a small boost.
    final List<(double, dynamic)> scored = [];
    for (int i = 1; i < results.length; i++) {
      final bool isArtistBucket = artist != null && i == 1;
      for (final row in results[i]) {
        final int rowId = row['id'] as int;
        if (seen.contains(rowId) || isVersionOfSource(row)) continue;
        seen.add(rowId);
        final List<int> tagIds = List<int>.from(row['tag_ids'] as List? ?? []);
        final int overlap = tagIds.where(sourceTagIds.contains).length;
        final double denominator = tagIds.isEmpty || sourceTagIds.isEmpty
            ? 1
            : math.sqrt(tagIds.length * sourceTagIds.length);
        scored.add((overlap / denominator + (isArtistBucket ? 0.3 : 0), row));
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    out.addAll([for (final s in scored) s.$2]);

    return out.take(limit).toList();
  }

  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) {
    final row = responseItem;
    final int id = row['id'] as int;
    final String thumbPath = row['thumbnail'].toString();
    final String thumb = thumbUrl(thumbPath);

    final List<Tag> tags = [
      for (final tagId in List<int>.from(row['tag_ids'] as List? ?? []))
        if (_tagCache[tagId] != null)
          Tag(
            _tagCache[tagId]!.name,
            tagType: _tagCache[tagId]!.type,
            count: tagSiteCount(_tagCache[tagId]!.name),
          ),
    ];

    final String english = row['english_title']?.toString() ?? '';
    final String? japanese = row['japanese_title']?.toString();

    final item = BooruItem(
      fileURL: thumb,
      sampleURL: thumb,
      thumbnailURL: thumb,
      tagsList: tags,
      postURL: makePostURL(id.toString()),
      serverId: id.toString(),
      // Real page dimensions come with the detail call; the thumb's aspect
      // ratio is what the grid needs now.
      fileWidth: (row['thumbnail_width'] as num?)?.toDouble(),
      fileHeight: (row['thumbnail_height'] as num?)?.toDouble(),
      description: [english, if (japanese?.isNotEmpty ?? false) japanese].join('\n'),
    );
    item.fileCountHint.value = row['num_pages'] as int? ?? 0;
    final int favs = row['num_favorites'] as int? ?? 0;
    if (favs > 0) item.score = favs.toString();

    for (final tag in tags) {
      addTagsWithType([tag.fullString], tag.tagType);
    }
    return item;
  }

  // ─────────────────────────── detail / book ───────────────────────────

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      await _ensureCdnConfig();
      final String id = item.serverId ?? '';
      if (id.isEmpty) return (item: null, failed: true, error: 'no gallery id');

      final response = await DioNetwork.get(
        '$_base/api/v2/galleries/$id',
        headers: getHeaders(),
        cancelToken: cancelToken,
      );
      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      }
      final data = _json(response.data);

      // Typed tags, by NAME this time.
      final List<Tag> tags = [];
      final Map<TagType, List<String>> byType = {};
      for (final t in data['tags'] as List? ?? []) {
        final TagType type = _mapType(t['type'].toString());
        final String name = _normalizeName(t['name'].toString());
        if (name.isEmpty || tags.any((x) => x.fullString == name)) continue;
        _recordSiteInfo(t);
        tags.add(Tag(name, tagType: type, count: tagSiteCount(name)));
        byType.putIfAbsent(type, () => []).add(name);
      }
      if (tags.isNotEmpty) {
        item.tagsList = tags;
        for (final entry in byType.entries) {
          addTagsWithType(entry.value, entry.key);
        }
      }

      // The whole book: every page becomes a real BooruItem so the reader,
      // the media cache and the snatcher all run their normal pipelines.
      final List<BooruItem> pages = [];
      for (final page in data['pages'] as List? ?? []) {
        final String path = page['path'].toString();
        final String pageThumb = page['thumbnail']?.toString() ?? '';
        pages.add(
          BooruItem(
            fileURL: imageUrl(path),
            sampleURL: imageUrl(path),
            thumbnailURL: pageThumb.isNotEmpty ? thumbUrl(pageThumb) : item.thumbnailURL,
            tagsList: tags,
            postURL: item.postURL,
            serverId: '${id}_p${page['number']}',
            fileWidth: (page['width'] as num?)?.toDouble(),
            fileHeight: (page['height'] as num?)?.toDouble(),
          ),
        );
      }
      if (pages.isNotEmpty) {
        ReaderHandler.instance.registerBook(item, pages);
        // The viewer shows the opened gallery as its first page in full
        // resolution — the grid thumb is only 250px.
        item
          ..fileURL = pages.first.fileURL
          ..fileWidth = pages.first.fileWidth
          ..fileHeight = pages.first.fileHeight
          // Set in the constructor normally; recompute since dims changed.
          ..fileAspectRatio = pages.first.fileAspectRatio;
      }

      final title = data['title'] as Map? ?? {};
      final String english = title['english']?.toString() ?? '';
      final String? japanese = title['japanese']?.toString();
      final String pretty = title['pretty']?.toString() ?? '';
      if (pretty.isNotEmpty) _prettyTitles[id] = pretty;
      final String scanlator = data['scanlator']?.toString() ?? '';
      item.description = [
        english,
        if (japanese?.isNotEmpty ?? false) japanese,
        if (scanlator.isNotEmpty) 'Scanlator: $scanlator',
      ].join('\n');

      final int favs = data['num_favorites'] as int? ?? 0;
      if (favs > 0) item.score = favs.toString();
      final int uploadDate = data['upload_date'] as int? ?? 0;
      if (uploadDate > 0) {
        item.postDate = uploadDate.toString();
        item.postDateFormat = 'unix';
      }

      item.isUpdated = true;
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log(e.toString(), className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  // ─────────────────────────── suggestions ───────────────────────────

  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final String query = input.trim().replaceAll('_', ' ');
    if (query.isEmpty) return const Right([]);
    try {
      final response = await DioNetwork.post(
        '$_base/api/v2/tags/search',
        data: {'query': query, 'limit': 25},
        headers: getHeaders(),
        cancelToken: cancelToken,
      );
      final List rows = _json(response.data) as List? ?? [];
      rows.forEach(_recordSiteInfo);
      return Right([
        for (final row in rows)
          TagSuggestion(
            // Suggestions insert the term the search understands: namespaced
            // for everything that has one, bare for plain tags.
            tag: row['type'].toString() == 'tag'
                ? _normalizeName(row['name'].toString())
                : '${row['type']}:${_normalizeName(row['name'].toString())}',
            count: row['count'] as int? ?? 0,
            type: _mapType(row['type'].toString()),
          ),
      ]);
    } catch (e, s) {
      Logger.Inst().log(e.toString(), className, 'getTagSuggestions', LogTypes.exception, s: s);
      return Left(ResponseError(message: 'tag suggestions failed', error: e));
    }
  }

  // ─────────────────────────── comments ───────────────────────────

  @override
  String makeCommentsURL(String postID, int pageNum) =>
      '$_base/api/v2/galleries/$postID?include=comments';

  @override
  List parseCommentsList(dynamic response) {
    final data = _json(response.data);
    return data['comments'] as List? ?? [];
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    final poster = responseItem['poster'] as Map? ?? {};
    // Relative ("avatars/123.png"); the i-servers host them (t 404s).
    final String avatar = poster['avatar_url']?.toString() ?? '';
    return CommentItem(
      id: responseItem['id']?.toString(),
      title: responseItem['gallery_id']?.toString(),
      content: responseItem['body']?.toString(),
      authorID: poster['id']?.toString(),
      authorName: poster['username']?.toString(),
      avatarUrl: avatar.isEmpty
          ? null
          : avatar.startsWith('http')
          ? avatar
          : imageUrl(avatar),
      postID: responseItem['gallery_id']?.toString(),
      createDate: responseItem['post_date']?.toString(),
      createDateFormat: 'unix',
    );
  }
}
