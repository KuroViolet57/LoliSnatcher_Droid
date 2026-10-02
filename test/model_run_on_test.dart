import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_embedding_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_look_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_tag_runner.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';

/// r86: Settings → Recommendations → Models → "Run on", per model: the CPU
/// (ONNX Runtime's own code, as before), XNNPACK or NNAPI - the three the
/// app's ONNX Runtime 1.23 build has. Each choice and the picture decoder
/// have an explain window with what they are good at and the timings this
/// phone measured.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final List<ModelKind> reopened = [];

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('model_run_on_test');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiModelsOff = false
      ..aiEncoder = true
      ..aiLook = true
      ..aiImageTagger = true;
    SettingsHandler.instance.modelRunOn.clear();
    reopened.clear();
    ModelTasks.save = () async {};
    ModelTasks.maxThreads = () => 8;
    ModelsPage.threadsChanged = reopened.add;
    ModelsPage.availableProviders = () async => ['CPU', 'NNAPI', 'XNNPACK'];
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

  test('every model runs on the CPU until you choose otherwise; the choice belongs to this phone', () async {
    final settings = SettingsHandler.instance;
    for (final ModelKind m in ModelKind.values) {
      expect(ModelTasks.runOn(m), ModelAccelerator.cpu, reason: m.name);
    }
    await ModelTasks.setRunOn(ModelKind.tagger, ModelAccelerator.nnapi);
    expect(ModelTasks.runOn(ModelKind.tagger), ModelAccelerator.nnapi);
    expect(settings.modelRunOn, {'tagger': 'nnapi'});
    await ModelTasks.setRunOn(ModelKind.tagger, ModelAccelerator.cpu);
    expect(settings.modelRunOn, isEmpty, reason: 'the default is not stored');
    expect(settings.deviceSpecificSettings, contains('modelRunOn'));
    expect(ModelTasks.parseRunOn({'tagger': 'nnapi', 'look': 'warp', 'other': 'cpu', 'text': 3}), {'tagger': 'nnapi'});
  });

  test('the CPU opens with exactly the options from before; the others ask for their provider first, then the CPU', () {
    final OrtSessionOptions cpu = onnxSessionOptions(threads: 2, accelerator: ModelAccelerator.cpu);
    expect(cpu.intraOpNumThreads, 2);
    expect(cpu.providers, isNull);
    expect(onnxSessionOptions(threads: 4, accelerator: ModelAccelerator.nnapi).providers, [OrtProvider.NNAPI, OrtProvider.CPU]);
    expect(onnxSessionOptions(threads: 4, accelerator: ModelAccelerator.xnnpack).providers, [OrtProvider.XNNPACK, OrtProvider.CPU]);
    expect(onnxSessionOptions(threads: 4, accelerator: ModelAccelerator.nnapi).intraOpNumThreads, 4);
  });

  test("each model's runner opens with the choice made for it", () async {
    await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.xnnpack);
    await ModelTasks.setRunOn(ModelKind.tagger, ModelAccelerator.nnapi);
    expect(OnnxLookRunner('image.onnx', 'text.onnx', threads: 2).options.providers, [OrtProvider.XNNPACK, OrtProvider.CPU]);
    expect(OnnxTagRunner('model.onnx', threads: 2).options.providers, [OrtProvider.NNAPI, OrtProvider.CPU]);
    expect(OnnxEmbeddingRunner('model.onnx', dim: 384, wantsTokenTypeIds: false, threads: 1).options.providers, isNull);
  });

  test('timings are kept per model and choice, per decoder, and across starts', () async {
    final ModelTimings t = ModelTimings.instance;
    t.recordRun(ModelKind.tagger, ModelAccelerator.nnapi, 100);
    t.recordRun(ModelKind.tagger, ModelAccelerator.nnapi, 300);
    t.recordOpen(ModelKind.tagger, ModelAccelerator.nnapi, 4200);
    t.recordDecode(PictureDecoder.phone, 40);
    final TimingStat s = t.run(ModelKind.tagger, ModelAccelerator.nnapi)!;
    expect((s.runs, s.averageMs, s.lastMs), (2, 200, 300));
    expect(t.run(ModelKind.tagger, ModelAccelerator.cpu), isNull);
    expect(ModelTimings.words(s, unit: 'run'), 'On this phone: 200 ms per run on average over 2 runs, the last 300 ms.');
    expect(ModelTimings.words(null, unit: 'run'), 'Not tried yet on this phone.');
    await t.saveNow();

    t.resetForTests(dir: '${tempDir.path}${Platform.pathSeparator}');
    expect(t.run(ModelKind.tagger, ModelAccelerator.nnapi), isNull);
    await t.load();
    expect(t.run(ModelKind.tagger, ModelAccelerator.nnapi)!.averageMs, 200);
    expect(t.open(ModelKind.tagger, ModelAccelerator.nnapi)!.lastMs, 4200);
    expect(t.decode(PictureDecoder.phone)!.lastMs, 40);
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 12000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ModelsPage()));
    await tester.pump();
  }

  testWidgets('Run on: a choice per model, applied at the next open, with an explain window and the timings', (tester) async {
    ModelTimings.instance.recordRun(ModelKind.tagger, ModelAccelerator.nnapi, 200);
    await openPage(tester);
    for (final ModelKind m in ModelKind.values) {
      expect(find.byKey(ValueKey('model-runon-${m.name}')), findsOneWidget, reason: m.name);
      expect(find.byKey(ValueKey('model-runon-${m.name}-explain')), findsOneWidget, reason: m.name);
    }
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('model-runon-tagger')), matching: find.text('NNAPI')));
    await tester.pump();
    expect(ModelTasks.runOn(ModelKind.tagger), ModelAccelerator.nnapi);
    expect(reopened, [ModelKind.tagger]);

    await tester.tap(find.byKey(const ValueKey('model-runon-tagger-explain')));
    await tester.pumpAndSettle();
    final Finder dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    for (final String name in ['CPU', 'XNNPACK', 'NNAPI']) {
      expect(find.descendant(of: dialog, matching: find.textContaining(name)), findsWidgets, reason: name);
    }
    expect(find.descendant(of: dialog, matching: find.textContaining('200 ms per run on average')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('Not tried yet on this phone')), findsWidgets);
    expect(find.descendant(of: dialog, matching: find.textContaining('CPU, NNAPI, XNNPACK')), findsOneWidget, reason: 'what this build has');
  });

  testWidgets('Picture decoding: the phone by default, "As before" a tap away, with its own explain window', (tester) async {
    ModelTimings.instance.recordDecode(PictureDecoder.dart, 979);
    await openPage(tester);
    expect(SettingsHandler.instance.pictureDecoder, PictureDecoder.phone);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('picture-decoder')), matching: find.text('As before')));
    await tester.pump();
    expect(SettingsHandler.instance.pictureDecoder, PictureDecoder.dart);

    await tester.tap(find.byKey(const ValueKey('picture-decoder-explain')));
    await tester.pumpAndSettle();
    final Finder dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.textContaining('979 ms per picture on average')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('Not tried yet on this phone')), findsOneWidget);
    SettingsHandler.instance.pictureDecoder = PictureDecoder.phone;
  });
}
