import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// kusowanka.com handler.
///
/// Not a booru engine — a bespoke PHP site — and its tag model is different
/// enough to shape every decision here.
///
/// ## How tags work on this site, and why it matters
///
/// Tags live in FIVE separate namespaces, each with its own id space and its
/// own browse route: tags, parodies, artists, characters, metadatas. They map
/// cleanly onto the app's [TagType]s (general / copyright / artist /
/// character / meta), which is the good news.
///
/// The bad news: **the grid only ever exposes numeric ids**, never names —
///
/// ```html
/// <div class="box_thumb" data-tags="1 11 16 27 …" data-artists="548284"
///      data-characters="" data-parodies="6" data-metadatas="12 23 142">
/// ```
///
/// Those numbers are meaningless outside this site. Writing them into the
/// app's tag store would poison everything that reads it — colouring, the tag
/// browser, cross-booru translation, For You seeds — with entries like `1988`
/// that can never match a real tag anywhere. So grid items are parsed with NO
/// tags at all, and the real, typed NAMES are filled in by [loadItem] from
/// the post page, which does spell them out:
///
/// ```html
/// <button type="artist" data_id="548284" name="chun jian he" …>
/// ```
///
/// Consequence worth knowing: the tag blacklist cannot act on a kusowanka
/// grid until a post has been opened, because until then the app genuinely
/// does not know what is in the picture. Emitting fake tags to paper over
/// that would be worse — it would filter the wrong things.
///
/// ## Searching
///
/// The search FORM (`/search/?qt_key=…`) does not work as a plain GET: the
/// ids are accepted and then ignored. Verified by checking whether returned
/// posts actually carry the requested id — `qt_key=30` returned 55 posts, 0
/// of which had tag 30, and `qt_key=1` "matched" 41/55 only because `1girl`
/// is on most posts. It presumably needs the site's own session/CSRF dance.
///
/// The per-tag browse routes DO work and were verified the same way (every
/// returned post carries the requested id):
/// `/tag/{slug}/`, `/artist/{slug}/`, `/character/{slug}/`,
/// `/parody/{slug}/`, `/metadata/{slug}/` — each with `?page=N`.
///
/// They take exactly ONE facet — `/tag/1girl+solo/` and friends all 404 — so
/// multi-tag queries are impossible here and the handler says so rather than
/// silently returning "everything" for a two-word search.
class KusowankaHandler extends BooruHandler {
  KusowankaHandler(super.booru, super.limit);

  // Reads neither field (audited): the fields are hidden on the edit page.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


  static const String _site = 'https://kusowanka.com';

  /// Query prefix -> (browse route segment, autocomplete type, tag type).
  static const Map<String, (String route, String type, TagType tagType)> _facets = {
    'tag': ('tag', 'tags', TagType.none),
    'artist': ('artist', 'artists', TagType.artist),
    'character': ('character', 'characters', TagType.character),
    'parody': ('parody', 'parodies', TagType.copyright),
    'metadata': ('metadata', 'metadatas', TagType.meta),
  };

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => true;

  /// One facet per query — the site has no boolean tag logic at all.
  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  /// The animated/video toggle would have to be combined with the current
  /// query, and this site cannot combine facets — `metadata:animated` is
  /// reachable as a search in its own right instead. An empty list hides the
  /// control rather than shipping a button that quietly replaces your search.
  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  Map<String, String> getHeaders() => {
    'Accept': 'text/html,application/xml,application/json',
    'User-Agent': Tools.browserUserAgent,
    'Referer': '$_site/',
  };

  @override
  String validateTags(String tags) => tags.trim();

  /// `artist:foo` / bare `foo` -> the route that serves it.
  ///
  /// Slugs are what the URLs use: lowercase, spaces and underscores to
  /// hyphens (`chun jian he` -> `chun-jian-he`), which is also how the app's
  /// underscored tags come in from elsewhere.
  static String slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-()]'), '')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  ({String? route, String? slug, bool tooMany}) _parse(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return (route: null, slug: null, tooMany: false);

    // A facet prefix is matched against the WHOLE query BEFORE splitting on
    // spaces: `artist:chun jian he` is one artist with a three-word name, not
    // three terms. Splitting first rejected every multi-word name outright.
    final int colon = trimmed.indexOf(':');
    if (colon > 0) {
      final String key = trimmed.substring(0, colon).toLowerCase();
      final String value = trimmed.substring(colon + 1).trim();
      final facet = _facets[key];
      if (facet != null && value.isNotEmpty) {
        return (route: facet.$1, slug: slugify(value), tooMany: false);
      }
    }

    // Only one facet is representable; several bare terms would silently
    // become "just the first one", which is the kind of quiet wrong answer
    // worth refusing outright.
    final List<String> terms = trimmed.split(' ').where((t) => t.trim().isNotEmpty).toList();
    if (terms.length > 1) return (route: null, slug: null, tooMany: true);
    return (route: 'tag', slug: slugify(terms.first), tooMany: false);
  }

  @override
  String makeURL(String tags) {
    final parsed = _parse(tags);
    if (parsed.tooMany) {
      errorString = 'kusowanka can only browse one tag at a time — '
          'it has no way to combine them. Try a single tag, or '
          'artist:name / character:name / parody:name / metadata:name.';
      locked = true;
      return '';
    }

    final int page = pageNum < 0 ? 1 : pageNum + 1;
    final String suffix = page <= 1 ? '' : '?page=$page';
    if (parsed.route == null || (parsed.slug?.isEmpty ?? true)) {
      // No query: the front page is the newest-first feed.
      return '$_site/$suffix';
    }
    return '$_site/${parsed.route}/${parsed.slug}/$suffix';
  }

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    return DioNetwork.get(uri.toString(), headers: getHeaders(), queryParameters: queryParams);
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Document document = parse(response.data?.toString() ?? '');
    return document.querySelectorAll('div.box_thumb');
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final Element block = responseItem as Element;
    final String? href = block.querySelector('a')?.attributes['href'];
    final String id = RegExp(r'/post/(\d+)').firstMatch(href ?? '')?.group(1) ?? '';
    // `data-bg` on the lazy-loading div, not an <img src>.
    final String thumb = block.querySelector('[data-bg]')?.attributes['data-bg'] ?? '';
    if (id.isEmpty || thumb.isEmpty) return null;

    // thumbs/ and samples/ share the directory tree and the file hash, so the
    // larger preview is derivable without opening the post. The ORIGINAL
    // needs the real extension, which only the post page carries — hence
    // needToLoadItem below.
    final String sample = thumb.replaceFirst('/thumbs/', '/samples/');

    final BooruItem item = BooruItem(
      fileURL: sample,
      sampleURL: sample,
      thumbnailURL: thumb,
      // Deliberately EMPTY: the grid only has numeric ids (see the class
      // doc). loadItem fills in real names with real types.
      tagsList: const [],
      postURL: makePostURL(id),
      serverId: id,
    );
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  @override
  String makePostURL(String id) => '$_site/post/$id/';

  /// Opens the post page for the things the grid cannot give: the real file
  /// extension (and therefore media type), the dimensions, and above all the
  /// tag NAMES with their namespaces.
  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final response = await DioNetwork.get(
        item.postURL,
        headers: getHeaders(),
        cancelToken: cancelToken,
      );
      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      }

      final Document html = parse(response.data?.toString() ?? '');
      final Element? preview = html.querySelector('.preview_image [data-src], .preview_image img[data-src]');
      final String sample = preview?.attributes['data-src'] ?? item.sampleURL;

      // The site's own viewer builds the full-size URL exactly this way:
      // strip the sample's extension, swap `samples` for `original`, and
      // append data-type (jpg/png/gif/webm/mp4 — the true extension).
      final String type = html.querySelector('[data-type]')?.attributes['data-type']?.toLowerCase() ?? '';
      String fileURL = sample;
      if (type.isNotEmpty && sample.contains('/samples/')) {
        final String noExt = sample.replaceFirst(RegExp(r'\.[^/.]+$'), '');
        fileURL = '${noExt.replaceFirst('/samples/', '/original/')}.$type';
      }

      item
        ..fileURL = fileURL
        ..sampleURL = sample
        ..fileExt = type.isEmpty ? Tools.getFileExt(fileURL) : type
        ..fileWidth = double.tryParse(html.querySelector('[data-width]')?.attributes['data-width'] ?? '')
        ..fileHeight = double.tryParse(html.querySelector('[data-height]')?.attributes['data-height'] ?? '');
      item.fileAspectRatio = (item.fileWidth != null && item.fileHeight != null && item.fileHeight != 0)
          ? item.fileWidth! / item.fileHeight!
          : null;
      item.possibleMediaType.value = null;
      item.mediaType.value = MediaType.fromExtension(item.fileExt);

      // Tag names, typed by the namespace the button declares. Each tag has
      // a `-` and a `+` button with identical attributes, hence the dedupe.
      final Map<TagType, List<String>> byType = {};
      final List<Tag> tags = [];
      for (final Element button in html.querySelectorAll('button[data_id][name][type]')) {
        final String namespace = button.attributes['type'] ?? '';
        final String name = button.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        final facet = _facets[namespace];
        if (facet == null) continue;

        // Underscores are the app-wide convention for a tag token.
        final String tagName = name.toLowerCase().replaceAll(' ', '_');
        // Non-general namespaces keep their prefix so tapping one goes back
        // to the right route rather than being guessed at as a plain tag.
        final String token = namespace == 'tag' ? tagName : '$namespace:$tagName';
        if (tags.any((t) => t.fullString == token)) continue;
        tags.add(Tag(token, tagType: facet.$3));
        byType.putIfAbsent(facet.$3, () => []).add(token);
      }
      if (tags.isNotEmpty) {
        item.tagsList = tags;
        for (final entry in byType.entries) {
          addTagsWithType(entry.value, entry.key);
        }
      }
      item.isUpdated = true;
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log(e.toString(), className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  // ─────────────────────────── suggestions ───────────────────────────

  /// Queries all five namespaces and returns real names, prefixed so they can
  /// be searched straight back. `minLength` on the site's own box is 3, and
  /// shorter queries return noise, so that is honoured.
  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final String query = input.trim().toLowerCase();
    if (query.length < 3) return const Right([]);

    final List<TagSuggestion> out = [];
    bool answered = false;

    final results = await Future.wait(
      _facets.entries.map((entry) async {
        try {
          final response = await DioNetwork.get(
            '$_site/inc/search.php',
            queryParameters: {'type': entry.value.$2, 'name': query},
            headers: {...getHeaders(), 'X-Requested-With': 'XMLHttpRequest'},
            cancelToken: cancelToken,
          );
          final dynamic data = response.data is String ? jsonDecode(response.data as String) : response.data;
          return (entry.key, entry.value.$3, data is List ? data : const []);
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          return (entry.key, entry.value.$3, const []);
        }
      }),
    );

    for (final (namespace, tagType, list) in results) {
      if (list.isNotEmpty) answered = true;
      for (final entry in list) {
        if (entry is! Map) continue;
        final String name = entry['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final String tagName = name.toLowerCase().replaceAll(' ', '_');
        final String token = namespace == 'tag' ? tagName : '$namespace:$tagName';
        if (out.any((s) => s.tag == token)) continue;
        out.add(TagSuggestion(tag: token, type: tagType));
      }
    }

    if (!answered && out.isEmpty) {
      return const Left(ResponseError(message: 'no suggestion source answered'));
    }
    return Right(out);
  }
}
