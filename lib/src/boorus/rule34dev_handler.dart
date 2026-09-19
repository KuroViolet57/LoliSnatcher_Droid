import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// app.rule34.dev handler.
///
/// app.rule34.dev is a Next.js meta-search that aggregates a dozen boorus
/// behind one video-forward UI. Rather than re-scrape each site, this handler
/// reads the app's own server-rendered data endpoint:
///
///   GET https://app.rule34.dev/_next/data/{buildId}/{source}/{page}/{tags}.json
///     -> { pageProps: { newResult: [ [ post, ... ] ] } }
///
/// Every post is already normalised by the site (file_url / sample_url /
/// preview_url / tags / width / height / score / rating / duration), so this
/// endpoint gives the exact aggregated feed the website shows — images,
/// animations and video posts alike — without hammering the site's private
/// scraping proxy (the _next/data route is static + Cloudflare-cached).
///
/// `<source>` picks which underlying booru to read (r34 = rule34.xxx default,
/// gel = gelbooru, e621, r34paheal, ...). It's chosen with the `source:`
/// chip / prefix; `<page>` is 0-based; multiple tags join with `+`.
///
/// The buildId rotates whenever the site redeploys, so it's fetched from the
/// homepage once, cached, and re-fetched automatically on the 404 a stale id
/// produces.
class Rule34DevHandler extends BooruHandler {
  Rule34DevHandler(super.booru, super.limit);

  // Reads neither field (audited): the fields are hidden on the edit page.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


  static const String _appBase = 'https://app.rule34.dev';

  // Sources that the site's data route serves as distinct feeds. `r34`
  // (rule34.xxx) is the default the website itself opens on.
  static const List<String> knownSources = ['r34', 'gel', 'e621', 'r34paheal'];
  static const String _defaultSource = 'r34';

  // Per-source native autocomplete endpoints (all public), so tag suggestions
  // match the source currently being browsed.
  static const Map<String, String> _autocompleteUrls = {
    'r34': 'https://api.rule34.xxx/autocomplete.php?q=',
    'gel': 'https://gelbooru.com/index.php?page=autocomplete2&type=tag_query&limit=10&term=',
    'e621': 'https://e621.net/tags/autocomplete.json?expiry=7&search%5Bname_matches%5D=',
    'r34paheal': 'https://rule34.paheal.net/api/internal/autocomplete?s=',
  };

  // Cached Next.js buildId (shared across instances); refreshed on demand.
  static String? _buildId;

  // Source used by the most recent makeURL — drives autocomplete routing.
  String _lastSource = _defaultSource;

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  // The site queries each booru with space-separated tags AND-ed together;
  // there's no cross-source OR, so collapse any OR groups with a warning.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  // Keep tags raw — the base implementation URL-encodes the whole string,
  // which would mangle the `source:` prefix and the `+` join done in makeURL.
  @override
  String validateTags(String tags) => tags.trim();

  @override
  List<MetaTag> availableMetaTags() {
    return [
      // Source selector — which underlying booru app.rule34.dev reads.
      MetaTagWithValues(
        name: 'Source',
        keyName: 'source',
        isFree: true,
        values: [
          MetaTagValue(name: 'Rule34.xxx', value: 'r34'),
          MetaTagValue(name: 'Gelbooru', value: 'gel'),
          MetaTagValue(name: 'e621', value: 'e621'),
          MetaTagValue(name: 'Paheal', value: 'r34paheal'),
        ],
      ),
    ];
  }

  //
  // buildId handling

  Future<String?> _ensureBuildId({bool force = false}) async {
    if (!force && _buildId?.isNotEmpty == true) return _buildId;
    try {
      final response = await DioNetwork.get(
        '$_appBase/',
        headers: {'User-Agent': Tools.browserUserAgent},
        options: Options(responseType: ResponseType.plain),
      );
      final String html = response.data?.toString() ?? '';
      final match = RegExp('"buildId":"([^"]+)"').firstMatch(html);
      final String? id = match?.group(1);
      if (id?.isNotEmpty == true) {
        _buildId = id;
        return id;
      }
    } catch (e, s) {
      Logger.Inst().log(
        'failed to get rule34.dev buildId: $e',
        className,
        '_ensureBuildId',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
    }
    return _buildId;
  }

  @override
  Future<bool> searchSetup() async {
    final id = await _ensureBuildId();
    return id?.isNotEmpty == true;
  }

  //
  // Query building

  ({String source, String tags}) _splitSourceAndTags(String input) {
    final List<String> terms = input.split(' ').where((t) => t.isNotEmpty).toList();
    String source = _defaultSource;
    final List<String> tags = [];
    for (final term in terms) {
      final lower = term.toLowerCase();
      if (lower.startsWith('source:') || lower.startsWith('src:')) {
        final value = lower.split(':').last;
        if (value.isNotEmpty) source = value;
      } else {
        tags.add(term);
      }
    }
    return (source: source, tags: tags.join('+'));
  }

  @override
  String makeURL(String tags) {
    final parts = _splitSourceAndTags(tags);
    _lastSource = parts.source;
    // Placeholder buildId; searchSetup() populates the real one first, and
    // fetchSearch refreshes it on a stale-id 404.
    final String buildId = _buildId ?? 'latest';
    final String encodedTags = parts.tags.isEmpty ? '' : Uri.encodeComponent(parts.tags);
    // /_next/data/<buildId>/<source>/<page>/<tags>.json  (page is 0-based)
    return '$_appBase/_next/data/$buildId/${parts.source}/$pageNum/$encodedTags.json';
  }

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    Future<Response<dynamic>> doGet(String url) => DioNetwork.get(
          url,
          headers: getHeaders(),
          queryParameters: queryParams,
        );

    try {
      return await doGet(uri.toString());
    } on DioException catch (e) {
      // A rotated buildId makes the old data URL 404. Refresh it once and
      // rebuild the URL against the new id.
      if (e.response?.statusCode == 404) {
        final String? fresh = await _ensureBuildId(force: true);
        if (fresh?.isNotEmpty == true) {
          final String rebuilt = makeURL(input);
          return doGet(rebuilt);
        }
      }
      rethrow;
    }
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      'Referer': '$_appBase/',
    };
  }

  //
  // Response parsing

  @override
  List parseListFromResponse(dynamic response) {
    final data = response.data;
    final Map? pageProps = data is Map ? data['pageProps'] as Map? : null;
    final List? groups = pageProps?['newResult'] as List?;
    if (groups == null) return [];
    // newResult is a list of groups (usually one) of posts; flatten it.
    final List<dynamic> posts = [];
    for (final group in groups) {
      if (group is List) {
        posts.addAll(group);
      } else if (group is Map) {
        posts.add(group);
      }
    }
    return posts;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map current = responseItem;

    final String? fileURL = current['file_url']?.toString();
    if (fileURL == null || fileURL.isEmpty) return null;

    final String sampleURL = _nonEmpty(current['sample_url']) ?? fileURL;
    final String thumbURL = _nonEmpty(current['preview_url']) ?? sampleURL;
    final String id = current['id']?.toString() ?? '';

    final List<Tag> tags = ((current['tags'] as List?) ?? [])
        .map((t) => t.toString().trim())
        .where((t) => t.isNotEmpty)
        .map((t) => Tag(t.replaceAll(' ', '_')))
        .toList();

    final String? source = _nonEmpty(current['source']);
    final int? change = int.tryParse(current['change']?.toString() ?? '');

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL,
      thumbnailURL: thumbURL,
      tagsList: tags,
      postURL: source ?? fileURL,
      fileExt: Tools.getFileExt(fileURL),
      serverId: id,
      md5String: _nonEmpty(current['md5']),
      rating: _nonEmpty(current['rating']),
      score: current['score']?.toString(),
      fileWidth: double.tryParse(current['width']?.toString() ?? ''),
      fileHeight: double.tryParse(current['height']?.toString() ?? ''),
      sampleWidth: double.tryParse(current['sample_width']?.toString() ?? ''),
      sampleHeight: double.tryParse(current['sample_height']?.toString() ?? ''),
      previewWidth: double.tryParse(current['preview_width']?.toString() ?? ''),
      previewHeight: double.tryParse(current['preview_height']?.toString() ?? ''),
      sources: source != null ? [source] : null,
      postDate: change?.toString(),
      postDateFormat: change != null ? 'unix' : null,
    );
  }

  String? _nonEmpty(dynamic value) {
    final String s = value?.toString() ?? '';
    return s.isEmpty ? null : s;
  }

  //
  // Tag autocomplete (routed to whichever source is being browsed)

  @override
  String makeTagURL(String input) {
    final String base = _autocompleteUrls[_lastSource] ?? _autocompleteUrls[_defaultSource]!;
    return '$base${Uri.encodeComponent(input.trim())}';
  }

  @override
  Future<Response<dynamic>> fetchTagSuggestions(Uri uri, String input, {CancelToken? cancelToken}) async {
    return DioNetwork.get(
      uri.toString(),
      headers: {
        'Accept': 'application/json',
        'User-Agent': Tools.browserUserAgent,
      },
      cancelToken: cancelToken,
    );
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final data = response.data;
    if (data is List) return data;
    // e621 returns a bare array; gelbooru/rule34 too. Paheal returns an
    // object keyed by tag → count.
    if (data is Map) {
      return data.entries.map((e) => {'value': e.key, 'count': e.value}).toList();
    }
    return [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    if (responseItem is! Map) {
      // Paheal's autocomplete can return a plain list of strings.
      final String text = responseItem?.toString() ?? '';
      if (text.isEmpty) return null;
      return TagSuggestion(tag: text.replaceAll(' ', '_'));
    }
    // Common shapes across the sources:
    //   rule34/gelbooru: {label|value, post_count|value}
    //   e621: {name, post_count, ...}
    final String tag =
        (responseItem['value'] ?? responseItem['name'] ?? responseItem['label'] ?? responseItem['tag'] ?? '')
            .toString();
    if (tag.isEmpty) return null;
    final int count = int.tryParse(
          (responseItem['post_count'] ?? responseItem['count'] ?? responseItem['value'] ?? '0').toString(),
        ) ??
        0;
    return TagSuggestion(
      tag: tag.replaceAll(' ', '_'),
      count: count,
    );
  }
}
