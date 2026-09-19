import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r44: e621 first. Its posts carry nine tag groups; the app read six and
/// dropped contributor (the modelers of an animation), lore and invalid. The
/// cheatsheet's choosable options become filters, its text and number
/// metatags builders; the tag builder lists contributors and lore too. And the
/// blur of a hidden post follows the same source rules as its removal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru e621() => Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('e621_r44');
    final SettingsHandler s = SettingsHandler.instance;
    s.path = '${tempDir.path}${Platform.pathSeparator}';
    s.hiddenTags.clear();
    s.hiddenTagsPerBooru.clear();
    s.filterHated = false;
    s.invalidateBlacklistCache();
  });

  tearDown(() {
    final SettingsHandler s = SettingsHandler.instance;
    s.hiddenTags.clear();
    s.hiddenTagsPerBooru.clear();
    s.invalidateBlacklistCache();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('contributors and lore', () {
    test('an e621 post keeps its contributor, lore and invalid tags, each typed', () async {
      final Map<String, dynamic> post =
          (jsonDecode(File('test/fixtures/e621_post_contributor.json').readAsStringSync())['posts'] as List).first as Map<String, dynamic>;
      final List<String> contributors = (post['tags']['contributor'] as List).cast<String>();
      final List<String> artists = (post['tags']['artist'] as List).cast<String>();
      expect(contributors, isNotEmpty, reason: 'the fixture is a post with modelers');
      final e621Handler h = e621Handler(e621(), 20);
      final BooruItem item = h.parseItemFromResponse(post, 0)!;
      final List<String> names = item.tagsList.map((t) => t.fullString).toList();
      expect(names, containsAll(contributors));
      // The types are written to the tag store asynchronously.
      await pumpEventQueue();
      for (final String c in contributors) {
        expect(TagHandler.instance.getTag(c).tagType, TagType.contributor, reason: c);
      }
      if (artists.isNotEmpty) expect(names.indexOf(contributors.first), greaterThan(names.indexOf(artists.first)));
    });

    test('the new types: names, colours, the tag builder order, the e621 category codes', () {
      expect(TagType.fromString('contributor'), TagType.contributor);
      expect(TagType.fromString('lore'), TagType.lore);
      expect(TagType.contributor.getColour(), isNotNull);
      expect(TagType.lore.getColour(), isNotNull);
      expect(TagIndexSource.catalogOrder.indexOf(TagType.contributor), TagIndexSource.catalogOrder.indexOf(TagType.artist) + 1);
      expect(E621TagIndex.categoryCodes[TagType.contributor], '2');
      expect(E621TagIndex.categoryCodes[TagType.lore], '8');
      expect(const E621TagIndex().categoryQuery(TagType.contributor, 0), contains('search[category]=2'));
      final e621Handler h = e621Handler(e621(), 20);
      expect(h.tagTypeMap['2'], TagType.contributor);
      expect(h.tagTypeMap['8'], TagType.lore);
      expect(h.tagCatalog!.namespaces.map((n) => n.key), containsAll(['contributor', 'lore']));
    });
  });

  group("the cheatsheet's search options", () {
    test('every choosable option is a filter group, each starting at the site default', () {
      final DoujinFilterSpec spec = e621Handler(e621(), 20).doujinFilters;
      expect(
        spec.groups.map((g) => g.key),
        containsAll([
          'order',
          'rating',
          'type',
          'status',
          'date',
          'score',
          'favcount',
          'duration',
          'ischild',
          'isparent',
          'inpool',
          'hassource',
          'hasdescription',
          'artverified',
        ]),
      );
      expect(spec.group('order')!.options.map((o) => o.value), containsAll(['', 'score', 'favcount', 'hot', 'random', 'duration', 'comment_count']));
      expect(spec.group('rating')!.options.map((o) => o.value), ['', 's', 'q', 'e']);
      expect(spec.group('type')!.options.map((o) => o.value), containsAll(['webm', 'mp4', 'gif', 'swf']));
      for (final DoujinFilterGroup g in spec.groups) {
        expect(g.multi, isFalse, reason: '${g.key}: e621 ANDs repeated metatags');
        expect(g.options.first.value, '', reason: '${g.key} starts at the site default');
      }
      expect(DoujinFilters.apply('fox', 'score', ['>=100']), 'fox score:>=100');
      expect(DoujinFilters.selected('fox score:>=100', 'score'), ['>=100']);
    });

    test('the text and number metatags are builders in the search window', () {
      final List<String> keys = e621Handler(e621(), 20).availableMetaTags().map((m) => m.keyName).toList();
      expect(
        keys,
        containsAll(['user', 'fav', 'pool', 'set', 'source', 'description', 'note', 'score', 'favcount', 'duration', 'width', 'height', 'randseed']),
      );
    });
  });

  group('the blur follows the source blacklist rules (the FurAffinity report)', () {
    BooruItem item(String tag) =>
        BooruItem(fileURL: 'https://x.invalid/$tag.jpg', sampleURL: '', thumbnailURL: '', tagsList: [Tag(tag)], postURL: 'https://x.invalid/$tag');

    test("a source that ignores the global blacklist does not blur what only the global list hides; its own list still does", () {
      final SettingsHandler s = SettingsHandler.instance;
      s.hiddenTags.add('cat');
      s.invalidateBlacklistCache();
      final Booru booru = e621()..ignoreGlobalBlacklist = true;
      s.addTagToBooruHiddenList(booru.name!, 'dog');
      final e621Handler h = e621Handler(booru, 20);
      final BooruItem cat = item('cat');
      final BooruItem dog = item('dog');
      h.fetched.addAll([cat, dog]);
      h.filterFetched();
      expect(cat.isHidden, isFalse, reason: 'only the global list hides it, and this source ignores that list');
      expect(dog.isHidden, isTrue, reason: "the source's own list");
      booru.ignoreGlobalBlacklist = false;
      h.filterFetched();
      expect(cat.isHidden, isTrue, reason: 'the global list applies again');
    });
  });
}
