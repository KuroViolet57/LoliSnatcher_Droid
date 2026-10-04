import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' show parseFragment;

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/sankaku_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_tag.dart';
import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/sources/framework/tags/tag_catalog_source.dart';
import 'package:lolisnatcher/core/network/dio_network.dart';
import 'package:lolisnatcher/core/utils/tools.dart';

part 'tag_index_source/gelbooru_tag_index.dart';
part 'tag_index_source/danbooru_tag_index.dart';
part 'tag_index_source/e621_tag_index.dart';
part 'tag_index_source/philomena_tag_index.dart';
part 'tag_index_source/moebooru_tag_index.dart';
part 'tag_index_source/sankaku_tag_index.dart';

/// How a booru exposes its **tag database** (as opposed to its posts).
///
/// Three things are wanted from a site, and sites differ on all three:
///   * [pageAt]  — walk the whole index, to build a local snapshot;
///   * [search]  — substring lookup, so the browser can find a tag the
///                 snapshot doesn't have yet;
///   * [exact]   — one authoritative row for one tag name, which is how a
///                 tag's type gets *corrected* rather than guessed.
///
/// A fourth, for the search editor's tag builder: the site's tag categories
/// as namespaces ([catalogNamespaces]), walked one category at a time where
/// the site can ([categoryPageAt]) or as one count-ordered list otherwise
/// ([catalogPageAt]). Rows always land in the snapshot with no namespace and
/// the category as their type, which is how the chips read them back
/// ([TagCatalogNamespace.byType]).
///
/// Everything here was verified against the live APIs. Notable results:
///   * Gelbooru-0.2 (`page=dapi&s=tag&q=index`) honours `name=` (exact, one
///     row) and `name_pattern=%x%` (SQL LIKE), ignores `names=` entirely, and
///     ignores `json=1` on rule34.xxx — it always answers XML. It also
///     ignores `orderby=count`, so its index comes out in id order, and it
///     cannot filter by type at all.
///   * Danbooru/e621 (`/tags.json`) *do* honour `search[order]=count` and
///     `search[category]`, so their snapshots arrive most-used-first, one
///     category at a time. Moebooru (`/tag.json?order=count&type=`) and
///     sankaku (`/tags?order=count&type=`) do the same (2026-09-06).
///   * Philomena has no artist category: artists are `origin` tags named
///     `artist:…`, and general tags have no category at all.
abstract class TagIndexSource {
  const TagIndexSource();

  /// Rows per [pageAt] request.
  int get pageSize;

  /// How deep a full-index pull is allowed to go. Nobody wants a site's
  /// entire tag database on a phone; the point is the useful end of it.
  int get maxIndexPages => 60;

  /// Whether [pageAt] returns the most-used tags first. When false, walking
  /// the index is a slog through whatever internal order the site uses.
  bool get orderedByCount => false;

  /// One page of the full tag index. [page] is 0-based.
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page);

  /// Substring search against the site's tag database.
  Future<List<BooruTagEntry>> search(Booru booru, String query);

  /// The single authoritative row for [name], or null when the site has no
  /// such tag. Null return from an *unsupported* site is indistinguishable
  /// from a miss on purpose — callers only ever use it to fill in a blank.
  Future<BooruTagEntry?> exact(Booru booru, String name);

  //
  // The tag builder's view of the family
  //

  /// The namespaces the search editor's tag builder offers for this family:
  /// the site's tag categories, each read by type from the snapshot
  /// ([TagCatalogNamespace.byType]). Empty = no builder for this family.
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) => const [];

  /// True when the site lists ONE category at a time ([categoryPageAt]);
  /// false when the whole index is walked once, most-used first, and every
  /// chip reads its own type out of it ([catalogPageAt]).
  bool get walksByCategory => false;

  /// One page of the whole index, most-used first — the shared walk, and the
  /// tag browser's pull. Defaults to [pageAt].
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      pageAt(booru, page);

  /// One page of ONE category, most-used first; empty past the end.
  Future<List<BooruTagEntry>> categoryPageAt(
    Booru booru,
    TagType type,
    int page, {
    Map<String, String>? headers,
  }) async => const [];

  /// Pages one pull of the builder fetches before it stops and waits for
  /// "Pull more" — a tap should finish well under a minute at [catalogDelay].
  int get catalogPagesPerPull => maxIndexPages;

  /// Pause between the builder's pages. Sites rate-limit sustained walks.
  Duration get catalogDelay => const Duration(milliseconds: 350);

  /// Rows one builder page holds for [booru] — some families take a bigger
  /// page than [pageAt] uses, and some sites render more than others.
  int pageSizeFor(Booru booru) => pageSize;

  /// Whether [rows] was the last page of a walk, so the next one need not be
  /// asked for. A page short of [pageSizeFor] is the end on every API.
  bool lastPage(Booru booru, List<BooruTagEntry> rows) => rows.length < pageSizeFor(booru);

  /// The order chips are offered in.
  static const List<TagType> catalogOrder = [
    TagType.artist,
    TagType.contributor,
    TagType.character,
    TagType.copyright,
    TagType.species,
    TagType.meta,
    TagType.lore,
    TagType.none,
  ];

  /// The builder chip for a type. Key and label follow the doujin catalogs'
  /// convention (`artist`, `character`, …, `tag` for the general ones), so a
  /// typed `artist:x` reaches the same autocomplete.
  static TagCatalogNamespace typeNamespace(TagType type, {int? maxShards}) {
    final (String key, String label) = switch (type) {
      TagType.artist => ('artist', 'Artists'),
      TagType.character => ('character', 'Characters'),
      TagType.copyright => ('copyright', 'Copyrights'),
      TagType.species => ('species', 'Species'),
      TagType.meta => ('meta', 'Meta'),
      TagType.contributor => ('contributor', 'Contributors'),
      TagType.lore => ('lore', 'Lore'),
      TagType.none => ('tag', 'Tags'),
    };
    return TagCatalogNamespace(key: key, label: label, type: type, maxShards: maxShards, byType: true);
  }

  /// The chips for [types], in [catalogOrder].
  static List<TagCatalogNamespace> namespacesFor(Iterable<TagType> types, {int? maxShards}) => [
    for (final type in catalogOrder)
      if (types.contains(type)) typeNamespace(type, maxShards: maxShards),
  ];

  static final Map<String, Map<String, TagType>> _typeMaps = {};

  /// The family's raw-type → [TagType] numbering, read off the booru's own
  /// handler so there is exactly one copy of it — built once per booru, not
  /// once per row (a page carries up to a thousand).
  static Map<String, TagType> typeMapFor(Booru booru) {
    final String key = '${booru.type?.name}|${hostOf(booru)}';
    return _typeMaps.putIfAbsent(key, () {
      try {
        return Map<String, TagType>.unmodifiable(
          BooruHandlerFactory().getBooruHandler([booru], null).booruHandler.tagTypeMap,
        );
      } catch (_) {
        return const {};
      }
    });
  }

  /// Maps a site's raw type value onto the app's [TagType].
  static TagType typeFor(Booru booru, String raw) =>
      raw.isEmpty ? TagType.none : (typeMapFor(booru)[raw] ?? TagType.none);

  /// Host without `www.`: the key of anything remembered per site.
  static String hostOf(Booru booru) =>
      (Uri.tryParse(booru.baseURL ?? '')?.host ?? '').replaceFirst('www.', '').toLowerCase();

  @visibleForTesting
  static void resetForTests() {
    _typeMaps.clear();
    GelbooruTagIndex.resetForTests();
  }

  static TagIndexSource? forBooru(Booru? booru) {
    if (booru?.type == null || (booru!.baseURL?.isEmpty ?? true)) return null;
    return switch (booru.type!) {
      BooruType.Gelbooru || BooruType.GelbooruAlike || BooruType.Realbooru => const GelbooruTagIndex(),
      BooruType.Danbooru => const DanbooruTagIndex(),
      BooruType.e621 => const E621TagIndex(),
      BooruType.Philomena => const PhilomenaTagIndex(),
      BooruType.Moebooru => const MoebooruTagIndex(),
      BooruType.Sankaku => const SankakuTagIndex(),
      _ => null,
    };
  }

  static bool supports(Booru? booru) => forBooru(booru) != null;
}
