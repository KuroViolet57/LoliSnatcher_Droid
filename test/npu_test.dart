import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_look_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_tag_runner.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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
      expect(a[0].compileTo, '/m/model.onnx.npu-1234-whole.onnx');
      expect(a[0].options.sessionConfig, {
        'session.disable_cpu_ep_fallback': '1',
        'ep.context_enable': '1',
        'ep.context_file_path': '/m/model.onnx.npu-1234-whole.onnx',
        'ep.context_embed_mode': '1',
      });
      expect(a[0].options.symbolicDims, {'*': 1}, reason: 'the NPU needs fixed sizes: every free one is 1');
      expect(a[1].compileTo, '/m/model.onnx.npu-1234-mixed.onnx');
      expect(a[1].options.sessionConfig!.containsKey('session.disable_cpu_ep_fallback'), isFalse);
    });

    test('a compiled copy is opened as it is; a new download (another size) compiles again', () {
      final List<NpuAttempt> whole = npuAttempts('/m/model.onnx', modelBytes: 1234, threads: 2, exists: (p) => p.endsWith('1234-whole.onnx'));
      expect(whole.map((x) => (x.path, x.whole, x.compileTo)), [('/m/model.onnx.npu-1234-whole.onnx', true, null)]);
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

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 16000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ModelsPage()));
    await tester.pump();
  }

  Finder segment(String model, String label) => find.descendant(of: find.byKey(ValueKey('model-runon-$model')), matching: find.text(label));

  testWidgets('Models page: NPU for the looks model and the tagger, not for the text model', (tester) async {
    ModelsPage.availableProviders = () async => ['CPU', 'NNAPI', 'QNN', 'XNNPACK'];
    ModelsPage.threadsChanged = (_) {};
    await openPage(tester);
    expect(segment('tagger', 'NPU'), findsOneWidget);
    expect(segment('look', 'NPU'), findsOneWidget);
    expect(segment('text', 'NPU'), findsNothing);
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
    await openPage(tester);
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
}
