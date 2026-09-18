import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/board_query.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r73: how a board's description becomes booru tags. Words and word pairs
/// are looked up in the pulled tag lists of the chosen sources (exact names
/// first), then asked of the sites' suggestions, and the downloaded encoder
/// ranks the candidates by how close they read to the whole description.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name) => Booru(name, BooruType.Gelbooru, '', 'https://$name.example', '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('board_query');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    BoardQueryBuilder.resetForTests();
  });
  tearDown(() {
    BoardQueryBuilder.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('tokens: lowercase words without punctuation or stop words; pairs joined with an underscore', () {
    final List<String> words = BoardQueryBuilder.tokens('A blonde girl, with Cat ears; on the beach at sunset!');
    expect(words, ['blonde', 'girl', 'cat', 'ears', 'beach', 'sunset']);
    expect(BoardQueryBuilder.bigrams(words), ['blonde_girl', 'girl_cat', 'cat_ears', 'ears_beach', 'beach_sunset']);
    expect(BoardQueryBuilder.tokens(''), isEmpty);
    expect(BoardQueryBuilder.tokens('the and of'), isEmpty);
  });

  test('deriveTags: exact tag-list names first, then prefix matches, then site suggestions; seeds from an image outrank all', () async {
    final Map<String, List<String>> lists = {
      'blonde': ['blonde_hair', 'blonde'],
      'cat_ears': ['cat_ears'],
      'beach': ['beach', 'beach_umbrella'],
      'sunset': ['sunset'],
    };
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => [
      for (final String name in lists[query] ?? const <String>[]) BooruTagEntry(name: name, tagType: TagType.none, count: name.length),
    ];
    final List<String> asked = [];
    BoardQueryBuilder.siteSuggest = (handler, String word) async {
      asked.add(word);
      return word == 'girl' ? ['1girl', 'girl_on_top'] : <String>[];
    };
    final List<WeightedTag> tags = await BoardQueryBuilder.deriveTags(
      'blonde girl with cat ears on the beach at sunset',
      sources: [b('one')],
      seedTags: const ['sakamata_chloe'],
      limit: 6,
    );
    final List<String> names = tags.map((t) => t.tag).toList();
    expect(names.first, 'sakamata_chloe', reason: 'an image match is the strongest evidence');
    expect(names, containsAll(['cat_ears', 'beach', 'sunset', 'blonde']));
    expect(names.indexOf('cat_ears'), lessThan(names.indexOf('1girl')), reason: 'a list name beats a site suggestion');
    expect(names, hasLength(6));
    expect(asked, contains('girl'), reason: 'only words the lists do not know go to the site');
    expect(asked, isNot(contains('beach')));
    for (int i = 1; i < tags.length; i++) {
      expect(tags[i - 1].weight, greaterThanOrEqualTo(tags[i].weight));
    }
  });

  test('deriveTags: the encoder pulls the candidates that read like the description ahead of lexical ties', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => switch (query) {
      'red' => [BooruTagEntry(name: 'red_hair', tagType: TagType.none), BooruTagEntry(name: 'red_car', tagType: TagType.none)],
      _ => const <BooruTagEntry>[],
    };
    BoardQueryBuilder.siteSuggest = (handler, String word) async => const <String>[];
    // A toy encoder: the description and "red hair" point the same way, "red car" the other.
    Float32List vec(String text) => text.contains('car')
        ? Float32List.fromList([0, 1])
        : Float32List.fromList([1, 0]);
    BoardQueryBuilder.embed = (String text) async => vec(text);
    final List<WeightedTag> tags = await BoardQueryBuilder.deriveTags('red hair girl', sources: [b('one')], limit: 2);
    expect(tags.map((t) => t.tag).toList(), ['red_hair', 'red_car']);
    expect(tags.first.weight, greaterThan(tags.last.weight));
  });

  test('tokens: tilde and other punctuation split words; a prefix counts only at an underscore', () async {
    expect(BoardQueryBuilder.tokens('girl~ cat` dog'), ['girl', 'cat', 'dog']);
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'girl'
        ? [BooruTagEntry(name: 'girls_und_panzer', tagType: TagType.none), BooruTagEntry(name: 'girl_on_top', tagType: TagType.none)]
        : const [];
    BoardQueryBuilder.siteSuggest = (handler, String word) async => const <String>[];
    final List<WeightedTag> tags = await BoardQueryBuilder.deriveTags('girl', sources: [b('one')]);
    expect(tags.map((t) => t.tag).toList(), ['girl_on_top', 'girls_und_panzer']);
    expect(tags.first.weight, greaterThan(tags.last.weight), reason: 'girl_on_top is girl + a word; girls_und_panzer only contains it');
  });

  test('candidate tags are embedded in one batch when the encoder offers it', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'red'
        ? [BooruTagEntry(name: 'red_hair', tagType: TagType.none), BooruTagEntry(name: 'red_car', tagType: TagType.none)]
        : const [];
    BoardQueryBuilder.siteSuggest = (handler, String word) async => const <String>[];
    int batches = 0;
    BoardQueryBuilder.embed = (String text) async => Float32List.fromList([1, 0]);
    BoardQueryBuilder.embedMany = (List<String> texts) async {
      batches++;
      return [for (final String t in texts) Float32List.fromList(t.contains('car') ? [0, 1] : [1, 0])];
    };
    final List<WeightedTag> tags = await BoardQueryBuilder.deriveTags('red hair girl', sources: [b('one')], limit: 2);
    expect(batches, 1);
    expect(tags.map((t) => t.tag).toList(), ['red_hair', 'red_car']);
  });

  test('deriveTags: must-have and excluded tags never come back as derived ones; nothing known -> empty', () async {
    BoardQueryBuilder.storeLookup = (Booru booru, String query) async => query == 'animated' ? [BooruTagEntry(name: 'animated', tagType: TagType.none)] : const [];
    BoardQueryBuilder.siteSuggest = (handler, String word) async => const <String>[];
    final List<WeightedTag> tags = await BoardQueryBuilder.deriveTags('animated', sources: [b('one')], exclude: const {'animated'});
    expect(tags, isEmpty);
    expect(await BoardQueryBuilder.deriveTags('zzzz qqqq', sources: [b('one')]), isEmpty);
  });

  test('accepts: every must-have tag present (raw or the site spelling), no excluded tag; case-insensitive', () {
    BooruItem item(List<String> tags) => BooruItem(fileURL: 'f', sampleURL: 's', thumbnailURL: 't', tagsList: tags.map(Tag.new).toList(), postURL: 'p');
    expect(BoardQueryBuilder.accepts(item(['Animated', 'blonde_hair', 'solo']), must: ['animated', 'blonde_hair'], exclude: ['male']), isTrue);
    expect(BoardQueryBuilder.accepts(item(['animated', 'male']), must: ['animated'], exclude: ['male']), isFalse);
    expect(BoardQueryBuilder.accepts(item(['blonde_hair']), must: ['animated'], exclude: const []), isFalse);
    expect(
      BoardQueryBuilder.accepts(item(['video']), must: ['animated'], exclude: const [], aliases: {'animated': 'video'}),
      isTrue,
      reason: 'the site spells the must-have tag its own way',
    );
    expect(BoardQueryBuilder.accepts(item(const []), must: const [], exclude: const []), isTrue);
  });
}
