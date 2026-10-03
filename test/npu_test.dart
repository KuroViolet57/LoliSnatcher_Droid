import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_look_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_availability.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_tag_runner.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/model_page.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';

/// r87 (branch claude/r87-npu): the S24 Ultra's NPU (Snapdragon 8 Gen 3,
/// Hexagon HTP v75) through ONNX Runtime's QNN execution provider -
/// Microsoft's onnxruntime-android-qnn 1.23.0, the same ONNX Runtime as
/// before, with Qualcomm's qnn-runtime 2.37.1. The plugin is our own copy
/// (third_party/flutter_onnxruntime) so it can pass the provider options,
/// session config entries and fixed input sizes the NPU needs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('npu_test');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiModelsOff = false
      ..aiEncoder = true
      ..aiLook = true
      ..aiImageTagger = true;
    SettingsHandler.instance.modelRunOn.clear();
    ModelTasks.save = () async {};
    ModelTasks.maxThreads = () => 8;
    ModelTimings.instance.resetForTests(dir: '${tempDir.path}${Platform.pathSeparator}');
  });

  tearDown(() {
    ModelTasks.resetForTests();
    ModelsPage.resetForTests();
    ModelTimings.instance.resetForTests();
    SettingsHandler.instance.modelRunOn.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the plugin copy passes what the NPU needs', () {
    test('provider options, session config entries and fixed input sizes reach the platform side', () {
      final Map<String, dynamic> m = OrtSessionOptions(
        intraOpNumThreads: 2,
        providers: [OrtProvider.QNN, OrtProvider.CPU],
        providerOptions: const {
          'QNN': {'backend_path': 'libQnnHtp.so'},
        },
        sessionConfig: const {'ep.context_enable': '1'},
        symbolicDims: const {'*': 1},
      ).toMap();
      expect(m['providerOptions'], {
        'QNN': {'backend_path': 'libQnnHtp.so'},
      });
      expect(m['sessionConfig'], {'ep.context_enable': '1'});
      expect(m['symbolicDims'], {'*': 1});
      expect(OrtSessionOptions(intraOpNumThreads: 1).toMap(), {'intraOpNumThreads': 1}, reason: 'nothing new unless asked');
    });

    test('the Android side reads them, and builds on the QNN package of the same ONNX Runtime', () {
      final String kt = File('third_party/flutter_onnxruntime/android/src/main/kotlin/com/masicai/flutteronnxruntime/FlutterOnnxruntimePlugin.kt').readAsStringSync();
      for (final String s in ['"providerOptions"', '"sessionConfig"', '"symbolicDims"', 'addConfigEntry(', 'setSymbolicDimensionValue(', 'getDimensionNames(']) {
        expect(kt, contains(s), reason: s);
      }
      expect(kt, isNot(contains('addQnn(mapOf())')));
      expect(kt, isNot(contains('addXnnpack(mapOf())')));
      final String gradle = File('third_party/flutter_onnxruntime/android/build.gradle').readAsStringSync();
      expect(gradle, contains("'com.microsoft.onnxruntime:onnxruntime-android-qnn:1.23.0'"));
      expect(gradle, isNot(contains("'com.microsoft.onnxruntime:onnxruntime-android:1.23.0'")));
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'flutter_onnxruntime:\s*\n\s*path: third_party/flutter_onnxruntime').hasMatch(pubspec), isTrue);
      expect(File('third_party/flutter_onnxruntime/LOLISNATCHER_PATCH.md').existsSync(), isTrue);
    });

    test('the app lets the DSP load its libraries', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(RegExp(r'<uses-native-library\s+android:name="libcdsprpc.so"\s+android:required="false"\s*/>').hasMatch(manifest), isTrue);
      final String kt = File('android/app/src/main/kotlin/com/noaisu/loliSnatcher/MainActivity.kt').readAsStringSync();
      expect(kt, contains('ADSP_LIBRARY_PATH'));
      expect(kt, contains('nativeLibraryDir'));
      final String gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('useLegacyPackaging = dartEnvVars["LS_IS_STORE"] != "true"'), reason: 'native libraries as real files');
      expect(gradle, contains('"**/libQnnGpu.so"'), reason: 'backends the app never uses are left out');
      expect(gradle, isNot(contains('libQnnHtp')), reason: 'every NPU generation and the compiler stay');
    });
  });

  group('the options per choice', () {
    test('NPU: QNN with the HTP backend at 16-bit, the CPU for the rest', () {
      final OrtSessionOptions o = onnxSessionOptions(threads: 2, accelerator: ModelAccelerator.npu);
      expect(o.providers, [OrtProvider.QNN, OrtProvider.CPU]);
      expect(o.providerOptions!['QNN'], {
        'backend_path': 'libQnnHtp.so',
        'enable_htp_fp16_precision': '1',
        'htp_performance_mode': 'high_performance',
      });
      expect(o.intraOpNumThreads, 2);
    });

    test('XNNPACK now gets the thread count (its own pool), the session one thread, no spinning', () {
      final OrtSessionOptions o = onnxSessionOptions(threads: 4, accelerator: ModelAccelerator.xnnpack);
      expect(o.intraOpNumThreads, 1);
      expect(o.providerOptions, {
        'XNNPACK': {'intra_op_num_threads': '4'},
      });
      expect(o.sessionConfig, {'session.intra_op.allow_spinning': '0'});
    });

    test('the CPU and NNAPI are as in r86', () {
      final OrtSessionOptions cpu = onnxSessionOptions(threads: 2, accelerator: ModelAccelerator.cpu);
      expect((cpu.providers, cpu.providerOptions, cpu.sessionConfig, cpu.symbolicDims), (null, null, null, null));
      expect(onnxSessionOptions(threads: 2, accelerator: ModelAccelerator.nnapi).providers, [OrtProvider.NNAPI, OrtProvider.CPU]);
    });
  });

  group('compiled once, kept', () {
    test('the first opening compiles the whole model (no CPU fallback), then allows a mixed one', () {
      final List<NpuAttempt> a = npuAttempts('/m/model.onnx', modelBytes: 1234, threads: 2, exists: (_) => false);
      expect(a.map((x) => (x.path, x.whole)), [('/m/model.onnx', true), ('/m/model.onnx', false)]);
      expect(a[0].compileTo, '/m/model.onnx.npu2-1234-whole.onnx');
      expect(a[0].options.sessionConfig, {
        'session.disable_cpu_ep_fallback': '1',
        'ep.context_enable': '1',
        'ep.context_file_path': '/m/model.onnx.npu2-1234-whole.onnx',
        'ep.context_embed_mode': '1',
      });
      expect(a[0].options.symbolicDims, {'*': 1}, reason: 'the NPU needs fixed sizes: every free one is 1');
      expect(a[0].options.providers, [OrtProvider.QNN], reason: 'r88: no CPU listed next to a forbidden CPU fallback');
      expect(a[1].options.providers, [OrtProvider.QNN, OrtProvider.CPU]);
      expect(a[1].compileTo, '/m/model.onnx.npu2-1234-mixed.onnx');
      expect(a[1].options.sessionConfig!.containsKey('session.disable_cpu_ep_fallback'), isFalse);
    });

    test('a compiled copy is opened as it is; a new download (another size) compiles again', () {
      final List<NpuAttempt> whole = npuAttempts('/m/model.onnx', modelBytes: 1234, threads: 2, exists: (p) => p.endsWith('1234-whole.onnx'));
      expect(whole.map((x) => (x.path, x.whole, x.compileTo)), [('/m/model.onnx.npu2-1234-whole.onnx', true, null)]);
      expect(whole.single.options.symbolicDims, isNull);
      final List<NpuAttempt> mixed = npuAttempts('/m/model.onnx', modelBytes: 1234, threads: 2, exists: (p) => p.endsWith('1234-mixed.onnx'));
      expect(mixed.single.whole, isFalse);
      final List<NpuAttempt> other = npuAttempts('/m/model.onnx', modelBytes: 999, threads: 2, exists: (p) => p.endsWith('1234-whole.onnx'));
      expect(other.first.path, '/m/model.onnx');
    });
  });

  group('which models may use the NPU', () {
    test('the looks model and the tagger; the text model stays off it (its inputs change length)', () async {
      expect(ModelAccelerator.choicesFor(ModelKind.text), [ModelAccelerator.cpu, ModelAccelerator.xnnpack, ModelAccelerator.nnapi]);
      expect(ModelAccelerator.choicesFor(ModelKind.tagger), ModelAccelerator.values);
      expect(ModelAccelerator.choicesFor(ModelKind.look), ModelAccelerator.values);
      await ModelTasks.setRunOn(ModelKind.text, ModelAccelerator.npu);
      expect(ModelTasks.runOn(ModelKind.text), ModelAccelerator.cpu);
      expect(ModelTasks.parseRunOn({'text': 'npu', 'tagger': 'npu'}), {'tagger': 'npu'});
    });

    test("the looks model's picture half runs on the NPU only from its full-precision file; its text half stays on the CPU", () async {
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      final OnnxLookRunner npuFile = OnnxLookRunner('/d/${LookModelHandler.npuImageFileName}', '/d/text_model.onnx', threads: 2);
      expect(npuFile.acceleratorFor(image: true), ModelAccelerator.npu);
      expect(npuFile.acceleratorFor(image: false), ModelAccelerator.cpu);
      final OnnxLookRunner int8 = OnnxLookRunner('/d/vision_model.onnx', '/d/text_model.onnx', threads: 2);
      expect(int8.acceleratorFor(image: true), ModelAccelerator.cpu, reason: 'the int8 file is not for the NPU');
      await ModelTasks.setRunOn(ModelKind.tagger, ModelAccelerator.npu);
      expect(OnnxTagRunner('/t/model.onnx', threads: 2).options.providers, [OrtProvider.QNN, OrtProvider.CPU]);
      expect(LookModelHandler.npuImageRemote, 'onnx/vision_model.onnx');
      expect(LookPreset.s0.npuImageBytes, 45543630);
      expect(LookPreset.s2.npuImageBytes, 143020962);
    });
  });

  Future<void> openModel(WidgetTester tester, ModelKind kind) async {
    tester.view.physicalSize = const Size(1200, 16000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ModelPage(kind: kind)));
    await tester.pump();
  }

  Finder segment(String model, String label) => find.descendant(of: find.byKey(ValueKey('model-runon-$model')), matching: find.text(label));

  testWidgets("a model's page: NPU for the looks model and the tagger, not for the text model", (tester) async {
    OnnxAvailability.setForTests({'CPU', 'NNAPI', 'QNN', 'XNNPACK'});
    addTearDown(OnnxAvailability.resetForTests);
    ModelsPage.threadsChanged = (_) {};
    for (final (ModelKind kind, bool npu) in [(ModelKind.tagger, true), (ModelKind.look, true), (ModelKind.text, false)]) {
      await openModel(tester, kind);
      expect(segment(kind.name, 'NPU'), npu ? findsOneWidget : findsNothing, reason: kind.name);
    }
    await openModel(tester, ModelKind.tagger);
    await tester.tap(segment('tagger', 'NPU'));
    await tester.pump();
    expect(ModelTasks.runOn(ModelKind.tagger), ModelAccelerator.npu);

    await tester.tap(find.byKey(const ValueKey('model-runon-tagger-explain')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Dialog), matching: find.textContaining('compiles')), findsWidgets);
  });

  testWidgets('NPU for the looks model asks to download its full-precision picture half first, with its size', (tester) async {
    final List<String> fetched = [];
    bool ready = false;
    ModelsPage.threadsChanged = (_) {};
    ModelsPage.lookNpuReady = () => ready;
    ModelsPage.lookNpuBytes = () => 45543630;
    ModelsPage.downloadLookNpu = (void Function(double) progress) async {
      fetched.add('picture half');
      progress(1);
      ready = true;
      return true;
    };
    OnnxAvailability.setForTests({'CPU', 'QNN'});
    addTearDown(OnnxAvailability.resetForTests);
    await openModel(tester, ModelKind.look);
    await tester.tap(segment('look', 'NPU'));
    await tester.pumpAndSettle();
    expect(find.textContaining('43.4 MB'), findsOneWidget);
    expect(ModelTasks.runOn(ModelKind.look), ModelAccelerator.cpu, reason: 'not before the file is there');
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(fetched, ['picture half']);
    expect(ModelTasks.runOn(ModelKind.look), ModelAccelerator.npu);

    // Already there: no question.
    await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.cpu);
    await tester.pump();
    await tester.tap(segment('look', 'NPU'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(ModelTasks.runOn(ModelKind.look), ModelAccelerator.npu);
  });

  testWidgets('r89: under Run on, which NPU copy the model has; the failure note in plain words', (tester) async {
    final String model = '${tempDir.path}${Platform.pathSeparator}vision_model_npu.onnx';
    File(model).writeAsBytesSync(List<int>.filled(100, 1));
    ModelsPage.threadsChanged = (_) {};
    ModelsPage.lookNpuReady = () => true;
    ModelsPage.npuModelPath = (ModelKind kind) => kind == ModelKind.look ? model : null;
    OnnxAvailability.setForTests({'CPU', 'QNN'});
    addTearDown(OnnxAvailability.resetForTests);
    await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);

    Finder line() => find.byKey(const ValueKey('model-npu-copy-look'));
    String text() => tester.widget<Text>(line()).data!;

    await openModel(tester, ModelKind.look);
    expect(text(), startsWith('Not compiled yet'));

    File('$model.npu2-100-whole.onnx').writeAsBytesSync([1]);
    await openModel(tester, ModelKind.look);
    expect(text(), startsWith('On the NPU: the whole model'));

    File('$model.npu2-100-whole.onnx').deleteSync();
    File('$model.npu2-100-mixed.onnx').writeAsBytesSync([1]);
    File(npuWholeFailedMarker(model, 100)).writeAsBytesSync(const []);
    await openModel(tester, ModelKind.look);
    expect(text(), startsWith('On the NPU: some parts on the CPU'));
    expect(text(), contains('the whole model failed here'));

    ModelTimings.instance.recordNpuFailure(
      ModelKind.look,
      "PlatformException(INFERENCE_ERROR, Error code - ORT_FAIL - message: Non-zero status code returned while running QNN_15335302194635400314_107 node. Name:'QNNExecutionProvider_QNN_15335302194635400314_107_52' Status Message: QNN graph execute error. Error code: 6033, ai.onnxruntime.OrtException: …",
    );
    await openModel(tester, ModelKind.look);
    final Finder note = find.byKey(const ValueKey('model-npu-failed-look'));
    expect(find.descendant(of: note, matching: find.textContaining('QNN error 6033 (the NPU timed out) in part 107 of the model')), findsOneWidget);
    expect(find.descendant(of: note, matching: find.textContaining('PlatformException')), findsNothing, reason: 'the whole text stays in the log');

    // The CPU chosen: no NPU line.
    await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.cpu);
    await openModel(tester, ModelKind.look);
    expect(line(), findsNothing);
  });

  // ── r88 ──

  group('r88: a failed NPU run hands the work to the CPU, never breaks the model', () {
    test('the picture runs again on the CPU, and the failure is counted for that model', () async {
      final List<String> ran = [];
      final String out = await runGuarded<String>(
        model: ModelKind.look,
        used: ModelAccelerator.npu,
        who: 'look (picture half)',
        run: () async {
          ran.add('npu');
          throw Exception('QNN graph execute error. Error code: 6033');
        },
        onCpu: () async {
          ran.add('cpu');
          return 'vector';
        },
      );
      expect(out, 'vector');
      expect(ran, ['npu', 'cpu']);
      expect(ModelTimings.instance.npuFailures(ModelKind.look)!.count, 1);
      expect(ModelTimings.instance.npuFailures(ModelKind.look)!.reason, contains('6033'));
    });

    test('a failure on the CPU is a real failure (it is thrown)', () async {
      Object? error;
      try {
        await runGuarded<String>(
          model: ModelKind.tagger,
          used: ModelAccelerator.cpu,
          who: 'tagger',
          run: () async => throw StateError('broken model'),
          onCpu: () async => 'never',
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<StateError>());
      expect(ModelTimings.instance.npuFailures(ModelKind.tagger), isNull);
    });

    test('after two failures the model stays on the CPU until the NPU is picked again', () async {
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      ModelTimings.instance.recordNpuFailure(ModelKind.look, 'timed out');
      expect(savedAccelerator(ModelKind.look), ModelAccelerator.npu, reason: 'one failure: tried again at the next opening');
      ModelTimings.instance.recordNpuFailure(ModelKind.look, 'timed out');
      expect(savedAccelerator(ModelKind.look), ModelAccelerator.cpu);
      expect(ModelTasks.runOn(ModelKind.look), ModelAccelerator.npu, reason: 'the choice itself is kept, and shown');
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.cpu);
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      expect(ModelTimings.instance.npuFailures(ModelKind.look), isNull, reason: 'picking it again starts over');
      expect(savedAccelerator(ModelKind.look), ModelAccelerator.npu);
    });
  });

  group("r88: an opening the NPU took no part of is the CPU's (emulator, 2026-10-03)", () {
    late List<String> opened;
    late List<String> closed;
    late String model;

    setUp(() {
      opened = [];
      closed = [];
      model = '${tempDir.path}${Platform.pathSeparator}vision_model.onnx';
      File(model).writeAsBytesSync(List<int>.filled(100, 1));
      closeOrtSession = (s) async => closed.add(s.id);
    });
    tearDown(resetOnnxSeamsForTests);

    OrtSession session(String id) => OrtSession.fromMap({'sessionId': id});

    test('QNN cannot start: the mixed try opens with every part on the CPU and compiles nothing - so it is the CPU', () async {
      // The emulator: "QNN SetupBackend failed"; ONNX Runtime still opened
      // the mixed try, the CPU ran it all, and the timings said NPU.
      createOrtSession = (path, options) async {
        opened.add(path);
        if (!(options?.providers ?? const [OrtProvider.CPU]).contains(OrtProvider.CPU)) throw Exception('QNN SetupBackend failed');
        return session('s${opened.length}');
      };
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      final OpenedSession s = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(s.used, ModelAccelerator.cpu);
      expect(s.provider, 'CPU x1 (NPU refused)');
      expect(closed, ['s2'], reason: 'the mixed session, all on the CPU under the NPU name, is closed');
      expect(ModelTimings.instance.open(ModelKind.look, ModelAccelerator.npu), isNull);
      expect(ModelTimings.instance.open(ModelKind.look, ModelAccelerator.cpu), isNotNull);
      // The emulator's card said "runs on NPU" for this: what was asked for
      // and what it got is kept, so the pages can tell.
      expect(actualAccelerator(ModelKind.look), (used: ModelAccelerator.cpu, refused: 'the NPU took no part of it'));
    });

    test('the NPU compiles: the copy is written and opened - the NPU', () async {
      createOrtSession = (path, options) async {
        opened.add(path);
        if (!(options?.providers ?? const [OrtProvider.CPU]).contains(OrtProvider.CPU)) throw Exception('the NPU cannot run every part');
        final String? to = options?.sessionConfig?['ep.context_file_path'];
        if (to != null) File(to).writeAsBytesSync([1]);
        return session('s${opened.length}');
      };
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      final OpenedSession s = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(s.used, ModelAccelerator.npu);
      expect(s.provider, 'NPU + CPU');
      expect(opened.last, '$model.npu2-100-mixed.onnx', reason: 'switched to the compiled copy');
      expect(closed, ['s2'], reason: 'the compiling session');
      expect(ModelTimings.instance.open(ModelKind.look, ModelAccelerator.npu), isNotNull);
      expect(actualAccelerator(ModelKind.look), (used: ModelAccelerator.npu, refused: null));
    });

    test('a refusal speaks for that choice only: picked again (or another), the choice is shown until the model opens', () async {
      ModelTimings.instance.recordOpened(ModelKind.look, tried: ModelAccelerator.npu, used: ModelAccelerator.cpu, refused: 'x');
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.cpu);
      expect(actualAccelerator(ModelKind.look), (used: ModelAccelerator.cpu, refused: null));
      await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
      expect(actualAccelerator(ModelKind.look), (used: ModelAccelerator.npu, refused: null), reason: 'NPU picked again: a new try, shown as chosen');
    });
  });

  // ── r89 (phone log 2026-10-03) ──

  group('r89: one fresh compile, the whole model first', () {
    test("build 117's copies (npu-…) do not count: the whole model is tried, as npu2", () {
      final List<NpuAttempt> a = npuAttempts(
        '/m/vision_model_npu.onnx',
        modelBytes: 143020962,
        threads: 2,
        exists: (p) => p == '/m/vision_model_npu.onnx.npu-143020962-mixed.onnx',
      );
      expect(a.map((x) => (x.whole, x.compileTo)), [
        (true, '/m/vision_model_npu.onnx.npu2-143020962-whole.onnx'),
        (false, '/m/vision_model_npu.onnx.npu2-143020962-mixed.onnx'),
      ]);
    });

    test('a whole copy that failed while running is not compiled again: the mixed kind is', () {
      final List<NpuAttempt> a = npuAttempts('/m/model.onnx', modelBytes: 1234, threads: 2, exists: (p) => p == npuWholeFailedMarker('/m/model.onnx', 1234));
      expect(a.map((x) => (x.whole, x.compileTo)), [(false, '/m/model.onnx.npu2-1234-mixed.onnx')]);
      expect(npuWholeFailedMarker('/m/model.onnx', 1234), '/m/model.onnx.npu2-1234-whole.failed');
    });

    test("old and other-size copies next to the model are cleared; this size's copies and mark stay", () {
      const String m = '/m/model.onnx';
      expect(
        staleNpuFiles(m, 1234, [
          '/m/model.onnx',
          '/m/model.onnx.npu-1234-mixed.onnx',
          '/m/model.onnx.npu-999-whole.onnx',
          '/m/model.onnx.npu2-999-mixed.onnx',
          '/m/model.onnx.npu2-999-whole.failed',
          '/m/model.onnx.npu2-1234-whole.onnx',
          '/m/model.onnx.npu2-1234-whole.failed',
          '/m/text_model.onnx.npu-1-mixed.onnx',
          '/m/tokenizer.json',
        ]),
        unorderedEquals([
          '/m/model.onnx.npu-1234-mixed.onnx',
          '/m/model.onnx.npu-999-whole.onnx',
          '/m/model.onnx.npu2-999-mixed.onnx',
          '/m/model.onnx.npu2-999-whole.failed',
        ]),
      );
    });
  });

  group('r89: openings and failures with real files', () {
    late List<String> opened;
    late List<String> closed;
    late String model;

    setUp(() {
      opened = [];
      closed = [];
      model = '${tempDir.path}${Platform.pathSeparator}vision_model_npu.onnx';
      File(model).writeAsBytesSync(List<int>.filled(100, 1));
      closeOrtSession = (s) async => closed.add(s.id);
      // The NPU takes the whole model: the compile writes its copy.
      createOrtSession = (path, options) async {
        opened.add(path);
        final String? to = options?.sessionConfig?['ep.context_file_path'];
        if (to != null) File(to).writeAsBytesSync([1]);
        return OrtSession.fromMap({'sessionId': 's${opened.length}'});
      };
    });
    tearDown(resetOnnxSeamsForTests);

    test("the first opening clears build 117's copy, compiles the whole model, and starts the failure count over", () async {
      File('$model.npu-100-mixed.onnx').writeAsBytesSync([1]);
      ModelTimings.instance.recordNpuFailure(ModelKind.look, 'QNN graph execute error. Error code: 6033');
      final OpenedSession s = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(s.used, ModelAccelerator.npu);
      expect(s.provider, 'NPU');
      expect(s.npuCopy, '$model.npu2-100-whole.onnx');
      expect(File('$model.npu-100-mixed.onnx').existsSync(), isFalse, reason: "build 117's copy is gone");
      expect(File('$model.npu2-100-whole.onnx').existsSync(), isTrue);
      expect(ModelTimings.instance.npuFailures(ModelKind.look), isNull, reason: 'a new copy gets a fresh chance');
    });

    test('opened from a copy, the failure count is kept', () async {
      File('$model.npu2-100-mixed.onnx').writeAsBytesSync([1]);
      ModelTimings.instance.recordNpuFailure(ModelKind.look, 'x');
      final OpenedSession s = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(s.npuCopy, '$model.npu2-100-mixed.onnx');
      expect(s.provider, 'NPU + CPU');
      expect(ModelTimings.instance.npuFailures(ModelKind.look)!.count, 1);
    });

    test('a whole copy that fails while running is deleted and marked; the next opening compiles the mixed kind', () async {
      final OpenedSession s = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(s.npuCopy, '$model.npu2-100-whole.onnx');
      await runGuarded<String>(
        model: ModelKind.look,
        used: s.used,
        copy: s.npuCopy,
        who: 'look (picture half)',
        run: () async => throw Exception('QNN graph execute error. Error code: 6033'),
        onCpu: () async => 'cpu',
      );
      expect(File('$model.npu2-100-whole.onnx').existsSync(), isFalse);
      expect(File(npuWholeFailedMarker(model, 100)).existsSync(), isTrue);
      expect(ModelTimings.instance.npuFailures(ModelKind.look)!.count, 1);

      opened.clear();
      final OpenedSession again = await openOnnxSession(model, model: ModelKind.look, threads: 1, accelerator: ModelAccelerator.npu, who: 'look');
      expect(again.provider, 'NPU + CPU');
      expect(again.npuCopy, '$model.npu2-100-mixed.onnx');
      expect(opened.first, model, reason: 'compiled from the model, the mixed kind straight away');
      expect(opened, isNot(contains('$model.npu2-100-whole.onnx')));
    });

    test('a mixed copy that fails while running is kept (the same one would be built again)', () async {
      File('$model.npu2-100-mixed.onnx').writeAsBytesSync([1]);
      await runGuarded<String>(
        model: ModelKind.tagger,
        used: ModelAccelerator.npu,
        copy: '$model.npu2-100-mixed.onnx',
        who: 'tagger',
        run: () async => throw Exception('QNN graph execute error. Error code: 6033'),
        onCpu: () async => 'cpu',
      );
      expect(File('$model.npu2-100-mixed.onnx').existsSync(), isTrue);
      expect(File(npuWholeFailedMarker(model, 100)).existsSync(), isFalse);
    });

    test('what the NPU copy next to a model is, for the Speed part', () async {
      expect(npuCopyState(model), (whole: null, compiled: null, wholeFailed: false), reason: 'nothing compiled yet');
      File('$model.npu2-100-mixed.onnx').writeAsBytesSync([1]);
      File(npuWholeFailedMarker(model, 100)).writeAsBytesSync(const []);
      final state = npuCopyState(model);
      expect(state.whole, isFalse);
      expect(state.wholeFailed, isTrue);
      expect(state.compiled, isNotNull);
      File('$model.npu2-100-whole.onnx').writeAsBytesSync([1]);
      expect(npuCopyState(model).whole, isTrue);
    });
  });

  group("r89: the failure note in plain words (the phone's own error, 2026-10-03)", () {
    // The reason r88 stored for the looks model, as the phone's log has it.
    const String phone =
        "PlatformException(INFERENCE_ERROR, Error code - ORT_FAIL - message: Non-zero status code returned while running QNN_15335302194635400314_107 node. Name:'QNNExecutionProvider_QNN_15335302194635400314_107_52' Status Message: QNN graph execute error. Error code: 6033, ai.onnxruntime.OrtException: Error code - ORT_FAIL - message: Non-zero status code returned while running QNN_15335302194635400314_107 node.";

    test('the code, what it means, and the part of the model', () {
      expect(npuErrorWords(phone), 'QNN error 6033 (the NPU timed out) in part 107 of the model');
    });

    test('without a code: the first line, kept short', () {
      expect(npuErrorWords('Exception: something else\nat a.b'), 'Exception: something else');
      expect(npuErrorWords('x' * 300).length, lessThanOrEqualTo(121));
    });
  });

  group('r88: only what this build has is offered', () {
    tearDown(OnnxAvailability.resetForTests);

    test("the NPU build has no XNNPACK (log 2026-10-02: 'not supported in this build')", () async {
      OnnxAvailability.setForTests({'CPU', 'QNN'});
      expect(OnnxAvailability.choicesFor(ModelKind.tagger), [ModelAccelerator.cpu, ModelAccelerator.npu]);
      expect(OnnxAvailability.choicesFor(ModelKind.text), [ModelAccelerator.cpu]);
      await ModelTasks.setRunOn(ModelKind.text, ModelAccelerator.xnnpack);
      expect(savedAccelerator(ModelKind.text), ModelAccelerator.cpu, reason: 'a stored choice the build lacks runs on the CPU');
    });

    test('before the build has been asked, every choice is offered', () {
      OnnxAvailability.resetForTests();
      expect(OnnxAvailability.choicesFor(ModelKind.tagger), ModelAccelerator.values);
    });
  });
}
