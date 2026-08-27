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
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
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

  @override
  bool get hasSizeData => false;

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

  ({String query, String? sort, String? relatedId}) _parse(String input) {
    final List<String> terms = [];
    String? sort;
    String? relatedId;

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
      terms.add(_siteTerm(term));
    }
    return (query: terms.join(' '), sort: sort, relatedId: relatedId);
  }

  /// Related feeds are a single fixed list — makeURL flags it so parsing can
  /// refuse to "paginate" the same five items forever.
  bool _relatedMode = false;

  @override
  String makeURL(String tags) {
    final parsed = _parse(tags);
    final int page = pageNum < 0 ? 1 : pageNum + 1;

    _relatedMode = parsed.relatedId != null;
    if (parsed.relatedId != null) {
      return '$_base/api/v2/galleries/${parsed.relatedId}/related';
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
    final dynamic data = _json(response.data);

    // Related endpoint: fixed list, no pagination — a second "page" would
    // return the same items forever.
    if (_relatedMode && pageNum > 0) return [];

    final List rows = (data is Map ? data['result'] : data) as List? ?? [];
    if (data is Map && data['total'] != null) {
      totalCount.value = data['total'] as int? ?? 0;
    }

    await _resolveTagIds([
      for (final row in rows) ...List<int>.from(row['tag_ids'] as List? ?? []),
    ]);
    return rows;
  }

  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) {
    final row = responseItem;
    final int id = row['id'] as int;
    final String thumbPath = row['thumbnail'].toString();
    final String thumb = thumbUrl(thumbPath);

    final List<Tag> tags = [
      for (final tagId in List<int>.from(row['tag_ids'] as List? ?? []))
        if (_tagCache[tagId] != null) Tag(_tagCache[tagId]!.name, tagType: _tagCache[tagId]!.type),
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
        tags.add(Tag(name, tagType: type));
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
