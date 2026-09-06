import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';

/// A source-specific picker for one namespace: opened in place of the
/// generic list sheet, returns the term to insert (null = nothing picked).
typedef TagCatalogPicker = Future<String?> Function(BuildContext context, Booru booru);

/// One namespace a source can list in full: the chip in the tag builder.
class TagCatalogNamespace {
  const TagCatalogNamespace({
    required this.key,
    required this.label,
    required this.type,
    this.shards,
    this.maxShards,
    this.customPicker,
    this.byType = false,
  });

  /// When set, the chip opens this instead of the generic picker (kemono's
  /// Artists page: 108,000 names want banners and a service filter).
  final TagCatalogPicker? customPicker;

  /// The source's own key: `artist`, `circle`, `female`, `tag`, …
  final String key;
  final String label;

  /// The app-level type the namespace collapses to (chip colour).
  final TagType type;

  /// How many shards make up the full list when known (hitomi: 27 letter
  /// pages, schale: 1 dump). Null = walk until the source says there is no
  /// such shard (asmhentai's `?page=N`).
  final int? shards;

  /// Cap for an open-ended walk, so a site with 258 pages of artists cannot
  /// swallow the phone; the walk resumes from here on the next pull.
  final int? maxShards;

  /// True when the rows of this namespace are the snapshot rows whose
  /// `tagType` is [type] and whose namespace column is EMPTY â€” how classic
  /// boorus store their tag database (the tag browser, `genTagObjects` and
  /// snapshot import all write that shape), so the chips light up on any
  /// list already pulled. Doujin and kemono sources file rows under the
  /// site's own namespace instead and leave this false.
  final bool byType;
}

/// A source's tag INDEX: every tag of a namespace, fetched a shard at a time
/// into [BooruTagStore] under the source's host. Per-source implementations
/// live beside their handlers (schale_tag_catalog.dart, …) and are reached
/// through `BooruHandler.tagCatalog`.
///
/// Offer a namespace only when BOTH hold: the site enumerates it, and the
/// handler's search accepts the term [searchTerm] produces for it. A chip
/// that lists tags the search then rejects is worse than no chip.
abstract class TagCatalogSource {
  List<TagCatalogNamespace> get namespaces;

  /// Pause between shards. Sites rate-limit sustained walks.
  Duration get shardDelay => const Duration(milliseconds: 350);

  /// True when one request feeds EVERY namespace (schale's single dump,
  /// nhentai's prefix walk). The puller then runs one job for the source,
  /// asks [shardAt] with an empty namespace, and every chip mirrors it.
  bool get sharedShards => false;

  /// Shard count of a shared walk; null = until [shardAt] returns null.
  int? get sharedShardCount => null;

  /// Cap for ONE pull of a namespace that declares no
  /// [TagCatalogNamespace.maxShards] â€” a shared walk, or the plain '' index
  /// walk the tag browser runs. The next pull continues from the resume
  /// point. Null = no cap.
  int? get maxShardsPerPull => null;

  /// The badge for a namespace whose rows live somewhere other than the tag
  /// snapshot (kemono's creator index). Null = count the snapshot.
  Future<int?> customCount(Booru booru, String namespace) async => null;

  /// The entries of one shard, each carrying its namespace. Null when the
  /// shard does not exist (past the last page) — an EMPTY list is a real,
  /// empty shard (a letter with no artists) and the walk continues.
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard);

  /// The term the handler's search accepts for a row: bare for plain tags,
  /// `namespace:name` otherwise. Overridden where a site wants the prefix on
  /// everything (hitomi) or nothing.
  String searchTerm(BooruTagEntry e) =>
      (e.namespace.isEmpty || e.namespace == 'tag') ? e.name : '${e.namespace}:${e.name}';

  TagCatalogNamespace? namespaceFor(String key) {
    for (final ns in namespaces) {
      if (ns.key == key) return ns;
    }
    return null;
  }

  static final RegExp _typed = RegExp(r'^([a-z_]+):(.*)$');

  /// Suggestions for a typed `namespace:partial` from the local catalog, or
  /// null when the input is not a catalogued namespace (the caller then
  /// falls back to the metatag's own autocomplete). Replaces the dead end
  /// where `artist:` inserted by a chip produced no suggestions at all.
  static Future<List<TagSuggestion>?> suggestFromCatalog(BooruHandler handler, Booru booru, String input) async {
    final TagCatalogSource? catalog = handler.tagCatalog;
    if (catalog == null) return null;
    final match = _typed.firstMatch(input.trim().toLowerCase());
    if (match == null) return null;
    final TagCatalogNamespace? ns = catalog.namespaceFor(match.group(1)!);
    if (ns == null) return null;
    final rows = await BooruTagStore.browseNamespace(booru, ns, query: match.group(2)!, limit: 25);
    return [
      for (final e in rows)
        TagSuggestion(tag: catalog.searchTerm(e), count: e.count, type: e.tagType),
    ];
  }
}
