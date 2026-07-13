import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/creator_info.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// xxxfollow.com (formerly Xfollow) handler.
///
/// Site = React SPA over a Laravel JSON API (same-origin `/api/v1`), verified
/// live. Video-first ("TikTok porn"). Unlike xxxtik, media is served as direct
/// MP4 files (downloadable), not HLS.
///
/// The one content endpoint powers everything:
///   GET /api/v1/post/search/tag?query=Q&genders=G&limit=L&page=N
///     - query present -> { tags:[…similar…], users:[…creators…], search:[…posts…] }
///     - query empty    -> a discovery payload { new, popular, popular_search,
///                          tags_trending, … } used as the default browse feed.
///
/// A session cookie must be established first (a plain GET of the site root),
/// and every API call needs `X-Requested-With: XMLHttpRequest`.
///
/// Note: as a guest the API returns a limited/teaser set of public posts per
/// tag (deeper pages come back empty); that's a site-side restriction, not a
/// pagination bug.
class XXXFollowHandler extends BooruHandler {
  XXXFollowHandler(super.booru, super.limit);

  static const String _root = 'https://www.xxxfollow.com';
  static const String _api = '$_root/api/v1';

  bool _sessionReady = false;

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String validateTags(String tags) => tags.trim();

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'All', value: 'all'),
          MetaTagValue(name: 'Female', value: 'female'),
          MetaTagValue(name: 'Male', value: 'male'),
        ],
      ),
    ];
  }

  ({String query, String genders}) _parse(String input) {
    String genders = '';
    final List<String> terms = [];
    for (final term in input.split(' ').where((t) => t.isNotEmpty)) {
      final lower = term.toLowerCase();
      if (lower.startsWith('sort:') || lower.startsWith('order:') || lower.startsWith('gender:')) {
        final v = lower.split(':').last;
        if (v == 'female' || v == 'f') {
          genders = 'f';
        } else if (v == 'male' || v == 'm') {
          genders = 'm';
        } else {
          genders = '';
        }
      } else {
        terms.add(term);
      }
    }
    // xxxfollow tags are single words joined by hyphens on the site; the query
    // matches against tag text, so join multiple words with spaces and let the
    // backend tokenise. Underscores (local convention) become spaces.
    return (query: terms.join(' ').replaceAll('_', ' '), genders: genders);
  }

  @override
  String makeURL(String tags) {
    final parts = _parse(tags);
    return Uri.parse('$_api/post/search/tag').replace(
      queryParameters: {
        'query': parts.query,
        'genders': parts.genders,
        'limit': limit.toString(),
        'page': pageNum.toString(),
      },
    ).toString();
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': Tools.browserUserAgent,
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '$_root/',
      'Origin': _root,
    };
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    try {
      // A plain GET of the site root hands back the Laravel session cookies the
      // API expects; DioNetwork persists them in its cookie jar.
      await DioNetwork.get(
        '$_root/',
        headers: {'User-Agent': Tools.browserUserAgent},
      );
      _sessionReady = true;
    } catch (_) {
      // Non-fatal — the API often still answers; try again next search.
    }
  }

  @override
  Future<bool> searchSetup() async {
    await _ensureSession();
    return true;
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

  @override
  List parseListFromResponse(dynamic response) {
    final data = response.data;
    if (data is! Map) return [];

    relatedTags = _extractTagNames(data['tags']);
    relatedCreators = _extractCreators(data['users']);

    // Query present -> `search` (paginated). Empty query -> the discovery
    // payload, which ignores `page`, so only serve it once and let subsequent
    // pages come back empty (locking the feed).
    final search = data['search'];
    if (search is List) {
      return search;
    }
    if (pageNum > 1) return [];

    final List<dynamic> merged = [];
    final Set<String> seen = {};
    for (final key in ['popular', 'new', 'popular_search']) {
      final bucket = data[key];
      if (bucket is List) {
        for (final entry in bucket) {
          final id = _postId(entry);
          if (id != null && seen.add(id)) merged.add(entry);
        }
      }
    }
    return merged;
  }

  List<String> _extractTagNames(dynamic tags) {
    if (tags is! List) return [];
    return tags
        .map((t) => (t is Map ? t['tag']?.toString() : null) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<CreatorInfo> _extractCreators(dynamic users) {
    if (users is! List) return [];
    final List<CreatorInfo> out = [];
    for (final u in users) {
      if (u is! Map) continue;
      final String username = u['username']?.toString() ?? '';
      if (username.isEmpty) continue;
      out.add(
        CreatorInfo(
          searchQuery: username,
          displayName: _nonEmpty(u['display_name']) ?? username,
          avatarUrl: _nonEmpty(u['public_avatar_url']) ?? _nonEmpty(u['fans_avatar_url']),
          coverUrl: _nonEmpty(u['public_cover_picture_url']) ?? _nonEmpty(u['fans_cover_picture_url']),
        ),
      );
    }
    return out;
  }

  String? _postId(dynamic entry) {
    if (entry is! Map) return null;
    final post = entry['post'];
    if (post is Map) return post['id']?.toString();
    return entry['id']?.toString();
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map post = responseItem['post'] is Map ? responseItem['post'] as Map : responseItem;

    final List mediaList = (post['media'] as List?) ?? [];
    if (mediaList.isEmpty) return null;
    // Representative media = the first in display order.
    final Map media = (mediaList.firstWhere(
      (m) => m is Map && (m['order'] == 0 || m['order'] == null),
      orElse: () => mediaList.first,
    )) as Map;

    final bool isVideo = (media['type']?.toString() ?? 'video') == 'video';

    final String? fileURL = isVideo
        ? (_nonEmpty(media['uhd_url']) ??
              _nonEmpty(media['fhd_url']) ??
              _nonEmpty(media['url']) ??
              _nonEmpty(media['sd_url']))
        : _nonEmpty(media['url']);
    if (fileURL == null) return null;

    final String? sampleURL = isVideo ? (_nonEmpty(media['sd_url']) ?? fileURL) : fileURL;
    final String? thumbURL =
        _nonEmpty(media['thumb_url']) ?? _nonEmpty(media['start_url']) ?? _nonEmpty(media['blur_url']);

    final double? w = double.tryParse(media['width']?.toString() ?? '');
    final double? h = double.tryParse(media['height']?.toString() ?? '');

    final int likes = int.tryParse(responseItem['like_count']?.toString() ?? '') ?? 0;
    final String id = post['id']?.toString() ?? '';

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL ?? fileURL,
      thumbnailURL: thumbURL ?? fileURL,
      fileExt: Tools.getFileExt(fileURL),
      tagsList: const <Tag>[],
      postURL: makePostURL(id),
      serverId: id.isEmpty ? null : id,
      score: likes > 0 ? likes.toString() : null,
      fileWidth: w,
      fileHeight: h,
      description: _nonEmpty(post['text']),
    );
  }

  String? _nonEmpty(dynamic value) {
    if (value == null) return null;
    final String s = value.toString();
    return (s.isEmpty || s == 'null') ? null : s;
  }

  @override
  String makePostURL(String id) => '$_root/post/$id';

  //
  // Autocomplete — the tag query itself returns matching/related `tags`.

  @override
  String makeTagURL(String input) {
    return Uri.parse('$_api/post/search/tag').replace(
      queryParameters: {
        'query': input.trim(),
        'genders': '',
        'limit': '1',
        'page': '1',
      },
    ).toString();
  }

  @override
  Future<Response<dynamic>> fetchTagSuggestions(Uri uri, String input, {CancelToken? cancelToken}) async {
    await _ensureSession();
    return DioNetwork.get(
      uri.toString(),
      headers: getHeaders(),
      cancelToken: cancelToken,
    );
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final data = response.data;
    if (data is! Map) return [];
    // Prefer the related `tags`; fall back to trending tags on an empty query.
    final tags = data['tags'];
    if (tags is List && tags.isNotEmpty) return tags;
    final trending = data['tags_trending'];
    return trending is List ? trending : [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final String tag = responseItem['tag']?.toString() ?? '';
    if (tag.isEmpty) return null;
    // `posts` may be a list (sample posts) or a count.
    int count = 0;
    final posts = responseItem['posts'];
    if (posts is List) {
      count = posts.length;
    } else {
      count = int.tryParse(posts?.toString() ?? '') ?? 0;
    }
    return TagSuggestion(tag: tag, count: count);
  }
}
