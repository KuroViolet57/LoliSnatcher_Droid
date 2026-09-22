import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';

/// r80: Settings → Recommendations → Models: every job of the three models
/// with its own switch, two thread counts per model, and one switch for all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  int saves = 0;
  final List<ModelKind> reopened = [];

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('models_page');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiModelsOff = false
      ..aiEncoder = true
      ..aiLook = true
      ..aiImageTagger = true
      ..videoFrames = true
      ..taggerOnReactions = false;
    SettingsHandler.instance.modelTasks.clear();
    SettingsHandler.instance.modelThreads.clear();
    saves = 0;
    reopened.clear();
    ModelTasks.save = () async => saves++;
    ModelTasks.maxThreads = () => 8;
    ModelsPage.threadsChanged = reopened.add;
  });

  tearDown(() {
    ModelTasks.resetForTests();
    ModelsPage.resetForTests();
    SettingsHandler.instance.modelTasks.clear();
    SettingsHandler.instance.modelThreads.clear();
    SettingsHandler.instance.aiModelsOff = false;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ModelsPage()));
    await tester.pump();
  }

  Switch switchOf(WidgetTester tester, String key) => tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)));

  Future<void> flip(WidgetTester tester, String key) async {
    await tester.tap(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)));
    await tester.pump();
  }

  testWidgets('every job of every model has its switch; the frames and reaction switches are the ones from before', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('models-all-off')), findsOneWidget);
    for (final ModelKind m in ModelKind.values) {
      expect(find.byKey(ValueKey('model-use-${m.name}')), findsOneWidget, reason: m.name);
    }
    for (final ModelTask t in ModelTasks.all) {
      expect(find.byKey(ValueKey('model-task-${t.key}')), findsOneWidget, reason: t.key);
      expect(switchOf(tester, 'model-task-${t.key}').value, isTrue, reason: t.key);
    }
    expect(find.byKey(const ValueKey('model-task-look.frames')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-task-tagger.reactions')), findsOneWidget);

    await flip(tester, 'model-task-look.forYou');
    expect(ModelTasks.isOn(ModelTasks.lookForYou), isFalse);
    expect(switchOf(tester, 'model-task-look.forYou').value, isFalse);
    expect(saves, 1);

    await flip(tester, 'model-task-look.frames');
    expect(SettingsHandler.instance.videoFrames, isFalse, reason: 'the same switch as in the Looks model section');
    await flip(tester, 'model-task-tagger.reactions');
    expect(SettingsHandler.instance.taggerOnReactions, isTrue);
    await flip(tester, 'model-use-look');
    expect(SettingsHandler.instance.aiLook, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("thread counts: today's shown, changed one step at a time within 1 and the cores, applied to that model", (tester) async {
    await open(tester);
    Text count(String key) => tester.widget<Text>(find.byKey(ValueKey(key)));
    expect(count('model-threads-tagger-waiting').data, '4');
    expect(count('model-threads-tagger-background').data, '2');
    expect(count('model-threads-look-waiting').data, '1');
    expect(count('model-threads-text-background').data, '1');

    await tester.tap(find.byKey(const ValueKey('model-threads-tagger-waiting-plus')));
    await tester.pump();
    expect(count('model-threads-tagger-waiting').data, '5');
    expect(ModelTasks.threads(ModelKind.tagger, ModelUse.waiting), 5);
    expect(reopened, [ModelKind.tagger], reason: 'the tagger picks the new count up now');
    expect(saves, 1);

    final Finder minus = find.byKey(const ValueKey('model-threads-look-waiting-minus'));
    expect(tester.widget<IconButton>(minus).onPressed, isNull, reason: 'never below one');
    for (int i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const ValueKey('model-threads-look-background-plus')));
      await tester.pump();
    }
    expect(count('model-threads-look-background').data, '8', reason: 'never above the cores');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('model-threads-look-background-plus'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("r81: frames for For You and for other tabs start on 'While it plays'; another choice is stored", (tester) async {
    await open(tester);
    SegmentedButton<FrameMode> choice(String key) =>
        tester.widget<SegmentedButton<FrameMode>>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(SegmentedButton<FrameMode>)));
    expect(choice('frames-foryou').selected, {FrameMode.playing});
    expect(choice('frames-other').selected, {FrameMode.playing});

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('frames-other')), matching: find.text('When you react')));
    await tester.pump();
    expect(SettingsHandler.instance.framesOtherTabs, FrameMode.reaction);
    expect(SettingsHandler.instance.framesForYou, FrameMode.playing, reason: 'only that place');
    expect(choice('frames-other').selected, {FrameMode.reaction});
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('frames-foryou')), matching: find.text('Off')));
    await tester.pump();
    expect(SettingsHandler.instance.framesForYou, FrameMode.off);
    expect(saves, 2);
    SettingsHandler.instance
      ..framesForYou = FrameMode.playing
      ..framesOtherTabs = FrameMode.playing;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("r81: 'Remember the looks of posts you open' is off until switched on", (tester) async {
    await open(tester);
    expect(switchOf(tester, 'model-task-look.remember').value, isFalse);
    await flip(tester, 'model-task-look.remember');
    expect(SettingsHandler.instance.rememberLooks, isTrue);
    expect(saves, 1);
    SettingsHandler.instance.rememberLooks = false;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r81: space for saved vectors: 250 MB to begin with, the space used shown; a smaller size frees the room', (tester) async {
    final List<(int, bool)> applied = [];
    ModelsPage.vectorUsage = () async => (text: 1024 * 1024, looks: 3 * 1024 * 1024);
    ModelsPage.applyVectorSpace = (int mb, {required bool smaller}) async => applied.add((mb, smaller));
    await open(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('vector-space-250'))).selected, isTrue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('vector-space-used'))).data, 'Used: 4.0 MB of 250 MB (text 1.0 MB, looks 3.0 MB).');

    await tester.tap(find.byKey(const ValueKey('vector-space-1000')));
    await tester.pump();
    expect(SettingsHandler.instance.vectorSpaceMb, 1000);
    expect(applied, [(1000, false)]);
    await tester.tap(find.byKey(const ValueKey('vector-space-100')));
    await tester.pump();
    expect(SettingsHandler.instance.vectorSpaceMb, 100);
    expect(applied.last, (100, true), reason: 'smaller: the extra goes and the file shrinks');
    SettingsHandler.instance.vectorSpaceMb = 250;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all models off: every switch below is greyed and every job off; on again, the choices are back', (tester) async {
    await ModelTasks.set(ModelTasks.textBoards, false);
    saves = 0;
    await open(tester);
    await flip(tester, 'models-all-off');
    expect(SettingsHandler.instance.aiModelsOff, isTrue);
    expect(saves, 1);
    for (final ModelTask t in ModelTasks.all) {
      expect(ModelTasks.isOn(t), isFalse, reason: t.key);
      expect(switchOf(tester, 'model-task-${t.key}').onChanged, isNull, reason: 'greyed: ${t.key}');
    }
    await flip(tester, 'models-all-off');
    expect(ModelTasks.isOn(ModelTasks.textLearning), isTrue);
    expect(ModelTasks.isOn(ModelTasks.textBoards), isFalse, reason: 'switched off before: still off');
    expect(switchOf(tester, 'model-task-text.boards').value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
