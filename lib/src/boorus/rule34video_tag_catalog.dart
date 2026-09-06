import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/rule34video_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34video_query.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// rule34video's three indexes, read through KVS's async block endpoint
/// (probed 2026-09-06):
///
/// - tags: `/tags/?mode=async&function=get_block&block_id=list_tags_tags_list
///   &sort_by=tag&from=N`, N = 1..74, 120 rows of `div.item > a[href=…/tags/{id}/]
///   name <span>count</span>` (8,845 tags);
/// - artists ("models"): `/models/?…block_id=list_models_models_list
///   &sort_by=model_viewed&from=N`, N = 1..299, 48 rows of
///   `a.wrap_item[href=…/models/{slug}/] .name` (a rating %, no count) —
///   most viewed first, so a partial pull is the useful half;
/// - categories: `/categories/?…block_id=list_categories_categories_list
///   &sort_by=total_videos&from=N`, N = 1..68, 36 rows of
///   `div.thumb.item a.th[href=…/categories/{slug}/] .thumb_title`.
///
/// Every fragment carries its pagination with `data-parameters="…from:N"`,
/// the highest N being the last page, so the walk stops without a request
/// past the end. Tag pages are id-keyed and the slug routes are slug-keyed,
/// so the id or slug travels with the row ([BooruTagEntry.sourceId]) and the
/// handler routes a picked term through it.
class Rule34VideoTagCatalog extends TagCatalogSource {
  Rule34VideoTagCatalog(this.handler);

  final Rule34VideoHandler handler;

  /// Fragments one pull walks before stopping; the next pull resumes.
  /// Tags: 74 fragments -> two pulls. Artists: 299 -> six pulls, the first
  /// being the 2,400 most viewed. Categories: 68 -> two pulls.
  static const int tagShardsPerPull = 40;
  static const int artistShardsPerPull = 50;
  static const int categoryShardsPerPull = 35;

  /// The last fragment each index reported, read off the pagination.
  final Map<String, int> _lastShard = {};

  @override
  Duration get shardDelay => const Duration(milliseconds: 500);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none, maxShards: tagShardsPerPull),
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: TagType.artist, maxShards: artistShardsPerPull),
    TagCatalogNamespace(key: 'category', label: 'Categories', type: TagType.copyright, maxShards: categoryShardsPerPull),
  ];

  /// Tags are bare (the handler routes a known name to `/tags/{id}/`);
  /// artists and categories keep their prefix so the query grammar knows
  /// which slug route to open.
  @override
  String searchTerm(BooruTagEntry e) => e.namespace == 'tag' ? e.name : '${e.namespace}:${e.name}';

  /// The async block URL of one fragment; [shard] is zero-based, the site's
  /// `from` one-based.
  static String? blockUrl(String site, String namespace, int shard) {
    final int from = shard + 1;
    return switch (namespace) {
      'tag' => '$site/tags/?mode=async&function=get_block&block_id=list_tags_tags_list&sort_by=tag&from=$from',
      'artist' =>
        '$site/models/?mode=async&function=get_block&block_id=list_models_models_list&sort_by=model_viewed&from=$from',
      'category' =>
        '$site/categories/?mode=async&function=get_block&block_id=list_categories_categories_list&sort_by=total_videos&from=$from',
      _ => null,
    };
  }

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    final String? url = blockUrl(handler.site, namespace, shard);
    if (url == null || shard < 0) return null;
    final int? last = _lastShard[namespace];
    if (last != null && shard + 1 > last) return null;
    final ({int status, String body}) response = await handler.fetchPage(url);
    if (response.status == 404) return null;
    if (response.status != 200) {
      throw Exception('rule34video answered ${response.status} for the $namespace list, fragment ${shard + 1}');
    }
    final int? reported = lastShardOf(response.body);
    if (reported != null) _lastShard[namespace] = reported;
    final List<BooruTagEntry> got = switch (namespace) {
      'tag' => parseTags(response.body),
      'artist' => parseModels(response.body),
      _ => parseCategories(response.body),
    };
    return got.isEmpty ? null : got;
  }

  static final RegExp _fromParam = RegExp(r'from[a-z_+]*:(\d+)');

  /// The highest `from:N` in a fragment's pagination — the last page of that
  /// list. Null when the fragment has no pagination at all.
  @visibleForTesting
  static int? lastShardOf(String body) {
    int? last;
    for (final m in _fromParam.allMatches(body)) {
      final int n = int.parse(m.group(1)!);
      if (last == null || n > last) last = n;
    }
    return last;
  }

  static final RegExp _tagHref = RegExp(r'/tags/(\d+)/?$');
  static final RegExp _modelHref = RegExp(r'/models/([^/?#]+)/?$');
  static final RegExp _categoryHref = RegExp(r'/categories/([^/?#]+)/?$');
  static final RegExp _digits = RegExp(r'^\d+$');

  /// The list container of a fragment (`…_items`), or the whole fragment
  /// when the markup changed — the sidebar strips a full page carries
  /// (Top Artists) must not leak into the rows.
  static dom.Element _listOf(dom.Document doc) {
    for (final dom.Element e in doc.querySelectorAll('[id]')) {
      if (e.id.endsWith('_items')) return e;
    }
    return doc.body ?? doc.documentElement!;
  }

  static String _ownText(dom.Element a) =>
      a.nodes.whereType<dom.Text>().map((t) => t.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Rows of one tag fragment: the name is the anchor's own text, the count
  /// the digits of its `<span>`.
  @visibleForTesting
  static List<BooruTagEntry> parseTags(String body) {
    final dom.Element list = _listOf(parse(body));
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final dom.Element a in list.querySelectorAll('a[href]')) {
      final RegExpMatch? m = _tagHref.firstMatch(a.attributes['href'] ?? '');
      if (m == null) continue;
      final String name = Rule34VideoQuery.normalizeName(_ownText(a));
      if (name.isEmpty || !seen.add(name)) continue;
      final String digits = (a.querySelector('span')?.text ?? '').replaceAll(RegExp('[^0-9]'), '');
      out.add(
        BooruTagEntry(
          name: name,
          tagType: TagType.none,
          count: digits.isEmpty ? 0 : int.parse(digits),
          namespace: 'tag',
          sourceId: m.group(1),
        ),
      );
    }
    return out;
  }

  /// Rows of one artist fragment: `.name` text, the slug as source id. The
  /// site shows a rating, not a count, so counts stay 0.
  @visibleForTesting
  static List<BooruTagEntry> parseModels(String body) {
    final dom.Element list = _listOf(parse(body));
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final dom.Element a in list.querySelectorAll('a[href]')) {
      final RegExpMatch? m = _modelHref.firstMatch(a.attributes['href'] ?? '');
      // Pagination links are /models/N/ too; a slug is never all digits.
      if (m == null || _digits.hasMatch(m.group(1)!)) continue;
      final String raw = a.querySelector('.name')?.text ?? _ownText(a);
      final String name = Rule34VideoQuery.normalizeName(raw);
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(BooruTagEntry(name: name, tagType: TagType.artist, namespace: 'artist', sourceId: m.group(1)));
    }
    return out;
  }

  /// Rows of one category fragment: `.thumb_title` text, the slug as source id.
  @visibleForTesting
  static List<BooruTagEntry> parseCategories(String body) {
    final dom.Element list = _listOf(parse(body));
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final dom.Element a in list.querySelectorAll('a[href]')) {
      final RegExpMatch? m = _categoryHref.firstMatch(a.attributes['href'] ?? '');
      if (m == null || _digits.hasMatch(m.group(1)!)) continue;
      final String raw = a.querySelector('.thumb_title')?.text ?? _ownText(a);
      final String name = Rule34VideoQuery.normalizeName(raw);
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(BooruTagEntry(name: name, tagType: TagType.copyright, namespace: 'category', sourceId: m.group(1)));
    }
    return out;
  }
}
