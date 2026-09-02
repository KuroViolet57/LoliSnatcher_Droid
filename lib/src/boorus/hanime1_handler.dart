import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/hanime_dictionary.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// hanime1.me handler — a Chinese-language hentai video site, presented in
/// English.
///
/// The site's whole tag vocabulary is FIXED — its search form enumerates all
/// 240 tags, 9 genres and 7 sort orders — so the language barrier is solved
/// with a complete built-in dictionary ([HanimeDictionary]) instead of a
/// translation service:
///   * tags on posts are displayed as booru-style English;
///   * you search in English and the exact Chinese string the site expects
///     is sent (`creampie` -> `tags[]=內射`);
///   * autocomplete matches both languages and suggests the English token.
/// Typing the raw Chinese tag still works too.
///
/// Titles and artist names are FREE TEXT (mostly Chinese/Japanese) and no
/// dictionary can cover them; the original is kept and an English machine
/// translation is fetched best-effort per post (see [_translateFreeText])
/// and shown alongside it in the description.
///
/// Site behaviour (verified live):
///   * `GET /search` with `query=`, `genre=`, repeated `tags[]=`, `sort=`,
///     `page=` — multiple tags are ANDed; `broad=on` turns that into OR.
///   * The watch page carries plain `<source>` mp4s in up to three qualities
///     with signed, expiring URLs — so items must be refetched, never
///     replayed from old data.
///   * The grid carries title/thumbnail/duration but NO tags, so tags are
///     filled by [loadItem] like the other scrape sites.
///   * Grids embed sponsor cards using the same markup with an outbound
///     link; anything whose link is not `watch?v=` is skipped.
class Hanime1Handler extends BooruHandler {
  Hanime1Handler(super.booru, super.limit);

  // Reads neither field (audited): the fields are hidden on the edit page.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


  /// hanime1.me and hanime1.com serve the IDENTICAL site, but their
  /// Cloudflare configs differ: .me hard-blocks clients whose TLS handshake
  /// is not a real browser's (a user's log showed "Sorry, you have been
  /// blocked" from a residential IP that browses the site fine in Chrome —
  /// so the block keys on the client fingerprint, not the address, and there
  /// is no captcha to solve on that page). .com accepted plain HTTP clients
  /// in every test. When one domain serves the block page, the same request
  /// is retried on the other, and the winner is remembered for the session.
  static String? _workingHost;

  static const List<String> _hosts = ['hanime1.me', 'hanime1.com'];

  String get _base {
    String url = booru.baseURL ?? 'https://hanime1.me';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final String? host = _workingHost;
    if (host != null) {
      url = url.replaceFirst(RegExp(r'hanime1\.(me|com)'), host);
    }
    return url;
  }

  static bool _isCfBlock(Response? response) =>
      response?.statusCode == 403 && (response?.data?.toString().contains('cf-error-details') ?? false);

  static String? _flipDomain(String url) {
    for (final host in _hosts) {
      if (url.contains(host)) {
        final String other = _hosts.firstWhere((h) => h != host);
        return url.replaceFirst(host, other);
      }
    }
    return null;
  }

  /// GET with the cross-domain retry described on [_workingHost].
  Future<Response<dynamic>> _getWithDomainFallback(String url, {CancelToken? cancelToken}) async {
    try {
      return await DioNetwork.get(url, headers: getHeaders(), cancelToken: cancelToken);
    } on DioException catch (e) {
      final String? flipped = _flipDomain(url);
      if (!_isCfBlock(e.response) || flipped == null) rethrow;
      Logger.Inst().log(
        'cloudflare block on $url — retrying via alternate domain',
        className,
        '_getWithDomainFallback',
        LogTypes.booruHandlerInfo,
      );
      final response = await DioNetwork.get(flipped, headers: getHeaders(), cancelToken: cancelToken);
      _workingHost = Uri.parse(flipped).host;
      return response;
    }
  }

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => true;

  /// AND is the site's native combination; the app's OR groups would need
  /// `broad=on`, which ORs EVERY tag, not one group — close enough to be
  /// wrong, so it is not pretended. `mode:any` exposes broad matching
  /// explicitly instead.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  /// Video-only site — the filter would select everything.
  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  Map<String, String> getHeaders() => {
    'Accept': 'text/html,application/xml,application/json',
    'User-Agent': Tools.browserUserAgent,
    'Referer': '$_base/',
  };

  @override
  String validateTags(String tags) => tags.trim();

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        values: [
          for (final entry in HanimeDictionary.sorts.entries)
            MetaTagValue(name: entry.value, value: entry.key),
        ],
      ),
      MetaTagWithValues(
        name: 'Genre',
        keyName: 'genre',
        values: [
          for (final entry in HanimeDictionary.genres.entries)
            MetaTagValue(name: entry.value, value: entry.key),
        ],
      ),
    ];
  }

  // ─────────────────────────── query building ───────────────────────────

  ({List<String> zhTags, String query, String? genre, String? sort, bool broad}) _parse(String input) {
    final List<String> zhTags = [];
    final List<String> freeText = [];
    String? genre;
    String? sort;
    bool broad = false;

    for (final term in input.split(' ').where((t) => t.trim().isNotEmpty)) {
      final int colon = term.indexOf(':');
      final String key = colon > 0 ? term.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? term.substring(colon + 1).trim() : '';

      if (key == 'sort' && value.isNotEmpty) {
        sort = HanimeDictionary.sorts[value.toLowerCase()] ??
            (HanimeDictionary.sorts.containsValue(value) ? value : null);
        continue;
      }
      if (key == 'genre' && value.isNotEmpty) {
        genre = HanimeDictionary.genres[value.toLowerCase()] ??
            (HanimeDictionary.genres.containsValue(value) ? value : null);
        continue;
      }
      if (key == 'mode' && value.toLowerCase() == 'any') {
        broad = true;
        continue;
      }
      // Artists have no tag namespace on the site — its own artist links go
      // through the free-text search, so that is where `artist:` goes too.
      if (key == 'artist' && value.isNotEmpty) {
        freeText.add(value.replaceAll('_', ' '));
        continue;
      }

      // English dictionary token -> the exact Chinese string the site wants.
      final HanimeTag? byEn = HanimeDictionary.fromEn(term);
      if (byEn != null) {
        zhTags.add(byEn.zh);
        continue;
      }
      // Raw Chinese tag typed/tapped directly.
      final HanimeTag? byZh = HanimeDictionary.fromZh(term);
      if (byZh != null) {
        zhTags.add(byZh.zh);
        continue;
      }
      // Anything else is a free-text title/keyword search term. Underscores
      // come from the app's tag conventions; titles use spaces.
      freeText.add(term.replaceAll('_', ' '));
    }

    return (zhTags: zhTags, query: freeText.join(' '), genre: genre, sort: sort, broad: broad);
  }

  @override
  String makeURL(String tags) {
    final parsed = _parse(tags);
    final int page = pageNum < 0 ? 1 : pageNum + 1;

    // Built by hand because `tags[]` repeats — Uri.replace with a map cannot
    // express that.
    final List<String> params = [
      'query=${Uri.encodeQueryComponent(parsed.query)}',
      if (parsed.genre != null) 'genre=${Uri.encodeQueryComponent(parsed.genre!)}',
      for (final zh in parsed.zhTags) 'tags%5B%5D=${Uri.encodeQueryComponent(zh)}',
      if (parsed.broad) 'broad=on',
      if (parsed.sort != null) 'sort=${Uri.encodeQueryComponent(parsed.sort!)}',
      'page=$page',
    ];
    return '$_base/search?${params.join('&')}';
  }

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    return _getWithDomainFallback(uri.toString());
  }

  // ───────────────────────────── parsing ─────────────────────────────

  /// The site renders TWO grid layouts and picks per genre, not per URL:
  /// most searches use horizontal `video-item-container` cards, but 裏番
  /// (`genre:hentai`) pages use vertical `home-rows-videos-div` covers with
  /// the link WRAPPING the card instead of inside it. Both are parsed.
  @override
  List parseListFromResponse(dynamic response) {
    final Document document = parse(response.data?.toString() ?? '');
    final List<Element> horizontal = document.querySelectorAll('div.video-item-container');
    if (horizontal.isNotEmpty) return horizontal;
    // Vertical layout: hand back the wrapping <a> so the item parser can
    // reach both the link and the card content.
    return [
      for (final link in document.querySelectorAll('a'))
        if ((link.attributes['href'] ?? '').contains('watch?v=') &&
            link.querySelector('.home-rows-videos-div') != null)
          link,
    ];
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final Element block = responseItem as Element;
    final String href = block.localName == 'a'
        ? (block.attributes['href'] ?? '')
        : (block.querySelector('a.video-link')?.attributes['href'] ?? '');
    // Sponsor cards reuse the same markup with an outbound link.
    final String id = RegExp(r'watch\?v=(\d+)').firstMatch(href)?.group(1) ?? '';
    if (id.isEmpty) return null;

    final String thumb =
        block.querySelector('img.main-thumb')?.attributes['src'] ??
        block.querySelector('.video-card-inner img')?.attributes['src'] ??
        '';
    if (thumb.isEmpty) return null;
    final String title = (block.attributes['title'] ??
            block.querySelector('.home-rows-videos-title')?.text ??
            '')
        .trim();

    final BooruItem item = BooruItem(
      // Placeholder until loadItem resolves the real mp4 — the grid has no
      // media URL at all.
      fileURL: thumb,
      sampleURL: thumb,
      thumbnailURL: thumb,
      tagsList: const [],
      postURL: makePostURL(id),
      serverId: id,
      description: title,
    );
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  @override
  String makePostURL(String id) => '$_base/watch?v=$id';

  /// Watch page -> real video (highest quality `<source>`), poster, typed
  /// English tags, artist, date, views, and a best-effort English title.
  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final response = await _getWithDomainFallback(item.postURL, cancelToken: cancelToken);
      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      }
      final String body = response.data?.toString() ?? '';
      final Document html = parse(body);

      // Highest-quality mp4 wins; `size` is the vertical resolution.
      Element? best;
      int bestSize = -1;
      for (final source in html.querySelectorAll('video#player source')) {
        final int size = int.tryParse(source.attributes['size'] ?? '') ?? 0;
        if ((source.attributes['src']?.isNotEmpty ?? false) && size > bestSize) {
          best = source;
          bestSize = size;
        }
      }
      final String? videoUrl = best?.attributes['src'];
      final String? poster = html.querySelector('video#player')?.attributes['poster'];
      if (videoUrl == null || videoUrl.isEmpty) {
        return (item: null, failed: true, error: 'No video source found');
      }

      item
        ..fileURL = videoUrl
        ..sampleURL = poster ?? item.sampleURL
        ..fileExt = 'mp4';
      item.possibleMediaType.value = null;
      item.mediaType.value = MediaType.video;

      // The tag strip carries two link shapes, both inside `single-video-tag`:
      //
      //   /search?tags[]=<zh>   the site's 240 attribute tags -> dictionary
      //   /search?query=<zh>    `#`-prefixed source work and its characters
      //
      // Attribute tags are translated to English through the dictionary. The
      // `query=` ones are proper nouns and stay in Chinese on purpose: a
      // machine translation of a character name would no longer match
      // anything when tapped, and searchable beats readable. Scoping to the
      // strip also keeps unrelated `tags[]` links elsewhere on the page out.
      final List<Tag> tags = [];
      final Map<TagType, List<String>> byType = {};
      String? franchise;

      void addTag(String token, TagType type) {
        if (token.isEmpty || tags.any((t) => t.fullString == token)) return;
        tags.add(Tag(token, tagType: type));
        byType.putIfAbsent(type, () => []).add(token);
      }

      for (final container in html.querySelectorAll('div.single-video-tag')) {
        final String href = container.querySelector('a')?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final String? attribute = RegExp(r'tags(?:%5B%5D|\[\])=([^&"]+)').firstMatch(href)?.group(1);
        if (attribute != null) {
          final String zh = _decodeParam(attribute);
          if (zh.isEmpty) continue;
          final HanimeTag? known = HanimeDictionary.fromZh(zh);
          addTag(known?.en ?? zh, known?.type ?? TagType.none);
          continue;
        }

        final String? named = RegExp(r'[?&]query=([^&"]+)').firstMatch(href)?.group(1);
        if (named == null) continue;
        final String zh = _decodeParam(named);
        if (zh.isEmpty) continue;
        // The work is listed before its characters, so the first entry is
        // always the franchise; a later entry that extends it (e.g. 偶像大師
        // 閃耀色彩 under 偶像大師) is a sub-series rather than a character.
        final bool isWork = franchise == null || zh.startsWith(franchise);
        franchise ??= zh;
        // Spaces would split into two tags under the app's tag conventions;
        // `_parse` turns the underscores back into spaces when searching.
        addTag(zh.replaceAll(' ', '_'), isWork ? TagType.copyright : TagType.character);
      }

      final String artist = html.querySelector('#video-artist-name')?.text.trim() ?? '';
      if (artist.isNotEmpty) {
        addTag('artist:${artist.toLowerCase().replaceAll(' ', '_')}', TagType.artist);
        item.uploaderName = artist;
      }

      if (tags.isNotEmpty) {
        item.tagsList = tags;
        for (final entry in byType.entries) {
          addTagsWithType(entry.value, entry.key);
        }
      }

      // 觀看次數：22.1萬次  2026-08-20
      final RegExpMatch? stats = RegExp(r'觀看次數：([\d.,]+)(萬)?次[^\d]*(\d{4}-\d{2}-\d{2})').firstMatch(body);
      if (stats != null) {
        final double count = double.tryParse(stats.group(1)?.replaceAll(',', '') ?? '') ?? 0;
        final int views = (count * (stats.group(2) == '萬' ? 10000 : 1)).round();
        if (views > 0) item.score = views.toString();
        item.postDate = stats.group(3);
        item.postDateFormat = 'yyyy-MM-dd';
      }

      // Title: original stays authoritative, machine translation is added
      // when it can be fetched — never blocks the post on failure.
      final String title = html.querySelector('#shareBtn-title')?.text.trim() ??
          RegExp(r'<title>([^<]+?)(?:&nbsp;-|\s-\s|</title>)').firstMatch(body)?.group(1)?.trim() ??
          (item.description ?? '');
      final String caption = html.querySelector('.video-caption-text')?.text.trim() ?? '';
      String description = title;
      final String? english = await _translateFreeText(title);
      if (english != null && english.trim().toLowerCase() != title.trim().toLowerCase()) {
        description += '\nEN: $english';
      }
      if (caption.isNotEmpty) description += '\n\n$caption';
      item.description = description;

      item.isUpdated = true;
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log(e.toString(), className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  /// hanime1 writes its tag links with raw UTF-8 in the query string
  /// (`/search?tags[]=同人作品`), and Dart's URI decoders throw
  /// `Illegal percent encoding` on any unencoded non-ASCII byte — not just on
  /// a malformed `%` sequence. Decoding unconditionally therefore threw on the
  /// first Chinese tag of every single item and took all of [loadItem] down
  /// with it. Decode only what is actually percent-encoded, and never let a
  /// malformed value escape as an exception.
  static String _decodeParam(String raw) {
    if (!raw.contains('%')) return raw.trim();
    try {
      return Uri.decodeComponent(raw).trim();
    } catch (_) {
      return raw.trim();
    }
  }

  // ──────────────────────── free-text translation ────────────────────────

  static final Map<String, String> _translationCache = {};

  /// Best-effort machine translation for titles — the one thing a fixed
  /// dictionary cannot cover. Uses the keyless `translate_a/single` endpoint
  /// (the same one the Google Translate browser extension calls). Failures
  /// are swallowed: the original title is always shown regardless.
  static Future<String?> _translateFreeText(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    // Nothing to do for text that is already ASCII.
    if (!RegExp(r'[^\x00-\x7F]').hasMatch(trimmed)) return null;
    final String? cached = _translationCache[trimmed];
    if (cached != null) return cached.isEmpty ? null : cached;

    try {
      final response = await DioNetwork.get(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {'client': 'gtx', 'sl': 'auto', 'tl': 'en', 'dt': 't', 'q': trimmed},
        headers: {'User-Agent': Tools.browserUserAgent},
      );
      final dynamic data = response.data is String ? jsonDecode(response.data as String) : response.data;
      final dynamic segments = data is List && data.isNotEmpty ? data.first : null;
      if (segments is! List) throw Exception('unexpected response shape');
      final String result = [
        for (final segment in segments)
          if (segment is List && segment.isNotEmpty) segment.first.toString(),
      ].join().trim();
      _translationCache[trimmed] = result;
      return result.isEmpty ? null : result;
    } catch (e) {
      // Cache the miss for this session so a dead endpoint is not re-hit on
      // every post.
      _translationCache[trimmed] = '';
      Logger.Inst().log('title translation failed: $e', 'Hanime1Handler', '_translateFreeText', LogTypes.booruHandlerInfo);
      return null;
    }
  }

  // ──────────────────────────── suggestions ────────────────────────────

  /// Local dictionary lookup, matching either language, suggesting English.
  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final String query = input.trim();
    if (query.length < 2) return const Right([]);

    final List<TagSuggestion> out = [
      for (final tag in HanimeDictionary.search(query)) TagSuggestion(tag: tag.en, type: tag.type),
    ];
    final String lower = query.toLowerCase();
    for (final entry in HanimeDictionary.genres.keys) {
      if (out.length >= 25) break;
      if (entry.contains(lower)) out.add(TagSuggestion(tag: 'genre:$entry', type: TagType.meta));
    }
    return Right(out.take(25).toList());
  }
}
