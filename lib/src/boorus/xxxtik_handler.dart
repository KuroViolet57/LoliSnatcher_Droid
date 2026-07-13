import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// xxxtik.com handler.
///
/// xxxtik is a short-form ("porn TikTok") video site with a clean JSON API
/// (verified live against the production backend). It is video-only.
///
/// API host:  https://xxxtik-api-iw98m.ondigitalocean.app
/// Media CDN: https://p5rn.com/cdn/production/media/0312/
///
/// Feeds (all return a flat JSON array of posts):
///   GET /post/new?limit=20&cursor=LASTID            — recent
///   GET /post/top/{week|month|year|all}?limit&cursor — top for a period
///   GET /post/tag/NAME?limit&cursor                 — a tag's videos
///   GET /post/creator/USERNAME?limit&cursor         — a creator's videos
///   GET /search?query=Q  -> [name,count,type tag|profile]
///
/// Pagination is keyset: `cursor` is the numeric `id` of the last post seen
/// (0 for the first page). This handler maps the app's page-based flow onto
/// that cursor and resets it whenever the query changes.
///
/// Media per post:
///   uid post   -> video  {cdn}{uid}/master.m3u8   (HLS)
///                 thumb  {cdn}{uid}/thumbnail.webp
///                 sample {cdn}{uid}/preview.mp4    (3s teaser)
///   redgifs    -> redGifsVideoUrl / redGifsThumbnailUrl (direct mp4)
class XXXTikHandler extends BooruHandler {
  XXXTikHandler(super.booru, super.limit);

  static const String _api = 'https://xxxtik-api-iw98m.ondigitalocean.app';
  static const String _cdn = 'https://p5rn.com/cdn/production/media/0312/';
  static const String _site = 'https://xxxtik.com/';

  static const List<String> _periods = ['week', 'month', 'year', 'all'];

  // Keyset pagination state.
  int _cursor = 0;
  String? _cursorKey;

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  // xxxtik feeds are single-tag / single-creator; no boolean tag logic.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  // Keep tags raw — the query is parsed by makeURL, not URL-encoded wholesale.
  @override
  String validateTags(String tags) => tags.trim();

  // xxxtik is video-only, so the "videos only" preview filter would be a
  // no-op — expose none so the UI hides that button.
  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Recent', value: 'new'),
          MetaTagValue(name: 'Top — Week', value: 'week'),
          MetaTagValue(name: 'Top — Month', value: 'month'),
          MetaTagValue(name: 'Top — Year', value: 'year'),
          MetaTagValue(name: 'Top — All time', value: 'all'),
        ],
      ),
    ];
  }

  ({String sort, String? tag, String? creator}) _parse(String input) {
    String sort = 'new';
    String? creator;
    final List<String> tags = [];
    for (final term in input.split(' ').where((t) => t.isNotEmpty)) {
      final lower = term.toLowerCase();
      if (lower.startsWith('sort:') || lower.startsWith('order:')) {
        final v = lower.split(':').last;
        if (v == 'new' || v == 'recent') {
          sort = 'new';
        } else if (_periods.contains(v)) {
          sort = v;
        } else if (v == 'top') {
          sort = 'week';
        }
      } else if (lower.startsWith('creator:') || lower.startsWith('artist:')) {
        final v = term.substring(term.indexOf(':') + 1).trim();
        if (v.isNotEmpty) creator = v;
      } else {
        tags.add(term);
      }
    }
    // xxxtik tags are single words; if several are typed, use the first.
    return (sort: sort, tag: tags.isEmpty ? null : tags.first.toLowerCase(), creator: creator);
  }

  @override
  String makeURL(String tags) {
    final parts = _parse(tags);

    // Endpoint (without the cursor) — the key that, when it changes, resets
    // keyset pagination.
    final String path;
    if (parts.creator != null) {
      path = '/post/creator/${Uri.encodeComponent(parts.creator!)}';
    } else if (parts.tag != null) {
      path = '/post/tag/${Uri.encodeComponent(parts.tag!)}';
    } else if (parts.sort != 'new') {
      path = '/post/top/${parts.sort}';
    } else {
      path = '/post/new';
    }

    if (_cursorKey != path) {
      _cursorKey = path;
      _cursor = 0;
    }

    return Uri.parse('$_api$path').replace(
      queryParameters: {
        'limit': limit.toString(),
        'cursor': _cursor.toString(),
      },
    ).toString();
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      'Origin': 'https://xxxtik.com',
      'Referer': _site,
    };
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
    if (data is! List) return [];
    // Advance the keyset cursor to the last post's id for the next page.
    if (data.isNotEmpty) {
      final last = data.last;
      if (last is Map) {
        final int? id = int.tryParse(last['id']?.toString() ?? '');
        if (id != null) _cursor = id;
      }
    }
    return data;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map post = responseItem;

    final String uid = post['uid']?.toString() ?? '';
    final bool redgifs = post['redgifs'] == true;
    final String? path = _nonEmpty(post['path']);
    final String? videoName = _nonEmpty(post['videoName']);

    // Video (full) + thumbnail, mirroring the site's own media builders.
    String? fileURL;
    String? thumbURL;
    String? sampleURL;
    if (uid.isNotEmpty) {
      fileURL = '$_cdn$uid/master.m3u8';
      thumbURL = '$_cdn$uid/thumbnail.webp';
      sampleURL = '$_cdn$uid/preview.mp4';
    } else if (redgifs && path != null) {
      fileURL = '$_api/util/source?path=$path&type=hd';
      thumbURL = '$_api/util/source?path=$path&type=thumbnail';
    } else if (redgifs) {
      fileURL = _nonEmpty(post['redGifsVideoUrl'])?.replaceAll('-mobile', '');
      thumbURL = _nonEmpty(post['redGifsThumbnailUrl']);
    } else if (videoName != null) {
      fileURL = '${_cdn}videos/$videoName/$videoName-0.mp4';
      thumbURL = '${_cdn}videos/$videoName/$videoName.png';
    }
    if (fileURL == null || fileURL.isEmpty) return null;
    thumbURL ??= fileURL;
    sampleURL ??= fileURL;

    // Force the item to be treated as a video. Native xxxtik posts stream via
    // HLS (.m3u8); the players detect HLS from the URL, but the app derives
    // media type from the extension, so pin it to a video extension.
    final bool isHls = fileURL.contains('.m3u8');
    final String fileExt = isHls ? 'mp4' : Tools.getFileExt(fileURL);

    final List<Tag> tags = ((post['tags'] as List?) ?? [])
        .map((t) => (t is Map ? t['name']?.toString() : t?.toString()) ?? '')
        .where((t) => t.trim().isNotEmpty)
        .map((t) => Tag(t.replaceAll(' ', '_').toLowerCase()))
        .toList();

    // Creator (author) as an artist tag so it colours + routes to the creator
    // feed via `creator:<name>`.
    final Map? author = post['author'] as Map?;
    final String? creatorName = author == null ? null : _nonEmpty(author['name']);
    if (creatorName != null) {
      final String creatorTag = 'creator:${creatorName.toLowerCase()}';
      tags.add(Tag(creatorTag, tagType: TagType.artist));
      addTagsWithType([creatorTag], TagType.artist);
    }

    final double? w = double.tryParse(post['width']?.toString() ?? '');
    final double? h = double.tryParse(post['height']?.toString() ?? '');
    final int likes = (post['_count'] is Map) ? int.tryParse(post['_count']['reactions']?.toString() ?? '') ?? 0 : 0;

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL,
      thumbnailURL: thumbURL,
      fileExt: fileExt,
      tagsList: tags,
      postURL: makePostURL(uid.isNotEmpty ? uid : (post['uuid']?.toString() ?? '')),
      serverId: post['id']?.toString(),
      score: likes > 0 ? likes.toString() : null,
      fileWidth: w,
      fileHeight: h,
      description: _nonEmpty(post['description']),
      uploaderName: creatorName,
    );
  }

  String? _nonEmpty(dynamic value) {
    if (value == null) return null;
    final String s = value.toString();
    return (s.isEmpty || s == 'null') ? null : s;
  }

  @override
  String makePostURL(String id) => 'https://xxxtik.com/post/$id';

  //
  // Autocomplete — returns both tags and creators (creators as creator:<name>).

  @override
  String makeTagURL(String input) {
    return Uri.parse('$_api/search').replace(queryParameters: {'query': input.trim()}).toString();
  }

  @override
  Future<Response<dynamic>> fetchTagSuggestions(Uri uri, String input, {CancelToken? cancelToken}) async {
    return DioNetwork.get(
      uri.toString(),
      headers: getHeaders(),
      cancelToken: cancelToken,
    );
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final data = response.data;
    return data is List ? data : [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final String name = responseItem['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    final String type = responseItem['type']?.toString() ?? 'tag';
    final int count = int.tryParse(responseItem['count']?.toString() ?? '0') ?? 0;
    final bool isCreator = type == 'profile';
    return TagSuggestion(
      tag: isCreator ? 'creator:${name.toLowerCase()}' : name.replaceAll(' ', '_').toLowerCase(),
      count: count,
    );
  }
}
