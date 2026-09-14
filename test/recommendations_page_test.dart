import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
import 'package:lolisnatcher/src/pages/settings/recommendations_page.dart';

/// r33: Settings → Recommendations holds the two switches, independent of
/// each other; the For You page comes in a doujin flavour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('recommendations_page');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false
      ..aiRecommendations = true
      ..aiLearning = true;
    RecommenderHandler.register();
    SearchHandler.register();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    RecommenderHandler.unregister();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The pages read the model files (real I/O), which a widget test's fake
  /// clock never completes: load both models under real time first, so the
  /// pages find them ready — as they do in the app after the first surface.
  Future<void> warm(WidgetTester tester) async {
    await tester.runAsync(
      () => Future.wait([
        RecommenderHandler.instance.modelFor(RecommenderWorld.booru),
        RecommenderHandler.instance.modelFor(RecommenderWorld.doujin),
      ]),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the two switches flip independently', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await tester.pump(const Duration(milliseconds: 300));
    final Finder recommendations = find.byKey(const ValueKey('ai-recommendations-toggle'));
    final Finder learning = find.byKey(const ValueKey('ai-learning-toggle'));
    expect(recommendations, findsOneWidget);
    expect(learning, findsOneWidget);

    await tester.tap(find.descendant(of: recommendations, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiRecommendations, isFalse);
    expect(SettingsHandler.instance.aiLearning, isTrue, reason: 'learning stays on while the classic ordering is shown');

    await tester.tap(find.descendant(of: learning, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiLearning, isFalse);
    expect(SettingsHandler.instance.aiRecommendations, isFalse);

    await tester.tap(find.descendant(of: recommendations, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiRecommendations, isTrue);
    expect(SettingsHandler.instance.aiLearning, isFalse, reason: 'a frozen model can still serve');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the page reports both worlds, empty until something is learned', (tester) async {
    // Tall enough for both cards to be built below the two switches.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('recommender-report-booru')), findsOneWidget);
    expect(find.byKey(const ValueKey('recommender-report-doujin')), findsOneWidget);
    expect(find.textContaining('Nothing learned yet'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the doujin For You page seeds with a namespaced tag and lists the doujin model, not the classic profile', (tester) async {
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: ForYouPage(world: RecommenderWorld.doujin)));
    await settle(tester);
    expect(find.text('For You (doujin)'), findsOneWidget);
    expect(find.widgetWithText(TextField, ''), findsOneWidget);
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, contains('parody:'));
    expect(find.text('Your taste profile'), findsNothing, reason: 'the classic tag profile is a booru thing');
    expect(find.textContaining('What the model learned'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
