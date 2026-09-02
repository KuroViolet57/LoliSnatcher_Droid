import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';

import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The MEDIA downloads feed: booru images and videos from store.db, each
/// checked against the download folder before it is listed. Doujins are a
/// different kind of object (a folder of pages) and have their own surface,
/// DoujinDownloadsPage, read from disk; their rows are excluded here.
class DownloadsHandler extends BooruHandler {
  DownloadsHandler(super.booru, super.limit);

  /// SQL keeping doujin galleries out of the media list, by post URL host —
  /// the known doujin hosts plus every configured doujin source's host.
  static List<String> doujinExclusionConditions() {
    final Set<String> hosts = {...DoujinDataHandler.knownDoujinHosts};
    try {
      for (final b in SettingsHandler.instance.booruList) {
        if (!DoujinDataHandler.isDoujinBooru(b)) continue;
        final String h = DoujinDataHandler.hostOf(b);
        if (h.isNotEmpty) hosts.add(h);
      }
    } catch (_) {}
    return [
      for (final h in hosts) "bi.postURL NOT LIKE '%://${h.replaceAll("'", "''")}/%'",
    ];
  }

  @override
  bool get hasTagSuggestions => true;

  @override
  String validateTags(String tags) {
    return tags;
  }

  // Local DB search has no OR — drop with a warning, search the rest.
  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  bool get hasNativeOrSupport => false;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    // set custom page number
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    // validate tags
    tags = validateTags(translateOrSyntax(tags.trim()));

    // if tags are different than previous tags, reset fetched
    if (prevTags != tags) {
      fetched.value = [];
      totalCount.value = 0;
    }

    // get amount of items before fetching
    final int length = fetched.length;

    final List<BooruItem> newItems = [];
    try {
      final List<BooruItem> rows = await SettingsHandler.instance.dbHandler.searchDB(
        tags,
        (pageNum * limit).toString(),
        limit.toString(),
        isDownloads: true,
        customConditions: doujinExclusionConditions(),
      );
      // The database says what was snatched; the folder says what is still
      // there. Rows without a file are held back (see DownloadsReconciler)
      // and can be forgotten from the downloads drawer, never dropped silently.
      final reconciler = DownloadsReconciler.instance;
      final r = await reconciler.check(rows);
      if (r.missing.isNotEmpty) {
        reconciler.missing.addAll(r.missing.where((m) => !reconciler.missing.any((x) => x.postURL == m.postURL)));
      }
      Logger.Inst().log(
        'downloads page $pageNum: ${rows.length} rows, ${r.present.length - r.unknown.length} with a file, '
        '${r.missing.length} missing on disk, ${r.unknown.length} unchecked (no matching booru)'
        '${reconciler.storageProblem != null ? ' — storage problem: ${reconciler.storageProblem}' : ''}',
        'DownloadsHandler',
        'search',
        LogTypes.booruHandlerInfo,
      );
      newItems.addAll(r.present);
    } catch (e, s) {
      Logger.Inst().log(
        'DB FAILED',
        'DownloadsHandler',
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
      Logger.Inst().log(
        'dbhandler dbLocked',
        'DownloadsHandler',
        'search',
        LogTypes.booruHandlerInfo,
        s: StackTrace.current,
      );
      locked = true;
    }

    return fetched;
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
  Future<void> searchCount(String input) async {
    totalCount.value = await SettingsHandler.instance.dbHandler.searchDBCount(
      input,
      isDownloads: true,
      customConditions: doujinExclusionConditions(),
    );
    return;
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
      LocalDbSiteMetaTag(),
    ];
  }
}
