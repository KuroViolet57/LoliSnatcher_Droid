import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/suggestion_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';

/// r76 (build 96): the Suggested strip's "open in new tab" gave the new tab
/// the placeholder word "suggestions", so the site was searched for that
/// tag. The new tab's query now carries what the strip's loader needs from
/// the post (`suggest: c:… f:… a:… t:… s:… post:…`), and a tab with such a
/// query builds the same loader. It survives a restart and stays out of
/// the search history.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru gelbooru = Booru('Gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    SettingsHandler.register();
    TagHandler.register();
    SearchHandler.register();
    SearchHandler.instance.tabs.clear();
    tempDir = Directory.systemTemp.createTempSync('suggestion_query');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    SettingsHandler.instance.booruList.value = [gelbooru, e621];
  });
  tearDown(() {
    SearchHandler.instance.tabs.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem booruPost() => BooruItem(
    fileURL: 'https://static1.e621.net/data/aa/bb/x.webm',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [
      Tag('meow_skulls', tagType: TagType.character),
      Tag('wild_card', tagType: TagType.character),
      Tag('fortnite', tagType: TagType.copyright),
      Tag('taanukic', tagType: TagType.artist),
      Tag('anthro', count: 900000),
      Tag('3d_(artwork)', count: 90000),
      Tag('blender_(software)', count: 40000),
      Tag('3d', count: 1000000),
      Tag('gun', count: 30000),
      Tag('neon_lights', count: 800),
      Tag('forest_at_night', count: 120),
      Tag('bandana', count: 5000),
      Tag('100%_orange juice', count: 60),
      Tag('sound_warning', count: 2000),
      Tag('webm', count: 700000),
      Tag('animated', count: 800000),
    ],
    postURL: 'https://e621.net/posts/5155223',
  );

  BooruItem doujinPost() => BooruItem(
    fileURL: 'https://nhentai.net/g/412345/',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [
      Tag('ganyu', tagType: TagType.character),
      Tag('genshin_impact', tagType: TagType.copyright),
      Tag('mizuryu_kei', tagType: TagType.artist),
      Tag('stockings'),
      Tag('sole_female'),
      Tag('horns'),
    ],
    postURL: 'https://nhentai.net/g/412345/',
  );

  List<String> facetsOf(BooruItem item, int seed) => [
    for (final f in SuggestionEngine.facetsForItem(item, seed: seed)) '${f.kind.name}|${f.query}|${f.quota}|${f.excludeCharacters}',
  ];

  test('the query carries the post, and the post rebuilt from it gives the same facets round after round (booru and doujin)', () {
    for (final BooruItem original in [booruPost(), doujinPost()]) {
      final String q = SuggestionHandler.queryFor(original);
      expect(q, startsWith('suggest: '));
      expect(q, contains('post:${original.postURL}'));
      expect(SuggestionHandler.isQuery(q), isTrue);
      final SuggestionHandler h = SuggestionHandler.fromQuery(gelbooru, 30, q)!;
      expect(h.sourceItem.postURL, original.postURL);
      for (int seed = 0; seed < 6; seed++) {
        expect(facetsOf(h.sourceItem, seed), facetsOf(original, seed), reason: '${original.postURL} round $seed');
      }
      expect(facetsOf(original, 0), isNotEmpty);
    }
    expect(SuggestionHandler.queryFor(booruPost()), contains('c:meow_skulls c:wild_card f:fortnite a:taanukic'));
  });

  test('tags with spaces or percent signs, the video filter and the chosen sources survive the round trip', () {
    final BooruItem post = BooruItem(
      fileURL: 'https://img.gelbooru.com/1.jpg',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: [Tag('foo bar', tagType: TagType.character), Tag('100%', tagType: TagType.artist), Tag('beach', count: 5)],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=7',
    );
    final String q = SuggestionHandler.queryFor(post, filter: 'animated|video', boorus: [gelbooru, e621]);
    expect(q, contains('with:animated|video'));
    expect(q, contains('on:Gelbooru'));
    expect(q, contains('on:e621'));
    final SuggestionHandler h = SuggestionHandler.fromQuery(e621, 30, q)!;
    expect(h.extraFilter, 'animated|video');
    expect(h.targetBoorus.map((b) => b.name).toList(), ['Gelbooru', 'e621']);
    expect(SuggestionEngine.tagsOfType(h.sourceItem, TagType.character), ['foo bar']);
    expect(SuggestionEngine.tagsOfType(h.sourceItem, TagType.artist), ['100%']);
    expect(h.sourceItem.postURL, 'https://gelbooru.com/index.php?page=post&s=view&id=7');
    // Without sources named, the tab's own booru is asked.
    expect(SuggestionHandler.fromQuery(e621, 30, SuggestionHandler.queryFor(post))!.targetBoorus.single.name, 'e621');
  });

  test('only a query that starts with the marker and names a post counts', () {
    expect(SuggestionHandler.isQuery('suggestions'), isFalse, reason: 'the old placeholder');
    expect(SuggestionHandler.isQuery('suggest: c:x'), isFalse, reason: 'no post');
    expect(SuggestionHandler.isQuery('cat suggest: post:https://x/1'), isFalse, reason: 'the marker must come first');
    expect(SuggestionHandler.isQuery('suggest: post:https://x/1'), isTrue);
    expect(SuggestionHandler.fromQuery(gelbooru, 30, 'cat_ears'), isNull);
  });

  test('a tab with such a query holds the suggestion loader for that post, also when rebuilt from a saved tab; a normal query does not', () {
    final String q = SuggestionHandler.queryFor(booruPost());
    final SearchTab tab = SearchTab(e621, null, q);
    expect(tab.booruHandler, isA<SuggestionHandler>());
    expect((tab.booruHandler as SuggestionHandler).sourceItem.postURL, 'https://e621.net/posts/5155223');
    expect(SearchTab(e621, null, 'meow_skulls').booruHandler, isNot(isA<SuggestionHandler>()));
    final String saved = jsonEncode([TabBackup(tags: q, booru: 'e621').toJson()]);
    final TabBackup restored = TabBackup.fromJsonList(saved).single;
    expect(restored.tags, q);
    expect(SearchTab(e621, null, restored.tags).booruHandler, isA<SuggestionHandler>());
  });

  test('the strip\'s new-tab query comes from the post it shows, not from the placeholder; other strips keep their tag', () {
    final BooruItem post = booruPost();
    expect(
      TagContentPreview.newTabQuery(effectiveTag: 'suggestions', suggestFor: post, filter: 'animated|video'),
      SuggestionHandler.queryFor(post, filter: 'animated|video'),
    );
    expect(TagContentPreview.newTabQuery(effectiveTag: 'taanukic'), 'taanukic');
  });

  test('suggestion queries stay out of the search history and are not counted as searches', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = SettingsHandler.instance.dbHandler;
    db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.updateTable();
    SettingsHandler.instance
      ..dbEnabled = true
      ..searchHistoryEnabled = true;
    final String q = SuggestionHandler.queryFor(booruPost());
    expect(SearchHandler.isPlainSearch(q), isFalse);
    expect(SearchHandler.isPlainSearch('cat_ears'), isTrue);
    SearchHandler.instance.addTabByString(q, customBooru: e621);
    SearchHandler.instance.addTabByString('cat_ears', customBooru: e621);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final List<String> history = (await db.getSearchHistory()).map((h) => h.searchText).toList();
    expect(history, contains('cat_ears'));
    expect(history, isNot(contains(q)));
    expect(SearchHandler.instance.tabs.map((t) => t.booruHandler.runtimeType.toString()), contains('SuggestionHandler'));
    await db.db?.close();
    db.db = null;
  });
}
