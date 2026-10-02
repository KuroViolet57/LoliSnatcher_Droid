import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// nhentai's tags through the search API the app already uses
/// (`POST /api/v2/tags/search {query, limit}` → `[{id, name, type, count}]`,
/// every type at once). The site publishes no listing endpoint, so the list
/// is walked by PREFIX: 36 one-character queries, and any prefix whose answer
/// is cut off at the limit is expanded into its two-character children.
class NHentaiTagCatalog extends TagCatalogSource {
  NHentaiTagCatalog(this.handler);

  final NHentaiHandler handler;

  /// Rows asked for per prefix. The site's ceiling is unverified from here;
  /// a prefix that comes back full is expanded, so a low ceiling only costs
  /// requests, never tags.
  static int limit = 500;

  static const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final List<String> _queue = [];

  @override
  bool get sharedShards => true;

  @override
  int? get sharedShardCount => null;

  @override
  Duration get shardDelay => const Duration(milliseconds: 300);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'parody', label: 'Parodies', type: doujinCopyrightType),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: doujinCharacterType),
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType),
    TagCatalogNamespace(key: 'group', label: 'Groups', type: doujinArtistType),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType),
  ];

  /// Prefixes still to ask, for the picker's "N prefixes done" line.
  int get queued => _queue.length;

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard == 0) {
      _queue
        ..clear()
        ..addAll([for (int i = 0; i < alphabet.length; i++) alphabet[i]]);
    }
    if (shard < 0 || shard >= _queue.length) return null;
    final String prefix = _queue[shard];
    final List rows = await handler.searchTagsRaw(prefix, limit: limit);
    if (shouldExpand(rows.length, limit)) _queue.addAll(expand(prefix));
    return fromRows(rows);
  }

  @visibleForTesting
  static bool shouldExpand(int returned, int limit) => returned >= limit;

  @visibleForTesting
  static List<String> expand(String prefix) => [for (int i = 0; i < alphabet.length; i++) '$prefix${alphabet[i]}', '$prefix '];

  @visibleForTesting
  static List<BooruTagEntry> fromRows(List rows) {
    final List<BooruTagEntry> out = [];
    for (final row in rows) {
      if (row is! Map) continue;
      // Lowercased: the app compares tags case-insensitively and the site's
      // search is case-insensitive too.
      final String name = normalizeDoujinTagName(NHentaiHandler.normalizeName(row['name']?.toString() ?? ''));
      final String ns = row['type']?.toString() ?? 'tag';
      if (name.isEmpty) continue;
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
