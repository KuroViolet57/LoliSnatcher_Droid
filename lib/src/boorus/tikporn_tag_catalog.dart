import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/tikporn_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// tik.porn's whole vocabulary, which is small and fixed: 84 tags
/// (`GET /gettaglist`) and 131 acts (`GET /getactionlist`), each a
/// `{id, name, slug}` (verified 2026-09-09).
///
/// The handler already downloads both lists before every search and keeps
/// them in statics, so a chip costs nothing beyond what the source does
/// anyway — this is the cheapest catalog in the app after hanime1's built-in
/// dictionary. One shard per namespace.
///
/// Rows carry the site's SLUG as the name, because that is what the handler
/// resolves to a numeric id (`tag:` → `/gettagvideos?tagid=`); the numeric id
/// travels along as `sourceId`. A tag term is inserted bare, which the
/// handler upgrades to the tag feed by itself; an act keeps its `action:`
/// prefix, which is the only spelling that reaches `/getactionvideos`.
class TikPornTagCatalog extends TagCatalogSource {
  TikPornTagCatalog(this.handler);

  final TikPornHandler handler;

  static const String tagKey = 'tag';
  static const String actionKey = 'action';

  /// Nothing is fetched per shard beyond the two lists the handler loads.
  @override
  Duration get shardDelay => Duration.zero;

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: tagKey, label: 'Tags', type: TagType.none, shards: 1),
    TagCatalogNamespace(key: actionKey, label: 'Acts', type: TagType.none, shards: 1),
  ];

  /// A bare tag is enough: the handler recognises a known tag word and opens
  /// its feed. An act must say so, or it would be read as a tag first.
  @override
  String searchTerm(BooruTagEntry e) => e.namespace == actionKey ? '$actionKey:${e.name}' : e.name;

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard != 0 || namespaceFor(namespace) == null) return null;
    await handler.loadVocabularyForCatalog();
    final Map<String, int> source = namespace == actionKey
        ? TikPornHandler.actionIdsForCatalog
        : TikPornHandler.tagIdsForCatalog;
    if (source.isEmpty) {
      throw Exception('tik.porn did not answer with its ${namespace == actionKey ? 'act' : 'tag'} list');
    }
    return [
      for (final MapEntry<String, int> e in source.entries)
        BooruTagEntry(name: e.key, tagType: TagType.none, namespace: namespace, sourceId: e.value.toString()),
    ];
  }

  @visibleForTesting
  static const String tagListPath = '/gettaglist';
  @visibleForTesting
  static const String actionListPath = '/getactionlist';
}
