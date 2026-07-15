import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Virtual booru that browses saved-post collections from the local DB.
///
/// Mirrors `FavouritesHandler` but filters by collection membership instead of
/// the favourite flag. A `collection:<id>` term in the query selects a single
/// album; without it the feed spans every collection. Any remaining terms are
/// normal in-collection tag search (AND / OR / exclude / wildcards / site:),
/// handled by the shared `DatabaseHandler.searchDB` engine.
class CollectionsHandler extends BooruHandler {
  CollectionsHandler(super.booru, super.limit);

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasNativeOrSupport => false;

  // Local DB search has no OR groups — drop them with a warning, search rest.
  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String validateTags(String tags) => tags;

  // -1 => browse across all collections; otherwise a single collection id.
  ({int collectionId, String tags}) _split(String input) {
    int collectionId = -1;
    final List<String> rest = [];
    for (final term in input.split(' ').where((t) => t.isNotEmpty)) {
      if (term.toLowerCase().startsWith('collection:')) {
        final parsed = int.tryParse(term.substring('collection:'.length));
        if (parsed != null) collectionId = parsed;
      } else {
        rest.add(term);
      }
    }
    return (collectionId: collectionId, tags: rest.join(' '));
  }

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    tags = validateTags(translateOrSyntax(tags.trim()));

    if (prevTags != tags) {
      fetched.value = [];
      totalCount.value = 0;
    }

    final int length = fetched.length;
    final parts = _split(tags);

    final List<BooruItem> newItems = [];
    try {
      newItems.addAll(
        await SettingsHandler.instance.dbHandler.searchDB(
          parts.tags,
          (pageNum * limit).toString(),
          limit.toString(),
          collectionId: parts.collectionId,
        ),
      );
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'CollectionsHandler',
        'search',
        LogTypes.booruHandlerInfo,
        s: s,
      );
      errorString = 'DATABASE ERROR: $e';
      locked = true;
    }

    await afterParseResponse(newItems);
    prevTags = tags;

    if (fetched.isEmpty || fetched.length == length) {
      locked = true;
    }

    return fetched;
  }

  @override
  Future<void> searchCount(String input) async {
    final parts = _split(validateTags(translateOrSyntax(input.trim())));
    totalCount.value = await SettingsHandler.instance.dbHandler.searchDBCount(
      parts.tags,
      collectionId: parts.collectionId,
    );
    return;
  }

  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    try {
      final tagsWithCount = await SettingsHandler.instance.dbHandler.getTagsByUsageCount(
        input.isEmpty ? null : input,
        limit,
      );
      final List<TagSuggestion> tags = tagsWithCount
          .where((t) => t.name.trim().isNotEmpty)
          .map((t) => TagSuggestion(tag: t.name, count: t.count))
          .toList();
      return Right(tags);
    } catch (e, s) {
      return Left(
        ResponseError(
          message: 'getTagSuggestions error',
          error: e,
          stackTrace: s,
        ),
      );
    }
  }

  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        values: [
          MetaTagValue(name: 'Random', value: 'random'),
          MetaTagValue(name: 'Reverse', value: 'reverse'),
        ],
      ),
    ];
  }
}
