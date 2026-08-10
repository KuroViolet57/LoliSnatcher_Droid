import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';

/// bakemono.app — a Gelbooru 0.2-compatible archive of paysite creator posts.
///
/// Everything below was verified against the live site. Its documented API
/// (`tags · pid · limit · id · json`) is a strict subset of gelbooru's, but the
/// site's own frontend exposes more than the API does, so several capabilities
/// come from the HTML instead:
///   * autocomplete lives at /autocomplete.php, not index.php?page=autocomplete2
///   * dapi silently ignores sort/order/orderby/dir/source; /posts honours them
///   * dapi returns only a post's COVER image; the post page carries the full
///     file list as JSON, and dapi's has_children is always false (it lies)
class BakemonoProfile extends SiteProfile {
  const BakemonoProfile();

  @override
  String get id => 'bakemono';

  @override
  Set<String> get hosts => const {'bakemono.app'};

  //
  // Autocomplete
  //

  @override
  String? tagSuggestionsUrl(Booru booru, String input) =>
      '${booru.baseURL}/autocomplete.php?q=${Uri.encodeQueryComponent(input)}';

  /// Responses look like
  /// `{"category":1,"label":"anna_anon (29603)","type":"artist","value":"anna_anon"}`
  /// — `value` and `type` are read by the shared parser, but the post count
  /// only exists inside the display label.
  @override
  int? tagSuggestionCount(dynamic responseItem) {
    if (responseItem is! Map) return null;
    final String label = responseItem['label']?.toString() ?? '';
    final match = RegExp(r'\((\d[\d,\s]*)\)\s*$').firstMatch(label);
    if (match == null) return null;
    return int.tryParse(match.group(1)!.replaceAll(RegExp(r'[,\s]'), ''));
  }

  //
  // Meta tags — only what the site can actually do
  //

  @override
  List<MetaTag>? metaTags() => [
        SortMetaTag(
          values: [
            MetaTagValue(name: 'Date created', value: 'created'),
            MetaTagValue(name: 'Date created (ascending)', value: 'created:asc'),
            MetaTagValue(name: 'Views', value: 'views'),
            MetaTagValue(name: 'Views (ascending)', value: 'views:asc'),
          ],
        ),
        SourceMetaTag(),
      ];

  /// bakemono's tags are only the creator name, the source platform and words
  /// from the post title — there is no `animated`, `video` or `gif` tag to
  /// filter on, and the listing markup carries no video marker either (a video
  /// post's card thumbnail is just a .gif/.jpg like any other). File kinds ARE
  /// known, but only from each post's own page, so filtering a grid by them
  /// would cost one extra request per post. Hidden rather than wired to tags
  /// that match nothing.
  @override
  List<String>? animatedFilters() => const [];

  //
  // Alternate listing: /posts, which can sort and filter by source
  //

  static const int _listingPageSize = 24;

  @override
  int get listingPageSize => _listingPageSize;

  static const Set<String> _sources = {'fanbox', 'fansly', 'onlyfans', 'patreon'};

  /// Splits `sort:views source:patreon foo` into its parts.
  static ({String? sort, String? dir, String? source, String query}) parseQuery(String tags) {
    String? sort, dir, source;
    final List<String> rest = [];
    for (final term in tags.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      final String lower = term.toLowerCase();
      if (lower.startsWith('sort:')) {
        final String value = lower.substring(5);
        final List<String> parts = value.split(':');
        sort = parts.first;
        dir = parts.length > 1 && parts[1] == 'asc' ? 'asc' : 'desc';
      } else if (lower.startsWith('source:') && _sources.contains(lower.substring(7))) {
        source = lower.substring(7);
      } else {
        rest.add(term);
      }
    }
    return (sort: sort, dir: dir, source: source, query: rest.join(' ').trim());
  }

  @override
  String? listingUrl(Booru booru, String tags, int pageNum, int limit) {
    final parsed = parseQuery(tags);
    // The API handles plain browsing and search fine, and returns ~4x more
    // items per request than the 24-item listing — only take over when the
    // query needs something dapi silently ignores.
    if (parsed.sort == null && parsed.source == null) return null;

    final params = <String, String>{
      // /posts pages are 1-based; the app's pageNum for gelbooru is 0-based.
      'page': '${pageNum + 1}',
      if (parsed.query.isNotEmpty) 'q': parsed.query,
      if (parsed.source != null) 'source': parsed.source!,
      // Sorting is ignored while a search term is present (verified: /posts?q=x
      // and /posts?q=x&sort=views return identical order), so don't pretend.
      if (parsed.sort != null && parsed.query.isEmpty) ...{
        'sort': parsed.sort!,
        'dir': parsed.dir ?? 'desc',
      },
    };
    return Uri.parse('${booru.baseURL}/posts').replace(queryParameters: params).toString();
  }

  @override
  List<BooruItem>? parseListing(String body, Booru booru) {
    final String base = booru.baseURL ?? '';
    try {
      final doc = html_parser.parse(body);
      final cards = doc.querySelectorAll('a.post-card');
      // No cards at all on a page that returned 200 means the markup moved —
      // report a parse failure so the caller can fall back to the API.
      if (cards.isEmpty) return null;

      final List<BooruItem> items = [];
      for (final card in cards) {
        final String? href = card.attributes['href'];
        final String? thumb = card.querySelector('.thumb img')?.attributes['src'];
        if (href == null || thumb == null) continue;

        final String thumbUrl = thumb.startsWith('http') ? thumb : '$base$thumb';
        // Full-size lives at the same path without the /thumbnail prefix;
        // ?f=cover.jpeg is what the API serves for the cover too.
        final String fileUrl = '$base${_stripThumbPrefix(thumb)}?f=cover.jpeg';

        final String title = card.querySelector('.post-card__title')?.text.trim() ?? '';
        final String creator = card.querySelector('.post-card__creator')?.text.trim() ?? '';
        final String meta = card.querySelector('.post-card__meta')?.text.trim() ?? '';
        final String viewsText = card.querySelector('.post-card__views')?.text.trim() ?? '';

        // href is /p/{platform}/{creatorId}/{postId}
        final List<String> segments = href.split('/').where((s) => s.isNotEmpty).toList();
        final String platform = segments.length > 1 ? segments[1] : '';
        final String postId = segments.isNotEmpty ? segments.last : '';

        items.add(
          BooruItem(
            fileURL: fileUrl,
            sampleURL: fileUrl,
            thumbnailURL: thumbUrl,
            tagsList: [
              if (creator.isNotEmpty) Tag(creator.replaceAll(' ', '_'), tagType: TagType.artist),
              if (platform.isNotEmpty) Tag(platform),
              ...title
                  .toLowerCase()
                  .split(RegExp(r'[^\w぀-ヿ一-龯]+'))
                  .where((w) => w.length > 2)
                  .take(8)
                  .map(Tag.new),
            ],
            postURL: '$base$href',
            serverId: postId,
            score: _firstInt(viewsText)?.toString(),
            // The card's file count includes non-media attachments, so it is an
            // upper bound; the post page is authoritative once opened.
            fileNameExtras: '',
          )..fileCountHint = _firstInt(meta),
        );
      }
      return items;
    } catch (_) {
      return null;
    }
  }

  static String _stripThumbPrefix(String path) {
    final String noQuery = path.split('?').first;
    return noQuery.startsWith('/thumbnail') ? noQuery.substring('/thumbnail'.length) : noQuery;
  }

  static int? _firstInt(String text) {
    final match = RegExp(r'(\d[\d,]*)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  //
  // Multi-file posts
  //

  @override
  bool get hasMultipleFilesPerPost => true;

  /// The post page. Built from the API's `source` link when the item came from
  /// dapi (`.../creator/{creatorId}/post/{postId}` -> `/p/{platform}/{creatorId}/{postId}`),
  /// or straight from postURL when the item came from the listing scrape.
  @override
  String? postFilesUrl(Booru booru, BooruItem item) {
    final String base = booru.baseURL ?? '';
    if (item.postURL.contains('/p/')) return item.postURL;

    for (final source in item.sources ?? const <String>[]) {
      final match = RegExp(r'/(fanbox|fansly|onlyfans|patreon)/?.*?creator/(\d+)/post/(\d+)').firstMatch(source) ??
          RegExp(r'(fanbox|fansly|onlyfans|patreon).*?/(\d+)/post/(\d+)').firstMatch(source);
      if (match != null) {
        return '$base/p/${match.group(1)}/${match.group(2)}/${match.group(3)}';
      }
    }
    return null;
  }

  /// `<script type="application/json" id="viewer-data">{"files":[...]}</script>`
  /// with an explicit `kind` per file, so no extension sniffing is needed.
  @override
  List<PostFile>? parsePostFiles(String body, Booru booru) {
    final String base = booru.baseURL ?? '';
    try {
      final match = RegExp(
        r'<script[^>]*id="viewer-data"[^>]*>(.*?)</script>',
        dotAll: true,
      ).firstMatch(body);
      if (match == null) return null;

      final decoded = jsonDecode(match.group(1)!.trim());
      final List<dynamic> files = (decoded is Map ? decoded['files'] : decoded) as List<dynamic>? ?? [];

      final List<PostFile> out = [];
      for (final f in files) {
        if (f is! Map) continue;
        final String src = f['src']?.toString() ?? '';
        if (src.isEmpty) continue;
        final String? thumb = (f['thumb'] ?? f['preview'])?.toString();
        out.add(
          PostFile(
            url: src.startsWith('http') ? src : '$base$src',
            isVideo: f['kind']?.toString().toLowerCase() == 'video',
            thumbnailUrl: (thumb == null || thumb.isEmpty || thumb == 'null')
                ? null
                : (thumb.startsWith('http') ? thumb : '$base$thumb'),
          ),
        );
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}

/// Source-platform filter, e.g. `source:patreon`. Only meaningful on sites
/// that aggregate several upstream platforms.
class SourceMetaTag extends MetaTagWithValues {
  SourceMetaTag()
      : super(
          name: 'Source',
          keyName: 'source',
          values: [
            MetaTagValue(name: 'Fanbox', value: 'fanbox'),
            MetaTagValue(name: 'Fansly', value: 'fansly'),
            MetaTagValue(name: 'OnlyFans', value: 'onlyfans'),
            MetaTagValue(name: 'Patreon', value: 'patreon'),
          ],
        );
}
