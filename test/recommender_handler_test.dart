import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/ftrl_model.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/rewards.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r33: the recommender behind every surface. Events are logged and train
/// the world's model at once; the two toggles are independent; the worlds
/// never mix; a lost model file is rebuilt from the log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late bool dbReady;

  BooruItem booruPost(String artist, {String tag = 'red_hair', String id = ''}) => BooruItem(
    fileURL: 'https://img.gelbooru.com/$artist-$tag$id.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag(artist, tagType: TagType.artist), Tag(tag)],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$artist-$tag$id',
  );

  BooruItem doujinGallery(String artist) => BooruItem(
    fileURL: 'https://nhentai.net/g/$artist/',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag(artist, tagType: TagType.artist), Tag('big_breasts')],
    postURL: 'https://nhentai.net/g/$artist/',
    description: 'A book by $artist',
  )..fileCountHint.value = 20;

  final Booru gelbooru = Booru('g', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('n', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('recommender');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      await db.createCriticalIndexes();
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
    SettingsHandler.instance
      ..dbEnabled = true
      ..aiLearning = true
      ..aiRecommendations = true;
    RecommenderHandler.register();
  });

  tearDown(() async {
    RecommenderHandler.unregister();
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Ten likes for alice, ten flicks past bob.
  Future<void> teach(RecommenderHandler r) async {
    for (int i = 0; i < 10; i++) {
      await r.onEvent(booruPost('alice', id: '$i'), InteractionKind.favourite);
      await r.onEvent(booruPost('bob', id: '$i'), InteractionKind.skip);
    }
  }

  test('learning off: nothing is logged and nothing is learned', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    SettingsHandler.instance.aiLearning = false;
    await r.onEvent(booruPost('alice'), InteractionKind.favourite);
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0);
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 0);
  });

  test('learning on: an event is logged, trains at once, and its features are named', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await r.onEvent(booruPost('alice'), InteractionKind.favourite);
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 1);
    expect(await r.score(booruPost('alice', tag: 'glasses')), greaterThan(0.5));
    final RecommenderReport report = await r.report(RecommenderWorld.booru);
    expect(report.events, 1);
    expect(report.liked.map((e) => e.name), contains('type:artist:alice'));
  });

  test('a glance teaches nothing and is not logged; a flick past is a quiet no', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await r.onEvent(booruPost('alice'), InteractionKind.view, value: 2);
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0);
    await r.onEvent(booruPost('bob'), InteractionKind.view, value: 0.5);
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
    expect(await r.score(booruPost('bob', tag: 'glasses')), lessThan(0.5));
  });

  test('recommendations off: the order stands, seeds are empty, scores are neutral — learning goes on', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    SettingsHandler.instance.aiRecommendations = false;
    final List<BooruItem> items = [booruPost('bob', id: 'x'), booruPost('alice', id: 'x')];
    expect(await r.rerank(items), items);
    expect(await r.seedTerms(RecommenderWorld.booru), isEmpty);
    expect(await r.score(items.last), 0.5);
    await r.onEvent(booruPost('alice', id: 'y'), InteractionKind.favourite);
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 21, reason: 'still learning');
    SettingsHandler.instance.aiRecommendations = true;
    expect((await r.rerank(items)).first.postURL, contains('alice'));
    expect(await r.seedTerms(RecommenderWorld.booru), contains('alice'));
    expect(await r.seedTerms(RecommenderWorld.booru, prefix: 'type:artist:'), ['alice']);
  });

  test('the worlds never mix: a doujin event trains the doujin model only', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await r.onEvent(doujinGallery('wakahi'), InteractionKind.favourite);
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 0);
    expect((await r.modelFor(RecommenderWorld.doujin)).updates, 1);
    expect((await r.report(RecommenderWorld.booru)).events, 0);
    expect((await r.report(RecommenderWorld.doujin)).events, 1);
    expect((await r.report(RecommenderWorld.doujin)).liked.map((e) => e.name), contains('ns:artist:wakahi'));
  });

  test('a search is learned as its terms, in the world of the source searched', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await r.onQuery('genshin_impact sort:score', gelbooru, InteractionKind.search);
    await r.onQuery('parody:genshin_impact', nhentai, InteractionKind.search);
    expect((await r.report(RecommenderWorld.booru)).liked.map((e) => e.name), ['tag:genshin_impact']);
    expect((await r.report(RecommenderWorld.doujin)).liked.map((e) => e.name), containsAll(['ns:parody:genshin_impact', 'tag:genshin_impact']));
  });

  test('the model survives on disk, and a lost file is rebuilt from the log', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    final double before = await r.score(booruPost('alice', tag: 'glasses'));
    await r.flush();
    final File file = File('${tempDir.path}${Platform.pathSeparator}recommender${Platform.pathSeparator}booru.bin');
    expect(file.existsSync(), isTrue);
    RecommenderHandler.unregister();
    RecommenderHandler.register();
    expect(await RecommenderHandler.instance.score(booruPost('alice', tag: 'glasses')), before);
    file.deleteSync();
    RecommenderHandler.unregister();
    RecommenderHandler.register();
    final FtrlModel rebuilt = await RecommenderHandler.instance.modelFor(RecommenderWorld.booru);
    expect(rebuilt.updates, 20, reason: 'replayed from the twenty logged events');
    expect(await RecommenderHandler.instance.score(booruPost('alice', tag: 'glasses')), greaterThan(0.5));
  });

  test('shown on screen and passed over is a quiet no; opened is spared; never drawn is nothing — and none of it is logged', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    final BooruItem a = booruPost('alice');
    final BooruItem b = booruPost('bob', tag: 'glasses');
    final BooruItem c = booruPost('chuck', tag: 'hat');
    // A strip hands the recommender thirty items and draws four: only what
    // was actually drawn can have been passed over (review, r33).
    await r.onExposed([a, b, c], 'suggested');
    r.onRendered(a);
    r.onRendered(b);
    await r.onEvent(a, InteractionKind.view, value: 10);
    final double bobBefore = await r.score(booruPost('bob', tag: 'glasses'));
    await r.onExposed([booruPost('carol')], 'suggested');
    final FtrlModel model = await r.modelFor(RecommenderWorld.booru);
    expect(await r.score(booruPost('bob', tag: 'glasses')), lessThan(bobBefore), reason: 'drawn, never touched, gone: a quiet no');
    expect(model.weight(ItemFeatures.hash('tag:hat')), 0, reason: 'chuck was never on screen; nothing about him was learned');
    expect(await r.score(booruPost('alice', tag: 'glasses')), greaterThan(0.5));
    // Lapses train the model but are not the record: the log holds what
    // the user did, so a rebuild is not drowned in what they scrolled past.
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1, reason: 'the view only');
  });

  test("Forget while the world's model is still loading does not bring the old one back", () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    await r.flush();
    r.resetForTests();
    final Future<FtrlModel> loading = r.modelFor(RecommenderWorld.booru);
    await r.reset(RecommenderWorld.booru);
    await loading;
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 0);
    expect(File(r.fileFor(RecommenderWorld.booru)).existsSync(), isFalse);
  });

  test('a model file with another bucket count is not used: rebuilt from the log instead', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    final File file = File(r.fileFor(RecommenderWorld.booru));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync((FtrlModel(buckets: 16)..update(const [1, 2], positive: true)).toBytes());
    final FtrlModel model = await r.modelFor(RecommenderWorld.booru);
    expect(model.buckets, ItemFeatures.buckets);
    expect(model.updates, 0);
    expect(await r.score(booruPost('alice')), 0.5, reason: 'and predicting with it cannot go out of range');
  });

  test('rerank leaves every fifth slot to something the model has not seen', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    final List<BooruItem> items = [
      for (int i = 0; i < 8; i++) booruPost('alice', tag: 'red_hair', id: 'k$i'),
      booruPost('dave', tag: 'new_thing_1', id: 'n1'),
      booruPost('erin', tag: 'new_thing_2', id: 'n2'),
    ];
    final List<BooruItem> out = await r.rerank(items);
    expect(out, hasLength(10));
    expect(out.toSet(), items.toSet());
    expect(out[4].postURL, anyOf(contains('dave'), contains('erin')), reason: 'the fifth slot explores');
    expect(out.first.postURL, contains('alice'));
  });

  test('forgetting a learned like pushes it down', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    final double before = await r.score(booruPost('alice', tag: 'glasses'));
    for (int i = 0; i < 3; i++) {
      await r.forgetFeature(RecommenderWorld.booru, 'type:artist:alice');
    }
    expect(await r.score(booruPost('alice', tag: 'glasses')), lessThan(before));
  });

  test('reset forgets the world: no events, no weights, no file', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    await teach(r);
    await r.flush();
    await r.reset(RecommenderWorld.booru);
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 0);
    expect((await r.report(RecommenderWorld.booru)).events, 0);
    expect(File('${tempDir.path}${Platform.pathSeparator}recommender${Platform.pathSeparator}booru.bin').existsSync(), isFalse);
    expect(await r.score(booruPost('alice', tag: 'glasses')), 0.5);
  });

  test("the classic profile's entry points feed the recommender too — each world its own model", () async {
    if (!dbReady) return;
    InterestsHandler.register();
    addTearDown(InterestsHandler.unregister);
    SettingsHandler.instance.enableInterestTracking = true;
    final InterestsHandler interests = InterestsHandler.instance;
    final r = RecommenderHandler.instance;
    interests.onItemViewed(booruPost('alice'), const Duration(seconds: 10));
    interests.onItemViewed(doujinGallery('wakahi'), const Duration(seconds: 10));
    interests.onItemFavourited(booruPost('alice', id: '2'), nowFavourite: true);
    interests.onSearch('touhou', booru: gelbooru);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await r.modelFor(RecommenderWorld.booru)).updates, 3, reason: 'view, favourite, search');
    expect((await r.modelFor(RecommenderWorld.doujin)).updates, 1, reason: 'the doujin view, refused by the classic profile, still teaches the doujin model');
    expect(interests.pendingSignals.keys, isNot(contains('wakahi')), reason: 'the classic profile still refuses doujins');
  });

  test('r34: "Not interested" is a loud no, the item never comes back, and it survives a restart through the log', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    final BooruItem gone = booruPost('bob', id: 'gone');
    await r.dismiss(gone);
    expect(r.isDismissed(gone), isTrue);
    expect((await r.withoutDismissed([booruPost('alice'), gone])).map((i) => i.postURL), [booruPost('alice').postURL]);
    expect(await r.score(booruPost('bob', tag: 'glasses')), lessThan(0.5));
    final rows = await SettingsHandler.instance.dbHandler.recentInteractions('booru', limit: 5);
    expect(rows.single.kind, InteractionKind.notInterested);
    r.resetForTests();
    expect(r.isDismissed(gone), isFalse, reason: 'forgotten with the session');
    // The first page after a restart asks before any model was loaded
    // (review): the filter loads what it needs.
    expect((await r.withoutDismissed([booruPost('alice'), gone])).map((i) => i.postURL), [booruPost('alice').postURL]);
    expect(r.isDismissed(gone), isTrue, reason: 'read back from the log with the world');
  });

  test('r34: "Not interested" is kept even while learning is off — it is an order, not a signal (review)', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    final FtrlModel model = await r.modelFor(RecommenderWorld.booru);
    SettingsHandler.instance.aiLearning = false;
    final BooruItem gone = booruPost('bob', id: 'gone2');
    await r.dismiss(gone);
    expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1, reason: 'logged so it survives a restart');
    expect(model.updates, 0, reason: 'but nothing was learned while learning is off');
    r.resetForTests();
    expect(await r.withoutDismissed([gone]), isEmpty);
  });

  test('r34: with an encoder, what an item says counts — an unseen artist whose name reads like a liked one scores above one that reads like a skipped one', () async {
    if (!dbReady) return;
    final r = RecommenderHandler.instance;
    // Without an encoder the two are indistinguishable: every hashed feature is new.
    await teach(r);
    final BooruItem likeAlice = booruPost('alice_liddell', tag: 'blue_hair');
    final BooruItem likeBob = booruPost('bob_ross', tag: 'blue_hair');
    final double plainAlice = await r.score(likeAlice);
    final double plainBob = await r.score(likeBob);
    expect((plainAlice - plainBob).abs(), lessThan(0.02), reason: 'nothing links alice_liddell to alice without reading the words');
    // With one: the encoder's vectors join the features, and the taste
    // centroid of what was liked adds a similarity feature.
    EncoderHandler.unregister();
    final EncoderHandler encoder = EncoderHandler.register();
    encoder.runnerFactory = (String p, {required bool wantsTokenTypeIds}) => _WordRunner();
    encoder.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
        to.parent.createSync(recursive: true);
        to.writeAsStringSync(
          url.endsWith('vocab.txt')
              ? '[PAD]\n[UNK]\n[CLS]\n[SEP]\nalice\nbob\nred\nhair\nblue\nliddell\nross\n'
              : url.endsWith('config.json')
              ? '{"hidden_size": 16}'
              : url.endsWith('tokenizer_config.json')
              ? '{"do_lower_case": true}'
              : 'model',
        );
      };
    addTearDown(EncoderHandler.unregister);
    expect(await encoder.download('english'), isTrue);
    r.resetForTests();
    await r.reset(RecommenderWorld.booru);
    await teach(r);
    final double readAlice = await r.score(likeAlice);
    final double readBob = await r.score(likeBob);
    expect(readAlice, greaterThan(readBob + 0.1), reason: 'the word alice in the name carries the liking over');
    expect(readAlice, greaterThan(0.5));
    expect(readBob, lessThan(0.5));
    // The report names the encoder's part in what was learned.
    final RecommenderReport report = await r.report(RecommenderWorld.booru);
    expect(report.encoderFeatures, greaterThan(0));
  });

  test('the log is bounded', () async {
    if (!dbReady) return;
    final db = SettingsHandler.instance.dbHandler;
    for (int i = 0; i < 30; i++) {
      await db.addInteraction(world: 'booru', itemKey: 'k$i', host: 'h', kind: 'favourite', value: 0, features: const [1, 2]);
    }
    await db.pruneInteractions(keep: 10);
    expect(await db.countInteractions('booru'), 10);
    final rows = await db.recentInteractions('booru', limit: 100);
    expect(rows.first.itemKey, 'k29', reason: 'the newest are kept, newest first');
  });

  group('r74: reactions tagged with the picture', () {
    tearDown(RecommenderHandler.resetSeamsForTests);

    test('a strong reaction on a booru post carries the picture\'s tags as tag features; views, doujins and the switch off never ask', () async {
      if (!dbReady) return;
      final List<String> asked = [];
      RecommenderHandler.pixelTagsFor = (BooruItem item, handler) async {
        asked.add(item.postURL);
        return ['cat_ears', 'red_hair'];
      };
      SettingsHandler.instance.taggerOnReactions = true;
      final RecommenderHandler r = RecommenderHandler.instance;
      await r.onEvent(booruPost('alice'), InteractionKind.favourite);
      expect(asked, hasLength(1));
      final RecommenderReport report = await r.report(RecommenderWorld.booru);
      expect(report.liked.map((e) => e.name), contains('tag:cat_ears'));
      expect(report.liked.map((e) => e.name), contains('tag:red_hair'));
      await r.onEvent(booruPost('alice', id: '2'), InteractionKind.view, value: 10);
      expect(asked, hasLength(1), reason: 'a view is not worth a second of the tagger');
      await r.onEvent(doujinGallery('carol'), InteractionKind.favourite);
      expect(asked, hasLength(1), reason: 'the booru world only');
      SettingsHandler.instance.taggerOnReactions = false;
      await r.onEvent(booruPost('alice', id: '3'), InteractionKind.favourite);
      expect(asked, hasLength(1));
    });

    test('a tagger that fails still lets the reaction teach the site\'s tags', () async {
      if (!dbReady) return;
      RecommenderHandler.pixelTagsFor = (BooruItem item, handler) async => throw StateError('no model');
      SettingsHandler.instance.taggerOnReactions = true;
      final RecommenderHandler r = RecommenderHandler.instance;
      await r.onEvent(booruPost('alice'), InteractionKind.favourite);
      final RecommenderReport report = await r.report(RecommenderWorld.booru);
      expect(report.events, 1);
      expect(report.liked.map((e) => e.name), contains('type:artist:alice'));
    });
  });
}

/// A stand-in encoder: every token id has its own fixed direction (a
/// seeded pseudo-random vector), so texts sharing a word share a direction.
class _WordRunner implements EmbeddingRunner {
  @override
  int get dim => 16;

  @override
  bool get wantsTokenTypeIds => true;

  @override
  Future<Float32List> run(List<List<int>> ids, List<List<int>> mask) async {
    final int length = ids.first.length;
    final Float32List out = Float32List(ids.length * length * dim);
    for (int b = 0; b < ids.length; b++) {
      for (int t = 0; t < length; t++) {
        int seed = ids[b][t] * 2654435761 + 12345;
        for (int d = 0; d < dim; d++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          out[(b * length + t) * dim + d] = (seed % 2000) / 1000 - 1;
        }
      }
    }
    return out;
  }

  @override
  Future<void> close() async {}
}
