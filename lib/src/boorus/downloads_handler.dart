import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/hidden_by_filters.dart';

import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/download_folders.dart';
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

  /// r82: why the Downloads tab is empty when the database has downloads
  /// but none of their files is found.
  static String missingNote(int rows, {required int earlier}) {
    final String elsewhere = earlier == 0 ? '' : (earlier == 1 ? ' or the earlier folder' : ' or the $earlier earlier folders');
    return 'None of your $rows most recent downloads has its file in the download folder$elsewhere. '
        'If you changed the download folder, add the one you used before: Settings → Save & cache → Earlier download folders.';
  }

  /// r85: the list ends where the database runs out of rows - not where a
  /// page's rows all lack their file (before, that page ended the list).
  static bool reachedEnd({required int rows, required int limit}) => rows < limit;

  /// r85: how many downloads were looked for without a file while nothing
  /// was listed yet. The empty list's note counts them all, and keeps them
  /// when the database's last page is empty; a find or a new search ends it.
  static int checkedWithoutFile({
    required int before,
    required int pageNum,
    required int rows,
    required int present,
    required int listedBefore,
  }) {
    if (present > 0 || listedBefore > 0) return 0;
    return (pageNum == 0 ? 0 : before) + rows;
  }

  int _withoutFile = 0;

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
    int rowsRead = -1;
    try {
      final List<BooruItem> rows = await SettingsHandler.instance.dbHandler.searchDB(
        tags,
        (pageNum * limit).toString(),
        limit.toString(),
        isDownloads: true,
        customConditions: doujinExclusionConditions(),
      );
      rowsRead = rows.length;
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
      // r82: a list whose files are all somewhere else says so. r85: over
      // every page read so far - the pages after the first are read at once.
      _withoutFile = checkedWithoutFile(
        before: _withoutFile,
        pageNum: pageNum,
        rows: rows.length,
        present: r.present.length,
        listedBefore: length,
      );
      emptyNote = _withoutFile > 0 ? missingNote(_withoutFile, earlier: DownloadFolders.earlier.length) : null;
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

    // r85: what the filters left of the list, so a log says why it looks empty.
    final String hidden = HiddenByFilters.summary(hiddenBy);
    if (hidden.isNotEmpty) {
      Logger.Inst().log(
        'downloads: ${filteredFetched.length} of ${fetched.length} listed show; hidden by filters: $hidden',
        'DownloadsHandler',
        'search',
        LogTypes.booruHandlerInfo,
      );
    }

    if (rowsRead >= 0 && reachedEnd(rows: rowsRead, limit: limit)) {
      Logger.Inst().log(
        'downloads: the end of the list (page $pageNum, ${fetched.length} listed)',
        'DownloadsHandler',
        'search',
        LogTypes.booruHandlerInfo,
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
