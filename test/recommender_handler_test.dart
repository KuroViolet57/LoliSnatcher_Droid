import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
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
import 'package:lolisnatcher/src/handlers/recommender/deferred_learning.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_work.dart';
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
    // r77: dismiss returns at once; its learning is a background step.
    await ModelWork.instance.drained();
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
    // r75: with tag pairs in the mix the site and media features carry a
    // little net liking, so the bar is the tags-only score, not 0.5.
    expect(readBob, lessThan(plainBob), reason: 'reading the name pulls a bob-like item below its tags-only score');
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

  group('r75: why, corrections and looks', () {
    tearDown(RecommenderHandler.resetSeamsForTests);

    test('explain names what pulled a post up and down, in plain words', () async {
      if (!dbReady) return;
      final RecommenderHandler r = RecommenderHandler.instance;
      await teach(r);
      final Explanation e = await r.explain(booruPost('alice'));
      expect(e.positive.map((p) => p.label), contains('artist alice'));
      expect(e.positive.length, lessThanOrEqualTo(4));
      expect(e.negative.length, lessThanOrEqualTo(3));
      final Explanation bad = await r.explain(booruPost('bob'));
      expect(bad.negative.map((p) => p.label), contains('artist bob'));
      expect(Explanation.labelOf('pair:hatsune_miku|beach'), 'hatsune miku with beach');
      expect(Explanation.labelOf('type:character:hatsune_miku'), 'character hatsune miku');
      expect(Explanation.labelOf('tag:red_hair'), 'red hair');
      expect(Explanation.labelOf('site:gelbooru.com'), 'from gelbooru.com');
      expect(Explanation.labelOf('emb:m:3'), 'how it reads');
      expect(Explanation.labelOf('look:clip:3'), 'how it looks');
      final Explanation unseen = await r.explain(booruPost('nobody', tag: 'zzz'));
      expect(unseen.positive.map((p) => p.label), isNot(contains('artist nobody')), reason: 'an unseen artist has no weight');
      expect(unseen.positive.map((p) => p.label), isNot(contains('zzz')));
    });

    test('adjust: forget zeroes a learned tag, less and more move it, and the report follows', () async {
      if (!dbReady) return;
      final RecommenderHandler r = RecommenderHandler.instance;
      await teach(r);
      final FtrlModel m = await r.modelFor(RecommenderWorld.booru);
      final int h = ItemFeatures.hash('type:artist:alice');
      final double before = m.weight(h);
      expect(before, greaterThan(0));
      await r.adjust(RecommenderWorld.booru, 'type:artist:alice', how: 'less');
      expect(m.weight(h), lessThan(before));
      await r.adjust(RecommenderWorld.booru, 'type:artist:alice', how: 'more');
      expect(m.weight(h), closeTo(before, 1e-6));
      await r.adjust(RecommenderWorld.booru, 'type:artist:alice', how: 'forget');
      expect(m.weight(h), 0);
      expect((await r.report(RecommenderWorld.booru)).liked.map((e) => e.name), isNot(contains('type:artist:alice')));
    });

    test('look vectors join the features and shape a visual taste; nothing is asked for views', () async {
      if (!dbReady) return;
      int asked = 0;
      RecommenderHandler.lookVectorsFor = (List<BooruItem> items, handler) async {
        asked += items.length;
        return [for (final BooruItem _ in items) Float32List.fromList([0.6, 0.8])];
      };
      final RecommenderHandler r = RecommenderHandler.instance;
      await r.onEvent(booruPost('alice'), InteractionKind.favourite);
      expect(asked, 1);
      final FtrlModel m = await r.modelFor(RecommenderWorld.booru);
      expect(m.weight(ItemFeatures.hash('look:look:0')), isNot(0), reason: 'the look components were learned');
      expect((await r.report(RecommenderWorld.booru)).lookTasteCount, 1);
      final Explanation e = await r.explain(booruPost('alice', id: '9'));
      expect(e.positive.map((p) => p.label), contains('how it looks'));
      RecommenderHandler.lookVectorsFor = (List<BooruItem> items, handler) async => throw StateError('model down');
      await r.onEvent(booruPost('alice', id: '2'), InteractionKind.favourite);
      expect((await r.report(RecommenderWorld.booru)).events, 2, reason: 'a failing model never blocks learning');
    });
  });
  group('r77: learning is a background step', () {
    late DateTime now;

    /// r78: kept learning must not leak from one test into the next, where
    /// register() would replay it.
    void keptInItsOwnFile() {
      final Directory dir = Directory.systemTemp.createTempSync('kept_learning');
      DeferredLearning.instance.resetForTests();
      DeferredLearning.instance.fileFor = () => '${dir.path}${Platform.pathSeparator}deferred.json';
      addTearDown(() {
        DeferredLearning.instance.resetForTests();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
    }

    setUp(() {
      ModelWork.resetForTests();
      // register() hooks the save-after-leaving callback the reset cleared.
      RecommenderHandler.register();
      now = DateTime(2026, 9, 19, 12);
      ActivityClock.instance.now = () => now;
    });

    tearDown(() {
      ModelWork.resetForTests();
      RecommenderHandler.resetSeamsForTests();
      SettingsHandler.instance.taggerOnReactions = false;
    });

    test('r78: an event the app could not finish is kept, then learned with the models next time', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      // The app is leaving the screen with a step still waiting.
      ModelWork.instance.away = () => true;
      ActivityClock.instance.mark();
      await r.onEvent(booruPost('alice'), InteractionKind.favourite);
      await ModelWork.instance.drained();
      expect(
        await SettingsHandler.instance.dbHandler.countInteractions('booru'),
        0,
        reason: 'r78: not learned half-way, without the models',
      );
      expect(DeferredLearning.instance.waiting, 1, reason: 'kept for later');
      // A later run, with time to do it properly.
      ModelWork.instance.away = () => false;
      now = now.add(const Duration(seconds: 2));
      await r.replayKept();
      await ModelWork.instance.drained();
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
      expect((await r.modelFor(RecommenderWorld.booru)).updates, 1);
      expect(DeferredLearning.instance.waiting, 0, reason: 'handed over once');
    });

    test('r78: kept learning is picked up by itself on the next run, without being asked', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      ModelWork.instance.away = () => true;
      ActivityClock.instance.mark();
      await r.onEvent(booruPost('kept-one'), InteractionKind.favourite);
      await ModelWork.instance.drained();
      expect(DeferredLearning.instance.waiting, 1);
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0);
      // A new run of the app: the first thing the person does picks it up.
      // (register() cannot: it runs before SettingsHandler exists.)
      r.resetForTests();
      ModelWork.instance.away = () => false;
      now = now.add(const Duration(seconds: 2));
      await r.onEvent(booruPost('new-one'), InteractionKind.favourite);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await ModelWork.instance.drained();
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 2, reason: 'the kept one and the new one');
      expect(DeferredLearning.instance.waiting, 0);
    });

    test('r80: before a restore the recommender stops writing, so it cannot write over the restored files', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      await r.onEvent(booruPost('alice'), InteractionKind.favourite);
      await ModelWork.instance.drained();
      r.stopWritingForRestore();
      // What the restore wrote.
      final File file = File(r.fileFor(RecommenderWorld.booru));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([1, 2, 3]);
      await r.flush();
      expect(file.readAsBytesSync(), [1, 2, 3], reason: 'the learning in memory was not written over it');
      // Leaving the app with a step waiting keeps nothing either.
      DeferredLearning.instance.keep({'kind': 'favourite'});
      expect(DeferredLearning.instance.waiting, 0);
    });

    test('r78: a step with nothing to keep (exposures) still learns lite when the app leaves', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      ModelWork.instance.away = () => true;
      await r.onExposed([booruPost('alice'), booruPost('bob')], 'feed');
      await ModelWork.instance.drained();
      expect(DeferredLearning.instance.waiting, 0, reason: 'exposures are not worth keeping');
    });

    test('r78: nothing waits for ever - a step runs after the deadline even while the person keeps touching', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      ModelWork.instance.maxWait = const Duration(seconds: 20);
      ActivityClock.instance.mark();
      unawaited(r.onEvent(booruPost('alice'), InteractionKind.favourite));
      for (int i = 0; i < 60; i++) {
        now = now.add(const Duration(milliseconds: 500));
        ActivityClock.instance.mark();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        if (await SettingsHandler.instance.dbHandler.countInteractions('booru') > 0) break;
      }
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1, reason: 'it ran anyway');
      expect((await r.modelFor(RecommenderWorld.booru)).updates, 1);
    });

    test('an event right after a touch is learned only once 1.5 s have passed without one', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      ActivityClock.instance.mark();
      unawaited(r.onEvent(booruPost('alice'), InteractionKind.favourite));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0, reason: 'still touching');
      now = now.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
      expect((await r.modelFor(RecommenderWorld.booru)).updates, 1);
    });

    test('r78: leaving the app keeps a waiting event for later instead of learning it without the models', () async {
      if (!dbReady) return;
      int looks = 0;
      int pixels = 0;
      RecommenderHandler.lookVectorsFor = (List<BooruItem> items, handler) async {
        looks++;
        return List<Float32List?>.filled(items.length, Float32List.fromList([1, 0]));
      };
      RecommenderHandler.pixelTagsFor = (BooruItem item, handler) async {
        pixels++;
        return const ['from_the_picture'];
      };
      SettingsHandler.instance.taggerOnReactions = true;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      ActivityClock.instance.mark();
      final Future<void> learned = r.onEvent(booruPost('bob'), InteractionKind.favourite);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0);
      ModelWork.instance.away = () => true;
      ModelWork.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
      await learned;
      // r77 learned it here without the models, which could not be undone.
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0, reason: 'r78: nothing is learned half-way');
      expect(DeferredLearning.instance.waiting, 1, reason: 'kept for the next run');
      expect(looks, 0, reason: 'no model runs while the app is away');
      expect(pixels, 0);
    });

    test('"Not interested" returns at once while its learning waits; the post is left out right away', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      final BooruItem post = booruPost('dave');
      ActivityClock.instance.mark();
      final Stopwatch sw = Stopwatch()..start();
      await r.dismiss(post);
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(r.isDismissed(post), isTrue);
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0, reason: 'learned at the next quiet moment');
      now = now.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
    });

    test('a step queued before the model was reset is dropped, not learned into the fresh model', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      await r.modelFor(RecommenderWorld.booru);
      ActivityClock.instance.mark();
      unawaited(r.onEvent(booruPost('erin'), InteractionKind.favourite));
      await r.reset(RecommenderWorld.booru);
      now = now.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 0);
      expect((await r.modelFor(RecommenderWorld.booru)).updates, 0);
    });

    test('learning switched off while a "Not interested" waited: it is still logged as an order', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      // Loaded first, so the check below does not replay the logged row.
      await r.modelFor(RecommenderWorld.booru);
      ActivityClock.instance.mark();
      await r.dismiss(booruPost('frank'));
      SettingsHandler.instance.aiLearning = false;
      now = now.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
      expect((await r.modelFor(RecommenderWorld.booru)).updates, 0, reason: 'logged, not learned');
      SettingsHandler.instance.aiLearning = true;
    });

    test('after steps ran lite as the app left, the models are written to disk', () async {
      if (!dbReady) return;
      final r = RecommenderHandler.instance;
      keptInItsOwnFile();
      await r.modelFor(RecommenderWorld.booru);
      // Something learned and not yet written: this is what the flush saves.
      await r.onEvent(booruPost('gina'), InteractionKind.favourite);
      await ModelWork.instance.drained();
      expect(await SettingsHandler.instance.dbHandler.countInteractions('booru'), 1);
      // r78: a learning event is kept for later now, so the step that still
      // runs lite is an exposure.
      ActivityClock.instance.mark();
      final Future<void> seen = r.onExposed([booruPost('gina')], 'feed');
      ModelWork.instance.away = () => true;
      ModelWork.instance.didChangeAppLifecycleState(AppLifecycleState.paused);
      await seen;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(File(r.fileFor(RecommenderWorld.booru)).existsSync(), isTrue);
    });

    test('exposures wait their turn behind a running step and never overlap it', () async {
      if (!dbReady) return;
      final Completer<void> gate = Completer<void>();
      final List<String> order = [];
      unawaited(ModelWork.instance.run('busy', (bool lite) async {
        order.add('busy start');
        await gate.future;
        order.add('busy end');
      }));
      final Future<void> exposed = RecommenderHandler.instance.onExposed([booruPost('carol')], 'test-surface').then((_) => order.add('exposed'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(order, ['busy start']);
      gate.complete();
      await exposed;
      expect(order, ['busy start', 'busy end', 'exposed']);
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
