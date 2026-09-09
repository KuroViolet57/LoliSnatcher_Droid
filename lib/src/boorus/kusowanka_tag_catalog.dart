import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// kusowanka's five browse indexes, one per namespace (probed 2026-09-09):
/// `/tags/`, `/artists/`, `/characters/`, `/parodies/`, `/metadatas/`, each
/// `?page=N` with 126 entries a page. A row is
/// `<a href="/artist/<slug>/"><h2 class="btm_artist">#Name</h2></a>`, and the
/// pager names the last page.
///
/// The lists are deep (artists ran to 8,802 pages the day this was written),
/// so a pull is capped and resumes where it stopped, like the gelbooru walk.
/// A row keeps the site's DISPLAY name so the list reads and filters like a
/// tag list, and its SLUG as `sourceId` — the slug is what routes, and
/// slugifying a punctuated display name back would not reproduce it.
class KusowankaTagCatalog extends TagCatalogSource {
  KusowankaTagCatalog(this.handler);

  final KusowankaHandler handler;

  /// Pages one pull walks before stopping; the next pull continues.
  static const int pagesPerPull = 20;

  /// Namespace key -> the index path and the per-row link prefix.
  static const Map<String, (String index, String row)> routes = {
    'tag': ('tags', 'tag'),
    'artist': ('artists', 'artist'),
    'character': ('characters', 'character'),
    'parody': ('parodies', 'parody'),
    'metadata': ('metadatas', 'metadata'),
  };

  /// The last page each index reported, so the walk stops without a request
  /// past the end.
  final Map<String, int> _lastPage = {};

  /// Test seam: answers the index request in place of the network.
  @visibleForTesting
  Future<({int status, String body})> Function(String url)? fetcher;

  @override
  Duration get shardDelay => const Duration(milliseconds: 400);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: TagType.artist, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: TagType.character, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'parody', label: 'Parodies', type: TagType.copyright, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'metadata', label: 'Metadata', type: TagType.meta, maxShards: pagesPerPull),
  ];

  /// Always qualified: the handler takes one facet per query, and a bare word
  /// would be read as a plain tag whatever namespace it came from.
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.sourceId ?? e.name}';

  String indexUrl(String namespace, int shard) {
    final String index = routes[namespace]!.$1;
    final int page = shard + 1;
    const String site = KusowankaHandler.site;
    return page <= 1 ? '$site/$index/' : '$site/$index/?page=$page';
  }

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || !routes.containsKey(namespace)) return null;
    final int? last = _lastPage[namespace];
    if (last != null && shard + 1 > last) return null;
    final String url = indexUrl(namespace, shard);
    final ({int status, String body}) response = await (fetcher?.call(url) ?? _get(url));
    if (response.status == 404) return null;
    if (response.status != 200) {
      throw Exception('kusowanka answered ${response.status} for the $namespace list, page ${shard + 1}');
    }
    final int? reported = lastPageOf(response.body, routes[namespace]!.$1);
    if (reported != null) _lastPage[namespace] = reported;
    final List<BooruTagEntry> rows = parseIndex(response.body, namespace);
    // The FIRST page with neither rows nor a pager means the markup changed;
    // say so rather than walk the whole cap in blanks. An empty page later on
    // is simply the end of a list whose pager did not name its last page.
    if (rows.isEmpty) {
      if (shard == 0 && reported == null) {
        throw Exception('the $namespace list had neither rows nor a pager — the page changed');
      }
      return null;
    }
    return rows;
  }

  Future<({int status, String body})> _get(String url) async {
    final Response response = await DioNetwork.get(
      url,
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true),
    );
    return (status: response.statusCode ?? 0, body: response.data?.toString() ?? '');
  }

  /// The highest page the pager links FOR THIS INDEX — a sidebar link to
  /// another index would otherwise set the walk's last page to that one's.
  @visibleForTesting
  static int? lastPageOf(String body, String index) {
    int? last;
    for (final m in RegExp('/${RegExp.escape(index)}/\\?page=(\\d+)').allMatches(body)) {
      final int n = int.parse(m.group(1)!);
      if (last == null || n > last) last = n;
    }
    return last;
  }

  /// The few entities the site's titles carry.
  static String _unescape(String raw) => raw
      .replaceAll('&#039;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// The rows of one index page. Each entry is linked several times
  /// (thumbnails, Latest, Popular, the title); only the title link carries
  /// the display name:
  /// `<a href="/artist/13/"><h2 class="btm_artist">#13</h2></a>`, so matching
  /// that shape both names the row and deduplicates it.
  @visibleForTesting
  static List<BooruTagEntry> parseIndex(String body, String namespace) {
    final (String, String)? route = routes[namespace];
    if (route == null) return const [];
    final RegExp link = RegExp(
      'href="/${route.$2}/([^"/]+)/"><h2 class="btm_${route.$2}">#?([^<]*)</h2>',
    );
    final TagType type = switch (namespace) {
      'artist' => TagType.artist,
      'character' => TagType.character,
      'parody' => TagType.copyright,
      'metadata' => TagType.meta,
      _ => TagType.none,
    };
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final m in link.allMatches(body)) {
      final String slug = m.group(1)!.trim().toLowerCase();
      if (slug.isEmpty || slug == 'popular' || !seen.add(slug)) continue;
      final String shown = _unescape(m.group(2) ?? '').trim();
      final String name = shown.isEmpty ? slug : shown.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      out.add(BooruTagEntry(name: name, tagType: type, namespace: namespace, sourceId: slug));
    }
    return out;
  }
}
