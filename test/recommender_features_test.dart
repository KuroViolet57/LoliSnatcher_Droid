import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r33: what the learner sees of an item. Every tag, the typed tags with
/// their type, the site, the medium, buckets for score and length, title
/// words for doujins — as stable hashes with their names kept beside them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  BooruItem booruPost() => BooruItem(
    fileURL: 'https://img.gelbooru.com/x.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [
      Tag('hakurei_reimu', tagType: TagType.character),
      Tag('zun', tagType: TagType.artist),
      Tag('touhou', tagType: TagType.copyright),
      Tag('1girl'),
      Tag('red_hair'),
    ],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
    score: '25',
  );

  BooruItem doujinGallery() => BooruItem(
    fileURL: 'https://nhentai.net/g/1/',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [
      Tag('genshin_impact', tagType: TagType.copyright),
      Tag('wakahi', tagType: TagType.artist),
      Tag('big_breasts'),
      Tag('english', tagType: TagType.meta),
    ],
    postURL: 'https://nhentai.net/g/123456/',
    description: 'Tales of Hu Tao 3\n胡桃物語',
  )..fileCountHint.value = 40;

  group('ItemFeatures', () {
    test('a booru post: every tag, the typed tags with their type, the site, the medium, a score bucket', () {
      final FeatureVector v = ItemFeatures.of(booruPost(), RecommenderWorld.booru);
      expect(
        v.names,
        containsAll([
          'tag:hakurei_reimu',
          'tag:zun',
          'tag:1girl',
          'type:character:hakurei_reimu',
          'type:artist:zun',
          'type:copyright:touhou',
          'site:gelbooru.com',
          'media:image',
          'score:10-49',
        ]),
      );
      expect(v.names, isNot(contains('type:none:1girl')), reason: 'untyped tags carry no type feature');
      expect(v.hashes.length, v.names.length);
      expect(v.hashes.toSet().length, v.hashes.length, reason: 'no two of these collide');
      expect(v.hashes.every((h) => h >= 0 && h < ItemFeatures.buckets), isTrue);
    });

    test('hashing is deterministic and names survive beside their hashes', () {
      expect(ItemFeatures.hash('tag:red_hair'), ItemFeatures.hash('tag:red_hair'));
      expect(ItemFeatures.hash('tag:red_hair'), isNot(ItemFeatures.hash('tag:blue_hair')));
      final FeatureVector v = ItemFeatures.of(booruPost(), RecommenderWorld.booru);
      for (int i = 0; i < v.names.length; i++) {
        expect(v.hashes[i], ItemFeatures.hash(v.names[i]));
      }
    });

    test('a doujin gallery: namespaced tags, title words, a length bucket, the book medium', () {
      final FeatureVector v = ItemFeatures.of(
        doujinGallery(),
        RecommenderWorld.doujin,
        namespaces: const {'genshin_impact': 'parody', 'wakahi': 'artist', 'big_breasts': 'female', 'english': 'language'},
      );
      expect(
        v.names,
        containsAll([
          'ns:parody:genshin_impact',
          'ns:artist:wakahi',
          'ns:female:big_breasts',
          'ns:language:english',
          'tag:big_breasts',
          'site:nhentai.net',
          'media:book',
          'pages:26-60',
          'title:tales',
          'title:tao',
          'title:胡桃',
        ]),
      );
      expect(v.names, isNot(contains('title:of')), reason: 'stop words and short words are not title features');
    });

    test('without a namespace map the tag types stand in for the namespaces', () {
      final FeatureVector v = ItemFeatures.of(doujinGallery(), RecommenderWorld.doujin);
      expect(v.names, containsAll(['ns:parody:genshin_impact', 'ns:artist:wakahi', 'tag:big_breasts']));
    });

    test('a remembered gallery (namespaced tag strings, no item) yields the same features', () {
      final FeatureVector fromItem = ItemFeatures.of(
        doujinGallery(),
        RecommenderWorld.doujin,
        namespaces: const {'genshin_impact': 'parody', 'wakahi': 'artist', 'big_breasts': 'female', 'english': 'language'},
      );
      final FeatureVector fromParts = ItemFeatures.ofDoujinParts(
        namespacedTags: const ['parody:genshin_impact', 'artist:wakahi', 'female:big_breasts', 'language:english'],
        // Both title lines, as the history keeps them.
        title: 'Tales of Hu Tao 3\n胡桃物語',
        host: 'nhentai.net',
        pages: 40,
      );
      expect(fromParts.names.toSet(), fromItem.names.toSet());
    });

    test('the world of an item follows its host', () {
      expect(ItemFeatures.worldOf(doujinGallery()), RecommenderWorld.doujin);
      expect(ItemFeatures.worldOf(booruPost()), RecommenderWorld.booru);
      final Booru nh = Booru('n', BooruType.NHentai, '', 'https://nhentai.net', '');
      final Booru gb = Booru('g', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
      expect(ItemFeatures.worldOfBooru(nh), RecommenderWorld.doujin);
      expect(ItemFeatures.worldOfBooru(gb), RecommenderWorld.booru);
    });

    test('a search is a pseudo-item of its terms: metatags dropped, namespaces kept', () {
      expect(
        ItemFeatures.ofQuery('genshin_impact sort:score -rating:safe', RecommenderWorld.booru).names,
        ['tag:genshin_impact'],
      );
      expect(
        ItemFeatures.ofQuery('parody:genshin_impact female:big_breasts', RecommenderWorld.doujin).names.toSet(),
        {'ns:parody:genshin_impact', 'tag:genshin_impact', 'ns:female:big_breasts', 'tag:big_breasts'},
      );
      expect(ItemFeatures.ofQuery('', RecommenderWorld.booru).names, isEmpty);
    });

    test('score and length buckets', () {
      expect(ItemFeatures.scoreBucket(0), '0');
      expect(ItemFeatures.scoreBucket(7), '1-9');
      expect(ItemFeatures.scoreBucket(49), '10-49');
      expect(ItemFeatures.scoreBucket(150), '50-199');
      expect(ItemFeatures.scoreBucket(999), '200-999');
      expect(ItemFeatures.scoreBucket(5000), '1000+');
      expect(ItemFeatures.pagesBucket(8), '1-10');
      expect(ItemFeatures.pagesBucket(25), '11-25');
      expect(ItemFeatures.pagesBucket(60), '26-60');
      expect(ItemFeatures.pagesBucket(150), '61-150');
      expect(ItemFeatures.pagesBucket(300), '151+');
    });

    test('seed-worthy features are the typed and namespaced ones, never generic tags or buckets', () {
      expect(ItemFeatures.isSeedable('type:character:hakurei_reimu'), isTrue);
      expect(ItemFeatures.isSeedable('ns:parody:genshin_impact'), isTrue);
      expect(ItemFeatures.isSeedable('tag:red_hair'), isTrue);
      expect(ItemFeatures.isSeedable('tag:1girl'), isFalse);
      expect(ItemFeatures.isSeedable('site:nhentai.net'), isFalse);
      expect(ItemFeatures.isSeedable('score:1-9'), isFalse);
      expect(ItemFeatures.isSeedable('title:tao'), isFalse);
      expect(ItemFeatures.isSeedable('ns:language:english'), isFalse);
    });
  });

  group('r75: pairs and looks', () {
    BooruItem post() => BooruItem(
      fileURL: 'https://img.gelbooru.com/1.jpg',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: [Tag('hatsune_miku', tagType: TagType.character), Tag('vocaloid', tagType: TagType.copyright), Tag('beach'), Tag('solo')],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
    );

    test('pair features: a lead tag (character, copyright, artist) with each general tag, booru world only', () {
      final FeatureVector f = ItemFeatures.of(post(), RecommenderWorld.booru);
      expect(f.names, containsAll(['pair:hatsune_miku|beach', 'pair:hatsune_miku|solo', 'pair:vocaloid|beach', 'pair:vocaloid|solo']));
      expect(f.names.where((n) => n.startsWith('pair:')), hasLength(4));
      expect(f.names, containsAll(['tag:hatsune_miku', 'tag:beach']));
      final BooruItem gallery = BooruItem(
        fileURL: 'https://nhentai.net/g/1/',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: [Tag('artist_x', tagType: TagType.artist), Tag('big_breasts')],
        postURL: 'https://nhentai.net/g/1/',
      );
      expect(ItemFeatures.of(gallery, RecommenderWorld.doujin).names.where((n) => n.startsWith('pair:')), isEmpty);
    });

    test('withLook adds one valued feature per component and a taste bucket, keeps the logged count, and stacks with the encoder', () {
      final FeatureVector base = ItemFeatures.of(post(), RecommenderWorld.booru);
      final FeatureVector f = ItemFeatures.withLook(base, [0.6, 0.8], model: 'clip', taste: [0.6, 0.8]);
      expect(f.names, containsAll(['look:clip:0', 'look:clip:1']));
      expect(f.names.any((n) => n.startsWith('ltaste:clip:')), isTrue);
      expect(f.values, isNotNull);
      expect(f.values!.length, f.hashes.length);
      expect(f.logged, base.hashes.length);
      expect(f.values![base.hashes.length], closeTo(0.6 * ItemFeatures.lookScale, 1e-9));
      final FeatureVector both = ItemFeatures.withLook(ItemFeatures.withEmbedding(base, [1, 0], model: 'm'), [0, 1], model: 'clip');
      expect(both.logged, base.hashes.length);
      expect(both.names, containsAll(['emb:m:0', 'look:clip:1']));
      expect(both.values!.length, both.hashes.length);
      expect(ItemFeatures.withLook(base, const [], model: 'clip'), same(base));
    });
  });
}
