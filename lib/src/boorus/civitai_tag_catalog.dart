import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/civitai_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// civitai's public tag list: `GET /api/v1/tags?limit=200&page=N`, answering
/// `{items: [{name, link}], metadata: {...}}` (probed 2026-09-09).
///
/// The metadata is not trustworthy — the same request reported
/// `totalItems: 0, totalPages: 1` while page 2 answered a full page — so the
/// walk simply stops at the first page that comes back empty, and a pull is
/// capped either way.
///
/// One namespace: the site has no tag namespaces. Names are stored
/// underscored, the app's convention; the handler turns them back into spaces
/// when it resolves a name to the numeric id its image API filters by.
class CivitaiTagCatalog extends TagCatalogSource {
  CivitaiTagCatalog(this.handler);

  final CivitaiHandler handler;

  /// Rows per request, and pages per pull. The API caps a page at 100
  /// whatever `limit` asks for (checked against its own answer), so a pull
  /// is 10 pages = 1,000 tags — past the useful tail of a popularity list.
  static const int pageSize = 100;
  static const int pagesPerPull = 10;

  /// Rank 0 would sort last; start high enough that a full pull stays
  /// ordered and no row lands on a negative count.
  static const int maxRank = pageSize * pagesPerPull;

  /// Test seam: answers the page request in place of the network.
  @visibleForTesting
  Future<({int status, dynamic body})> Function(String url)? fetcher;

  @override
  Duration get shardDelay => const Duration(milliseconds: 500);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none, maxShards: pagesPerPull),
  ];

  String pageUrl(int shard) => '${handler.booru.baseURL}/api/v1/tags?limit=$pageSize&page=${shard + 1}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || namespace != 'tag') return null;
    final String url = pageUrl(shard);
    final ({int status, dynamic body}) response = await (fetcher?.call(url) ?? _get(url));
    if (response.status != 200) {
      throw Exception('civitai answered ${response.status} for the tag list, page ${shard + 1}');
    }
    final List<BooruTagEntry> rows = parseTags(response.body, rankFrom: shard * pageSize);
    // The site's own paging metadata is unreliable, so the empty page is the
    // end marker.
    return rows.isEmpty ? null : rows;
  }

  Future<({int status, dynamic body})> _get(String url) async {
    final Response response = await DioNetwork.get(
      url,
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true),
    );
    return (status: response.statusCode ?? 0, body: response.data);
  }

  @visibleForTesting
  /// The API answers most-used first, and the picker orders by count, so the
  /// position in the list is kept as a descending rank — otherwise page 10's
  /// rare tags would sit interleaved with page 1's under the same letter.
  static List<BooruTagEntry> parseTags(dynamic body, {int rankFrom = 0}) {
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const [];
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final item in items) {
      if (item is! Map) continue;
      final String raw = item['name']?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final String name = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      if (!seen.add(name)) continue;
      out.add(
        BooruTagEntry(
          name: name,
          tagType: TagType.none,
          namespace: 'tag',
          count: maxRank - (rankFrom + out.length),
        ),
      );
    }
    return out;
  }
}
