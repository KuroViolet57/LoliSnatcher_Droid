import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/models/booru_tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/booru/szurubooru_handler.dart';
import 'package:lolisnatcher/sources/framework/tags/tag_catalog_source.dart';
import 'package:lolisnatcher/core/network/dio_network.dart';

/// This instance's tag list: `GET /api/tags/?offset=&limit=&query=sort:usages`.
///
/// The official search executor caps `limit` at 100 and answers 400 above
/// that (`Parameter 'limit' may not exceed 100`, snootbooru.com, 2026-10-07).
/// A pull is 10 pages. The next pull continues from the resume point.
///
/// `names[0]` is the canonical name. Later names are aliases and are not
/// stored as their own rows. `usages` is the post count. The category is
/// instance-defined and is not a post-search prefix (`category:name` filters
/// the tag list, and a post search would look for a tag of that spelling),
/// so every row is filed under `tag` and inserted as the bare name.
///
/// A colon is part of a legal tag name (`tag_name_regex` is `^\S+$` in
/// config.yaml.dist; snootbooru has `By:Muun`). Post search treats `:` as a
/// named-token separator, and the suggestion parser already escapes it, so
/// the inserted term does too.
///
/// Stock `tags:list` is rank `regular`. The request uses the handler's
/// headers, including the Token header when this booru has a user and a
/// token. A non-200 is a failed pull, not an empty list.
class SzurubooruTagCatalog extends TagCatalogSource {
  SzurubooruTagCatalog(this.handler);

  final SzurubooruHandler handler;

  static const int pageSize = 100;
  static const int pagesPerPull = 10;

  /// Test seam: answers the page request in place of the network.
  /// The headers are the ones production would send.
  @visibleForTesting
  Future<({int status, dynamic body})> Function(String url, Map<String, String> headers)? fetcher;

  @override
  Duration get shardDelay => const Duration(milliseconds: 500);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none, maxShards: pagesPerPull),
  ];

  String pageUrl(int shard) =>
      '${handler.booru.baseURL}/api/tags/?offset=${shard * pageSize}&limit=$pageSize'
      '&query=${Uri.encodeQueryComponent('sort:usages')}&fields=names,category,usages';

  @override
  String searchTerm(BooruTagEntry e) => super.searchTerm(e).replaceAll(':', r'\:');

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || namespace != 'tag') return null;
    final String url = pageUrl(shard);
    final Map<String, String> headers = handler.getHeaders();
    final ({int status, dynamic body}) response = await (fetcher?.call(url, headers) ?? _get(url, headers));
    if (response.status != 200) {
      throw Exception(_failure(response.status, response.body));
    }
    return parsePage(response.body);
  }

  Future<({int status, dynamic body})> _get(String url, Map<String, String> headers) async {
    final Response response = await DioNetwork.get(url, headers: headers, options: Options(validateStatus: (_) => true));
    return (status: response.statusCode ?? 0, body: response.data);
  }

  static String _failure(int status, dynamic body) {
    final String? description = body is Map ? body['description']?.toString() : null;
    final String detail = (description == null || description.isEmpty) ? '' : ' ($description)';
    return 'szurubooru answered $status for the tag list$detail';
  }

  /// Null when [body] is a finished page (`results` empty). An empty list
  /// means the page had rows and none of them were usable, so the walk
  /// continues. Anything that is not the paged object throws: a 200 page of
  /// HTML must not look like the end of the list.
  @visibleForTesting
  static List<BooruTagEntry>? parsePage(dynamic body) {
    if (body is! Map) {
      throw const FormatException('szurubooru tag list was not a JSON object');
    }
    final dynamic results = body['results'];
    if (results is! List) {
      throw const FormatException('szurubooru tag list had no results');
    }
    if (results.isEmpty) return null;
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final dynamic item in results) {
      if (item is! Map) continue;
      final dynamic names = item['names'];
      if (names is! List || names.isEmpty) continue;
      final String raw = names.first?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (!seen.add(raw.toLowerCase())) continue;
      out.add(
        BooruTagEntry(
          name: raw,
          tagType: TagType.none,
          namespace: 'tag',
          count: int.tryParse(item['usages']?.toString() ?? '') ?? 0,
        ),
      );
    }
    return out;
  }
}
