import 'dart:async';
import 'dart:convert';

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
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// tik.porn handler.
///
/// A short-form ("porn TikTok") vertical video site. Video-only, no images.
/// The site is a Next.js frontend over a plain, unauthenticated JSON API —
/// everything below was verified live against production.
///
/// API host: https://apiv2.tik.porn
///
/// Feeds (all return rows carrying ready-to-play media URLs):
///   GET /search?search_term=Q&index=search&search_type=video&limit&offset
///   GET /gettagvideos?tagid=ID&limit&offset&sort
///   GET /getactionvideos?actionid=ID&limit&offset&sort
///   GET /getuservideos?userid=ID&limit&offset&sort
///   GET /gettaglist            — all 84 tags   (id, name, slug)
///   GET /getactionlist         — all 131 acts  (id, name, slug)
///   GET /getuserbyslug?slug=S  — creator slug -> numeric id
///
/// Notable behaviour found while testing, which shapes the code below:
///   * `search_term=*` returns the whole catalogue (~102k videos) with
///     working limit/offset paging, so it is used for an empty query.
///   * `/getrecentvideos` ignores page AND limit AND offset — it is a fixed
///     ten-item strip, not a browsable feed, so it is not used at all.
///   * `/videos/popular` honours `offset` but pins the page size to 10.
///   * `sort` only does something on the id-based feeds, and only
///     `recent` (default) and `popular` differ — `views`, `likes`,
///     `trending`, `random`, `best` and `oldest` all silently return the
///     `recent` ordering. `/search` ignores `sort` entirely.
///   * Media URLs are signed and expire, so items must not be persisted and
///     replayed later — the app refetches feeds anyway.
class TikPornHandler extends BooruHandler {
  TikPornHandler(super.booru, super.limit);

  static const String _api = 'https://apiv2.tik.porn';
  static const String _site = 'https://tik.porn';

  /// Search-term suggestion index. The site's own frontend queries this
  /// directly from the browser with these exact credentials baked into its
  /// JavaScript bundle — they are a public read handle for the suggestion
  /// index, not a secret, and this makes the same read for the same purpose.
  static const String _elastic = 'https://elastic-prod.tik.porn';
  static const String _elasticAuth = 'elastic:fCVuOIdalCqK';

  /// slug -> numeric id, for the two fixed vocabularies. Both are small and
  /// change rarely, so they are fetched once per app run and shared.
  static final Map<String, int> _tagIds = {};
  static final Map<String, int> _actionIds = {};
  static final Map<String, String> _displayNames = {};
  static bool _vocabularyLoaded = false;
  static Future<void>? _vocabularyLoad;

  /// creator slug -> numeric id, resolved on demand.
  static final Map<String, int> _creatorIds = {};

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => true;

  /// One feed at a time — the API has no boolean tag logic.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String validateTags(String tags) => tags.trim();

  /// Video-only site, so the "videos only" filter would select everything.
  /// An empty list tells the UI to hide that control entirely.
  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Recent', value: 'recent'),
          MetaTagValue(name: 'Popular', value: 'popular'),
        ],
      ),
    ];
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      'Origin': _site,
      'Referer': '$_site/',
    };
  }

  // ─────────────────────────── query parsing ───────────────────────────

  ({String sort, String? tag, String? action, String? creator, String terms}) _parse(String input) {
    String sort = 'recent';
    String? tag;
    String? action;
    String? creator;
    final List<String> terms = [];

    for (final term in input.split(' ').where((t) => t.isNotEmpty)) {
      final String lower = term.toLowerCase();
      final int colon = term.indexOf(':');
      final String key = colon <= 0 ? '' : lower.substring(0, colon);
      final String value = colon <= 0 ? '' : term.substring(colon + 1).trim();

      switch (key) {
        case 'sort' || 'order':
          // Only these two orderings actually exist server-side; anything
          // else is accepted and quietly behaves as `recent`, exactly as the
          // API itself does.
          sort = (value.toLowerCase() == 'popular' || value.toLowerCase() == 'top') ? 'popular' : 'recent';
        case 'tag':
          if (value.isNotEmpty) tag = _slugify(value);
        case 'action':
          if (value.isNotEmpty) action = _slugify(value);
        case 'creator' || 'artist' || 'user':
          if (value.isNotEmpty) creator = value.toLowerCase();
        default:
          terms.add(term);
      }
    }

    // A single bare word that names a real tag or action is far better served
    // by that feed than by free-text search: it is exhaustive, ordered, and
    // supports the sort chip.
    if (tag == null && action == null && creator == null && terms.length == 1) {
      final String slug = _slugify(terms.first);
      if (_tagIds.containsKey(slug)) {
        tag = slug;
        terms.clear();
      } else if (_actionIds.containsKey(slug)) {
        action = slug;
        terms.clear();
      }
    }

    return (sort: sort, tag: tag, action: action, creator: creator, terms: terms.join(' ').trim());
  }

  static String _slugify(String value) => value.trim().toLowerCase().replaceAll('_', '-');

  /// What to put in `search_term` when no id-based feed matched.
  ///
  /// Two things this must get right:
  ///
  /// * **Underscores kill this search.** The index is natural language, not
  ///   booru-style tags: `teen_anal` returns 0 results and `teen anal`
  ///   returns 26722; `hatsune_miku` returns 0 and `hatsune miku` returns 4.
  ///   Every cross-booru feature (Tag Hub, Artist Hub, suggestions) hands
  ///   over underscored tags, so without this the site would look empty for
  ///   almost every one of them.
  ///
  /// * **A named-but-unresolved facet must not become "everything".** If you
  ///   asked for `creator:someone` and the lookup failed, falling back to the
  ///   bare `*` catalogue would quietly answer a completely different
  ///   question with 100k confident-looking results. Search the name instead
  ///   — wrong-ish beats wrong-and-invisible — and keep `*` for the case
  ///   where nothing was asked for at all.
  static String _searchTerm(({String sort, String? tag, String? action, String? creator, String terms}) parts) {
    final String text = [
      parts.terms,
      // Only reached when the id lookup for these came back empty.
      parts.creator ?? '',
      parts.tag ?? '',
      parts.action ?? '',
    ].where((part) => part.isNotEmpty).join(' ');

    if (text.isEmpty) return '*';
    return text.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  // ──────────────────────────── setup / url ────────────────────────────

  /// [makeURL] is called synchronously by the base handler, so everything
  /// that needs the network — the tag/action vocabulary, and turning a
  /// creator slug into the numeric id its feed is keyed on — is resolved
  /// here first. By the time the URL is built, every id is already cached.
  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    await _loadVocabulary();
    final parts = _parse(validateTags(tags.trim()));
    if (parts.creator != null) await _resolveCreator(parts.creator!);
    return super.search(tags, pageNumCustom, withCaptchaCheck: withCaptchaCheck);
  }

  Future<void> _loadVocabulary() {
    if (_vocabularyLoaded) return Future.value();
    return _vocabularyLoad ??= _fetchVocabulary();
  }

  Future<void> _fetchVocabulary() async {
    try {
      final responses = await Future.wait([
        DioNetwork.get('$_api/gettaglist', headers: getHeaders()),
        DioNetwork.get('$_api/getactionlist', headers: getHeaders()),
      ]);
      _collectVocabulary(responses[0].data, 'tags', 'tag_id', _tagIds);
      _collectVocabulary(responses[1].data, 'actions', 'action_id', _actionIds);
      _vocabularyLoaded = _tagIds.isNotEmpty || _actionIds.isNotEmpty;
    } catch (e, s) {
      Logger.Inst().log(
        'failed to load tik.porn tag/action list: $e',
        className,
        '_fetchVocabulary',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
    } finally {
      // Allow a retry on the next search rather than caching the failure.
      _vocabularyLoad = null;
    }
  }

  void _collectVocabulary(dynamic data, String key, String idKey, Map<String, int> into) {
    // Written out rather than chained: `?[` inside a conditional expression
    // is ambiguous to the Dart parser and won't compile.
    if (data is! Map) return;
    final dynamic payload = data['data'];
    if (payload is! Map) return;
    final dynamic group = payload[key];
    final dynamic content = group is Map ? group['content'] : null;
    if (content is! List) return;
    for (final entry in content) {
      if (entry is! Map) continue;
      final String slug = entry['slug']?.toString() ?? '';
      final int? id = int.tryParse(entry[idKey]?.toString() ?? '');
      if (slug.isEmpty || id == null) continue;
      into[slug] = id;
      final String name = entry['name']?.toString() ?? '';
      if (name.isNotEmpty) _displayNames[slug] = name;
    }
  }

  Future<void> _resolveCreator(String slug) async {
    if (_creatorIds.containsKey(slug)) return;
    try {
      final response = await DioNetwork.get(
        '$_api/getuserbyslug',
        queryParameters: {'slug': slug},
        headers: getHeaders(),
      );
      final dynamic data = response.data;
      final dynamic payload = data is Map ? data['user_account_id'] : null;
      final dynamic user = data is Map ? data['data'] : null;
      final int? id = int.tryParse(
        ((user is Map ? user['user_account_id'] : null) ?? payload)?.toString() ?? '',
      );
      if (id != null) _creatorIds[slug] = id;
    } catch (e) {
      Logger.Inst().log(
        'creator lookup failed for "$slug": $e',
        className,
        '_resolveCreator',
        LogTypes.booruHandlerFetchFailed,
      );
    }
  }

  @override
  String makeURL(String tags) {
    final parts = _parse(tags);
    final int page = pageNum < 0 ? 0 : pageNum;
    final int offset = page * limit;

    String path;
    final Map<String, String> params = {
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    final int? tagId = parts.tag == null ? null : _tagIds[parts.tag];
    final int? actionId = parts.action == null ? null : _actionIds[parts.action];
    final int? creatorId = parts.creator == null ? null : _creatorIds[parts.creator];

    if (tagId != null) {
      path = '/gettagvideos';
      params['tagid'] = tagId.toString();
      params['sort'] = parts.sort;
    } else if (actionId != null) {
      path = '/getactionvideos';
      params['actionid'] = actionId.toString();
      params['sort'] = parts.sort;
    } else if (creatorId != null) {
      path = '/getuservideos';
      params['userid'] = creatorId.toString();
      params['sort'] = parts.sort;
    } else {
      path = '/search';
      params['search_term'] = _searchTerm(parts);
      params['index'] = 'search';
      params['search_type'] = 'video';
    }

    return Uri.parse('$_api$path').replace(queryParameters: params).toString();
  }

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    return DioNetwork.get(
      uri.toString(),
      headers: getHeaders(),
      queryParameters: queryParams,
    );
  }

  // ───────────────────────────── parsing ─────────────────────────────

  @override
  List parseListFromResponse(dynamic response) {
    final data = response.data;
    if (data is! Map) return [];
    final dynamic payload = data['data'];

    // Two shapes across the endpoints used here:
    //   /search        -> data.content
    //   /get*videos    -> data.videos.content
    final dynamic videos = payload is Map ? payload['videos'] : null;
    final dynamic content = payload is Map
        ? (payload['content'] ?? (videos is Map ? videos['content'] : null))
        : payload;

    if (content is List) {
      _readTotal(payload);
      return content;
    }
    return [];
  }

  void _readTotal(dynamic payload) {
    final dynamic videos = payload is Map ? payload['videos'] : null;
    final dynamic pagination = payload is Map
        ? (payload['pagination'] ?? (videos is Map ? videos['pagination'] : null))
        : null;
    final dynamic total = pagination is Map ? pagination['total'] : null;
    final int? parsedTotal = int.tryParse(total?.toString() ?? '');
    if (parsedTotal != null && parsedTotal > 0) totalCount.value = parsedTotal;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map video = responseItem;

    final String id = video['video_id']?.toString() ?? '';
    final String fileURL = _nonEmpty(video['mp4_url']) ?? _nonEmpty(video['hls_url']) ?? '';
    if (id.isEmpty || fileURL.isEmpty) return null;

    // Poster is the vertical still; list-sm/md are the grid crops. Falling
    // back through them keeps a thumbnail even on older rows that predate
    // the extra formats.
    final String thumbnailURL =
        _nonEmpty(video['small_thumb']) ??
        _nonEmpty(video['medium_thumb']) ??
        _nonEmpty(video['poster_url']) ??
        fileURL;
    final String sampleURL = _nonEmpty(video['poster_url']) ?? thumbnailURL;

    final List<Tag> tags = [];
    for (final tag in (video['tags'] as List?) ?? const []) {
      if (tag is! Map) continue;
      final String slug = tag['slug']?.toString() ?? '';
      if (slug.isEmpty) continue;
      tags.add(Tag(slug));
    }

    // The "action" is the act performed (Anal Doggystyle, Teasing…). It is a
    // separate axis from tags on this site and has its own feed, so it goes
    // in as `action:<slug>` — tapping it lands on that feed rather than a
    // free-text search that would only match titles.
    final String actionSlug = video['action_slug']?.toString() ?? '';
    if (actionSlug.isNotEmpty) {
      final String actionTag = 'action:$actionSlug';
      tags.add(Tag(actionTag, tagType: TagType.meta));
      addTagsWithType([actionTag], TagType.meta);
    }

    // Creator, as an artist tag so it colours correctly and routes to that
    // creator's feed.
    final List creators = (video['creator'] as List?) ?? const [];
    final Map? creator = (creators.isNotEmpty && creators.first is Map) ? creators.first as Map : null;
    final String? creatorSlug = _nonEmpty(creator?['slug']) ?? _nonEmpty(video['user_slug']);
    final String? creatorName = _nonEmpty(creator?['name']) ?? _nonEmpty(video['user_name']);
    if (creatorSlug != null) {
      final String creatorTag = 'creator:${creatorSlug.toLowerCase()}';
      tags.add(Tag(creatorTag, tagType: TagType.artist));
      addTagsWithType([creatorTag], TagType.artist);
    }

    for (final pornstar in (video['pornstars'] as List?) ?? const []) {
      if (pornstar is! Map) continue;
      final String slug = pornstar['slug']?.toString() ?? '';
      if (slug.isEmpty) continue;
      final String starTag = 'star:$slug';
      tags.add(Tag(starTag, tagType: TagType.character));
      addTagsWithType([starTag], TagType.character);
    }

    for (final keyword in (video['keywords'] as List?) ?? const []) {
      final String word = keyword?.toString().trim() ?? '';
      if (word.isEmpty) continue;
      tags.add(Tag(word.toLowerCase().replaceAll(' ', '_')));
    }

    final int likes = int.tryParse(video['like_count']?.toString() ?? '') ?? 0;

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL,
      thumbnailURL: thumbnailURL,
      // The mp4 URL carries a query string and a signature; pin the extension
      // so the app classifies it as video without parsing that.
      fileExt: 'mp4',
      tagsList: tags,
      postURL: makePostURL(id),
      serverId: id,
      score: likes > 0 ? likes.toString() : null,
      postDate: _nonEmpty(video['published']) ?? _nonEmpty(video['video_date']),
      postDateFormat: 'yyyy-MM-dd HH:mm:ss',
      uploaderName: creatorName,
    );
  }

  String? _nonEmpty(dynamic value) {
    if (value == null) return null;
    final String string = value.toString();
    return (string.isEmpty || string == 'null') ? null : string;
  }

  @override
  String makePostURL(String id) => '$_site/video/$id';

  // ──────────────────────────── suggestions ────────────────────────────

  /// Suggestions come from two places, in this order:
  ///   * the fixed tag/action vocabulary, matched locally — these are the
  ///     terms that route to a real feed, so they are worth surfacing first;
  ///   * the site's own search-term index, for everything else.
  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final String query = input.trim().toLowerCase();
    if (query.isEmpty) return const Right([]);

    await _loadVocabulary();
    final String slugQuery = _slugify(query);

    final List<TagSuggestion> out = [];
    void addVocabulary(Map<String, int> source, String prefix, TagType type) {
      for (final slug in source.keys) {
        if (out.length >= 20) return;
        if (!slug.contains(slugQuery) && !(_displayNames[slug]?.toLowerCase().contains(query) ?? false)) {
          continue;
        }
        out.add(TagSuggestion(tag: '$prefix$slug', type: type));
      }
    }

    addVocabulary(_tagIds, '', TagType.none);
    addVocabulary(_actionIds, 'action:', TagType.meta);

    try {
      final List<TagSuggestion> keywords = await _searchTermSuggestions(query, cancelToken: cancelToken);
      for (final keyword in keywords) {
        if (out.length >= 25) break;
        if (out.any((existing) => existing.tag == keyword.tag)) continue;
        out.add(keyword);
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        return Left(ResponseError(message: 'cancelled', error: e));
      }
      // Vocabulary matches alone are still a useful answer.
    }

    return Right(out);
  }

  Future<List<TagSuggestion>> _searchTermSuggestions(String query, {CancelToken? cancelToken}) async {
    final response = await DioNetwork.post(
      '$_elastic/search_term/_search',
      data: {
        'sort': [
          '_score',
          {
            'word_count': {'order': 'asc'},
          },
          {
            'search_count': {'order': 'desc'},
          },
        ],
        'query': {
          'function_score': {
            'query': {
              'bool': {
                'must': [
                  {
                    'match': {'search_term': query},
                  },
                ],
                'filter': [
                  {
                    'term': {'keep': 1},
                  },
                ],
              },
            },
            'functions': [
              {
                'filter': {
                  'term': {'featured': 1},
                },
                'weight': 2,
              },
            ],
            'boost_mode': 'multiply',
          },
        },
        'size': 15,
      },
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': Tools.browserUserAgent,
        'Authorization': 'Basic ${base64Encode(utf8.encode(_elasticAuth))}',
      },
      cancelToken: cancelToken,
    );

    final dynamic data = response.data;
    final dynamic hitsRoot = data is Map ? data['hits'] : null;
    final dynamic hits = hitsRoot is Map ? hitsRoot['hits'] : null;
    if (hits is! List) return [];
    return [
      for (final hit in hits)
        if (hit is Map && hit['_source'] is Map && _nonEmpty(hit['_source']['search_term']) != null)
          TagSuggestion(
            tag: hit['_source']['search_term'].toString(),
            count: int.tryParse(hit['_source']['search_count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  // ───────────────────────────── comments ─────────────────────────────

  @override
  bool get hasCommentsSupport => true;

  @override
  String makeCommentsURL(String postID, int pageNum) {
    return Uri.parse('$_api/getvideocomments').replace(
      queryParameters: {
        'videoid': postID,
        'limit': '30',
        'offset': (pageNum * 30).toString(),
      },
    ).toString();
  }

  @override
  List parseCommentsList(dynamic response) {
    final dynamic data = response.data;
    final dynamic payload = data is Map ? data['data'] : null;
    final dynamic comments = payload is Map ? payload['video_comments'] : null;
    final dynamic content = comments is Map ? comments['content'] : null;
    return content is List ? content : [];
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final String content = responseItem['content']?.toString().trim() ?? '';
    if (content.isEmpty) return null;
    final String date = [
      responseItem['creationDate']?.toString() ?? '',
      responseItem['creationTime']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    return CommentItem(
      id: responseItem['id']?.toString(),
      title: responseItem['username']?.toString(),
      content: content,
      authorID: responseItem['owner_id']?.toString(),
      authorName: responseItem['username']?.toString(),
      avatarUrl: _nonEmpty(responseItem['avatar']),
      postID: responseItem['video_id']?.toString(),
      createDate: date.isEmpty ? null : date,
      createDateFormat: 'yyyy-MM-dd HH:mm:ss',
    );
  }
}
