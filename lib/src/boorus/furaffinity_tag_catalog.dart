import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' as html_parser;

import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// FurAffinity's tag builder (r40): the category, theme and species lists
/// of its own search form, one page read for all three. Terms go in by the
/// site's ids (`species:6017`), which is what the search takes.
class FurAffinityTagCatalog extends TagCatalogSource {
  FurAffinityTagCatalog(this.handler);

  final FurAffinityHandler handler;

  static const String categoryKey = 'category';
  static const String themeKey = 'theme';
  static const String speciesKey = 'species';

  static const Map<String, String> _selects = {categoryKey: 'category', themeKey: 'arttype', speciesKey: 'species'};

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: categoryKey, label: 'Categories', type: TagType.meta, shards: 1),
    TagCatalogNamespace(key: themeKey, label: 'Themes', type: TagType.meta, shards: 1),
    TagCatalogNamespace(key: speciesKey, label: 'Species', type: TagType.meta, shards: 1),
  ];

  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.sourceId ?? e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    final String? select = _selects[namespace];
    if (select == null || shard != 0) return null;
    final response = await DioNetwork.get('${FurAffinityQuery.site}/search/', headers: handler.getHeaders());
    return parseSelect(response.data?.toString() ?? '', select, namespace);
  }

  /// The options of one select of the search form, without the "All" /
  /// "Unspecified / Any" entry (value 1).
  @visibleForTesting
  static List<BooruTagEntry> parseSelect(String html, String select, String namespace) {
    final RegExpMatch? m = RegExp('<select[^>]*name="$select"[^>]*>(.*?)</select>', dotAll: true).firstMatch(html);
    if (m == null) return const [];
    final List<BooruTagEntry> out = [];
    for (final RegExpMatch o in RegExp(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)').allMatches(m.group(1)!)) {
      final String id = o.group(1)!.trim();
      final String label = html_parser.parseFragment(o.group(2)!).text?.trim() ?? '';
      if (id.isEmpty || id == '1' || label.isEmpty) continue;
      out.add(
        BooruTagEntry(
          name: label.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
          tagType: TagType.meta,
          namespace: namespace,
          sourceId: id,
        ),
      );
    }
    return out;
  }
}
