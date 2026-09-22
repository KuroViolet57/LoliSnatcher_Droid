import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// Who is waiting for a model's answer (r79 for the tagger, r80 for all
/// three): the work that opens a model decides how many threads it gets.
enum ModelUse {
  /// Try it, For You, a board, Posts like this: someone is looking at the
  /// screen for the answer.
  waiting,

  /// Learning from a reaction, a video's frames: nobody waits.
  background,
}

/// The three downloadable models.
enum ModelKind { text, look, tagger }

/// r81: when the frames of a playing video are taken, per place (For You,
/// or any other tab). Both start on [playing], the behaviour before r81.
enum FrameMode {
  /// After 2.5 s, then every 6 s while it plays (5 at most).
  playing,

  /// Only when you favourite, download or add the video to a collection
  /// while it plays: the frame on screen at once, then up to two more.
  reaction,

  /// None.
  off;

  String get label => switch (this) {
    FrameMode.playing => 'While it plays',
    FrameMode.reaction => 'When you react',
    FrameMode.off => 'Off',
  };

  /// A stored value; anything unknown reads as [playing].
  static FrameMode parse(Object? value) {
    for (final FrameMode m in FrameMode.values) {
      if (m.name == value) return m;
    }
    return FrameMode.playing;
  }
}

/// One job a model does, with its own switch in Settings → Recommendations
/// → Models (r80).
class ModelTask {
  const ModelTask({
    required this.key,
    required this.model,
    required this.title,
    required this.description,
    this.use = ModelUse.waiting,
  });

  /// Stored under this name in the settings' `modelTasks` map.
  final String key;
  final ModelKind model;
  final String title;

  /// What the model does for this job, and what happens without it.
  final String description;

  /// The thread count this job opens the model with.
  final ModelUse use;
}

/// r80 (Settings → Recommendations → Models): every job of each model can
/// be switched off on its own, each model has a thread count for work you
/// wait on and one for background work, and one switch turns every model
/// off. The values live in the settings file (`modelTasks`, `modelThreads`,
/// `aiModelsOff`); a job switched off is never started - the model is not
/// even opened for it.
///
/// Two jobs are older switches and stay where they were: the looks model's
/// video frames (`videoFrames`) and the tagger's reactions
/// (`taggerOnReactions`); the Models page shows them too.
class ModelTasks {
  const ModelTasks._();

  static const ModelTask textLearning = ModelTask(
    key: 'text.learning',
    model: ModelKind.text,
    title: 'Learning from your reactions',
    description: 'Reads the title and tags of what you favourite, open and skip, so the recommender learns what the words mean. Off: it learns from the tags alone.',
    use: ModelUse.background,
  );

  static const ModelTask textForYou = ModelTask(
    key: 'text.forYou',
    model: ModelKind.text,
    title: 'For You and recommendations',
    description: 'Reads the posts For You, the Suggested strip and the doujin Recommended strip are about to show, to order them. Off: they are ordered by their tags.',
  );

  static const ModelTask textBoards = ModelTask(
    key: 'text.boards',
    model: ModelKind.text,
    title: 'Boards and Posts like this',
    description: "Reads a board's description and the posts it finds, to put the ones that read alike first. Off: the tags alone order a board.",
  );

  static const ModelTask lookLearning = ModelTask(
    key: 'look.learning',
    model: ModelKind.look,
    title: 'Learning from your reactions',
    description: 'Looks at the picture of what you react to, so the recommender learns what you like to look at. Off: it learns from the tags alone.',
    use: ModelUse.background,
  );

  static const ModelTask lookForYou = ModelTask(
    key: 'look.forYou',
    model: ModelKind.look,
    title: 'For You and recommendations',
    description: 'Looks at the thumbnails For You and the Suggested strip are about to show, to order them by how they look. Off: nothing is loaded while you browse them.',
  );

  static const ModelTask lookSimilar = ModelTask(
    key: 'look.similar',
    model: ModelKind.look,
    title: 'Posts like this',
    description: "Compares the post's picture with what the sources find, lookalikes first. Off: Posts like this goes by the post's tags.",
  );

  static const ModelTask lookBoards = ModelTask(
    key: 'look.boards',
    model: ModelKind.look,
    title: 'Boards',
    description: "Compares a board's reference picture (or its words) with what the sources find, lookalikes first. Off: a board goes by its tags.",
  );

  static const ModelTask taggerTryIt = ModelTask(
    key: 'tagger.tryIt',
    model: ModelKind.tagger,
    title: 'Try it',
    description: 'The "Try it on a picture" button in the Image tagger section. Off: the button is not shown.',
  );

  static const ModelTask taggerBoards = ModelTask(
    key: 'tagger.boards',
    model: ModelKind.tagger,
    title: 'Boards and Posts like this',
    description: "Reads the tags of a board's reference picture, in the editor and when the board opens. Off: a board goes by its words, its must-have tags and SauceNAO.",
  );

  static const List<ModelTask> all = [
    textLearning,
    textForYou,
    textBoards,
    lookLearning,
    lookForYou,
    lookSimilar,
    lookBoards,
    taggerTryIt,
    taggerBoards,
  ];

  static List<ModelTask> of(ModelKind model) => [for (final ModelTask t in all) if (t.model == model) t];

  static SettingsHandler get _settings => SettingsHandler.instance;

  /// Bumped on every change, so a page showing the switches can redraw.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Writes the settings file; replaced in tests.
  @visibleForTesting
  static Future<void> Function() save = _defaultSave;

  static Future<void> _defaultSave() => SettingsHandler.instance.saveSettings(restate: false);

  /// How many cores the phone has; replaced in tests.
  @visibleForTesting
  static int Function() maxThreads = _defaultMaxThreads;

  static int _defaultMaxThreads() => Platform.numberOfProcessors;

  @visibleForTesting
  static void resetForTests() {
    save = _defaultSave;
    maxThreads = _defaultMaxThreads;
  }

  /// The job runs: every model is not switched off, and this job is on.
  static bool isOn(ModelTask task) => !_settings.aiModelsOff && (_settings.modelTasks[task.key] ?? true);

  /// The job's own switch, whatever "all models off" says.
  static bool isSwitchedOn(ModelTask task) => _settings.modelTasks[task.key] ?? true;

  /// The model's own switch (the one in its section of the Recommendations
  /// page).
  static bool modelOn(ModelKind model) => switch (model) {
    ModelKind.text => _settings.aiEncoder,
    ModelKind.look => _settings.aiLook,
    ModelKind.tagger => _settings.aiImageTagger,
  };

  static Future<void> setModelOn(ModelKind model, bool on) async {
    switch (model) {
      case ModelKind.text:
        _settings.aiEncoder = on;
      case ModelKind.look:
        _settings.aiLook = on;
      case ModelKind.tagger:
        _settings.aiImageTagger = on;
    }
    await _changed();
  }

  /// The two older job switches, shown with the others on the Models page.
  static bool get framesOn => _settings.videoFrames;

  static Future<void> setFrames(bool on) async {
    _settings.videoFrames = on;
    await _changed();
  }

  static bool get reactionsOn => _settings.taggerOnReactions;

  static Future<void> setReactions(bool on) async {
    _settings.taggerOnReactions = on;
    await _changed();
  }

  static Future<void> set(ModelTask task, bool on) async {
    if (on) {
      _settings.modelTasks.remove(task.key);
    } else {
      _settings.modelTasks[task.key] = false;
    }
    await _changed();
  }

  static Future<void> setAllOff(bool off) async {
    _settings.aiModelsOff = off;
    await _changed();
  }

  static Future<void> _changed() async {
    revision.value++;
    try {
      await save();
    } catch (_) {}
  }

  /// Only the jobs this build knows, and only as on/off.
  static Map<String, bool> parse(dynamic raw) {
    final Set<String> known = {for (final ModelTask t in all) t.key};
    final Map<String, bool> out = {};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && known.contains(key) && value is bool) out[key] = value;
      });
    }
    return out;
  }

  // ── space for vectors ──

  /// r81: the sizes offered for the vectors' database (MB).
  static const List<int> vectorSpaceChoices = [25, 50, 100, 250, 500, 1000, 2000];

  static String spaceLabel(int mb) => mb >= 1000 && mb % 1000 == 0 ? '${mb ~/ 1000} GB' : '$mb MB';

  static Future<void> setVectorSpace(int mb) async {
    _settings.vectorSpaceMb = mb;
    await _changed();
  }

  static Future<void> setFrameMode({required bool forYou, required FrameMode mode}) async {
    if (forYou) {
      _settings.framesForYou = mode;
    } else {
      _settings.framesOtherTabs = mode;
    }
    await _changed();
  }

  static bool get rememberLooks => _settings.rememberLooks;

  static Future<void> setRememberLooks(bool on) async {
    _settings.rememberLooks = on;
    await _changed();
  }

  // ── threads ──

  /// Today's counts: the tagger's from r79 (measured on the S24 Ultra), 1
  /// for the text and looks models, which showed no gain from more.
  static const Map<String, int> defaultThreads = {
    'text.waiting': 1,
    'text.background': 1,
    'look.waiting': 1,
    'look.background': 1,
    'tagger.waiting': 4,
    'tagger.background': 2,
  };

  static String threadsKey(ModelKind model, ModelUse use) => '${model.name}.${use.name}';

  /// The phone's cores, the most threads a model can get.
  static int get cores => math.max(1, maxThreads());

  /// The threads [model] opens with for [use]: the saved count or today's,
  /// never below 1 or above the phone's cores.
  static int threads(ModelKind model, ModelUse use) {
    final String key = threadsKey(model, use);
    final int wanted = _settings.modelThreads[key] ?? defaultThreads[key] ?? 1;
    return wanted.clamp(1, cores);
  }

  static Future<void> setThreads(ModelKind model, ModelUse use, int count) async {
    final String key = threadsKey(model, use);
    final int n = count.clamp(1, cores);
    if (n == defaultThreads[key]) {
      _settings.modelThreads.remove(key);
    } else {
      _settings.modelThreads[key] = n;
    }
    await _changed();
  }

  /// Only the counts this build knows, and only whole numbers of 1 or more.
  static Map<String, int> parseThreads(dynamic raw) {
    final Map<String, int> out = {};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && defaultThreads.containsKey(key) && value is int && value >= 1) out[key] = value;
      });
    }
    return out;
  }
}
