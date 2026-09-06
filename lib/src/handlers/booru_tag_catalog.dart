import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The tag builder for a classic booru: the site's tag categories as
/// namespaces (Artists, Characters, Copyrights, Species, Meta, Tags), each
/// read BY TYPE from the snapshot rows the family's [TagIndexSource] already
/// writes with no namespace — so a list pulled through the tag browser feeds
/// the chips, and the other way round.
///
/// Two kinds of walk. A family whose site lists one category at a time
/// (danbooru, e621, moebooru, sankaku, philomena) runs one job per chip
/// through [TagIndexSource.categoryPageAt]. The gelbooru family cannot filter
/// its list by type, so one shared walk of the count-ordered list
/// ([TagIndexSource.catalogPageAt]) feeds every chip; the tag browser's
/// "Pull tag index" is that same walk under the '' namespace.
class BooruTagCatalog extends TagCatalogSource {
  /// Prefer [forHandler]; this is for a test's fake index.
  BooruTagCatalog(this.handler, this.source);

  final BooruHandler handler;
  final TagIndexSource source;

  /// The catalog for [handler]'s booru, or null: no index for the family, a
  /// site profile that says its tags are not a tag database, or a family
  /// that lists nothing.
  static TagCatalogSource? forHandler(BooruHandler handler) {
    if (handler.siteProfile?.hasTagCatalog == false) return null;
    final TagIndexSource? source = TagIndexSource.forBooru(handler.booru);
    if (source == null || source.catalogNamespaces(handler.booru).isEmpty) return null;
    return BooruTagCatalog(handler, source);
  }

  Booru get booru => handler.booru;

  @override
  late final List<TagCatalogNamespace> namespaces = source.catalogNamespaces(booru);

  @override
  bool get sharedShards => !source.walksByCategory;

  @override
  int? get maxShardsPerPull => source.catalogPagesPerPull;

  @override
  Duration get shardDelay => source.catalogDelay;

  // searchTerm: the inherited default. Rows carry no namespace, so the bare
  // name goes into the query — what every booru's search takes.

  /// Namespaces whose last page came back short: the next shard is the end,
  /// and it costs no request.
  final Set<String> _ended = {};

  /// Namespaces already reported for a category filter the site ignored.
  final Set<String> _warned = {};

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || shard >= source.maxIndexPages || _ended.contains(namespace)) return null;
    final Map<String, String> headers = handler.getHeaders();
    final TagCatalogNamespace? ns = namespace.isEmpty ? null : namespaceFor(namespace);
    final List<BooruTagEntry> got = ns == null
        ? await source.catalogPageAt(booru, shard, headers: headers)
        : await source.categoryPageAt(booru, ns.type, shard, headers: headers);
    if (got.isEmpty) {
      if (shard == 0) {
        throw Exception(
          '${BooruTagStore.keyFor(booru)} listed nothing for ${ns == null ? 'its tag index' : ns.label.toLowerCase()}',
        );
      }
      return null;
    }
    // A category page should be that category. A site that ignores the
    // filter still yields typed rows (the chips read by type), only slower;
    // say so once so a log shows it. The general walk on philomena mixes
    // every category on purpose.
    if (ns != null && ns.type != TagType.none && _warned.add(namespace)) {
      final int matching = got.where((e) => e.tagType == ns.type).length;
      if (matching * 2 < got.length) {
        Logger.Inst().log(
          '${BooruTagStore.keyFor(booru)} ignored the ${ns.key} category filter: $matching of ${got.length} rows match',
          'BooruTagCatalog',
          'shardAt',
          LogTypes.booruHandlerInfo,
        );
      } else {
        _warned.remove(namespace);
      }
    }
    if (source.lastPage(booru, got)) _ended.add(namespace);
    return got;
  }
}
