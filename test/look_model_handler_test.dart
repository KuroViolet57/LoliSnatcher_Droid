import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r75: the downloadable "looks" model (MobileCLIP ONNX): a picture or a
/// sentence into one unit vector, so lookalikes sit close. The runner here
/// is a fake; the tokenizer is the real one over the small fixture.
class _FakeLook implements LookRunner {
  int imageRuns = 0;
  int textRuns = 0;
  int lastSize = 0;
  int lastLength = 0;
  List<int> lastIds = [];
  List<int> lastMask = [];
  bool closed = false;
  bool closedDuringRun = false;
  bool _running = false;
  Completer<void>? gate;
  Float32List Function(int run)? imageAnswer;

  @override
  String get provider => 'fake';

  @override
  Future<Float32List> image(Float32List nchw, int size) async {
    imageRuns++;
    lastSize = size;
    lastLength = nchw.length;
    _running = true;
    try {
      if (gate != null) await gate!.future;
    } finally {
      _running = false;
    }
    return imageAnswer?.call(imageRuns) ?? Float32List.fromList([3, 4]);
  }

  @override
  Future<Float32List> text(List<int> ids, List<int> mask) async {
    textRuns++;
    lastIds = List<int>.of(ids);
    lastMask = List<int>.of(mask);
    return Float32List.fromList([0, 2]);
  }

  @override
  Future<void> close() async {
    if (_running) closedDuringRun = true;
    closed = true;
  }
}

const String preprocessorJson =
    '{"crop_size":{"height":256,"width":256},"do_center_crop":true,"do_convert_rgb":true,"do_normalize":false,"do_rescale":true,"do_resize":true,"resample":2,"rescale_factor":0.00392156862745098,"size":{"shortest_edge":256}}';

Uint8List rgb(List<List<List<int>>> rows) {
  final img.Image image = img.Image(width: rows.first.length, height: rows.length);
  for (int y = 0; y < rows.length; y++) {
    for (int x = 0; x < rows[y].length; x++) {
      image.setPixelRgb(x, y, rows[y][x][0], rows[y][x][1], rows[y][x][2]);
    }
  }
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeLook runner;
  late bool dbReady;
  final List<String> fetched = [];
  int factoryCalls = 0;
  String preprocessor = preprocessorJson;
  final String tokenizerText = File('test/fixtures/clip_tokenizer_small.json').readAsStringSync();

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('look');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiLook = true
      ..lookModel = '';
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
    runner = _FakeLook();
    fetched.clear();
    factoryCalls = 0;
    preprocessor = preprocessorJson;
    LookModelHandler.unregister();
    final LookModelHandler h = LookModelHandler.register();
    h.runnerFactory = (String imagePath, String textPath) {
      factoryCalls++;
      return runner;
    };
    h.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
      fetched.add(url);
      to.parent.createSync(recursive: true);
      if (url.endsWith('tokenizer.json')) {
        to.writeAsStringSync(tokenizerText);
      } else if (url.endsWith('preprocessor_config.json')) {
        to.writeAsStringSync(preprocessor);
      } else if (url.contains('vision')) {
        to.writeAsBytesSync(List<int>.filled(1000, 1));
      } else {
        to.writeAsBytesSync(List<int>.filled(500, 2));
      }
      onProgress?.call(1000, 1000);
    };
    h.thumbnailFetcher = (BooruItem item, Booru? booru) async => rgb([
      [
        [10, 20, 30],
        [10, 20, 30],
      ],
      [
        [10, 20, 30],
        [10, 20, 30],
      ],
    ]);
  });

  tearDown(() async {
    await LookModelHandler.maybe?.close();
    LookModelHandler.unregister();
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<LookModelHandler> ready() async {
    final LookModelHandler h = LookModelHandler.instance;
    expect(await h.download('s0'), isTrue, reason: h.status.value.message);
    return h;
  }

  test('presets: the small MobileCLIP first (55 MB), the larger one after; files live under look/<slug>/', () {
    expect(LookPreset.values.map((p) => p.id).toList(), ['s0', 's2']);
    expect(LookPreset.s0.repo, 'Xenova/mobileclip_s0');
    expect(LookPreset.s0.bytes, 11846843 + 42799238);
    expect(LookPreset.s2.bytes, 36735889 + 64117260);
    expect(LookPreset.byId('nope'), isNull);
    expect(LookModelHandler.repoOf('s0'), 'Xenova/mobileclip_s0');
    expect(LookModelHandler.instance.dirFor('s0'), contains('look${Platform.pathSeparator}xenova__mobileclip_s0${Platform.pathSeparator}'));
    expect(LookModelHandler.instance.enabled, isFalse);
  });

  test('download: the two model halves, the tokenizer and the preprocessing config, then a manifest; refresh and delete', () async {
    final LookModelHandler h = await ready();
    expect(fetched, [
      'https://huggingface.co/Xenova/mobileclip_s0/resolve/main/onnx/vision_model_quantized.onnx',
      'https://huggingface.co/Xenova/mobileclip_s0/resolve/main/onnx/text_model_quantized.onnx',
      'https://huggingface.co/Xenova/mobileclip_s0/resolve/main/tokenizer.json',
      'https://huggingface.co/Xenova/mobileclip_s0/resolve/main/preprocessor_config.json',
    ]);
    final LookStatus s = h.status.value;
    expect(s.state, LookState.ready);
    expect(s.repo, 'Xenova/mobileclip_s0');
    expect(s.inputSize, 256);
    expect(s.bytes, 1500);
    expect(SettingsHandler.instance.lookModel, 's0');
    final String dir = h.dirFor('s0');
    for (final String f in ['vision_model.onnx', 'text_model.onnx', 'tokenizer.json', 'preprocessor_config.json', 'manifest.json']) {
      expect(File('$dir$f').existsSync(), isTrue, reason: f);
    }
    final Map<String, dynamic> manifest = jsonDecode(File('${dir}manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['inputSize'], 256);
    expect(manifest['mean'], isNull);
    expect(h.enabled, isTrue);
    expect(h.modelId, 'xenova__mobileclip_s0');

    LookModelHandler.unregister();
    final LookModelHandler again = LookModelHandler.register();
    await again.refresh();
    expect(again.status.value.state, LookState.ready);
    expect(again.inputSize, 256);
    await again.delete();
    expect(Directory(again.dirFor('s0')).existsSync(), isFalse);
    expect(SettingsHandler.instance.lookModel, '');
    expect(again.status.value.state, LookState.none);
  });

  test('a failed download keeps nothing and says why', () async {
    final LookModelHandler h = LookModelHandler.instance;
    h.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
      if (url.endsWith('tokenizer.json')) throw DioException(requestOptions: RequestOptions(path: url), message: 'tokenizer gone');
      to.parent.createSync(recursive: true);
      to.writeAsBytesSync(const [1, 2, 3]);
    };
    expect(await h.download('s0'), isFalse);
    expect(h.status.value.state, LookState.error);
    expect(h.status.value.message, contains('tokenizer gone'));
    expect(Directory(h.dirFor('s0')).existsSync(), isFalse);
    expect(await h.download('nope'), isFalse);
    expect(h.status.value.message, contains('owner/model'));
  });

  test('prepareImage: shortest edge to the size, centre crop, planes R then G then B, 0-1; mean and std when the model wants them', () {
    // 4 wide, 2 high, size 2: no resize (the short edge is 2), the middle two columns kept.
    final Uint8List wide = rgb([
      [
        [255, 0, 0],
        [0, 255, 0],
        [0, 0, 255],
        [255, 255, 255],
      ],
      [
        [255, 0, 0],
        [0, 255, 0],
        [0, 0, 255],
        [255, 255, 255],
      ],
    ]);
    final Float32List t = LookModelHandler.prepareImage(wide, 2);
    expect(t, hasLength(3 * 2 * 2));
    expect(t.sublist(0, 4), [0, 0, 0, 0], reason: 'R plane: green and blue pixels');
    expect(t.sublist(4, 8), [1, 0, 1, 0], reason: 'G plane');
    expect(t.sublist(8, 12), [0, 1, 0, 1], reason: 'B plane');
    // 2 wide, 4 high: the middle two rows kept.
    final Uint8List tall = rgb([
      [
        [255, 255, 255],
        [255, 255, 255],
      ],
      [
        [255, 0, 0],
        [255, 0, 0],
      ],
      [
        [0, 0, 255],
        [0, 0, 255],
      ],
      [
        [255, 255, 255],
        [255, 255, 255],
      ],
    ]);
    final Float32List u = LookModelHandler.prepareImage(tall, 2);
    expect(u.sublist(0, 4), [1, 1, 0, 0], reason: 'R plane: the red row then the blue row');
    expect(u.sublist(8, 12), [0, 0, 1, 1], reason: 'B plane');
    // Larger than the size: resized first, every value within 0-1.
    final img.Image big = img.Image(width: 8, height: 4);
    img.fill(big, color: img.ColorRgb8(255, 128, 0));
    final Float32List v = LookModelHandler.prepareImage(img.encodePng(big), 2);
    expect(v, hasLength(12));
    for (final double x in v) {
      expect(x, inInclusiveRange(0, 1));
    }
    expect(v[0], closeTo(1, 0.01));
    expect(v[4], closeTo(128 / 255, 0.02));
    // A model with mean/std (the OpenAI CLIP family): (x - mean) / std.
    final Float32List n = LookModelHandler.prepareImage(wide, 2, mean: const [0.5, 0.5, 0.5], std: const [0.5, 0.5, 0.5]);
    expect(n.sublist(0, 4), [-1, -1, -1, -1]);
    expect(n.sublist(4, 8), [1, -1, 1, -1]);
    expect(() => LookModelHandler.prepareImage(Uint8List.fromList([1, 2, 3, 4]), 2), throwsA(isA<FormatException>()));
  });

  test('imageVector: the picture through the model, as a unit vector; textVector: the sentence through the tokenizer and the text half', () async {
    final LookModelHandler h = await ready();
    final Float32List v = await h.imageVector(rgb([
      [
        [1, 2, 3],
      ],
    ]));
    expect(v[0], closeTo(0.6, 1e-6));
    expect(v[1], closeTo(0.8, 1e-6));
    expect(runner.imageRuns, 1);
    expect(runner.lastSize, 256);
    expect(runner.lastLength, 3 * 256 * 256);
    expect(h.dim, 2);
    expect(factoryCalls, 1);

    final Float32List? t = await h.textVector('a photo of a cat');
    expect(t, isNotNull);
    expect(t![0], closeTo(0, 1e-6));
    expect(t[1], closeTo(1, 1e-6));
    expect(runner.lastIds, hasLength(77));
    expect(runner.lastIds.sublist(0, 7), [49406, 320, 1125, 539, 320, 2368, 49407]);
    expect(runner.lastMask.sublist(0, 7), everyElement(1));
    expect(runner.lastMask[7], 0);
    expect(runner.lastIds[7], 0);
    await h.textVector('a photo of a cat');
    expect(runner.textRuns, 1, reason: 'a sentence is embedded once');
    expect(await h.textVector('   '), isNull);
    expect(factoryCalls, 1, reason: 'one runner for both halves');
  });

  test('imageVectors: thumbnails through the model once, then from memory, then from the database', () async {
    final LookModelHandler h = await ready();
    runner.imageAnswer = (int run) => Float32List.fromList([run.toDouble(), 0]);
    final List<BooruItem> items = [
      BooruItem(fileURL: 'https://x.example/1.jpg', sampleURL: '', thumbnailURL: 'https://x.example/t1.jpg', tagsList: const [], postURL: 'https://x.example/p/1'),
      BooruItem(fileURL: 'https://x.example/2.jpg', sampleURL: '', thumbnailURL: 'https://x.example/t2.jpg', tagsList: const [], postURL: 'https://x.example/p/2'),
      BooruItem(fileURL: 'https://x.example/3.jpg', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://x.example/p/3'),
    ];
    final List<Float32List?> first = await h.imageVectors(items);
    expect(first[0], isNotNull);
    expect(first[0]![0], closeTo(1, 1e-6));
    expect(first[1]![0], closeTo(1, 1e-6));
    expect(first[2], isNull, reason: 'no thumbnail, no vector');
    expect(runner.imageRuns, 2);
    expect(h.cached(items[0]), isNotNull);
    final List<Float32List?> second = await h.imageVectors(items);
    expect(second[0], isNotNull);
    expect(runner.imageRuns, 2, reason: 'from memory');
    if (dbReady) {
      h.resetMemoryForTests();
      expect(h.cached(items[0]), isNull);
      final List<Float32List?> third = await h.imageVectors(items);
      expect(third[1], isNotNull);
      expect(runner.imageRuns, 2, reason: 'from the database');
    }
    // A thumbnail that cannot be fetched leaves that item without a vector and the others fine.
    h.resetMemoryForTests();
    h.thumbnailFetcher = (BooruItem item, Booru? booru) async => item.thumbnailURL.endsWith('t1.jpg') ? null : rgb([
      [
        [5, 5, 5],
      ],
    ]);
    final List<BooruItem> more = [
      BooruItem(fileURL: 'https://x.example/4.jpg', sampleURL: '', thumbnailURL: 'https://x.example/t1.jpg', tagsList: const [], postURL: 'https://x.example/p/4'),
      BooruItem(fileURL: 'https://x.example/5.jpg', sampleURL: '', thumbnailURL: 'https://x.example/t5.jpg', tagsList: const [], postURL: 'https://x.example/p/5'),
    ];
    final List<Float32List?> fourth = await h.imageVectors(more);
    expect(fourth[0], isNull);
    expect(fourth[1], isNotNull);
  });

  test('the session closes after the idle time and opens again; a runner failure is shown until a refresh; the switch', () async {
    final LookModelHandler h = await ready();
    h.idleClose = const Duration(milliseconds: 40);
    await h.imageVector(rgb([
      [
        [1, 2, 3],
      ],
    ]));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(runner.closed, isTrue);
    expect(h.status.value.state, LookState.ready);
    runner = _FakeLook();
    await h.imageVector(rgb([
      [
        [1, 2, 3],
      ],
    ]));
    expect(factoryCalls, 2);
    SettingsHandler.instance.aiLook = false;
    expect(h.enabled, isFalse);
    expect(h.isReady, isTrue);
    SettingsHandler.instance.aiLook = true;
    h.runnerFactory = (String i, String t) => throw StateError('no runtime');
    await h.close();
    await expectLater(h.imageVector(rgb([
      [
        [1, 2, 3],
      ],
    ])), throwsA(isA<StateError>()));
    expect(h.status.value.state, LookState.error);
    expect(h.enabled, isFalse);
    h.runnerFactory = (String i, String t) => _FakeLook();
    await h.refresh();
    expect(h.status.value.state, LookState.ready);
  });

  group('r80: the thread counts and the switches of Settings → Models', () {
    Uint8List pic() => rgb([
      [
        [1, 2, 3],
      ],
    ]);

    setUp(() {
      ModelTasks.save = () async {};
      ModelTasks.maxThreads = () => 8;
    });

    tearDown(() {
      ModelTasks.resetForTests();
      SettingsHandler.instance.modelThreads.clear();
      SettingsHandler.instance.aiModelsOff = false;
    });

    test("learning opens the model with the background count, a board with the waiting count; today's are 1 and 1", () async {
      final LookModelHandler h = await ready();
      await h.imageVector(pic(), use: ModelUse.background);
      expect(h.openedThreads, 1);
      await h.close();
      await ModelTasks.setThreads(ModelKind.look, ModelUse.background, 3);
      await ModelTasks.setThreads(ModelKind.look, ModelUse.waiting, 5);
      await h.imageVector(pic(), use: ModelUse.background);
      expect(h.openedThreads, 3);
      await h.close();
      await h.imageVector(pic());
      expect(h.openedThreads, 5, reason: 'waiting is the default');
      await h.close();
      await h.textVector('a board about cats', use: ModelUse.background);
      expect(h.openedThreads, 3);
    });

    test('a new count applies at once, and never closes the model under a run', () async {
      final LookModelHandler h = await ready();
      await h.imageVector(pic());
      h.threadsChanged();
      await Future<void>.delayed(Duration.zero);
      expect(runner.closed, isTrue, reason: 'idle: closed now, opened again with the new count');

      runner = _FakeLook();
      final Completer<void> gate = Completer<void>();
      runner.gate = gate;
      final Future<Float32List> slow = h.imageVector(pic());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      h.threadsChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runner.closed, isFalse);
      gate.complete();
      await slow;
      await Future<void>.delayed(Duration.zero);
      expect(runner.closedDuringRun, isFalse);
      expect(runner.closed, isTrue, reason: 'closed once the run is done');
      expect(h.status.value.state, LookState.ready);
    });

    test('all models off: the looks model is off, its own switch untouched', () async {
      final LookModelHandler h = await ready();
      expect(h.enabled, isTrue);
      SettingsHandler.instance.aiModelsOff = true;
      expect(h.enabled, isFalse);
      expect(SettingsHandler.instance.aiLook, isTrue);
    });
  });

  test('a preprocessing config with mean and std lands in the manifest and is applied', () async {
    preprocessor = '{"do_normalize":true,"image_mean":[0.5,0.5,0.5],"image_std":[0.5,0.5,0.5],"size":{"shortest_edge":224},"crop_size":{"height":224,"width":224}}';
    final LookModelHandler h = await ready();
    expect(h.inputSize, 224);
    expect(h.mean, [0.5, 0.5, 0.5]);
    await h.imageVector(rgb([
      [
        [255, 255, 255],
      ],
    ]));
    expect(runner.lastSize, 224);
  });

  test('r76: putItemVector puts a video\'s vector in memory and the database, over its preview picture\'s; meanOf averages unit vectors', () async {
    final LookModelHandler h = await ready();
    runner.imageAnswer = (int run) => Float32List.fromList([1, 0]);
    final BooruItem item = BooruItem(fileURL: 'https://x.example/9.mp4', sampleURL: '', thumbnailURL: 'https://x.example/t9.jpg', tagsList: const [], postURL: 'https://x.example/p/9');
    await h.imageVectors([item]);
    expect(h.cached(item), [1, 0]);
    await h.putItemVector(item, Float32List.fromList([0, 1]));
    expect(h.cached(item), [0, 1]);
    if (dbReady) {
      h.resetMemoryForTests();
      final List<Float32List?> again = await h.imageVectors([item]);
      expect(again.single, [0, 1], reason: 'the database holds the frames\' vector now');
      expect(runner.imageRuns, 1, reason: 'the preview picture is not read again');
    }
    final Float32List m = LookModelHandler.meanOf([Float32List.fromList([1, 0]), Float32List.fromList([0, 1])]);
    expect(m[0], closeTo(0.70710678, 1e-6));
    expect(m[1], closeTo(0.70710678, 1e-6));
    expect(LookModelHandler.meanOf([Float32List.fromList([3, 4])]), [0.6000000238418579, 0.800000011920929]);
    expect(LookModelHandler.meanOf(const []), isEmpty);
  });
}
