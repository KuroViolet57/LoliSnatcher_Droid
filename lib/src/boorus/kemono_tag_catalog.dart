import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/pages/kemono_artists_page.dart';

/// kemono's tag builder: the site's global tag list (`/api/v1/posts/tags`,
/// 2,000 tags with counts, one shard) as the Tags chip, and the creator index
/// behind the Artists chip — which opens the Artists page, since a list of
/// 108,000 names wants banners, a service filter and a sort, not the
/// generic picker. On a creator tab a third chip lists that creator's own
/// tags live.
class KemonoTagCatalog extends TagCatalogSource {
  KemonoTagCatalog(this.handler);

  final KemonoHandler handler;

  static const String tagKey = 'tag';
  static const String creatorKey = 'creator';
  static const String creatorTagsKey = 'creator_tags';

  @override
  List<TagCatalogNamespace> get namespaces => [
    const TagCatalogNamespace(key: tagKey, label: 'Tags', type: TagType.none, shards: 1),
    const TagCatalogNamespace(
      key: creatorKey,
      label: 'Artists',
      type: TagType.artist,
      shards: 0,
      customPicker: KemonoArtistsPage.pick,
    ),
    if (handler.currentCreator != null)
      const TagCatalogNamespace(
        key: creatorTagsKey,
        label: "This creator's tags",
        type: TagType.none,
        shards: 0,
        customPicker: KemonoCreatorTagsSheet.pick,
      ),
  ];

  @override
  Future<int?> customCount(Booru booru, String namespace) async =>
      namespace == creatorKey ? KemonoCreatorStore.instance.count() : null;

  /// Tags are always inserted qualified: a bare word is a text search on
  /// this site.
  @override
  String searchTerm(BooruTagEntry e) => e.namespace == creatorKey ? 'creator:${e.name}' : 'tag:${e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (namespace != tagKey || shard != 0) return null;
    final data = await KemonoApi.getJson('${KemonoApi.api}/posts/tags', booru: handler.booru);
    return parseTags(data);
  }

  @visibleForTesting
  static List<BooruTagEntry> parseTags(dynamic data) {
    final List rows = data is List ? data : (data is Map && data['tags'] is List ? data['tags'] as List : const []);
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final row in rows) {
      if (row is! Map) continue;
      final String name = normalizeDoujinTagName(row['tag']?.toString() ?? '');
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(
        BooruTagEntry(
          name: name,
          namespace: tagKey,
          tagType: TagType.none,
          count: int.tryParse(row['post_count']?.toString() ?? '') ?? 0,
        ),
      );
    }
    return out;
  }
}
