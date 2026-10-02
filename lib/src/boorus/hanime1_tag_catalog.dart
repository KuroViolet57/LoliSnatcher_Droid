import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/hanime_dictionary.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// hanime1.me's Tag builder, served from [HanimeDictionary]: the site's
/// search form enumerates its whole vocabulary — 240 tags in seven groups
/// and nine genres — and the app carries it translated, so the chips list
/// it without a request. Each namespace is one instant shard; a "pull" is
/// the dictionary being written into the tag snapshot under the site's host.
///
/// Terms: tags insert bare (`creampie`), which the handler's grammar maps
/// back to the exact site string (`tags[]=內射`); genres insert `genre:mmd`.
/// The site string travels with the row as [BooruTagEntry.sourceId].
class Hanime1TagCatalog extends TagCatalogSource {
  static const String genreKey = 'genre';

  /// Nothing is fetched.
  @override
  Duration get shardDelay => Duration.zero;

  @override
  List<TagCatalogNamespace> get namespaces => [
    for (final HanimeGroup g in HanimeGroup.values)
      TagCatalogNamespace(
        key: g.key,
        label: g.label,
        type: g == HanimeGroup.attribute ? TagType.meta : TagType.none,
        shards: 1,
      ),
    const TagCatalogNamespace(key: genreKey, label: 'Genres', type: TagType.meta, shards: 1),
  ];

  @override
  String searchTerm(BooruTagEntry e) => e.namespace == genreKey ? '$genreKey:${e.name}' : e.name;

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard != 0) return null;
    if (namespace == genreKey) {
      return [
        for (final MapEntry<String, String> e in HanimeDictionary.genres.entries)
          BooruTagEntry(name: e.key, tagType: TagType.meta, namespace: genreKey, sourceId: e.value),
      ];
    }
    final HanimeGroup? group = HanimeGroup.byKey(namespace);
    if (group == null) return null;
    return [
      for (final HanimeTag t in HanimeDictionary.byGroup(group))
        BooruTagEntry(name: t.en, tagType: t.type, namespace: group.key, sourceId: t.zh),
    ];
  }
}
