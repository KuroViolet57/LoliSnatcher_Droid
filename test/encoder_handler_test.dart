import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r34: the downloaded encoder — a Hugging Face ONNX sentence model kept
/// beside the settings, run through a small runner, pooled into one vector
/// per item and cached. The runner here is a fake: one fixed vector per
/// token id, so pooling and caching can be checked by hand.
class _FakeRunner implements EmbeddingRunner {
  @override
  final int dim = 8;

  @override
  bool get wantsTokenTypeIds => true;

  int runs = 0;
  int tokensSeen = 0;
  bool closed = false;
  bool closedDuringRun = false;
  bool _running = false;
  Completer<void>? gate;

  /// Token id → a one-hot at 1 + id % (dim − 1); slot 0 is never used, so a
  /// padding token that leaked into the mean would show there.
  @override
  Future<Float32List> run(List<List<int>> ids, List<List<int>> mask) async {
    runs++;
    _running = true;
    try {
      if (gate != null) await gate!.future;
    } finally {
      _running = false;
    }
    final int length = ids.first.length;
    final Float32List out = Float32List(ids.length * length * dim);
    for (int b = 0; b < ids.length; b++) {
      for (int t = 0; t < length; t++) {
        tokensSeen++;
        out[(b * length + t) * dim + 1 + ids[b][t] % (dim - 1)] = 1;
      }
    }
    return out;
  }

  @override
  Future<void> close() async {
    if (_running) closedDuringRun = true;
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late bool dbReady;
  late _FakeRunner runner;
  final List<String> fetched = [];

  const String vocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nalice\nbob\nred\nhair\nglasses\nbook\n';

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('encoder');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiEncoder = true
      ..encoderModel = '';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      dbReady = true;
      SettingsHandler.instance.dbEnabled = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
      SettingsHandler.instance.dbEnabled = false;
    }
    runner = _FakeRunner();
    fetched.clear();
    EncoderHandler.unregister();
    final EncoderHandler encoder = EncoderHandler.register();
    encoder.runnerFactory = (String modelPath, {required bool wantsTokenTypeIds}) => runner;
    encoder.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
        fetched.add(url);
        to.parent.createSync(recursive: true);
        if (url.endsWith('vocab.txt')) {
          to.writeAsStringSync(vocab);
        } else if (url.endsWith('tokenizer_config.json')) {
          to.writeAsStringSync('{"do_lower_case": true, "model_max_length": 512}');
        } else if (url.endsWith('config.json')) {
          to.writeAsStringSync('{"hidden_size": 8, "model_type": "bert"}');
        } else {
          to.writeAsBytesSync(List<int>.filled(1000, 7));
        }
        onProgress?.call(1000, 1000);
      };
  });

  tearDown(() async {
    await EncoderHandler.maybe?.close();
    EncoderHandler.unregister();
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem post(String artist, {String tag = 'red_hair', String id = ''}) => BooruItem(
    fileURL: 'https://img.gelbooru.com/$artist-$tag$id.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag(artist, tagType: TagType.artist), Tag(tag)],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$artist-$tag$id',
  );

  BooruItem gallery(String title, List<String> tags) => BooruItem(
    fileURL: 'https://nhentai.net/g/1/',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [for (final t in tags) Tag(t)],
    postURL: 'https://nhentai.net/g/${title.hashCode}/',
    description: '$title\nsecond line',
  );

  group('presets and files', () {
    test('two presets with their sizes, dimensions and casing; a custom repo is any other id', () {
      expect(EncoderPreset.english.repo, 'Xenova/all-MiniLM-L6-v2');
      expect(EncoderPreset.english.bytes, 22972370);
      expect(EncoderPreset.english.dim, 384);
      expect(EncoderPreset.english.lowerCase, isTrue);
      expect(EncoderPreset.multilingual.repo, 'Xenova/distiluse-base-multilingual-cased-v2');
      expect(EncoderPreset.multilingual.bytes, 135317281);
      expect(EncoderPreset.multilingual.dim, 768);
      expect(EncoderPreset.multilingual.lowerCase, isFalse);
      expect(EncoderPreset.byId('english'), same(EncoderPreset.english));
      expect(EncoderPreset.byId('someone/some-model'), isNull);
      expect(EncoderHandler.repoOf('english'), 'Xenova/all-MiniLM-L6-v2');
      expect(EncoderHandler.repoOf('someone/some-model'), 'someone/some-model');
      expect(EncoderHandler.slugOf('Xenova/all-MiniLM-L6-v2'), 'xenova__all-minilm-l6-v2');
    });

    test('download fetches the four files from the repo, writes a manifest, and the encoder is ready', () async {
      final EncoderHandler e = EncoderHandler.instance;
      expect(e.status.value.state, EncoderState.none);
      final bool ok = await e.download('english');
      expect(ok, isTrue);
      expect(fetched, [
        'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx',
        'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
        'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/tokenizer_config.json',
        'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/config.json',
      ]);
      expect(e.status.value.state, EncoderState.ready);
      expect(e.status.value.dim, 8, reason: 'the dimension comes from the downloaded config, not the preset');
      expect(e.status.value.bytes, 1000);
      expect(SettingsHandler.instance.encoderModel, 'english');
      expect(File('${e.dirFor('english')}manifest.json').existsSync(), isTrue);
      expect(e.enabled, isTrue);
      // A fresh handler finds it again from the manifest.
      EncoderHandler.unregister();
      final EncoderHandler again = EncoderHandler.register();
      await again.refresh();
      expect(again.status.value.state, EncoderState.ready);
      expect(again.status.value.repo, 'Xenova/all-MiniLM-L6-v2');
    });

    test('a failed fetch leaves nothing half-downloaded behind and says so', () async {
      final EncoderHandler e = EncoderHandler.instance;
      e.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
        if (url.endsWith('vocab.txt')) throw DioException(requestOptions: RequestOptions(path: url), message: 'no network');
        to.parent.createSync(recursive: true);
        to.writeAsBytesSync(const [1, 2, 3]);
      };
      expect(await e.download('english'), isFalse);
      expect(e.status.value.state, EncoderState.error);
      expect(e.status.value.message, contains('no network'));
      expect(Directory(e.dirFor('english')).existsSync(), isFalse);
      expect(SettingsHandler.instance.encoderModel, '');
    });

    test('delete removes the files and the setting; the encoder switch alone can turn it off', () async {
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      expect(await e.embedText('alice'), isNotNull, reason: 'opens the session');
      SettingsHandler.instance.aiEncoder = false;
      expect(e.enabled, isFalse);
      SettingsHandler.instance.aiEncoder = true;
      expect(e.enabled, isTrue);
      await e.delete();
      expect(e.status.value.state, EncoderState.none);
      expect(Directory(e.dirFor('english')).existsSync(), isFalse);
      expect(SettingsHandler.instance.encoderModel, '');
      expect(runner.closed, isTrue, reason: 'the session is closed with the files');
    });
  });

  group('r80: the thread counts and the switches of Settings → Models', () {
    setUp(() {
      ModelTasks.save = () async {};
      ModelTasks.maxThreads = () => 8;
    });

    tearDown(() {
      ModelTasks.resetForTests();
      SettingsHandler.instance.modelThreads.clear();
      SettingsHandler.instance.aiModelsOff = false;
    });

    test("learning opens the model with the background count, For You with the waiting count; today's are 1 and 1", () async {
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      await e.embedTexts(['alice'], use: ModelUse.background);
      expect(e.openedThreads, 1);
      await e.close();
      await ModelTasks.setThreads(ModelKind.text, ModelUse.background, 2);
      await ModelTasks.setThreads(ModelKind.text, ModelUse.waiting, 4);
      await e.embedTexts(['bob'], use: ModelUse.background);
      expect(e.openedThreads, 2);
      await e.close();
      await e.embedItems([post('carol')]);
      expect(e.openedThreads, 4, reason: 'waiting is the default');
    });

    test('a new count applies at once, and never closes the model under a run', () async {
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      await e.embedText('alice');
      e.threadsChanged();
      await Future<void>.delayed(Duration.zero);
      expect(runner.closed, isTrue, reason: 'idle: closed now, opened again with the new count');

      runner = _FakeRunner();
      final Completer<void> gate = Completer<void>();
      runner.gate = gate;
      final Future<Float32List?> slow = e.embedText('bob');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      e.threadsChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runner.closed, isFalse);
      gate.complete();
      expect(await slow, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(runner.closedDuringRun, isFalse);
      expect(runner.closed, isTrue, reason: 'closed once the run is done');
      expect(e.status.value.state, EncoderState.ready);
    });

    test('all models off: the text model is off and answers nulls, its own switch untouched', () async {
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      expect(e.enabled, isTrue);
      SettingsHandler.instance.aiModelsOff = true;
      expect(e.enabled, isFalse);
      expect(await e.embedText('alice'), isNull);
      expect(runner.runs, 0);
      expect(SettingsHandler.instance.aiEncoder, isTrue);
    });
  });

  group('text and vectors', () {
    test('an item reads as its title and tags, namespaces dropped and underscores as spaces, names first', () {
      final BooruItem b = post('alice', tag: 'red_hair');
      b.tagsList.add(Tag('genshin_impact', tagType: TagType.copyright));
      expect(EncoderHandler.textOf(b, RecommenderWorld.booru), 'alice, genshin impact, red hair');
      final BooruItem g = gallery('Tales of Hu Tao', ['parody:genshin_impact', 'female:big_breasts']);
      expect(EncoderHandler.textOf(g, RecommenderWorld.doujin), 'Tales of Hu Tao. genshin impact, big breasts');
      expect(EncoderHandler.textOfDoujinParts(title: 'Book', namespacedTags: ['artist:wakahi', 'language:english']), 'Book. wakahi');
    });

    test('pooling: the mean of the token vectors under the mask, normalised to unit length; padding is ignored', () async {
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      // "alice red" → [CLS]=2 alice=4 red=6 [SEP]=3 → one-hots at slots 3, 5, 7, 4 → mean has 0.25 at each → unit norm 0.5 each.
      final Float32List? v = await e.embedText('alice red');
      expect(v, isNotNull);
      expect(v!.length, 8);
      expect(v[3], closeTo(0.5, 1e-6));
      expect(v[5], closeTo(0.5, 1e-6));
      expect(v[7], closeTo(0.5, 1e-6));
      expect(v[4], closeTo(0.5, 1e-6));
      expect(v[0], 0);
      // Two texts of different length in one batch: the shorter one's padding contributes nothing.
      final List<Float32List?> both = await e.embedTexts(['alice', 'alice red hair glasses']);
      expect(runner.runs, 2, reason: 'one run for the first text, one for the batch');
      expect(both[0]![5], closeTo(1 / 1.7320508, 1e-5), reason: '[CLS] alice [SEP]: three one-hots, unit norm');
      expect(both[0]![0], 0, reason: 'padding ([PAD]=0) never enters the mean');
      expect(both[1]![1], closeTo(1 / 2.4494897, 1e-5), reason: 'six tokens; hair (id 7) sits in slot 1: 1/sqrt(6)');
    });

    test('the vector width comes from what the model returns, not from what config.json claimed (review)', () async {
      final EncoderHandler e = EncoderHandler.instance;
      e.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
        to.parent.createSync(recursive: true);
        to.writeAsStringSync(url.endsWith('vocab.txt') ? vocab : url.endsWith('config.json') ? '{"hidden_size": 384}' : url.endsWith('tokenizer_config.json') ? '{}' : 'x');
      };
      await e.download('english');
      expect(e.status.value.dim, 384, reason: 'what the config said');
      final Float32List? v = await e.embedText('alice');
      expect(v!.length, 8, reason: 'what the model gave');
      expect(e.dim, 8);
      expect(e.status.value.dim, 8);
    });

    test('many texts go in batches of eight, and text vectors are kept in the database like item vectors (review)', () async {
      if (!dbReady) return;
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      final List<String> texts = [for (int i = 0; i < 20; i++) 'alice $i red'];
      final List<Float32List?> out = await e.embedTexts(texts);
      expect(out.every((v) => v != null), isTrue);
      expect(runner.runs, 3, reason: '20 texts: 8 + 8 + 4');
      EncoderHandler.unregister();
      final EncoderHandler again = EncoderHandler.register()..runnerFactory = (String p, {required bool wantsTokenTypeIds}) => runner;
      await again.refresh();
      await again.embedTexts(texts);
      expect(runner.runs, 3, reason: 'read back from the database, not recomputed');
    });

    test('a runner that fails is not Ready: the status says so, and a refresh gives it another go (review)', () async {
      final EncoderHandler e = EncoderHandler.instance;
      int made = 0;
      e.runnerFactory = (String p, {required bool wantsTokenTypeIds}) {
        made++;
        if (made == 1) throw StateError('no session for you');
        return runner;
      };
      await e.download('english');
      expect(await e.embedText('alice'), isNull);
      expect(e.status.value.state, EncoderState.error);
      expect(e.status.value.message, contains('no session'));
      expect(e.enabled, isFalse);
      await e.refresh();
      expect(e.status.value.state, EncoderState.ready);
      expect(await e.embedText('alice'), isNotNull);
      expect(made, 2);
    });

    test('downloading again replaces the running session, not only the files (review)', () async {
      final EncoderHandler e = EncoderHandler.instance;
      int made = 0;
      e.runnerFactory = (String p, {required bool wantsTokenTypeIds}) {
        made++;
        return _FakeRunner();
      };
      await e.download('english');
      await e.embedText('alice');
      expect(made, 1);
      await e.download('english');
      expect(e.status.value.state, EncoderState.ready);
      expect(await e.embedText('alice'), isNotNull, reason: 'a known text: from the cache, no session needed');
      await e.embedText('bob');
      expect(made, 2, reason: 'a new text: a fresh session over the fresh files');
    });

    test('stored vectors are pruned as they accumulate, learning or not (review)', () async {
      if (!dbReady) return;
      final EncoderHandler e = EncoderHandler.instance;
      EncoderHandler.pruneEvery = 5;
      EncoderHandler.pruneKeep = 12;
      addTearDown(() {
        EncoderHandler.pruneEvery = EncoderHandler.defaultPruneEvery;
        EncoderHandler.pruneKeep = EncoderHandler.defaultPruneKeep;
      });
      await e.download('english');
      for (int i = 0; i < 30; i++) {
        await e.embedItems([post('alice', id: '$i')]);
      }
      final int stored = await SettingsHandler.instance.dbHandler.countEmbeddings(e.modelId);
      expect(stored, lessThanOrEqualTo(12 + 5));
      expect(stored, greaterThan(0));
    });

    test('items are embedded once: the second call for the same items reads the cache, the database keeps it across handlers', () async {
      if (!dbReady) return;
      final EncoderHandler e = EncoderHandler.instance;
      await e.download('english');
      final List<BooruItem> items = [post('alice'), post('bob'), post('alice', id: '2')];
      final List<Float32List?> first = await e.embedItems(items);
      expect(first.every((v) => v != null), isTrue);
      expect(runner.runs, 1);
      await e.embedItems(items);
      expect(runner.runs, 1, reason: 'memory cache');
      expect(e.cached(items[1]), isNotNull);
      EncoderHandler.unregister();
      final EncoderHandler again = EncoderHandler.register()..runnerFactory = (String p, {required bool wantsTokenTypeIds}) => runner;
      await again.refresh();
      await again.embedItems(items);
      expect(runner.runs, 1, reason: 'the database cache');
      expect(again.cached(items[0]), isNotNull);
    });

    test('with the switch off or nothing downloaded, embedding answers nulls and never runs', () async {
      final EncoderHandler e = EncoderHandler.instance;
      expect(await e.embedItems([post('alice')]), [null]);
      await e.download('english');
      SettingsHandler.instance.aiEncoder = false;
      expect(await e.embedItems([post('alice')]), [null]);
      expect(runner.runs, 0);
    });
  });
}
