import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 2, item 10: bookmarks ARE collection entries — auto-created
/// "Default" collection, last-used-for-bookmarking stickiness, and the
/// one-time legacy bookmarks.json merge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem doujinItem(String id) => BooruItem(
    fileURL: 'https://images.invalid/$id.png',
    sampleURL: 'https://images.invalid/$id.png',
    thumbnailURL: 'https://thumbs.invalid/$id.png',
    tagsList: [Tag('vanilla')],
    postURL: 'https://nhentai.net/g/$id/',
    serverId: id,
  )..description = 'Bookmark Doujin $id';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_bookmark_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    DoujinDataHandler.instance.resetForTests();
  });

  tearDown(() {
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('first bookmark auto-creates the "Default" collection and files the doujin there', () {
    final store = DoujinDataHandler.instance;
    final item = doujinItem('1001');
    expect(store.collections, isEmpty);

    final (bool bookmarked, collection) = store.toggleBookmark(item, nhentaiBooru());
    expect(bookmarked, isTrue);
    expect(collection!.name, 'Default');
    expect(store.collections.single.name, 'Default');
    expect(store.isInAnyCollection(item), isTrue);

    // toggling again removes it from collections
    final (bool again, _) = store.toggleBookmark(item, nhentaiBooru());
    expect(again, isFalse);
    expect(store.isInAnyCollection(item), isFalse);
    // the collection itself survives
    expect(store.collections.single.name, 'Default');
  });

  test('bookmarks follow the LAST collection used for bookmarking', () {
    final store = DoujinDataHandler.instance;
    final booru = nhentaiBooru();
    store.createCollection('First');
    final special = store.createCollection('Special');

    // explicit pick (what the long-press picker does) marks Special as last
    store.addToCollection(special, doujinItem('1'), booru);
    expect(store.lastBookmarkCollectionId, special.id);

    // a plain bookmark now lands in Special, not First
    final (_, target) = store.toggleBookmark(doujinItem('2'), booru);
    expect(target!.id, special.id);
  });

  test('falls back to the first existing collection when nothing was used yet', () {
    final store = DoujinDataHandler.instance;
    final first = store.createCollection('Only one');
    final (_, target) = store.toggleBookmark(doujinItem('3'), nhentaiBooru());
    expect(target!.id, first.id);
  });

  test('legacy bookmarks merge once into the bookmark collection', () {
    final store = DoujinDataHandler.instance;
    final legacy = [
      const DoujinEntry(
        postURL: 'https://nhentai.net/g/501/',
        serverId: '501',
        thumbnailURL: '',
        title: 'Old bookmark',
        booruHost: 'nhentai.net',
        addedAt: 123,
      ),
    ];
    store.mergeLegacyBookmarks(legacy);
    expect(store.collections.single.name, 'Default');
    expect(store.collections.single.items.single.serverId, '501');
    expect(store.legacyBookmarksMerged, isTrue);

    // running again (next startup) must not duplicate
    store.mergeLegacyBookmarks(legacy);
    expect(store.collections.single.items.length, 1);
  });

  test('merged flag round-trips through export/import', () {
    final store = DoujinDataHandler.instance;
    store.mergeLegacyBookmarks(const []);
    final exported = store.exportJson();
    store.resetForTests();
    expect(store.legacyBookmarksMerged, isFalse);
    store.importJson(exported);
    expect(store.legacyBookmarksMerged, isTrue);
  });
}
