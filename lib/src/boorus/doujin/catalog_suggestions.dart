import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// Autocomplete from the source's own tag lists (r70 parity sweep).
///
/// Sites without a suggest endpoint (hitomi, asmhentai, hentaipaw, hentalk)
/// used to have no autocomplete at all, though every one of them has a Tag
/// builder whose lists sit in the local tag store once pulled. The search
/// box now answers from those rows, spelled the way the handler's search
/// wants them ([TagCatalogSource.searchTerm]). Before a pull the list is
/// empty - the chips' download button fills it.
mixin CatalogSuggestions on BooruHandler {
  @override
  bool get hasTagSuggestions => true;

  /// Rows of the local store as suggestions, in the catalog's search terms.
  static List<TagSuggestion> suggestionsFrom(TagCatalogSource catalog, Iterable<BooruTagEntry> rows) => [
    for (final BooruTagEntry e in rows) TagSuggestion(tag: catalog.searchTerm(e), count: e.count, type: e.tagType),
  ];

  /// `namespace:partial` splits into the store's namespace column and the
  /// name; a bare word searches every namespace.
  static ({String? namespace, String query}) splitInput(String input) {
    final String q = input.trim().replaceFirst(RegExp(r'^-'), '');
    final int colon = q.indexOf(':');
    if (colon <= 0) return (namespace: null, query: q.replaceAll(' ', '_'));
    return (namespace: q.substring(0, colon).toLowerCase(), query: q.substring(colon + 1).replaceAll(' ', '_'));
  }

  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(String input, {CancelToken? cancelToken}) async {
    final TagCatalogSource? catalog = tagCatalog;
    final ({String? namespace, String query}) split = splitInput(input);
    if (catalog == null || split.query.isEmpty) return const Right([]);
    try {
      final List<BooruTagEntry> rows = await BooruTagStore.browse(booru, query: split.query, namespace: split.namespace, limit: 25);
      // Nothing pulled yet is not "no such tag": the alias resolver would
      // record a miss for the day. Say so instead.
      if (rows.isEmpty && await BooruTagStore.snapshotSize(booru) == 0) {
        return const Left(ResponseError(message: 'no tag lists pulled yet: open the Tag builder and pull one'));
      }
      return Right(suggestionsFrom(catalog, rows));
    } catch (e) {
      return Left(ResponseError(message: 'catalog suggestions failed', error: e));
    }
  }
}
