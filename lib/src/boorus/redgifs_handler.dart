import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/creator_info.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// RedGifs (redgifs.com) handler.
///
/// API notes (verified against the live v2 API):
/// - Auth: GET /v2/auth/temporary returns a ~24h guest token bound to the
///   requesting IP + User-Agent. All API calls need `Authorization: Bearer`.
/// - Search: GET /v2/gifs/search?search_text=a,b&order=trending|top|latest
///   &count=N&page=N → {gifs: [...], total, pages}.
///   Multiple tags are comma-separated and AND together.
/// - Suggest: GET /v2/search/suggest?query=x → [{type,text,gifs}].
/// - Media urls (media.redgifs.com) are plain public GETs — no auth headers.
///
/// Local tag convention: tags use underscores (jasmine_grey); they're
/// converted to RedGifs' space form when building the query.
class RedGifsHandler extends BooruHandler {
  RedGifsHandler(super.booru, super.limit);

  static const String _apiBase = 'https://api.redgifs.com';

  // Guest token shared across instances; refetched when missing or expired.
  static String? _token;
  static DateTime? _tokenExpiry;

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  // RedGifs is exclusively animated content — a "videos only" filter stop
  // would be a no-op, so expose none and let the UI hide the button.
  @override
  List<String> get animatedPreviewFilters => const [];

  // Comma-joined tags AND together; there is no OR syntax.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Trending', value: 'trending'),
          MetaTagValue(name: 'Top', value: 'top'),
          MetaTagValue(name: 'Latest', value: 'latest'),
        ],
      ),
    ];
  }

  bool get _tokenValid =>
      _token?.isNotEmpty == true && _tokenExpiry != null && _tokenExpiry!.isAfter(DateTime.now());

  Future<bool> _ensureToken({bool force = false}) async {
    if (!force && _tokenValid) return true;
    try {
      final response = await DioNetwork.get(
        '$_apiBase/v2/auth/temporary',
        headers: {'User-Agent': Tools.browserUserAgent},
      );
      final token = response.data is Map ? response.data['token']?.toString() : null;
      if (token?.isNotEmpty == true) {
        _token = token;
        // Tokens last 24h; refresh well before that.
        _tokenExpiry = DateTime.now().add(const Duration(hours: 20));
        return true;
      }
    } catch (e, s) {
      Logger.Inst().log(
        'failed to get redgifs token: $e',
        className,
        '_ensureToken',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
    }
    return false;
  }

  @override
  Future<bool> searchSetup() async {
    return _ensureToken();
  }

  // The active bearer: a signed-in user token (persisted in booru.apiKey) when
  // present and unexpired, otherwise the anonymous guest token. RedGifs binds
  // the token to the request IP + User-Agent, so the login WebView captures the
  // token the site sends and it's replayed here with the same User-Agent.
  String? get _activeToken {
    final String? userToken = _validUserToken;
    if (userToken != null) return userToken;
    return _token;
  }

  String? get _validUserToken {
    final String? t = booru.apiKey;
    if (t == null || t.isEmpty) return null;
    final DateTime? exp = decodeJwtExpiry(t);
    // Keep a small safety margin; expired/undecodable tokens fall back to guest.
    if (exp == null || exp.isBefore(DateTime.now().add(const Duration(minutes: 2)))) {
      return null;
    }
    return t;
  }

  @override
  bool get hasSignInSupport => true;

  @override
  Future<bool> isSignedIn() async => _validUserToken != null;

  @override
  Future<dynamic> signOut({bool fromError = false}) async {
    // Drop the stored user token; browsing continues on a guest token.
    booru.apiKey = '';
  }

  /// Decodes the `exp` (seconds since epoch) claim from a JWT, or null if the
  /// string isn't a decodable JWT.
  static DateTime? decodeJwtExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final Map<String, dynamic> claims = jsonDecode(utf8.decode(base64.decode(payload)));
      final int? exp = int.tryParse(claims['exp']?.toString() ?? '');
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, String> getHeaders() {
    final String? token = _activeToken;
    return {
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token',
    };
  }

  // Empty search means "show me stuff" — use their catch-all tag so the
  // normal search/pagination path still applies.
  @override
  String validateTags(String tags) {
    if (tags.trim().isEmpty) {
      return 'nsfw sort:trending';
    }
    return tags;
  }

  ({String query, String order}) _splitQueryAndOrder(String input) {
    final List<String> terms = input.split(' ').where((t) => t.isNotEmpty).toList();
    String order = 'trending';
    final List<String> tags = [];
    for (final term in terms) {
      final lower = term.toLowerCase();
      if (lower.startsWith('sort:') || lower.startsWith('order:')) {
        final value = lower.split(':').last;
        if (['trending', 'top', 'latest'].contains(value)) {
          order = value;
        }
      } else {
        // local underscore convention -> RedGifs space form
        tags.add(term.replaceAll('_', ' '));
      }
    }
    return (query: tags.isEmpty ? 'nsfw' : tags.join(','), order: order);
  }

  @override
  String makeURL(String tags) {
    final parts = _splitQueryAndOrder(tags);
    _queryTagsLower = parts.query
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != 'nsfw')
        .toList();

    // A `niche:id` term routes to a curated RedGifs niche feed, e.g.
    // `niche:just-boobs`. Browse the catalogue at redgifs.com/niches.
    final String? niche = _prefixValue(tags, 'niche');
    if (niche != null) {
      return Uri.parse('$_apiBase/v2/niches/$niche/gifs').replace(
        queryParameters: {
          'order': _nicheOrder(parts.order),
          'count': limit.toString(),
          'page': pageNum.toString(),
        },
      ).toString();
    }

    // A `creator:name` term routes to the per-user feed endpoint (that's how
    // "more from this artist" fetches a creator's gifs — the plain tag search
    // doesn't match usernames).
    final String? creator = _creatorFromInput(tags);
    if (creator != null) {
      return Uri.parse('$_apiBase/v2/users/$creator/search').replace(
        queryParameters: {
          'order': _userOrder(parts.order),
          'count': limit.toString(),
          'page': pageNum.toString(),
        },
      ).toString();
    }

    // RedGifs renamed the search param: `search_text` is now ignored (returns
    // the global feed for anything), the query goes in `tags` (comma = AND).
    return Uri.parse('$_apiBase/v2/gifs/search').replace(
      queryParameters: {
        'tags': parts.query,
        'order': parts.order,
        'count': limit.toString(),
        'page': pageNum.toString(),
      },
    ).toString();
  }

  // The per-user feed endpoint accepts recent/best/latest/top/oldest/new but
  // NOT `trending` (the search default) — passing trending there silently
  // returns zero gifs, which looked like "this creator has no content" even
  // for creators with thousands of gifs. Map the sort chip to a valid value.
  String _userOrder(String order) {
    switch (order) {
      case 'top':
        return 'top';
      case 'latest':
        return 'latest';
      default: // 'trending' (chip default) is invalid here
        return 'best';
    }
  }

  // The niche feed accepts trending/oldest/latest/best/hot — NOT `top`.
  String _nicheOrder(String order) {
    switch (order) {
      case 'top':
        return 'best';
      case 'latest':
        return 'latest';
      default:
        return 'trending';
    }
  }

  String? _creatorFromInput(String input) {
    return _prefixValue(input, 'creator') ?? _prefixValue(input, 'artist');
  }

  String? _prefixValue(String input, String prefix) {
    for (final term in input.split(' ')) {
      if (term.toLowerCase().startsWith('$prefix:')) {
        final value = term.substring(term.indexOf(':') + 1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      return await DioNetwork.get(
        uri.toString(),
        headers: getHeaders(),
        queryParameters: queryParams,
      );
    } on DioException catch (e) {
      // Token can die early (IP change on mobile networks) — re-auth once.
      if (e.response?.statusCode == HttpStatus.unauthorized) {
        // A user token is IP/agent-bound; if it's the one being rejected, drop
        // it and continue on a fresh guest token rather than looping on 401s.
        if (_validUserToken != null) {
          booru.apiKey = '';
        }
        final bool ok = await _ensureToken(force: true);
        if (ok) {
          return DioNetwork.get(
            uri.toString(),
            headers: getHeaders(),
            queryParameters: queryParams,
          );
        }
      }
      rethrow;
    }
  }

  // The tags of the active query (space form, lowercased), captured in makeURL
  // so the discovery strip can exclude them from "similar tags".
  List<String> _queryTagsLower = [];

  @override
  List parseListFromResponse(dynamic response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) return [];
    totalCount.value = int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    final List gifs = (data['gifs'] as List?) ?? [];

    // Populate the discovery strip from the first page only (it reflects the
    // query, not deeper pages).
    if (pageNum <= 1) {
      _buildDiscoveryFromGifs(gifs, data['users']);
    }
    return gifs;
  }

  /// Distinct uploaders in the results -> creator strip; the most common tags
  /// across the results (minus the searched ones) -> similar tags.
  void _buildDiscoveryFromGifs(List gifs, dynamic usersRaw) {
    // username -> avatar, from the response's `users` block when present.
    final Map<String, String> avatars = {};
    if (usersRaw is List) {
      for (final u in usersRaw) {
        if (u is! Map) continue;
        final String name = (u['username'] ?? u['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final String? img = (u['profileImageUrl'] ?? u['thumbnailUrl'])?.toString();
        if (img != null && img.isNotEmpty) avatars[name.toLowerCase()] = img;
      }
    }

    final List<CreatorInfo> creators = [];
    final Set<String> seenCreators = {};
    final Map<String, int> tagCounts = {};
    for (final g in gifs) {
      if (g is! Map) continue;
      final String user = (g['userName'] ?? '').toString();
      if (user.isNotEmpty && seenCreators.add(user.toLowerCase()) && creators.length < 20) {
        creators.add(
          CreatorInfo(
            searchQuery: 'creator:${user.toLowerCase()}',
            displayName: user,
            avatarUrl: avatars[user.toLowerCase()],
          ),
        );
      }
      for (final t in (g['tags'] as List?) ?? []) {
        final String tag = t.toString().trim();
        if (tag.isEmpty) continue;
        if (_queryTagsLower.contains(tag.toLowerCase())) continue;
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    // Only show the creators row when there's real variety (a single-creator
    // feed would just repeat the one creator).
    relatedCreators = creators.length >= 2 ? creators : [];

    final List<MapEntry<String, int>> sorted = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    relatedTags = sorted.take(12).map((e) => e.key.replaceAll(' ', '_')).toList();
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map current = responseItem;
    final Map urls = (current['urls'] as Map?) ?? {};

    final String? hd = urls['hd']?.toString();
    final String? sd = urls['sd']?.toString();
    final String? fileURL = hd ?? sd;
    if (fileURL == null || fileURL.isEmpty) return null;

    final String thumb = urls['thumbnail']?.toString() ?? urls['poster']?.toString() ?? fileURL;
    final String id = current['id']?.toString() ?? '';

    final List<Tag> tags = ((current['tags'] as List?) ?? [])
        .map((t) => Tag(t.toString().replaceAll(' ', '_').toLowerCase()))
        .toList();
    final String? userName = current['userName']?.toString();
    if (userName != null && userName.isNotEmpty) {
      // Treat the creator as an artist so it lands in the info drawer's
      // "more from this artist" section and gets artist colouring. The colour
      // is looked up from the shared TagHandler store (not the Tag object),
      // so the type has to be registered there too.
      final String creatorTag = 'creator:${userName.toLowerCase()}';
      tags.add(Tag(creatorTag, tagType: TagType.artist));
      addTagsWithType([creatorTag], TagType.artist);
    }
    // Niches this gif belongs to, as tappable `niche:<id>` tags — typed as
    // meta so they get their own colour and group in the tag list.
    final List nichesRaw = (current['niches'] as List?) ?? [];
    if (nichesRaw.isNotEmpty) {
      final List<String> nicheTags = nichesRaw
          .map((n) => n.toString().trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .map((n) => 'niche:$n')
          .toList();
      tags.addAll(nicheTags.map((n) => Tag(n, tagType: TagType.meta)));
      addTagsWithType(nicheTags, TagType.meta);
    }
    if (current['hasAudio'] == true) {
      tags.add(Tag('sound'));
    }

    final int? createDate = int.tryParse(current['createDate']?.toString() ?? '');

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sd ?? fileURL,
      thumbnailURL: thumb,
      tagsList: tags,
      postURL: makePostURL(id),
      serverId: id,
      score: current['likes']?.toString(),
      fileWidth: double.tryParse(current['width']?.toString() ?? ''),
      fileHeight: double.tryParse(current['height']?.toString() ?? ''),
      sources: [makePostURL(id)],
      postDate: createDate?.toString(),
      postDateFormat: createDate != null ? 'unix' : null,
    );
  }

  @override
  String makePostURL(String id) {
    return 'https://www.redgifs.com/watch/${id.toLowerCase()}';
  }

  @override
  String makeTagURL(String input) {
    return Uri.parse('$_apiBase/v2/search/suggest')
        .replace(queryParameters: {'query': input.replaceAll('_', ' ')}).toString();
  }

  // Full niche catalogue (id/name/gifs), fetched once per app run and shared
  // across instances. ~1.8k entries; used to autocomplete `niche:` locally so
  // the user never has to go hunting on the website.
  static List<Map<String, dynamic>>? _nichesCache;
  static Future<List<Map<String, dynamic>>>? _nichesFuture;

  Future<List<Map<String, dynamic>>> _ensureNiches() {
    if (_nichesCache != null) return Future.value(_nichesCache);
    return _nichesFuture ??= _fetchAllNiches().whenComplete(() => _nichesFuture = null);
  }

  Future<List<Map<String, dynamic>>> _fetchAllNiches() async {
    await _ensureToken();
    final List<Map<String, dynamic>> all = [];
    int page = 1;
    int pages = 1;
    // The API caps `count` server-side (returns `pages` accordingly), so read
    // the real page count from each response. Hard cap as a safety net.
    while (page <= pages && page <= 25) {
      final response = await DioNetwork.get(
        '$_apiBase/v2/niches',
        queryParameters: {'count': '1000', 'page': page.toString()},
        headers: getHeaders(),
      );
      final data = response.data;
      if (data is! Map) break;
      pages = int.tryParse(data['pages']?.toString() ?? '1') ?? 1;
      final List list = (data['niches'] as List?) ?? [];
      if (list.isEmpty) break;
      for (final n in list) {
        if (n is Map && n['id'] != null) {
          all.add({
            'id': n['id'].toString(),
            'name': n['name']?.toString() ?? '',
            'gifs': int.tryParse(n['gifs']?.toString() ?? '0') ?? 0,
          });
        }
      }
      page++;
    }
    all.sort((a, b) => (b['gifs'] as int).compareTo(a['gifs'] as int));
    if (all.isNotEmpty) _nichesCache = all;
    return all;
  }

  @override
  Future<Response<dynamic>> fetchTagSuggestions(Uri uri, String input, {CancelToken? cancelToken}) async {
    // Typing `niche` / `niche:<query>` autocompletes from the full local
    // niche catalogue instead of the tag-suggest endpoint (which doesn't
    // know about niches).
    final String lower = input.trim().toLowerCase();
    if (lower == 'niche' || lower == 'niches' || lower.startsWith('niche:')) {
      final String query = lower.startsWith('niche:') ? lower.substring('niche:'.length) : '';
      final niches = await _ensureNiches();
      final matches = niches
          .where(
            (n) =>
                query.isEmpty ||
                n['id'].toString().contains(query) ||
                n['name'].toString().toLowerCase().contains(query),
          )
          .take(30)
          .map((n) => {'type': 'niche', 'text': n['id'], 'gifs': n['gifs']})
          .toList();
      return Response(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: 200,
        data: matches,
      );
    }

    await _ensureToken();
    return DioNetwork.get(
      uri.toString(),
      headers: getHeaders(),
      cancelToken: cancelToken,
    );
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final data = response.data;
    if (data is List) return data;
    return [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final String text = responseItem['text']?.toString() ?? '';
    if (text.isEmpty) return null;
    if (responseItem['type'] == 'niche') {
      return TagSuggestion(
        tag: 'niche:$text',
        count: int.tryParse(responseItem['gifs']?.toString() ?? '0') ?? 0,
      );
    }
    if (responseItem['type'] != 'tag') return null;
    return TagSuggestion(
      tag: text.replaceAll(' ', '_').toLowerCase(),
      count: int.tryParse(responseItem['gifs']?.toString() ?? '0') ?? 0,
    );
  }
}
