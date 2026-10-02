import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Virtual booru over the viewing history (ViewedPost table): every post the
/// user actually opened in the viewer, newest first. Search text filters the
/// stored items (each term must match somewhere in the item's tags/URLs).
///
/// Opened from the left drawer's Quick access section.
class HistoryHandler extends BooruHandler {
  HistoryHandler(super.booru, super.limit);

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String validateTags(String tags) => tags;

  @override
  List<MetaTag> availableMetaTags() => [];

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    tags = tags.trim();

    if (prevTags != tags) {
      fetched.value = [];
      totalCount.value = 0;
    }

    // Items already carry their tags; nothing to fetch through this handler.
    storeTagsGlobally = false;

    final int length = fetched.length;

    final List<BooruItem> newItems = [];
    try {
      newItems.addAll(
        await SettingsHandler.instance.dbHandler.getViewedPosts(
          tags,
          pageNum * limit,
          limit,
        ),
      );
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'HistoryHandler',
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
    try {
      totalCount.value = await SettingsHandler.instance.dbHandler.countViewedPosts(input.trim());
    } catch (_) {
      totalCount.value = 0;
    }
  }
}
