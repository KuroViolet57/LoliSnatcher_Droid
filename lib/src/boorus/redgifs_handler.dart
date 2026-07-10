import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
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

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      if (_token?.isNotEmpty == true) 'Authorization': 'Bearer $_token',
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
    return Uri.parse('$_apiBase/v2/gifs/search').replace(
      queryParameters: {
        'search_text': parts.query,
        'order': parts.order,
        'count': limit.toString(),
        'page': pageNum.toString(),
      },
    ).toString();
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

  @override
  List parseListFromResponse(dynamic response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) return [];
    totalCount.value = int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    return (data['gifs'] as List?) ?? [];
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

    final List<String> tags = ((current['tags'] as List?) ?? [])
        .map((t) => t.toString().replaceAll(' ', '_').toLowerCase())
        .toList();
    final String? userName = current['userName']?.toString();
    if (userName != null && userName.isNotEmpty) {
      tags.add('creator:${userName.toLowerCase()}');
    }
    if (current['hasAudio'] == true) {
      tags.add('sound');
    }

    final int? createDate = int.tryParse(current['createDate']?.toString() ?? '');

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sd ?? fileURL,
      thumbnailURL: thumb,
      tagsList: tags.map(Tag.new).toList(),
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

  @override
  Future<Response<dynamic>> fetchTagSuggestions(Uri uri, String input, {CancelToken? cancelToken}) async {
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
    if (responseItem['type'] != 'tag') return null;
    final String text = responseItem['text']?.toString() ?? '';
    if (text.isEmpty) return null;
    return TagSuggestion(
      tag: text.replaceAll(' ', '_').toLowerCase(),
      count: int.tryParse(responseItem['gifs']?.toString() ?? '0') ?? 0,
    );
  }
}
