import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// civitai.com — the AI-generation gallery, via its public REST API
/// (https://developer.civitai.com, /api/v1/images).
///
/// Query language:
///   plain tags        → resolved to Civitai numeric tag ids (the API only
///                       filters by id); `-tag` exclusions are applied
///                       client-side since the API has no exclusion support
///   artist:name       → username filter (`artist:me` = your own uploads,
///                       resolved through /api/v1/me with your API key)
///   sort: / period:   → feed controls (incl. random), timeframe
///   nsfw:             → none / soft / mature / x / all browsing level
///   type:             → image / video
///   basemodel:        → SDXL / Pony / Flux / Illustrious / SD 1.5 / ...
///   model:id post:id  → images of a specific model / post
///
/// Auth: put your Civitai API key in the booru config's API key field — it is
/// sent as a Bearer token (raises the visible browsing level to your
/// account's). NOTE: the public API has no "liked images" feed (that part of
/// the site is not exposed to external clients), `artist:me` is the closest.
class CivitaiHandler extends BooruHandler {
  CivitaiHandler(super.booru, super.limit);

  @override
  bool get hasTagSuggestions => true;

  @override
  Map<String, TagType> get tagTypeMap => {};

  bool get _hasApiKey => booru.apiKey?.isNotEmpty == true;

  Map<String, String> _authHeaders() => {
    ...getHeaders(),
    if (_hasApiKey) 'Authorization': 'Bearer ${booru.apiKey}',
  };

  // ── tag name → numeric id resolution ────────────────────────────────────
  // The images endpoint only accepts numeric tag ids. Ids are harvested from
  // every parsed item (withTags=true) and, for names we haven't seen yet,
  // scraped once from the tag's public page (its embedded JSON carries
  // {"id":N,"name":"..."}). Both live in a static cache.
  static final Map<String, int> _tagIdCache = {};

  Future<int?> _resolveTagId(String name) async {
    final String key = name.toLowerCase().replaceAll('_', ' ');
    final int? cached = _tagIdCache[key];
    if (cached != null) return cached;

    try {
      final res = await DioNetwork.get(
        '${booru.baseURL}/tag/${Uri.encodeComponent(key)}',
        headers: getHeaders(),
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final String body = res.data.toString();
      final RegExp pat = RegExp('\\{"id":(\\d+),"name":"${RegExp.escape(key)}"');
      final Match? m = pat.firstMatch(body);
      if (m != null) {
        final int id = int.parse(m.group(1)!);
        _tagIdCache[key] = id;
        return id;
      }
    } catch (e) {
      Logger.Inst().log(
        'civitai tag resolve failed for "$key": $e',
        className,
        '_resolveTagId',
        LogTypes.booruHandlerInfo,
      );
    }
    return null;
  }

  // ── own username (artist:me) ────────────────────────────────────────────
  static final Map<String, String> _ownUsernameCache = {};

  Future<String?> _ownUsername() async {
    if (!_hasApiKey) return null;
    final String key = booru.apiKey!;
    final String? cached = _ownUsernameCache[key];
    if (cached != null) return cached;
    try {
      final res = await DioNetwork.get(
        '${booru.baseURL}/api/v1/me',
        headers: _authHeaders(),
      );
      final String? name = (res.data is Map) ? res.data['username']?.toString() : null;
      if (name != null && name.isNotEmpty) {
        _ownUsernameCache[key] = name;
        return name;
      }
    } catch (e) {
      Logger.Inst().log(
        'civitai /me failed: $e',
        className,
        '_ownUsername',
        LogTypes.booruHandlerInfo,
      );
    }
    return null;
  }

  // ── query parsing ───────────────────────────────────────────────────────

  static const Map<String, String> _sortMap = {
    'newest': 'Newest',
    'new': 'Newest',
    'date': 'Newest',
    'oldest': 'Oldest',
    'old': 'Oldest',
    'reactions': 'Most Reactions',
    'likes': 'Most Reactions',
    'score': 'Most Reactions',
    'comments': 'Most Comments',
    'collected': 'Most Collected',
    'random': 'Random',
    'shuffle': 'Random',
  };

  static const Map<String, String> _periodMap = {
    'day': 'Day',
    'today': 'Day',
    'week': 'Week',
    'month': 'Month',
    'year': 'Year',
    'all': 'AllTime',
    'alltime': 'AllTime',
  };

  // Browsing levels are bit flags: PG 1, PG13 2, R 4, X 8, XXX 16.
  static const Map<String, String> _nsfwToBrowsingLevel = {
    'none': '1',
    'safe': '1',
    'soft': '2',
    'mature': '4',
    'x': '8',
    'xxx': '16',
    'all': '31',
    'any': '31',
  };

  ({
    List<String> includeTags,
    List<String> excludeTags,
    Map<String, String> params,
    bool wantsOwn,
  }) _parseQuery(String input) {
    final List<String> include = [];
    final List<String> exclude = [];
    final Map<String, String> params = {};
    bool wantsOwn = false;

    for (final rawTerm in input.trim().split(' ')) {
      if (rawTerm.isEmpty) continue;
      final bool negative = rawTerm.startsWith('-');
      final String term = negative ? rawTerm.substring(1) : rawTerm;
      final String lower = term.toLowerCase();

      String valueOf(String prefix) => term.substring(prefix.length);

      if (lower.startsWith('sort:')) {
        params['sort'] = _sortMap[lower.substring(5)] ?? 'Newest';
      } else if (lower.startsWith('period:')) {
        params['period'] = _periodMap[lower.substring(7)] ?? 'AllTime';
      } else if (lower.startsWith('nsfw:')) {
        params['browsingLevel'] = _nsfwToBrowsingLevel[lower.substring(5)] ?? '31';
      } else if (lower.startsWith('type:')) {
        final String v = lower.substring(5);
        if (v == 'image' || v == 'video') params['type'] = v;
      } else if (lower.startsWith('basemodel:')) {
        // Values use _ for spaces in the query (SD_1.5 → SD 1.5).
        params['baseModels'] = valueOf('basemodel:').replaceAll('_', ' ');
      } else if (lower.startsWith('artist:') || lower.startsWith('username:') || lower.startsWith('user:')) {
        final String v = valueOf('${lower.split(':').first}:');
        if (v.toLowerCase() == 'me') {
          wantsOwn = true;
        } else if (v.isNotEmpty) {
          params['username'] = v;
        }
      } else if (lower.startsWith('model:')) {
        params['modelId'] = valueOf('model:');
      } else if (lower.startsWith('modelversion:')) {
        params['modelVersionId'] = valueOf('modelversion:');
      } else if (lower.startsWith('post:')) {
        params['postId'] = valueOf('post:');
      } else if (negative) {
        exclude.add(lower.replaceAll('_', ' '));
      } else {
        include.add(lower.replaceAll('_', ' '));
      }
    }

    return (includeTags: include, excludeTags: exclude, params: params, wantsOwn: wantsOwn);
  }

  // Exclusions applied client-side in parseItemFromResponse.
  List<String> _activeExclusions = [];

  // ── search ──────────────────────────────────────────────────────────────

  String _cursor = '';

  @override
  String makeURL(String tags) {
    // Full URL construction happens in fetchSearch (needs async tag-id and
    // username resolution); this is only the base.
    return '${booru.baseURL}/api/v1/images';
  }

  @override
  String validateTags(String tags) => tags;

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    final parsed = _parseQuery(input);
    _activeExclusions = parsed.excludeTags;

    if (pageNum <= 0) {
      _cursor = '';
    }

    // Resolve plain tags to Civitai ids; unknown tags fail loudly instead of
    // silently returning the unfiltered feed.
    final List<int> tagIds = [];
    for (final name in parsed.includeTags) {
      final int? id = await _resolveTagId(name);
      if (id == null) {
        throw Exception('civitai: unknown tag "$name" — try a suggestion from the tag search.');
      }
      tagIds.add(id);
    }

    if (parsed.wantsOwn) {
      final String? own = await _ownUsername();
      if (own == null) {
        throw Exception(
          'civitai: artist:me needs a valid API key in this booru\'s config (could not resolve your username).',
        );
      }
      parsed.params['username'] = own;
    }

    final Map<String, dynamic> query = {
      'limit': limit.toString(),
      'withTags': 'true',
      // default to everything the account can see; nsfw: overrides
      if (!parsed.params.containsKey('browsingLevel')) 'browsingLevel': '31',
      if (tagIds.isNotEmpty) 'tags': tagIds.join(','),
      ...parsed.params,
      if (_cursor.isNotEmpty) 'cursor': _cursor,
    };

    Logger.Inst().log(
      'fetching civitai: $query',
      className,
      'Search',
      LogTypes.booruHandlerSearchURL,
    );

    return DioNetwork.get(
      uri.toString(),
      headers: _authHeaders(),
      queryParameters: query,
      options: fetchSearchOptions(),
      customInterceptor: withCaptchaCheck ? DioNetwork.captchaInterceptor : null,
    );
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    _cursor = parsedResponse['metadata']?['nextCursor']?.toString() ?? '';
    return (parsedResponse['items'] ?? []) as List;
  }

  // Rewrites an image-delivery URL's transform segment. Civitai URLs look like
  // https://image.civitai.com/{key}/{uuid}/original=true/{name}.{ext}
  String _transformUrl(String url, String transform, {String? forceExt}) {
    final List<String> parts = url.split('/');
    if (parts.length < 3) return url;
    parts[parts.length - 2] = transform;
    if (forceExt != null) {
      final String last = parts.last;
      final int dot = last.lastIndexOf('.');
      if (dot > 0) parts[parts.length - 1] = '${last.substring(0, dot)}.$forceExt';
    }
    return parts.join('/');
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final item = responseItem;
    final String url = item['url'] ?? '';
    if (url.isEmpty) return null;

    final bool isVideo = item['type'] == 'video';

    // Harvest tag ids + build the tags list (also powers the app's blacklist).
    final List<String> tagStrings = [];
    for (final t in (item['tags'] as List? ?? [])) {
      if (t is Map && t['name'] != null) {
        final String name = t['name'].toString().replaceAll(' ', '_').toLowerCase();
        tagStrings.add(name);
        final int? id = int.tryParse(t['id']?.toString() ?? '');
        if (id != null) {
          _tagIdCache[t['name'].toString().toLowerCase()] = id;
        }
      }
    }

    // Client-side exclusion (`-tag`) — the API can't do it server-side.
    if (_activeExclusions.isNotEmpty) {
      for (final ex in _activeExclusions) {
        if (tagStrings.contains(ex.replaceAll(' ', '_'))) return null;
      }
    }

    final String username = item['username']?.toString() ?? '';
    if (username.isNotEmpty) {
      final String artistTag = 'artist:$username';
      tagStrings.insert(0, artistTag);
      addTagsWithType([artistTag], TagType.artist);
    }
    final String? baseModel = item['baseModel']?.toString();
    if (baseModel?.isNotEmpty == true) {
      final String bmTag = 'basemodel:${baseModel!.replaceAll(' ', '_')}';
      tagStrings.add(bmTag);
      addTagsWithType([bmTag], TagType.meta);
    }

    final stats = item['stats'] as Map? ?? {};
    final int reactions =
        (stats['likeCount'] as int? ?? 0) +
        (stats['heartCount'] as int? ?? 0) +
        (stats['laughCount'] as int? ?? 0) +
        (stats['cryCount'] as int? ?? 0);

    final String thumbUrl = isVideo
        ? _transformUrl(url, 'anim=false,transcode=true,width=450', forceExt: 'jpeg')
        : _transformUrl(url, 'width=450');
    final String sampleUrl = isVideo
        ? _transformUrl(url, 'anim=false,transcode=true,width=1080', forceExt: 'jpeg')
        : _transformUrl(url, 'width=1080');

    return BooruItem(
      fileURL: url,
      sampleURL: sampleUrl,
      thumbnailURL: thumbUrl,
      fileWidth: double.tryParse(item['width']?.toString() ?? ''),
      fileHeight: double.tryParse(item['height']?.toString() ?? ''),
      tagsList: tagStrings.map(Tag.new).toList(),
      postURL: makePostURL(item['id'].toString()),
      serverId: item['id'].toString(),
      score: reactions.toString(),
      rating: item['nsfwLevel']?.toString(),
      uploaderName: username,
      sources: [
        if (item['postId'] != null) '${booru.baseURL}/posts/${item['postId']}',
      ],
      postDate: item['createdAt']?.toString(),
      postDateFormat: 'iso',
    );
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/images/$id';
  }

  // ── tag suggestions ─────────────────────────────────────────────────────

  @override
  String makeTagURL(String input) {
    return '${booru.baseURL}/api/v1/tags?limit=15&query=${Uri.encodeQueryComponent(input.replaceAll('_', ' '))}';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final parsedResponse = response.data;
    return (parsedResponse is Map ? parsedResponse['items'] : null) as List? ?? [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final String name = responseItem['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    return TagSuggestion(
      tag: name.replaceAll(' ', '_'),
      type: TagType.none,
    );
  }

  // ── metatags shown in the query editor ──────────────────────────────────

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Newest', value: 'newest'),
          MetaTagValue(name: 'Oldest', value: 'oldest'),
          MetaTagValue(name: 'Most Reactions', value: 'reactions'),
          MetaTagValue(name: 'Most Comments', value: 'comments'),
          MetaTagValue(name: 'Most Collected', value: 'collected'),
          MetaTagValue(name: 'Random', value: 'random'),
        ],
      ),
      MetaTagWithValues(
        name: 'Period',
        keyName: 'period',
        isFree: true,
        values: [
          MetaTagValue(name: 'Today', value: 'day'),
          MetaTagValue(name: 'This week', value: 'week'),
          MetaTagValue(name: 'This month', value: 'month'),
          MetaTagValue(name: 'This year', value: 'year'),
          MetaTagValue(name: 'All time', value: 'all'),
        ],
      ),
      MetaTagWithValues(
        name: 'NSFW level',
        keyName: 'nsfw',
        isFree: true,
        values: [
          MetaTagValue(name: 'Safe only', value: 'none'),
          MetaTagValue(name: 'Soft', value: 'soft'),
          MetaTagValue(name: 'Mature', value: 'mature'),
          MetaTagValue(name: 'X', value: 'x'),
          MetaTagValue(name: 'XXX', value: 'xxx'),
          MetaTagValue(name: 'Everything', value: 'all'),
        ],
      ),
      MetaTagWithValues(
        name: 'Media type',
        keyName: 'type',
        isFree: true,
        values: [
          MetaTagValue(name: 'Images', value: 'image'),
          MetaTagValue(name: 'Videos', value: 'video'),
        ],
      ),
      MetaTagWithValues(
        name: 'Base model',
        keyName: 'basemodel',
        isFree: true,
        values: [
          MetaTagValue(name: 'SDXL 1.0', value: 'SDXL_1.0'),
          MetaTagValue(name: 'Pony', value: 'Pony'),
          MetaTagValue(name: 'Illustrious', value: 'Illustrious'),
          MetaTagValue(name: 'Flux.1 D', value: 'Flux.1_D'),
          MetaTagValue(name: 'SD 1.5', value: 'SD_1.5'),
          MetaTagValue(name: 'NoobAI', value: 'NoobAI'),
        ],
      ),
      if (_hasApiKey)
        MetaTagWithValues(
          name: 'Artist',
          keyName: 'artist',
          isFree: true,
          values: [
            MetaTagValue(name: 'My uploads', value: 'me'),
          ],
        )
      else
        StringMetaTag(name: 'Artist', keyName: 'artist', isFree: true),
      StringMetaTag(name: 'Model id', keyName: 'model', isFree: true),
      StringMetaTag(name: 'Post id', keyName: 'post', isFree: true),
    ];
  }
}
