import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/pixel_tags.dart';
import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r74: the downloadable image tagger (WD v3 ONNX exports from Hugging
/// Face). The runner here is a fake answering fixed probabilities over a
/// synthetic tag list, so thresholds, order, the file handling and the
/// idle close can be checked by hand.
class _FakeRunner implements TagRunner {
  _FakeRunner(this.probs, {this.fail = false});

  final Float32List probs;
  final bool fail;
  int runs = 0;
  int lastSize = 0;
  int lastLength = 0;
  bool closed = false;

  /// r79: a run that waits on this, to catch a close in the middle of it.
  Completer<void>? gate;
  bool _running = false;
  bool closedDuringRun = false;

  @override
  String get provider => 'fake';

  @override
  Future<Float32List> run(Float32List nhwc, int size) async {
    runs++;
    lastSize = size;
    lastLength = nhwc.length;
    if (fail) throw StateError('the runtime said no');
    _running = true;
    try {
      await gate?.future;
    } finally {
      _running = false;
    }
    if (closed) throw StateError('INVALID_SESSION: the session was closed');
    return probs;
  }

  @override
  Future<void> close() async {
    if (_running) closedDuringRun = true;
    closed = true;
  }
}

/// Rows: 0-3 ratings, 4 1girl, 5 cat_ears, 6 long_hair, 7 ^_^, 8 beach,
/// 9 hatsune_miku (character), 10 sakamata_chloe (character).
const String csv =
    'tag_id,name,category,count\n'
    '9999999,general,9,10\n'
    '9999998,sensitive,9,10\n'
    '9999997,questionable,9,10\n'
    '9999996,explicit,9,10\n'
    '1,1girl,0,100\n'
    '2,cat_ears,0,90\n'
    '3,long_hair,0,80\n'
    '4,^_^,0,5\n'
    '5,beach,0,50\n'
    '6,hatsune_miku,4,70\n'
    '7,sakamata_chloe,4,60\n';

Float32List probsOf(Map<int, double> at) {
  final Float32List p = Float32List(11);
  at.forEach((int i, double v) => p[i] = v);
  return p;
}

Uint8List png({int w = 4, int h = 4}) {
  final img.Image image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(200, 100, 50));
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeRunner runner;
  final List<String> fetched = [];
  int factoryCalls = 0;
  int lastThreads = 0;
  String configText = '{"model_args": {"img_size": 448}}';
  String csvText = csv;
  bool failCsv = false;
  bool cancelDuringModel = false;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tagger');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiImageTagger = true
      ..imageTaggerModel = '';
    runner = _FakeRunner(probsOf({0: 0.2, 1: 0.7, 4: 0.9, 5: 0.5, 6: 0.2, 7: 0.4, 9: 0.9, 10: 0.5}));
    fetched.clear();
    factoryCalls = 0;
    configText = '{"model_args": {"img_size": 448}}';
    csvText = csv;
    failCsv = false;
    cancelDuringModel = false;
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler t = ImageTaggerHandler.register();
    t.runnerFactory = (String modelPath, int threads) {
      factoryCalls++;
      lastThreads = threads;
      return runner;
    };
    t.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
      fetched.add(url);
      to.parent.createSync(recursive: true);
      if (url.endsWith(ImageTaggerHandler.tagsFileName)) {
        if (failCsv) throw DioException(requestOptions: RequestOptions(path: url), message: 'csv gone');
        to.writeAsStringSync(csvText);
      } else if (url.endsWith(ImageTaggerHandler.configFileName)) {
        if (configText.isEmpty) throw DioException(requestOptions: RequestOptions(path: url), message: '404');
        to.writeAsStringSync(configText);
      } else {
        if (cancelDuringModel) {
          t.cancelDownload();
          throw DioException(requestOptions: RequestOptions(path: url), type: DioExceptionType.cancel);
        }
        to.writeAsBytesSync(List<int>.filled(1000, 7));
      }
      onProgress?.call(1000, 1000);
    };
  });

  tearDown(() async {
    await ImageTaggerHandler.maybe?.close();
    ImageTaggerHandler.unregister();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('presets: three WD v3 models, the ViT first; a setting is a preset id or a repo id; files live under tagger/<slug>/', () {
    expect(TaggerPreset.values.map((p) => p.id).toList(), ['wd-vit', 'wd-convnext', 'wd-swinv2']);
    expect(TaggerPreset.values.first.repo, 'SmilingWolf/wd-vit-tagger-v3');
    expect(TaggerPreset.byId('wd-vit')!.bytes, 378536310);
    expect(TaggerPreset.byId('nope'), isNull);
    expect(ImageTaggerHandler.repoOf('wd-vit'), 'SmilingWolf/wd-vit-tagger-v3');
    expect(ImageTaggerHandler.repoOf(' Someone/other-tagger '), 'Someone/other-tagger');
    expect(ImageTaggerHandler.slugOf('SmilingWolf/wd-vit-tagger-v3'), 'smilingwolf__wd-vit-tagger-v3');
    expect(ImageTaggerHandler.fileUrl('a/b', 'model.onnx'), 'https://huggingface.co/a/b/resolve/main/model.onnx');
    final String dir = ImageTaggerHandler.instance.dirFor('wd-vit');
    expect(dir, startsWith(SettingsHandler.instance.path));
    expect(dir, contains('tagger${Platform.pathSeparator}smilingwolf__wd-vit-tagger-v3${Platform.pathSeparator}'));
    expect(ImageTaggerHandler.instance.status.value.state, TaggerState.none);
    expect(ImageTaggerHandler.instance.enabled, isFalse);
  });

  test('download: the model, the tag list and the config come down in that order into a temp folder, then move into place with a manifest', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    expect(await t.download('wd-vit'), isTrue);
    expect(fetched, [
      'https://huggingface.co/SmilingWolf/wd-vit-tagger-v3/resolve/main/model.onnx',
      'https://huggingface.co/SmilingWolf/wd-vit-tagger-v3/resolve/main/selected_tags.csv',
      'https://huggingface.co/SmilingWolf/wd-vit-tagger-v3/resolve/main/config.json',
    ]);
    final TaggerStatus s = t.status.value;
    expect(s.state, TaggerState.ready);
    expect(s.repo, 'SmilingWolf/wd-vit-tagger-v3');
    expect(s.tagCount, 11);
    expect(s.inputSize, 448);
    expect(s.bytes, 1000);
    expect(s.downloadedAt, isNotNull);
    expect(SettingsHandler.instance.imageTaggerModel, 'wd-vit');
    final String dir = t.dirFor('wd-vit');
    expect(File('${dir}model.onnx').existsSync(), isTrue);
    expect(File('${dir}selected_tags.csv').existsSync(), isTrue);
    expect(File('${dir}config.json').existsSync(), isTrue);
    final Map<String, dynamic> manifest = jsonDecode(File('${dir}manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['repo'], 'SmilingWolf/wd-vit-tagger-v3');
    expect(manifest['setting'], 'wd-vit');
    expect(manifest['tagCount'], 11);
    expect(manifest['inputSize'], 448);
    expect(manifest['bytes'], 1000);
    expect(Directory('${SettingsHandler.instance.path}tagger').listSync().where((e) => e.path.contains('.download-')), isEmpty);
    expect(t.enabled, isTrue);
    expect(t.modelId, 'smilingwolf__wd-vit-tagger-v3');
  });

  test('the config names the input size; a missing config is not a failure (the preset\'s 448 stands)', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    configText = '{"pretrained_cfg": {"input_size": [3, 224, 224]}}';
    expect(await t.download('wd-convnext'), isTrue);
    expect(t.status.value.inputSize, 224);
    expect(t.inputSize, 224);
    configText = '';
    expect(await t.download('wd-vit'), isTrue);
    expect(t.status.value.inputSize, 448);
    expect(File('${t.dirFor('wd-vit')}config.json').existsSync(), isFalse);
  });

  test('a failed or cancelled download keeps nothing and says why; a tag list without names is refused', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    failCsv = true;
    expect(await t.download('wd-vit'), isFalse);
    expect(t.status.value.state, TaggerState.error);
    expect(t.status.value.message, contains('csv gone'));
    expect(Directory(t.dirFor('wd-vit')).existsSync(), isFalse);
    expect(Directory('${SettingsHandler.instance.path}tagger').existsSync() ? Directory('${SettingsHandler.instance.path}tagger').listSync() : const [], isEmpty);
    expect(SettingsHandler.instance.imageTaggerModel, '');

    failCsv = false;
    cancelDuringModel = true;
    expect(await t.download('wd-vit'), isFalse);
    expect(t.status.value.state, TaggerState.error);
    expect(t.status.value.message, 'Download cancelled.');
    expect(Directory(t.dirFor('wd-vit')).existsSync(), isFalse);

    cancelDuringModel = false;
    csvText = 'id,count\n1,2\n';
    expect(await t.download('wd-vit'), isFalse);
    expect(t.status.value.state, TaggerState.error);
    expect(t.status.value.message.toLowerCase(), contains('tag list'));
    expect(Directory(t.dirFor('wd-vit')).existsSync(), isFalse);

    expect(await t.download('not-a-repo'), isFalse);
    expect(t.status.value.message, contains('owner/model'));
  });

  test('refresh finds a downloaded model from its manifest; missing files are reported; delete removes everything', () async {
    expect(await ImageTaggerHandler.instance.download('wd-vit'), isTrue);
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler again = ImageTaggerHandler.register();
    expect(again.status.value.state, TaggerState.none);
    await again.refresh();
    expect(again.status.value.state, TaggerState.ready);
    expect(again.status.value.tagCount, 11);
    expect(again.status.value.inputSize, 448);
    expect(again.status.value.repo, 'SmilingWolf/wd-vit-tagger-v3');
    File('${again.dirFor('wd-vit')}selected_tags.csv').deleteSync();
    await again.refresh();
    expect(again.status.value.state, TaggerState.none);
    expect(again.status.value.message, contains('missing'));
    await again.delete();
    expect(Directory(again.dirFor('wd-vit')).existsSync(), isFalse);
    expect(SettingsHandler.instance.imageTaggerModel, '');
    expect(again.status.value.state, TaggerState.none);
  });

  test('tag(): the picture is decoded off the main isolate into the model\'s tensor; the answer is read by category and threshold', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    expect(await t.download('wd-vit'), isTrue);
    final TaggerResult r = await t.tag(png());
    expect(runner.runs, 1);
    expect(runner.lastSize, 448);
    expect(runner.lastLength, 448 * 448 * 3);
    expect(r.general.map((g) => g.tag).toList(), ['1girl', 'cat_ears', '^_^'], reason: 'above 0.35, strongest first; long_hair at 0.2 is out');
    expect(r.general.first.confidence, closeTo(0.9, 1e-6));
    expect(r.characters.map((c) => c.tag).toList(), ['hatsune_miku'], reason: 'sakamata_chloe at 0.5 is under the 0.85 character threshold');
    expect(r.characters.single.character, isTrue);
    expect(r.rating, 'sensitive');
    expect(r.ratingConfidence, closeTo(0.7, 1e-6));
    expect(r.all.map((p) => p.tag).toList(), ['hatsune_miku', '1girl', 'cat_ears', '^_^'], reason: 'characters first');
    expect(r.count, 4);
    expect(r.provider, 'fake');
    expect(factoryCalls, 1);
    await t.tag(png());
    expect(factoryCalls, 1, reason: 'one session, reused');
    expect(runner.runs, 2);
  });

  test('interpret(): the general cap, categories other than 4 and 9 read as general, a short answer is tolerated', () {
    final List<TagRow> rows = ImageTaggerHandler.parseTagsCsv(csv);
    final Float32List probs = probsOf({0: 0.9, 4: 0.5, 5: 0.6, 6: 0.7, 8: 0.8});
    final TaggerResult capped = ImageTaggerHandler.interpret(probs, rows, maxGeneral: 2);
    expect(capped.general.map((g) => g.tag).toList(), ['beach', 'long_hair']);
    expect(capped.rating, 'general');
    final TaggerResult odd = ImageTaggerHandler.interpret(probsOf({8: 0.9}), [...rows.take(8), const TagRow('artist_x', 1)]);
    expect(odd.general.map((g) => g.tag).toList(), ['artist_x']);
    final TaggerResult short = ImageTaggerHandler.interpret(Float32List.fromList([0.1, 0.9, 0.2]), rows);
    expect(short.rating, 'sensitive');
    expect(short.general, isEmpty);
    expect(short.characters, isEmpty);
    final TaggerResult empty = ImageTaggerHandler.interpret(Float32List(0), rows);
    expect(empty.rating, '');
    expect(empty.count, 0);
  });

  test('parseTagsCsv: columns by header name in any order, quoted names, blank and short rows skipped, underscores and kaomoji kept', () {
    final List<TagRow> rows = ImageTaggerHandler.parseTagsCsv(
      'name,category,tag_id\n'
      '"^_^",0,4\n'
      'long_hair,0,3\n'
      '\n'
      'broken\n'
      'hatsune_miku,4,6\n'
      'explicit,9,9999996\n',
    );
    expect(rows.map((r) => r.name).toList(), ['^_^', 'long_hair', 'hatsune_miku', 'explicit']);
    expect(rows.map((r) => r.category).toList(), [0, 0, 4, 9]);
    expect(ImageTaggerHandler.parseTagsCsv('id,count\n1,2\n'), isEmpty, reason: 'no name column');
    expect(ImageTaggerHandler.parseTagsCsv(''), isEmpty);
    expect(ImageTaggerHandler.parseTagsCsv(csv), hasLength(11));
  });

  group('r79: the tagger is fast when you wait for it', () {
    test('a picture you wait for opens the session with 4 threads; a background reaction opens it with 2', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      await t.tag(png());
      expect(lastThreads, ImageTaggerHandler.waitingThreads);
      expect(ImageTaggerHandler.waitingThreads, 4, reason: '1.5 s a picture on the phone at 4 threads, 2.9 s at 2');
      await t.close();
      runner = _FakeRunner(runner.probs);
      await t.tag(png(), use: TaggerUse.background);
      expect(lastThreads, ImageTaggerHandler.backgroundThreads);
      expect(ImageTaggerHandler.backgroundThreads, 2);
    });

    test('a background run uses the session already open instead of loading a second copy', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      await t.tag(png());
      await t.tag(png(), use: TaggerUse.background);
      expect(factoryCalls, 1, reason: 'about 400 MB each - never two at once');
      expect(runner.runs, 2);
    });

    test("a reaction's tags (PixelTags) are a background run", () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      PixelTags.resetForTests();
      await PixelTags.tagBytes(png());
      expect(lastThreads, ImageTaggerHandler.backgroundThreads);
    });

    test('the idle close never closes a session a run is still using', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      t.idleClose = const Duration(milliseconds: 40);
      expect(await t.download('wd-vit'), isTrue);
      await t.tag(png());
      // The next picture's run is slow; the idle timer from the first one
      // runs out while it is still going.
      final Completer<void> gate = Completer<void>();
      runner.gate = gate;
      final Future<TaggerResult> slow = t.tag(png());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(runner.closedDuringRun, isFalse, reason: 'r78 closed it here and the run failed: the tagger was off until a restart');
      gate.complete();
      final TaggerResult r = await slow;
      expect(r.count, greaterThan(0));
      expect(t.status.value.state, TaggerState.ready);
      // Idle again afterwards: now it closes.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(runner.closed, isTrue);
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

    test('a picture you wait for opens the session with its count, a background run with the other', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      await ModelTasks.setThreads(ModelKind.tagger, ModelUse.waiting, 6);
      await ModelTasks.setThreads(ModelKind.tagger, ModelUse.background, 1);
      await t.tag(png());
      expect(lastThreads, 6);
      await t.close();
      runner = _FakeRunner(runner.probs);
      await t.tag(png(), use: ModelUse.background);
      expect(lastThreads, 1);
    });

    test('a new count applies at once: the idle session closes, the next picture opens it with the new count', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      await t.tag(png());
      expect(lastThreads, 4);
      final _FakeRunner first = runner;
      await ModelTasks.setThreads(ModelKind.tagger, ModelUse.waiting, 3);
      t.threadsChanged();
      await Future<void>.delayed(Duration.zero);
      expect(first.closed, isTrue);
      runner = _FakeRunner(first.probs);
      await t.tag(png());
      expect(factoryCalls, 2);
      expect(lastThreads, 3);
    });

    test('a new count never closes a session under a run: it closes when the run ends', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      await t.tag(png());
      final Completer<void> gate = Completer<void>();
      runner.gate = gate;
      final Future<TaggerResult> slow = t.tag(png());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      t.threadsChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runner.closed, isFalse);
      gate.complete();
      expect((await slow).count, greaterThan(0));
      await Future<void>.delayed(Duration.zero);
      expect(runner.closed, isTrue, reason: 'closed once the run is done');
      expect(t.status.value.state, TaggerState.ready);
    });

    test('all models off: the tagger is off, its own switch untouched', () async {
      final ImageTaggerHandler t = ImageTaggerHandler.instance;
      expect(await t.download('wd-vit'), isTrue);
      expect(t.enabled, isTrue);
      SettingsHandler.instance.aiModelsOff = true;
      expect(t.enabled, isFalse);
      expect(SettingsHandler.instance.aiImageTagger, isTrue);
    });
  });

  test('the session is closed after the idle time and opened again on the next picture', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    t.idleClose = const Duration(milliseconds: 40);
    expect(await t.download('wd-vit'), isTrue);
    await t.tag(png());
    expect(runner.closed, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(runner.closed, isTrue);
    expect(t.status.value.state, TaggerState.ready, reason: 'closing for idleness is not a failure');
    final _FakeRunner second = _FakeRunner(runner.probs);
    runner = second;
    await t.tag(png());
    expect(factoryCalls, 2);
    expect(second.runs, 1);
  });

  test('enabled follows the switch; a runtime failure is shown and not retried until a refresh; a picture that cannot be decoded is its own error', () async {
    final ImageTaggerHandler t = ImageTaggerHandler.instance;
    expect(await t.download('wd-vit'), isTrue);
    SettingsHandler.instance.aiImageTagger = false;
    expect(t.enabled, isFalse);
    expect(t.isReady, isTrue);
    SettingsHandler.instance.aiImageTagger = true;
    expect(t.enabled, isTrue);

    await expectLater(t.tag(Uint8List.fromList([1, 2, 3])), throwsA(isA<FormatException>()));
    expect(runner.runs, 0);
    expect(t.status.value.state, TaggerState.ready, reason: 'a bad picture is not the model\'s fault');

    runner = _FakeRunner(runner.probs, fail: true);
    await t.close();
    await expectLater(t.tag(png()), throwsA(isA<StateError>()));
    expect(t.status.value.state, TaggerState.error);
    expect(t.status.value.message, contains('could not be run'));
    expect(t.enabled, isFalse);
    runner = _FakeRunner(runner.probs);
    await t.refresh();
    expect(t.status.value.state, TaggerState.ready);
    final TaggerResult r = await t.tag(png());
    expect(r.count, 4);
  });

  test('tag() without a model is a StateError, not a crash', () async {
    await expectLater(ImageTaggerHandler.instance.tag(png()), throwsA(isA<StateError>()));
  });
}
