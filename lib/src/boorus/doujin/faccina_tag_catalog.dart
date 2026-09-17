import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// hentalk's (faccina's) whole taxonomy in one answer (r70; captured
/// 2026-09-17): the SvelteKit page data `GET /__data.json` carries a
/// `tagList` of `{namespace, name}` for every artist, circle, magazine,
/// publisher, parody, event and tag - 4,427 rows. The payload is in
/// SvelteKit's "devalue" form (one flat array, objects and lists holding
/// indexes into it), decoded here. One request fills every chip.
class FaccinaTagCatalog extends TagCatalogSource {
  FaccinaTagCatalog(this.handler);

  final FaccinaHandler handler;

  /// Test seam: answers the data request in place of the network.
  @visibleForTesting
  Future<({int status, String body})> Function(String url)? fetcher;

  static const Map<String, String> labels = {
    'artist': 'Artists',
    'circle': 'Circles',
    'parody': 'Series',
    'magazine': 'Magazines',
    'publisher': 'Publishers',
    'event': 'Events',
    'tag': 'Tags',
  };

  @override
  bool get sharedShards => true;

  @override
  int? get sharedShardCount => 1;

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType),
    TagCatalogNamespace(key: 'circle', label: 'Circles', type: doujinArtistType),
    TagCatalogNamespace(key: 'parody', label: 'Series', type: doujinCopyrightType),
    TagCatalogNamespace(key: 'magazine', label: 'Magazines', type: doujinMetaType),
    TagCatalogNamespace(key: 'publisher', label: 'Publishers', type: doujinMetaType),
    TagCatalogNamespace(key: 'event', label: 'Events', type: doujinMetaType),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType),
  ];

  /// faccina matches typed terms exactly; a bare word is a text search.
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.name}';

  String get dataUrl => '${handler.booru.baseURL}/__data.json';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard != 0) return null;
    final ({int status, String body}) r = fetcher != null ? await fetcher!(dataUrl) : await _fetch();
    if (r.status != 200) throw Exception('hentalk answered ${r.status} for its tag list');
    return parseTagList(r.body);
  }

  Future<({int status, String body})> _fetch() async {
    final Response response = await DioNetwork.get(
      dataUrl,
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true, responseType: ResponseType.plain),
    );
    final data = response.data;
    return (status: response.statusCode ?? 0, body: data is String ? data : jsonEncode(data));
  }

  /// Every `{namespace, name}` of the page data's `tagList`.
  @visibleForTesting
  static List<BooruTagEntry> parseTagList(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final List nodes = decoded['nodes'] is List ? decoded['nodes'] as List : const [];
    for (final node in nodes) {
      if (node is! Map || node['data'] is! List) continue;
      final dynamic root = devalue(node['data'] as List);
      if (root is! Map || root['tagList'] is! List) continue;
      final List<BooruTagEntry> out = [];
      final Set<String> seen = {};
      for (final row in root['tagList'] as List) {
        if (row is! Map) continue;
        final String namespace = (row['namespace']?.toString() ?? '').toLowerCase();
        final String name = normalizeDoujinTagName(row['name']?.toString() ?? '');
        if (namespace.isEmpty || name.isEmpty || !seen.add('$namespace:$name')) continue;
        out.add(BooruTagEntry(name: name, namespace: namespace, tagType: typeFor(namespace)));
      }
      return out;
    }
    return const [];
  }

  static TagType typeFor(String namespace) => switch (namespace) {
    'artist' || 'circle' => doujinArtistType,
    'parody' => doujinCopyrightType,
    'character' => doujinCharacterType,
    'magazine' || 'publisher' || 'event' => doujinMetaType,
    _ => doujinNoneType,
  };

  /// SvelteKit's devalue: the array's first element is the root; an object's
  /// values and a list's elements are indexes into the array; a negative
  /// index is a hole (undefined, NaN, …).
  @visibleForTesting
  static dynamic devalue(List<dynamic> data, [int index = 0]) {
    final Map<int, dynamic> memo = {};
    dynamic get(int i) {
      if (i < 0 || i >= data.length) return null;
      if (memo.containsKey(i)) return memo[i];
      final dynamic v = data[i];
      if (v is Map) {
        final Map<String, dynamic> out = {};
        memo[i] = out;
        for (final MapEntry entry in v.entries) {
          final dynamic ref = entry.value;
          out[entry.key.toString()] = ref is int ? get(ref) : ref;
        }
        return out;
      }
      if (v is List) {
        final List<dynamic> out = [];
        memo[i] = out;
        for (final dynamic ref in v) {
          out.add(ref is int ? get(ref) : ref);
        }
        return out;
      }
      memo[i] = v;
      return v;
    }

    return get(index);
  }
}
