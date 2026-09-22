import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';
import 'package:lolisnatcher/src/pages/settings/recommendations_page.dart';
import 'package:lolisnatcher/src/utils/picker_watch.dart';

/// r33: Settings → Recommendations holds the two switches, independent of
/// each other; the For You page comes in a doujin flavour.
class _NoRunner implements TagRunner {
  @override
  String get provider => 'none';

  @override
  Future<Float32List> run(Float32List nhwc, int size) => throw StateError('no inference in this test');

  @override
  Future<void> close() async {}
}

class _NoLook implements LookRunner {
  @override
  String get provider => 'none';

  @override
  Future<Float32List> image(Float32List nchw, int size) => throw StateError('no inference in this test');

  @override
  Future<Float32List> text(List<int> ids, List<int> mask) => throw StateError('no inference in this test');

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// r78: the app going away to the picker and coming back.
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
  }

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

  testWidgets('r34: the Encoder section — pick a preset, download it, see it ready, turn it off, delete it', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final List<String> fetched = [];
    EncoderHandler.unregister();
    final EncoderHandler encoder = EncoderHandler.register();
    encoder.runnerFactory = (String p, {required bool wantsTokenTypeIds}) => throw StateError('no inference in this test');
    encoder.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
        fetched.add(url);
        to.parent.createSync(recursive: true);
        to.writeAsStringSync(url.endsWith('config.json') ? '{"hidden_size": 384}' : 'x');
      };
    addTearDown(EncoderHandler.unregister);
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('encoder-status')), findsOneWidget);
    expect(find.textContaining('No encoder'), findsOneWidget);
    expect(find.byKey(const ValueKey('encoder-preset-english')), findsOneWidget);
    expect(find.byKey(const ValueKey('encoder-preset-multilingual')), findsOneWidget);
    expect(find.byKey(const ValueKey('encoder-preset-custom')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('encoder-preset-english')));
    await settle(tester);
    expect(find.textContaining('23 MB'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('encoder-download')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(fetched, hasLength(4));
    expect(fetched.first, contains('Xenova/all-MiniLM-L6-v2'));
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(SettingsHandler.instance.encoderModel, 'english');
    final Finder toggle = find.byKey(const ValueKey('ai-encoder-toggle'));
    expect(toggle, findsOneWidget);
    await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiEncoder, isFalse);
    expect(SettingsHandler.instance.encoderModel, 'english', reason: 'off is not deleted');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('encoder-delete')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(SettingsHandler.instance.encoderModel, '');
    expect(find.textContaining('No encoder'), findsOneWidget);
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

  testWidgets('r74: the Image tagger section — presets, download, ready with the tag count, the two switches, Try it, delete', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final List<String> fetched = [];
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler tagger = ImageTaggerHandler.register();
    tagger.runnerFactory = (String p, int threads) => _NoRunner();
    tagger.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
      fetched.add(url);
      to.parent.createSync(recursive: true);
      if (url.endsWith('selected_tags.csv')) {
        to.writeAsStringSync('tag_id,name,category,count\n1,general,9,1\n2,sensitive,9,1\n3,questionable,9,1\n4,explicit,9,1\n5,1girl,0,1\n6,cat_ears,0,1\n');
      } else if (url.endsWith('config.json')) {
        to.writeAsStringSync('{"model_args": {"img_size": 448}}');
      } else {
        to.writeAsBytesSync(List<int>.filled(500, 3));
      }
      onProgress?.call(500, 500);
    };
    addTearDown(ImageTaggerHandler.unregister);
    addTearDown(RecommendationsPage.resetForTests);
    SettingsHandler.instance
      ..imageTaggerModel = ''
      ..aiImageTagger = true
      ..taggerOnReactions = false;
    RecommendationsPage.pickImageBytes = () async => Uint8List.fromList(List<int>.filled(10, 1));
    RecommendationsPage.tagImage = (Uint8List bytes) async => const TaggerResult(
      general: [(tag: 'cat_ears', confidence: 0.9, character: false)],
      characters: [(tag: 'hatsune_miku', confidence: 0.96, character: true)],
      rating: 'general',
      ratingConfidence: 0.6,
      decodeMs: 12,
      modelMs: 345,
      provider: 'CPU',
    );
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('tagger-status')), findsOneWidget);
    expect(find.textContaining('No image tagger'), findsOneWidget);
    expect(find.byKey(const ValueKey('tagger-preset-wd-vit')), findsOneWidget);
    expect(find.byKey(const ValueKey('tagger-preset-wd-convnext')), findsOneWidget);
    expect(find.byKey(const ValueKey('tagger-preset-wd-swinv2')), findsOneWidget);
    expect(find.byKey(const ValueKey('tagger-preset-custom')), findsOneWidget);
    expect(find.textContaining('379 MB'), findsWidgets);
    // r78: the button is never dead; before a download a tap says what is missing.
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('tagger-try'))).onPressed, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tagger-download')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    expect(fetched, hasLength(3));
    expect(fetched.first, contains('SmilingWolf/wd-vit-tagger-v3'));
    final Text status = tester.widget<Text>(find.byKey(const ValueKey('tagger-status')));
    expect(status.data, contains('Ready'));
    expect(status.data, contains('6 tags'));
    expect(SettingsHandler.instance.imageTaggerModel, 'wd-vit');
    final Finder use = find.byKey(const ValueKey('ai-tagger-toggle'));
    await tester.tap(find.descendant(of: use, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiImageTagger, isFalse);
    await tester.tap(find.descendant(of: use, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiImageTagger, isTrue);
    final Finder reactions = find.byKey(const ValueKey('tagger-reactions-toggle'));
    await tester.tap(find.descendant(of: reactions, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.taggerOnReactions, isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tagger-try')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(find.textContaining('hatsune_miku'), findsOneWidget);
    expect(find.textContaining('cat_ears'), findsOneWidget);
    expect(find.textContaining('357 ms'), findsOneWidget);
    // r77: nothing back from the picker is said, not swallowed.
    RecommendationsPage.pickImageBytes = () async => null;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tagger-try')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data, 'No picture came back from the picker.');
    RecommendationsPage.pickImageBytes = () async => throw StateError('photo picker unavailable');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tagger-try')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data, 'Could not read the picture: Bad state: photo picker unavailable');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tagger-delete')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(SettingsHandler.instance.imageTaggerModel, '');
    expect(find.textContaining('No image tagger'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r80: Models opens from here; with Try it switched off there, the button is not built', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ModelTasks.save = () async {};
    addTearDown(() {
      ModelTasks.resetForTests();
      SettingsHandler.instance.modelTasks.clear();
    });
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler tagger = ImageTaggerHandler.register();
    tagger.runnerFactory = (String p, int threads) => _NoRunner();
    addTearDown(ImageTaggerHandler.unregister);
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('tagger-try')), findsOneWidget);
    expect(find.byKey(const ValueKey('models-page')), findsOneWidget);

    await ModelTasks.set(ModelTasks.taggerTryIt, false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('tagger-try')), findsNothing);
    expect(find.byKey(const ValueKey('tagger-try-off')), findsOneWidget, reason: 'says where it was switched off');

    await tester.tap(find.byKey(const ValueKey('models-page')));
    await tester.pumpAndSettle();
    expect(find.byType(ModelsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('models-all-off')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r78: a picker that never answers ends by itself, says so, and frees the button', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler tagger = ImageTaggerHandler.register();
    tagger.runnerFactory = (String p, int threads) => _NoRunner();
    tagger.status.value = const TaggerStatus(state: TaggerState.ready, repo: 'SmilingWolf/wd-vit-tagger-v3', tagCount: 6, inputSize: 448, bytes: 500);
    addTearDown(ImageTaggerHandler.unregister);
    addTearDown(RecommendationsPage.resetForTests);
    addTearDown(PickerWatch.resetForTests);
    PickerWatch.afterResume = const Duration(milliseconds: 100);
    final Completer<Uint8List?> never = Completer<Uint8List?>();
    int picks = 0, kept = 0;
    RecommendationsPage.pickImageBytes = () {
      picks++;
      return never.future;
    };
    RecommendationsPage.lostPick = () async {
      kept++;
      return null;
    };
    RecommendationsPage.tagImage = (Uint8List bytes) async => const TaggerResult(
      general: [(tag: 'cat_ears', confidence: 0.9, character: false)],
      characters: [],
      rating: 'general',
      ratingConfidence: 0.6,
      decodeMs: 12,
      modelMs: 345,
      provider: 'CPU',
    );
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('tagger-try')));
    final int keptWhenOpened = kept;
    await tester.tap(find.byKey(const ValueKey('tagger-try')));
    await tester.pump();
    expect(picks, 1);
    expect(find.text('Reading…'), findsOneWidget);
    // The picker is in front: the app is away, and waiting is right.
    await lifecycle(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Reading…'), findsOneWidget, reason: 'the person is still choosing');
    // It closed, and no answer ever came.
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(kept, keptWhenOpened + 1, reason: 'the picker is asked whether it kept the picture');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data,
      'The picker closed without giving a picture. Try again.',
    );
    expect(find.text('Try it on a picture'), findsOneWidget, reason: 'the button is usable again');
    // r78: and a picture that turns up afterwards is still read.
    never.complete(Uint8List.fromList(List<int>.filled(10, 1)));
    await tester.pump();
    await settle(tester);
    expect(find.textContaining('cat_ears'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r78: taps that cannot read a picture say why instead of nothing', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler tagger = ImageTaggerHandler.register();
    tagger.runnerFactory = (String p, int threads) => _NoRunner();
    addTearDown(ImageTaggerHandler.unregister);
    addTearDown(RecommendationsPage.resetForTests);
    addTearDown(PickerWatch.resetForTests);
    int picks = 0;
    RecommendationsPage.pickImageBytes = () async {
      picks++;
      return null;
    };
    RecommendationsPage.lostPick = () async => null;
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('tagger-try')));
    // Nothing downloaded: the button is alive and says what is missing.
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('tagger-try'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('tagger-try')));
    await tester.pump();
    expect(picks, 0, reason: 'no picker without a tagger to read with');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data, 'Download an image tagger first.');
    tagger.status.value = const TaggerStatus(state: TaggerState.downloading, repo: 'SmilingWolf/wd-vit-tagger-v3', progress: 0.5);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tagger-try')));
    await tester.pump();
    expect(picks, 0);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data, 'The image tagger is still downloading.');
    // Ready, but already reading: the second tap says that too.
    tagger.status.value = const TaggerStatus(state: TaggerState.ready, repo: 'SmilingWolf/wd-vit-tagger-v3', tagCount: 6, inputSize: 448, bytes: 500);
    await tester.pump();
    final Completer<Uint8List?> never = Completer<Uint8List?>();
    RecommendationsPage.pickImageBytes = () {
      picks++;
      return never.future;
    };
    await tester.tap(find.byKey(const ValueKey('tagger-try')));
    await tester.pump();
    expect(picks, 1);
    await tester.tap(find.byKey(const ValueKey('tagger-try')));
    await tester.pump();
    expect(picks, 1, reason: 'one picker at a time');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tagger-try-message'))).data, 'Still reading the last picture…');
    never.complete(null);
    await tester.pump();
    await settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r77: a Try it picture that came back after Android ended the app is read when the page opens', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ImageTaggerHandler.unregister();
    final ImageTaggerHandler tagger = ImageTaggerHandler.register();
    tagger.runnerFactory = (String p, int threads) => _NoRunner();
    addTearDown(ImageTaggerHandler.unregister);
    addTearDown(RecommendationsPage.resetForTests);
    int asked = 0;
    RecommendationsPage.lostPick = () async {
      asked++;
      return Uint8List.fromList(List<int>.filled(10, 1));
    };
    RecommendationsPage.tagImage = (Uint8List bytes) async => const TaggerResult(
      general: [(tag: 'cat_ears', confidence: 0.9, character: false)],
      characters: [],
      rating: 'general',
      ratingConfidence: 0.6,
      decodeMs: 12,
      modelMs: 345,
      provider: 'CPU',
    );
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(asked, 1, reason: 'asked once, when the page opens');
    expect(find.textContaining('cat_ears'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r75: the Looks model section — presets, download, ready, the switch, delete', (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final List<String> fetched = [];
    LookModelHandler.unregister();
    final LookModelHandler look = LookModelHandler.register();
    look.runnerFactory = (String imagePath, String textPath) => _NoLook();
    final String tokenizerText = File('test/fixtures/clip_tokenizer_small.json').readAsStringSync();
    look.fetcher = (String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
      fetched.add(url);
      to.parent.createSync(recursive: true);
      if (url.endsWith('tokenizer.json')) {
        to.writeAsStringSync(tokenizerText);
      } else if (url.endsWith('preprocessor_config.json')) {
        to.writeAsStringSync('{"do_normalize":false,"size":{"shortest_edge":256},"crop_size":{"height":256,"width":256}}');
      } else {
        to.writeAsBytesSync(List<int>.filled(100, 1));
      }
      onProgress?.call(100, 100);
    };
    addTearDown(LookModelHandler.unregister);
    SettingsHandler.instance
      ..lookModel = ''
      ..aiLook = true;
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    expect(find.byKey(const ValueKey('look-status')), findsOneWidget);
    expect(find.textContaining('No looks model'), findsOneWidget);
    expect(find.byKey(const ValueKey('look-preset-s0')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-preset-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-preset-custom')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('look-download')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    expect(fetched, hasLength(4));
    expect(fetched.first, contains('Xenova/mobileclip_s0'));
    final Text status = tester.widget<Text>(find.byKey(const ValueKey('look-status')));
    expect(status.data, contains('Ready'));
    expect(SettingsHandler.instance.lookModel, 's0');
    final Finder use = find.byKey(const ValueKey('ai-look-toggle'));
    await tester.tap(find.descendant(of: use, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.aiLook, isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('look-delete')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(SettingsHandler.instance.lookModel, '');
    expect(find.textContaining('No looks model'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('r76: the frames switch sits in the Looks model section, flips the setting, and the setting survives a save and a load', (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    LookModelHandler.unregister();
    LookModelHandler.register();
    addTearDown(LookModelHandler.unregister);
    SettingsHandler.instance.videoFrames = true;
    await warm(tester);
    await tester.pumpWidget(const MaterialApp(home: RecommendationsPage()));
    await settle(tester);
    final Finder toggle = find.byKey(const ValueKey('look-video-frames-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.textContaining('Read frames from playing videos'), findsOneWidget);
    await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
    await tester.pump();
    expect(SettingsHandler.instance.videoFrames, isFalse);
    final Map<String, dynamic> json = SettingsHandler.instance.toJson();
    expect(json['videoFrames'], isFalse);
    SettingsHandler.instance.videoFrames = true;
    await tester.runAsync(() => SettingsHandler.instance.loadFromJSON(jsonEncode({'videoFrames': false}), false));
    expect(SettingsHandler.instance.videoFrames, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
