import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class WorldXyzHandler extends BooruHandler {
  WorldXyzHandler(super.booru, super.limit);

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  // ── Account auth (rule34.xyz "credentials" section) ────────────────────
  // userID = email/username, apiKey = password. Sign-in yields a JWT which is
  // sent as a Bearer header; the account id unlocks the liked / bookmarked
  // feeds and the user's playlists. Cached statically so tab switches don't
  // re-login; failed logins back off for 5 minutes.
  static final Map<String, String> _jwtCache = {};
  static final Map<String, String> _userIdCache = {};
  static final Map<String, int> _authFailedAt = {};
  static final Map<String, String> _lastAuthError = {};

  bool get _hasCredentials => booru.userID?.isNotEmpty == true && booru.apiKey?.isNotEmpty == true;

  // apiKey is part of the key so editing the password resets the backoff and
  // cached state immediately.
  String get _authKey => '${booru.name}|${booru.userID}|${booru.apiKey.hashCode}';

  String? get _jwt => _jwtCache[_authKey];

  String? get _accountId => _userIdCache[_authKey];

  // Playlists of the signed-in user (name -> id), fetched during searchSetup
  // and surfaced through the `playlist:` metatag in the query editor.
  static final Map<String, List<MetaTagValue>> _playlistCache = {};

  List<MetaTagValue> get _playlists => _playlistCache[_authKey] ?? [];

  Future<void> _ensureAuth() async {
    if (!_hasCredentials || (_jwt != null && _accountId != null)) return;

    final int? failedAt = _authFailedAt[_authKey];
    if (failedAt != null && DateTime.now().millisecondsSinceEpoch - failedAt < 5 * 60 * 1000) {
      return;
    }

    try {
      final res = await DioNetwork.post(
        '${booru.baseURL}/api/v2/auth/signin',
        headers: getHeaders(),
        data: {
          'email': booru.userID,
          'password': booru.apiKey,
        },
      );

      final dynamic data = res.data;
      String? token;
      String? userId;
      if (data is String && data.isNotEmpty) {
        token = data;
      } else if (data is Map) {
        token = (data['token'] ?? data['jwt'] ?? data['accessToken'] ?? data['access_token'])?.toString();
        userId = (data['user'] is Map ? data['user']['id'] : data['userId'])?.toString();
      }
      if (token == null || token.isEmpty) {
        throw Exception('no token in signin response');
      }

      if (userId == null || userId.isEmpty) {
        final me = await DioNetwork.post(
          '${booru.baseURL}/api/v2/account/me',
          headers: {
            ...getHeaders(),
            'Authorization': 'Bearer $token',
          },
          data: {},
        );
        if (me.data is Map) {
          userId = (me.data['id'] ?? me.data['user']?['id'])?.toString();
        }
      }
      if (userId == null || userId.isEmpty) {
        throw Exception('no user id after signin');
      }

      _jwtCache[_authKey] = token;
      _userIdCache[_authKey] = userId;
      _authFailedAt.remove(_authKey);
      _lastAuthError.remove(_authKey);
    } catch (e) {
      _authFailedAt[_authKey] = DateTime.now().millisecondsSinceEpoch;
      // Keep the server's own message ("Incorrect email or password", ...) so
      // the search error the user sees says WHY instead of silently failing.
      String message = e.toString();
      if (e is DioException && e.response?.data is Map) {
        message = (e.response!.data['message'] ?? message).toString();
      }
      _lastAuthError[_authKey] = message;
      Logger.Inst().log(
        'rule34.xyz signin failed: $e',
        className,
        '_ensureAuth',
        LogTypes.booruHandlerInfo,
      );
    }
  }

  Future<void> _fetchPlaylists() async {
    if (_jwt == null || _accountId == null || _playlistCache[_authKey] != null) return;
    try {
      final res = await DioNetwork.post(
        '${booru.baseURL}/api/v2/playlist/search/user/$_accountId',
        headers: {
          ...getHeaders(),
          'Authorization': 'Bearer $_jwt',
        },
        data: {'Skip': 0, 'take': 100},
      );
      final items = (res.data is Map ? res.data['items'] : null) as List? ?? [];
      _playlistCache[_authKey] = [
        for (final p in items)
          if (p is Map && p['id'] != null)
            MetaTagValue(
              name: (p['name'] ?? p['title'] ?? 'playlist ${p['id']}').toString(),
              value: p['id'].toString(),
            ),
      ];
    } catch (e) {
      Logger.Inst().log(
        'rule34.xyz playlists fetch failed: $e',
        className,
        '_fetchPlaylists',
        LogTypes.booruHandlerInfo,
      );
    }
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    try {
      cursor = parsedResponse['cursor'] ?? '';
      // quick way to tell difference between old(?) (i.e.animazone34.com) and new (i.e. rule34.world) engine version
      isXyz = parsedResponse.keys.contains('pagination');
      totalCount.value = totalCount.value > 0
          ? totalCount.value
          : int.tryParse(parsedResponse['totalCount']?.toString() ?? '0') ?? 0;
    } catch (_) {}
    return (parsedResponse['items'] ?? []) as List;
  }

  Map<String, dynamic> appConfig = {};

  String get storageBase {
    try {
      final storages = appConfig['storage']?['storages'] as List;
      return storages.firstWhereOrNull((s) => s['type'] == 1)?['parameters']?['PullZoneName'] ?? 'rule34storage';
    } catch (_) {
      return 'rule34storage';
    }
  }

  @override
  Future<bool> searchSetup() async {
    bool success = await super.searchSetup();
    if (!success) {
      return success;
    }

    try {
      final cookies = await getCookies();
      final res = await DioNetwork.get(
        '${booru.baseURL}/app.json',
        headers: {
          ...getHeaders(),
          if (cookies?.isNotEmpty == true) 'Cookie': cookies,
        },
      );

      appConfig = res.data;

      success = true;
    } catch (e) {
      Logger.Inst().log(
        e,
        className,
        'searchSetup',
        LogTypes.booruHandlerInfo,
      );
    }

    // Sign in (when credentials are set) and load the account's playlists so
    // the `feed:`/`playlist:` metatags work. Failures don't break search.
    await _ensureAuth();
    await _fetchPlaylists();

    return success;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem;

    //type 0: image, 1: video
    final bool isVideo = current['type'] == 1;

    const Map<int, String> thumbnailTypes = {
      11: 'PicThumbnail',
      12: 'PicThumbnailEx',
      // 31: 'PicThumbnailAvif',
      // 32: 'PicThumbnailExAvif',
    };

    const Map<int, String> sampleTypes = {
      13: 'PicPreview',
      14: 'PicSmall',
    };

    const Map<int, String> fileTypes = {
      1: 'Raw',
      10: 'Pic',
      14: 'PicSmall',
      // avif images seem to be broken after some date (example: 813195)
      // 30: 'PicAvif',
      // 33: 'PicPreviewAvif',
      // 34: 'PicSmallAvif',
      100: 'Mov',
      111: 'Mov360',
      112: 'Mov480',
      113: 'Mov720',
      114: 'Mov1080',
      200: 'MovHevc',
      211: 'Mov360Hevc',
      212: 'Mov480Hevc',
      213: 'Mov720Hevc',
      214: 'Mov1080Hevc',
      300: 'MovAv1',
      311: 'Mov360Av1',
      312: 'Mov480Av1',
      313: 'Mov720Av1',
      314: 'Mov1080Av1',
    };

    // old and new engine versions have different file extensions
    final Map<String, String> fileExts = isXyz
        ? {
            'Raw': 'raw',
            'Pic': 'pic.jpg',
            'PicThumbnail': 'pic256.jpg',
            'PicThumbnailEx': 'pic256ex.jpg',
            'PicPreview': 'picpreview.jpg',
            'PicSmall': 'picsmall.jpg',
            'PicAvif': 'picavif.avif',
            'PicThumbnailAvif': 'pic256avif.avif',
            'PicThumbnailExAvif': 'pic256exavif.avif',
            'PicPreviewAvif': 'picpreviewavif.avif',
            'PicSmallAvif': 'small.avif',
            'Mov': 'mov.mp4',
            'MovThumbnail': 'mov256.mp4',
            'MovThumbnailEx': 'mov256ex.mp4',
            'Mov360': '360.mp4',
            'Mov480': 'mov480.mp4',
            'Mov720': 'mov720.mp4',
            'Mov1080': '1080.mp4',
            'MovHevc': 'hevc.mp4',
            'MovThumbnailHevc': 'thumbnail.hevc.mp4',
            'MovThumbnailExHevc': 'thumbnailEx.hevc.mp4',
            'Mov360Hevc': '360.hevc.mp4',
            'Mov480Hevc': '480.hevc.mp4',
            'Mov720Hevc': '720.hevc.mp4',
            'Mov1080Hevc': '1080.hevc.mp4',
            'MovAv1': 'av1.mp4',
            'MovThumbnailAv1': 'thumbnail.av1.mp4',
            'MovThumbnailExAv1': 'thumbnailEx.av1.mp4',
            'Mov360Av1': '360.av1.mp4',
            'Mov480Av1': '480.av1.mp4',
            'Mov720Av1': '720.av1.mp4',
            'Mov1080Av1': '1080.av1.mp4',
          }
        : {
            'Raw': 'raw',
            'Pic': 'jpg',
            'PicThumbnail': 'thumbnail.jpg',
            'PicThumbnailEx': 'thumbnailex.jpg',
            'PicPreview': 'preview.jpg',
            'PicSmall': 'small.jpg',
            'PicAvif': 'avif',
            'PicThumbnailAvif': 'thumbnail.avif',
            'PicThumbnailExAvif': 'thumbnailex.avif',
            'PicPreviewAvif': 'preview.avif',
            'PicSmallAvif': 'small.avif',
            'Mov': 'mp4',
            'MovThumbnail': 'thumbnail.mp4',
            'MovThumbnailEx': 'thumbnailex.mp4',
            'Mov360': '360.mp4',
            'Mov480': '480.mp4',
            'Mov720': '720.mp4',
            'Mov1080': '1080.mp4',
            'MovHevc': 'hevc.mp4',
            'MovThumbnailHevc': 'thumbnail.hevc.mp4',
            'MovThumbnailExHevc': 'thumbnailEx.hevc.mp4',
            'Mov360Hevc': '360.hevc.mp4',
            'Mov480Hevc': '480.hevc.mp4',
            'Mov720Hevc': '720.hevc.mp4',
            'Mov1080Hevc': '1080.hevc.mp4',
            'MovAv1': 'av1.mp4',
            'MovThumbnailAv1': 'thumbnail.av1.mp4',
            'MovThumbnailExAv1': 'thumbnailEx.av1.mp4',
            'Mov360Av1': '360.av1.mp4',
            'Mov480Av1': '480.av1.mp4',
            'Mov720Av1': '720.av1.mp4',
            'Mov1080Av1': '1080.av1.mp4',
          };

    final Map<String, dynamic> files = current['files'] ?? {};
    final List<MapEntry<int, dynamic>> availableFileTypes =
        files.entries.map((e) => MapEntry(int.tryParse(e.key) ?? 0, e.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    final String id = current['id'].toString();
    // remove last 3 numbers of the id
    final String fileGroupId = id.substring(0, id.length - 3);

    String base = booru.baseURL!;

    MapEntry<int, dynamic>? thumbnailType = availableFileTypes.lastWhereOrNull(
      (t) => thumbnailTypes.containsKey(t.key),
    );
    thumbnailType ??= availableFileTypes.lastWhereOrNull((t) => t.key == 11);
    if (thumbnailType?.value is List) {
      base = thumbnailType!.value.first == 0 ? booru.baseURL! : 'https://$storageBase.b-cdn.net';
    }
    final String thumbnailFileExt =
        fileExts[thumbnailTypes[thumbnailType?.key]] ?? (isXyz ? 'pic256.jpg' : 'thumbnail.jpg');
    final String thumbnailUrl = '$base/posts/$fileGroupId/$id/$id.$thumbnailFileExt';

    MapEntry<int, dynamic>? sampleType = availableFileTypes.lastWhereOrNull((t) => sampleTypes.containsKey(t.key));
    sampleType ??= availableFileTypes.lastWhereOrNull((t) => t.key == 13);
    if (sampleType?.value is List) {
      base = sampleType!.value.first == 0 ? booru.baseURL! : 'https://$storageBase.b-cdn.net';
    }
    final String sampleFileExt = fileExts[sampleTypes[sampleType?.key]] ?? (isXyz ? 'picpreview.jpg' : 'preview.jpg');
    final String sampleUrl = isXyz ? '$base/posts/$fileGroupId/$id/$id.$sampleFileExt' : thumbnailUrl;

    MapEntry<int, dynamic>? fileType = availableFileTypes.lastWhereOrNull((t) => fileTypes.containsKey(t.key));
    fileType ??= availableFileTypes.lastWhereOrNull((t) => t.key == 10);
    if (fileType?.value is List) {
      base = fileType!.value.first == 0 ? booru.baseURL! : 'https://$storageBase.b-cdn.net';
    }
    final String fileFileExt =
        fileExts[fileTypes[fileType?.key]] ?? (isVideo ? 'mov.mp4' : (isXyz ? 'pic.jpg' : 'jpg'));
    final String fileUrl = '$base/posts/$fileGroupId/$id/$id.$fileFileExt';

    final String dateString = current['created'].split('.')[0]; // split off microseconds // use posted or created?
    final BooruItem item = BooruItem(
      fileURL: fileUrl,
      sampleURL: sampleUrl,
      thumbnailURL: thumbnailUrl,
      fileHeight: double.tryParse(current['height']?.toString() ?? ''),
      fileWidth: double.tryParse(current['width']?.toString() ?? ''),
      tagsList: const [],
      postURL: makePostURL(id),
      serverId: id,
      // use views as score, people don't rate stuff here often
      score: current['likes'].toString(),
      sources: List<String>.from(current['data']?['sources'] ?? []),
      postDate: dateString, // 2021-06-18T06:09:02.63366Z // microseconds?
      postDateFormat: 'iso',
    );

    return item;
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/post/$id';
  }

  @override
  String validateTags(String tags) {
    return tags;
  }

  String cursor = '';
  bool isXyz = true;

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    await _ensureAuth();

    final String cookies = await getCookies() ?? '';
    final Map<String, String> headers = {
      ...getHeaders(),
      if (cookies.isNotEmpty) 'Cookie': cookies,
      if (_jwt != null) 'Authorization': 'Bearer $_jwt',
    };

    Logger.Inst().log(
      'fetching: $uri with headers: $headers',
      className,
      'Search',
      LogTypes.booruHandlerSearchURL,
    );

    // ignores custom limit if search is empty, otherwise it works
    final int skip = (pageNum * limit) < 0 ? 0 : (pageNum * limit);

    if (skip == 0) {
      cursor = '';
    }

    // Pull the `sort:` metatag out of the query and map it to the API's
    // numeric sortBy (verified against rule34.xyz: 0 = newest, 1 = most
    // liked, 2 = most viewed, 3 = random; oldest = sortBy 0 + sortOrder 0).
    // The sort term itself is not a real tag, so it's excluded from
    // include/excludeTags below.
    final int sortBy = _sortByFromTags(input);

    // Account feeds: `feed:likes` / `feed:bookmarks` (aliases likes:me /
    // bookmarks:me) search within the signed-in account's liked/bookmarked
    // posts; `playlist:<id>` searches inside a playlist. Remaining tags still
    // filter within the feed.
    final _FeedRoute route = _feedRouteFromTags(input);

    bool isSpecialTerm(String f) {
      final String lower = f.toLowerCase().replaceAll(RegExp('^-'), '');
      return lower.startsWith('sort:') ||
          lower.startsWith('feed:') ||
          lower.startsWith('playlist:') ||
          lower == 'likes:me' ||
          lower == 'bookmarks:me';
    }

    final List<String> includeTags = input
        .split(' ')
        .where((f) => !f.startsWith('-') && !isSpecialTerm(f))
        .map((tag) => tag.replaceAll(RegExp('_'), ' '))
        .where((f) => f.isNotEmpty)
        .toList();
    final List<String> excludeTags = input
        .split(' ')
        .where((f) => f.startsWith('-') && !isSpecialTerm(f))
        .map(
          (tag) => tag.replaceAll(RegExp('_'), ' ').replaceAll(RegExp('^-'), ''),
        )
        .where((f) => f.isNotEmpty)
        .toList();

    String url = uri.toString();
    if (route.playlistId != null) {
      url = '${booru.baseURL}/api/v2/post/search/playlist/${route.playlistId}';
    } else if (route.liked || route.bookmarked) {
      // Never silently fall back to the public feed when the user explicitly
      // asked for their own likes/bookmarks — fail with the reason instead.
      if (_accountId == null) {
        final String reason = _lastAuthError[_authKey] ?? (_hasCredentials ? 'sign-in failed' : 'no credentials set');
        throw Exception(
          'rule34.xyz account sign-in required for feed:${route.liked ? 'likes' : 'bookmarks'} — $reason. '
          "Check the login/password in this booru's config.",
        );
      }
      url = route.liked
          ? '${booru.baseURL}/api/v2/post/search/liked/$_accountId'
          : '${booru.baseURL}/api/v2/post/search/bookmarked/$_accountId';
    }

    return DioNetwork.post(
      url,
      headers: headers,
      queryParameters: queryParams,
      options: fetchSearchOptions(),
      data: {
        'CountTotal': skip == 0,
        'Skip': skip,
        if (cursor.isNotEmpty) 'cursor': cursor,
        'includeTags': includeTags,
        if (excludeTags.isNotEmpty) 'excludeTags': excludeTags,
        if (sortBy == -1) ...{'sortBy': 0, 'sortOrder': 0} else 'sortBy': sortBy,
        'take': limit,
      },
      customInterceptor: withCaptchaCheck ? DioNetwork.captchaInterceptor : null,
    );
  }

  // Maps the `sort:` metatag value to the World/XYZ API's numeric sortBy.
  // Accepts a few aliases per option. Defaults to 0 (newest).
  int _sortByFromTags(String input) {
    for (final term in input.split(' ')) {
      final String lower = term.toLowerCase();
      if (!lower.startsWith('sort:')) continue;
      final String value = lower.substring('sort:'.length);
      switch (value) {
        case 'likes':
        case 'liked':
        case 'mostliked':
        case 'score':
          return 1;
        case 'views':
        case 'viewed':
        case 'mostviewed':
          return 2;
        case 'random':
        case 'shuffle':
          return 3;
        case 'oldest':
        case 'old':
          return -1;
        case 'date':
        case 'newest':
        case 'new':
          return 0;
      }
    }
    return 0;
  }

  _FeedRoute _feedRouteFromTags(String input) {
    bool liked = false;
    bool bookmarked = false;
    String? playlistId;
    for (final term in input.split(' ')) {
      final String lower = term.toLowerCase();
      if (lower == 'feed:likes' || lower == 'feed:liked' || lower == 'likes:me') {
        liked = true;
      } else if (lower == 'feed:bookmarks' || lower == 'feed:bookmarked' || lower == 'bookmarks:me') {
        bookmarked = true;
      } else if (lower.startsWith('playlist:')) {
        final String value = lower.substring('playlist:'.length);
        if (value.isNotEmpty) playlistId = value;
      }
    }
    return _FeedRoute(liked: liked, bookmarked: bookmarked, playlistId: playlistId);
  }

  // Surfaces in the query editor: sort options (incl. Random/Oldest), the
  // account feeds, and — once signed in — the account's playlists by name.
  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Newest', value: 'date'),
          MetaTagValue(name: 'Oldest', value: 'oldest'),
          MetaTagValue(name: 'Most Liked', value: 'likes'),
          MetaTagValue(name: 'Most Viewed', value: 'views'),
          MetaTagValue(name: 'Random', value: 'random'),
        ],
      ),
      if (_hasCredentials)
        MetaTagWithValues(
          name: 'My feed',
          keyName: 'feed',
          isFree: true,
          values: [
            MetaTagValue(name: 'My likes', value: 'likes'),
            MetaTagValue(name: 'My bookmarks', value: 'bookmarks'),
          ],
        ),
      if (_playlists.isNotEmpty)
        MetaTagWithValues(
          name: 'Playlist',
          keyName: 'playlist',
          isFree: true,
          values: _playlists,
        ),
    ];
  }

  @override
  String makeURL(String tags) {
    return '${booru.baseURL}/api/v2/post/search/root';
  }

  @override
  String makeTagURL(String input) {
    return '${booru.baseURL}/api/v2/tag/search/${input.replaceAll(' ', '_')}';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final parsedResponse = response.data;
    if (parsedResponse is List) {
      return parsedResponse;
    } else {
      return [];
    }
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final cookies = await getCookies();

      final response = await DioNetwork.get(
        '${booru.baseURL}/api/v2/post/${item.serverId}',
        headers: {
          ...getHeaders(),
          if (cookies?.isNotEmpty == true) 'Cookie': cookies,
          if (_jwt != null) 'Authorization': 'Bearer $_jwt',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
        cancelToken: cancelToken,
        customInterceptor: withCapcthaCheck ? DioNetwork.captchaInterceptor : null,
      );

      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      } else {
        final Map<String, dynamic> current = response.data;
        final List<dynamic> tags = current['tags'] ?? [];
        final newTags = [...item.tagsList];
        for (final rawTag in tags) {
          final String tag = rawTag['value']!.replaceAll(' ', '_');
          final int count = int.tryParse(rawTag['count']?.toString() ?? '0') ?? 0;
          if (item.tagsList.any((t) => t.fullString == tag)) continue;
          newTags.add(Tag(tag, count: count));
          if (rawTag['type'] != null) {
            addTagsWithType(
              [tag],
              tagTypeMap[rawTag['type']?.toString()] ?? TagType.none,
            );
          }
        }
        item.tagsList = newTags;
        item.sources = List<String>.from(current['data']?['sources'] ?? []);

        item.isUpdated = true;
        return (item: item, failed: false, error: null);
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        className,
        'loadItem',
        LogTypes.exception,
        s: s,
      );
      return (item: null, failed: true, error: e.toString());
    }
  }

  @override
  Map<String, TagType> get tagTypeMap => {
    '1': TagType.none,
    '2': TagType.copyright,
    '4': TagType.character,
    '8': TagType.artist,
  };

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    return TagSuggestion(
      tag: responseItem['value']?.replaceAll(RegExp(' '), '_') ?? '',
      count: responseItem['count'] ?? 0,
      type: tagTypeMap[responseItem['type']?.toString()] ?? TagType.none,
    );
  }
}

class _FeedRoute {
  const _FeedRoute({required this.liked, required this.bookmarked, this.playlistId});

  final bool liked;
  final bool bookmarked;
  final String? playlistId;
}

const String a = '''
// file types =
{
  1: 'Raw',
  10: 'Pic',
  11: 'PicThumbnail',
  12: 'PicThumbnailEx',
  13: 'PicPreview',
  14: 'PicSmall',
  30: 'PicAvif',
  31: 'PicThumbnailAvif',
  32: 'PicThumbnailExAvif',
  33: 'PicPreviewAvif',
  34: 'PicSmallAvif',
  100: 'Mov',
  101: 'MovThumbnail',
  102: 'MovThumbnailEx',
  111: 'Mov360',
  112: 'Mov480',
  113: 'Mov720',
  114: 'Mov1080',
  200: 'MovHevc',
  201: 'MovThumbnailHevc',
  202: 'MovThumbnailExHevc',
  211: 'Mov360Hevc',
  212: 'Mov480Hevc',
  213: 'Mov720Hevc',
  214: 'Mov1080Hevc',
  300: 'MovAv1',
  301: 'MovThumbnailAv1',
  302: 'MovThumbnailExAv1',
  311: 'Mov360Av1',
  312: 'Mov480Av1',
  313: 'Mov720Av1',
  314: 'Mov1080Av1',
}

// file exts
{
  'Raw': 'raw',
  'Pic': 'pic.jpg',
  'PicThumbnail': 'pic256.jpg',
  'PicThumbnailEx': 'pic256ex.jpg',
  'PicPreview': 'picpreview.jpg',
  'PicSmall': 'picsmall.jpg',
  'PicAvif': 'picavif.avif',
  'PicThumbnailAvif': 'pic256avif.avif',
  'PicThumbnailExAvif': 'pic256exavif.avif',
  'PicPreviewAvif': 'picpreviewavif.avif',
  'PicSmallAvif': 'small.avif',
  'Mov': 'mov.mp4',
  'MovThumbnail': 'mov256.mp4',
  'MovThumbnailEx': 'mov256ex.mp4',
  'Mov360': '360.mp4',
  'Mov480': 'mov480.mp4',
  'Mov720': 'mov720.mp4',
  'Mov1080': '1080.mp4',
  'MovHevc': 'hevc.mp4',
  'MovThumbnailHevc': 'thumbnail.hevc.mp4',
  'MovThumbnailExHevc': 'thumbnailEx.hevc.mp4',
  'Mov360Hevc': '360.hevc.mp4',
  'Mov480Hevc': '480.hevc.mp4',
  'Mov720Hevc': '720.hevc.mp4',
  'Mov1080Hevc': '1080.hevc.mp4',
  'MovAv1': 'av1.mp4',
  'MovThumbnailAv1': 'thumbnail.av1.mp4',
  'MovThumbnailExAv1': 'thumbnailEx.av1.mp4',
  'Mov360Av1': '360.av1.mp4',
  'Mov480Av1': '480.av1.mp4',
  'Mov720Av1': '720.av1.mp4',
  'Mov1080Av1': '1080.av1.mp4',
}

/// file url format
/// https://rule34vault.com/posts/607/607199/607199.mp4
/// https://{booruUrl}/posts/{id with last 3 symbols removed}/{id}/{id}.{best available option from files object matching type in file types above}


''';
