import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_availability.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/accounts_page.dart';
import 'package:lolisnatcher/src/pages/settings/model_page.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';
import 'package:lolisnatcher/src/pages/settings/recommendations_page.dart';

/// r88 (the user, 2026-10-02): settings were scattered - Recommendations
/// sat under Doujin, a model's settings were split between the
/// Recommendations page and the Models page (some twice), and the numbers
/// came without a word on what they do. Now: one home per thing, a page per
/// model in clear parts, and an explanation (with this phone's timings) for
/// every number.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('settings_layout_test');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..aiModelsOff = false
      ..aiEncoder = true
      ..aiLook = true
      ..aiImageTagger = true;
    ModelTasks.save = () async {};
    ModelTasks.maxThreads = () => 8;
    ModelTimings.instance.resetForTests(dir: '${tempDir.path}${Platform.pathSeparator}');
    OnnxAvailability.setForTests({'CPU', 'QNN'});
  });

  tearDown(() {
    ModelTasks.resetForTests();
    ModelsPage.resetForTests();
    ModelTimings.instance.resetForTests();
    OnnxAvailability.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the main Settings screen: one home per thing, in this order', () {
    final String src = File('lib/src/pages/settings_page.dart').readAsStringSync();
    final List<String> sections = [for (final m in RegExp(r"_sectionLabel\(context, '([^']+)'\)").allMatches(src)) m.group(1)!];
    expect(sections, ['SOURCES', 'RECOMMENDATIONS & AI', 'LOOK & FEEL', 'VIEWING', 'DOWNLOADS & STORAGE', 'SYSTEM', 'ABOUT']);
    int at(String s) {
      final int i = src.indexOf(s);
      expect(i, greaterThan(0), reason: s);
      return i;
    }

    void inSection(String page, String section) {
      final int p = at(page);
      final int s = at("_sectionLabel(context, '$section')");
      final int next = sections.indexOf(section) + 1 < sections.length ? at("_sectionLabel(context, '${sections[sections.indexOf(section) + 1]}')") : src.length;
      expect(p > s && p < next, isTrue, reason: '$page belongs under $section');
    }

    inSection('const BooruPage()', 'SOURCES');
    inSection('const AccountsPage()', 'SOURCES');
    inSection('const TagsFiltersPage()', 'SOURCES');
    inSection('const LinksPage()', 'SOURCES');
    inSection('const DoujinSettingsPage()', 'SOURCES');
    inSection('const RecommendationsPage()', 'RECOMMENDATIONS & AI');
    inSection('const ModelsPage()', 'RECOMMENDATIONS & AI');
    inSection('const UserInterfacePage()', 'LOOK & FEEL');
    inSection('const ModularUiPage()', 'LOOK & FEEL');
    inSection('const ThemePage()', 'LOOK & FEEL');
    inSection('const LanguageSettingsPage()', 'LOOK & FEEL');
    inSection('const GalleryPage()', 'VIEWING');
    inSection('const VideoSettingsPage()', 'VIEWING');
    inSection('const PerformancePage()', 'VIEWING');
    inSection('const SaveCachePage()', 'DOWNLOADS & STORAGE');
    inSection('const DatabasePage()', 'DOWNLOADS & STORAGE');
    inSection('const BackupRestorePage()', 'DOWNLOADS & STORAGE');
    inSection('const NetworkPage()', 'SYSTEM');
    inSection('const PrivacyPage()', 'SYSTEM');
    inSection('const LoliSyncPage()', 'SYSTEM');
    inSection('const DebugPage()', 'SYSTEM');
    inSection('const AboutPage()', 'ABOUT');
  });

  testWidgets('Accounts: the three sign-ins in one place', (tester) async {
    // The settings app bar's auto-sized title asserts at the test's default
    // 22 px (as in backup_page_test).
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20))),
        home: const AccountsPage(),
      ),
    );
    await tester.pump();
    for (final String key in ['account-ehentai', 'account-furaffinity', 'account-redgifs']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1200, 14000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  testWidgets('Models: what is shared, then a card per model that says what it runs on', (tester) async {
    await ModelTasks.setRunOn(ModelKind.tagger, ModelAccelerator.npu);
    await open(tester, const ModelsPage());
    expect(find.byKey(const ValueKey('models-all-off')), findsOneWidget);
    expect(find.byKey(const ValueKey('picture-decoder')), findsOneWidget);
    expect(find.byKey(const ValueKey('vector-space-250')), findsOneWidget);
    for (final ModelKind m in ModelKind.values) {
      expect(find.byKey(ValueKey('model-card-${m.name}')), findsOneWidget, reason: m.name);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('model-card-tagger')), matching: find.textContaining('NPU')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-task-tagger.tryIt')), findsNothing, reason: "jobs live on the model's own page");
    expect(find.byKey(const ValueKey('model-runon-tagger')), findsNothing);
  });

  for (final ModelKind kind in ModelKind.values) {
    testWidgets('${kind.name}: its own page, in labelled parts, every switch once, every number explained', (tester) async {
      await open(tester, ModelPage(kind: kind));
      for (final String part in ['model', 'jobs', 'speed']) {
        expect(find.byKey(ValueKey('model-part-${kind.name}-$part')), findsOneWidget, reason: part);
      }
      for (final ModelTask t in ModelTasks.of(kind)) {
        expect(find.byKey(ValueKey('model-task-${t.key}')), findsOneWidget, reason: t.key);
      }
      for (final ModelUse use in ModelUse.values) {
        expect(find.byKey(ValueKey('model-threads-${kind.name}-${use.name}-explain')), findsOneWidget, reason: use.name);
      }
      expect(find.byKey(ValueKey('model-runon-${kind.name}-explain')), findsOneWidget);
      expect(find.byKey(ValueKey('model-use-${kind.name}')), findsNothing, reason: '"Use the …" is in the Model part only');
      if (kind == ModelKind.look) {
        expect(find.byKey(const ValueKey('model-task-look.frames')), findsOneWidget);
        expect(find.byKey(const ValueKey('look-video-frames-toggle')), findsNothing, reason: 'once, not twice');
      }
      if (kind == ModelKind.tagger) {
        expect(find.byKey(const ValueKey('model-task-tagger.reactions')), findsOneWidget);
        expect(find.byKey(const ValueKey('tagger-reactions-toggle')), findsNothing, reason: 'once, not twice');
      }
    });
  }

  testWidgets('the thread explanation says what the number does, what it costs, what to pick, and what was measured', (tester) async {
    ModelTimings.instance.recordRun(ModelKind.tagger, ModelAccelerator.cpu, 2642, threads: 2);
    ModelTimings.instance.recordRun(ModelKind.tagger, ModelAccelerator.cpu, 1848, threads: 4);
    await open(tester, const ModelPage(kind: ModelKind.tagger));
    await tester.tap(find.byKey(const ValueKey('model-threads-tagger-waiting-explain')));
    await tester.pumpAndSettle();
    final Finder dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.textContaining('cores')), findsWidgets);
    expect(find.descendant(of: dialog, matching: find.textContaining('Recommended')), findsWidgets);
    expect(find.descendant(of: dialog, matching: find.textContaining('2 threads: 2642 ms')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('4 threads: 1848 ms')), findsOneWidget);
    // Seen on the emulator: the core count is this device's, and the heading
    // "Recommended" is not repeated in its text.
    expect(find.descendant(of: dialog, matching: find.textContaining('This phone has 8 cores')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('Recommended:')), findsNothing);
  });

  testWidgets('a choice the model refused when it opened: the card and the page say the CPU runs it, and why', (tester) async {
    // The emulator (no Qualcomm NPU): the card said "runs on NPU" while the
    // CPU did the work.
    await ModelTasks.setRunOn(ModelKind.look, ModelAccelerator.npu);
    ModelTimings.instance.recordOpened(ModelKind.look, tried: ModelAccelerator.npu, used: ModelAccelerator.cpu, refused: 'the NPU took no part of it');
    await open(tester, const ModelsPage());
    expect(find.descendant(of: find.byKey(const ValueKey('model-card-look')), matching: find.textContaining('runs on CPU (NPU refused it')), findsOneWidget);
    await open(tester, const ModelPage(kind: ModelKind.look));
    expect(find.byKey(const ValueKey('model-npu-refused-look')), findsOneWidget);
    expect(find.textContaining('the NPU took no part of it'), findsOneWidget);
  });

  testWidgets('Recommendations keeps the recommender; the models are a tap away', (tester) async {
    await open(tester, const RecommendationsPage());
    expect(find.byKey(const ValueKey('ai-recommendations-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('models-page')), findsOneWidget);
    for (final String key in ['encoder-status', 'look-status', 'tagger-status']) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: '$key moved to the model page');
    }
  });
}
