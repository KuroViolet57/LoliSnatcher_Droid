import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/hidden_by_filters.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r85: "Remove favourited items" and "Remove snatched items" are for the
/// sites' feeds. In your own lists - Downloads, Favourites, Collections,
/// History - they hid what the list is for: with the first one on, the
/// Downloads tab hid every download that is also a favourite, and showed
/// "Error, no results loaded" (log and screen recording of 2026-10-02).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  BooruItem item(String id, {bool favourite = false, bool snatched = false, List<String> tags = const ['solo']}) {
    final BooruItem i = BooruItem(
      fileURL: 'https://img.gelbooru.com/images/$id.png',
      sampleURL: 'https://img.gelbooru.com/samples/$id.png',
      thumbnailURL: 'https://img.gelbooru.com/thumbs/$id.png',
      tagsList: [for (final t in tags) Tag(t)],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$id',
      serverId: id,
    );
    i.isFavourite.value = favourite;
    i.isSnatched.value = snatched;
    return i;
  }

  BooruHandler handlerFor(BooruType type) {
    final Booru booru = Booru(type.name, type, '', type == BooruType.Gelbooru ? 'https://gelbooru.com' : '', '');
    return BooruHandlerFactory().getBooruHandler([booru], 20).booruHandler;
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('own_lists_filters_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SettingsHandler.instance
      ..filterFavourites = true
      ..filterSnatched = true;
  });

  tearDown(() {
    SettingsHandler.instance
      ..filterFavourites = false
      ..filterSnatched = false
      ..filterHated = false;
    SettingsHandler.instance.hiddenTags.clear();
    SettingsHandler.instance.invalidateBlacklistCache();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final BooruType type in [BooruType.Downloads, BooruType.Favourites, BooruType.Collections, BooruType.History]) {
    test('${type.name}: favourited and downloaded posts stay in your own list', () {
      final BooruHandler handler = handlerFor(type);
      handler.fetched.addAll([
        item('1', favourite: true, snatched: true),
        item('2', favourite: true),
        item('3', snatched: true),
      ]);
      handler.filterFetched();
      expect(handler.filteredFetched.map((i) => i.serverId), ['1', '2', '3']);
      expect(handler.hiddenBy, isEmpty);
    });
  }

  test('a site feed still removes favourited and downloaded posts, and says how many', () {
    final BooruHandler handler = handlerFor(BooruType.Gelbooru);
    handler.fetched.addAll([
      item('1', favourite: true),
      item('2', favourite: true, snatched: true),
      item('3', snatched: true),
      item('4'),
    ]);
    handler.filterFetched();
    expect(handler.filteredFetched.map((i) => i.serverId), ['4']);
    expect(handler.hiddenBy, {HiddenReason.favourited: 2, HiddenReason.snatched: 1});
  });

  test('hidden tags still apply in your own lists, and are counted', () {
    SettingsHandler.instance
      ..filterHated = true
      ..hiddenTags.add('gore');
    SettingsHandler.instance.invalidateBlacklistCache();
    final BooruHandler handler = handlerFor(BooruType.Downloads);
    handler.fetched.addAll([
      item('1', snatched: true, tags: ['gore']),
      item('2', snatched: true, favourite: true),
    ]);
    handler.filterFetched();
    expect(handler.filteredFetched.map((i) => i.serverId), ['2']);
    expect(handler.hiddenBy, {HiddenReason.hiddenTags: 1});
  });

  test('the counts start over at every filter pass', () {
    final BooruHandler handler = handlerFor(BooruType.Gelbooru);
    handler.fetched.add(item('1', favourite: true));
    handler.filterFetched();
    expect(handler.hiddenBy, {HiddenReason.favourited: 1});
    SettingsHandler.instance.filterFavourites = false;
    handler.filterFetched();
    expect(handler.hiddenBy, isEmpty);
  });

  test('the summary names the biggest reason first, in plain words', () {
    expect(HiddenByFilters.summary({}), '');
    expect(
      HiddenByFilters.summary({HiddenReason.hiddenTags: 6, HiddenReason.favourited: 14}),
      '14 favourited, 6 with hidden tags',
    );
    expect(HiddenByFilters.summary({HiddenReason.snatched: 1, HiddenReason.ai: 2}), '2 AI, 1 downloaded');
    expect(HiddenByFilters.title(20), 'Everything loaded (20) is hidden by your filters');
  });
}
