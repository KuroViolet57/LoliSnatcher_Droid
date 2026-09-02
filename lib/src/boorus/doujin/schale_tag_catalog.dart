import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// niyaniya's tag list, from `GET {api}/books/tags`.
///
/// Verified 2026-09-02 against api.schale.network (Origin header required,
/// not clearance-gated, rate limit 5 per window):
///   * no parameter        → general (code 0/absent), male (8), female (9),
///                           mixed (10): 422 rows
///   * `?namespace=1`      → every artist (2408 rows)
///   * `?namespace=2`      → every circle (444 rows)
///   * `?namespace=3|4|5`  → 400; `11|12` → the unfiltered list again
/// So parody, magazine, character and language cannot be listed and are not
/// offered. Three requests, paced under the rate limit, make one pull.
class SchaleTagCatalog extends TagCatalogSource {
  SchaleTagCatalog(this.handler);

  final SchaleHandler handler;

  static const List<String> shardQueries = ['', '?namespace=1', '?namespace=2'];

  /// Site namespace code → key. Extends the handler's item mapping with the
  /// codes the tag list uses for plain tags.
  static const Map<int, String> codeNames = {
    0: 'tag',
    1: 'artist',
    2: 'circle',
    3: 'parody',
    4: 'magazine',
    5: 'character',
    6: 'cosplayer',
    7: 'uploader',
    8: 'male',
    9: 'female',
    10: 'mixed',
    11: 'language',
    12: 'other',
  };

  @override
  bool get sharedShards => true;

  @override
  int? get sharedShardCount => shardQueries.length;

  @override
  Duration get shardDelay => const Duration(seconds: 4);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType),
    TagCatalogNamespace(key: 'circle', label: 'Circles', type: doujinArtistType),
    TagCatalogNamespace(key: 'female', label: 'Female', type: doujinNoneType),
    TagCatalogNamespace(key: 'male', label: 'Male', type: doujinNoneType),
    TagCatalogNamespace(key: 'mixed', label: 'Mixed', type: doujinNoneType),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType),
  ];

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || shard >= shardQueries.length) return null;
    final Response response = await DioNetwork.get(
      '${SchaleHandler.apiBase}/books/tags${shardQueries[shard]}',
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true),
    );
    if (response.statusCode != 200) {
      throw Exception('niyaniya answered ${response.statusCode} for the tag list');
    }
    return parseTags(response.data);
  }

  @visibleForTesting
  static List<BooruTagEntry> parseTags(dynamic data) {
    final List rows = data is List ? data : const [];
    final List<BooruTagEntry> out = [];
    for (final row in rows) {
      if (row is! Map) continue;
      final String name = normalizeDoujinTagName(row['name']?.toString() ?? '');
      if (name.isEmpty) continue;
      final int code = (row['namespace'] as num?)?.toInt() ?? 0;
      final String ns = codeNames[code] ?? 'tag';
      out.add(
        BooruTagEntry(
          name: name,
          namespace: ns,
          tagType: doujinTagTypeFor(ns),
          count: (row['count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }
}
