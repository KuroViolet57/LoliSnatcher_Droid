import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r80: Settings → Recommendations → Models. Every job each model does has
/// its own switch, each model has a thread count for work you wait on and
/// one for background work, and one switch turns every model off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  int saves = 0;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('model_tasks');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiModelsOff = false
      ..capturesPath = '';
    SettingsHandler.instance.modelTasks.clear();
    SettingsHandler.instance.modelThreads.clear();
    saves = 0;
    ModelTasks.save = () async => saves++;
    ModelTasks.maxThreads = () => 8;
  });

  tearDown(() {
    ModelTasks.resetForTests();
    SettingsHandler.instance.modelTasks.clear();
    SettingsHandler.instance.modelThreads.clear();
    SettingsHandler.instance.aiModelsOff = false;
    SettingsHandler.instance.isDebug.value = false;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('every job of every model is listed once, on until switched off, and says what it does', () {
    expect(ModelTasks.all.map((t) => t.key).toSet(), hasLength(ModelTasks.all.length), reason: 'one key per job');
    for (final ModelTask t in ModelTasks.all) {
      expect(ModelTasks.isOn(t), isTrue, reason: t.key);
      expect(t.title, isNotEmpty);
      expect(t.description.length, greaterThan(20), reason: 'a description, not a label: ${t.key}');
    }
    expect(ModelTasks.of(ModelKind.text), [ModelTasks.textLearning, ModelTasks.textForYou, ModelTasks.textBoards]);
    expect(ModelTasks.of(ModelKind.look), [ModelTasks.lookLearning, ModelTasks.lookForYou, ModelTasks.lookSimilar, ModelTasks.lookBoards]);
    expect(ModelTasks.of(ModelKind.tagger), [ModelTasks.taggerTryIt, ModelTasks.taggerBoards]);
    expect(ModelTasks.textLearning.use, ModelUse.background, reason: 'learning runs when nobody waits');
    expect(ModelTasks.lookLearning.use, ModelUse.background);
    expect(ModelTasks.lookForYou.use, ModelUse.waiting);
  });

  test('a job switched off stays off; back to on is not stored', () async {
    await ModelTasks.set(ModelTasks.lookForYou, false);
    expect(ModelTasks.isOn(ModelTasks.lookForYou), isFalse);
    expect(ModelTasks.isOn(ModelTasks.lookLearning), isTrue, reason: 'only that job');
    expect(SettingsHandler.instance.modelTasks, {'look.forYou': false});
    expect(saves, 1);
    await ModelTasks.set(ModelTasks.lookForYou, true);
    expect(SettingsHandler.instance.modelTasks, isEmpty);
    expect(saves, 2);
  });

  test('all models off turns every job off and keeps each choice for when they come back', () async {
    await ModelTasks.set(ModelTasks.taggerBoards, false);
    await ModelTasks.setAllOff(true);
    expect(SettingsHandler.instance.aiModelsOff, isTrue);
    for (final ModelTask t in ModelTasks.all) {
      expect(ModelTasks.isOn(t), isFalse, reason: t.key);
    }
    await ModelTasks.setAllOff(false);
    expect(ModelTasks.isOn(ModelTasks.taggerTryIt), isTrue);
    expect(ModelTasks.isOn(ModelTasks.taggerBoards), isFalse, reason: 'the job switched off before stays off');
  });

  test("thread counts: today's by default, kept within 1 and the phone's cores", () async {
    expect(ModelTasks.threads(ModelKind.text, ModelUse.waiting), 1);
    expect(ModelTasks.threads(ModelKind.text, ModelUse.background), 1);
    expect(ModelTasks.threads(ModelKind.look, ModelUse.waiting), 1);
    expect(ModelTasks.threads(ModelKind.look, ModelUse.background), 1);
    expect(ModelTasks.threads(ModelKind.tagger, ModelUse.waiting), 4);
    expect(ModelTasks.threads(ModelKind.tagger, ModelUse.background), 2);

    await ModelTasks.setThreads(ModelKind.look, ModelUse.waiting, 6);
    expect(ModelTasks.threads(ModelKind.look, ModelUse.waiting), 6);
    expect(ModelTasks.threads(ModelKind.look, ModelUse.background), 1, reason: 'only that count');
    expect(saves, 1);

    await ModelTasks.setThreads(ModelKind.tagger, ModelUse.waiting, 15);
    expect(ModelTasks.threads(ModelKind.tagger, ModelUse.waiting), 8, reason: 'no more than the cores');
    await ModelTasks.setThreads(ModelKind.tagger, ModelUse.background, 0);
    expect(ModelTasks.threads(ModelKind.tagger, ModelUse.background), 1, reason: 'at least one');

    // A count saved on a phone with more cores reads back within this one's.
    SettingsHandler.instance.modelThreads['text.waiting'] = 16;
    expect(ModelTasks.threads(ModelKind.text, ModelUse.waiting), 8);
  });

  test('the switches, the thread counts, debug mode and the captures folder survive a restart', () async {
    await ModelTasks.set(ModelTasks.textBoards, false);
    await ModelTasks.setThreads(ModelKind.tagger, ModelUse.waiting, 6);
    SettingsHandler.instance
      ..aiModelsOff = true
      ..capturesPath = 'content://captures'
      ..isDebug.value = true;
    final String saved = jsonEncode(SettingsHandler.instance.toJson());

    SettingsHandler.instance
      ..aiModelsOff = false
      ..capturesPath = ''
      ..isDebug.value = false;
    SettingsHandler.instance.modelTasks.clear();
    SettingsHandler.instance.modelThreads.clear();
    await SettingsHandler.instance.loadFromJSON(saved, false);

    expect(SettingsHandler.instance.aiModelsOff, isTrue);
    expect(SettingsHandler.instance.capturesPath, 'content://captures');
    expect(SettingsHandler.instance.isDebug.value, isTrue, reason: 'debug mode stays on until turned off');
    expect(SettingsHandler.instance.modelTasks, {'text.boards': false});
    expect(SettingsHandler.instance.modelThreads, {'tagger.waiting': 6});
  });

  test('a settings file with unknown or broken entries loads what it can', () async {
    await SettingsHandler.instance.loadFromJSON(
      jsonEncode({
        'modelTasks': {'look.similar': false, 'nonsense': 3, 'text.forYou': 'yes'},
        'modelThreads': {'look.background': 3, 'tagger.waiting': 'many', 'bogus.waiting': 2},
      }),
      false,
    );
    expect(SettingsHandler.instance.modelTasks, {'look.similar': false});
    expect(SettingsHandler.instance.modelThreads, {'look.background': 3});
  });

  test('thread counts and the captures folder stay on this phone when settings are synced', () {
    expect(SettingsHandler.instance.deviceSpecificSettings, containsAll(['modelThreads', 'capturesPath', 'isDebug']));
  });
}
