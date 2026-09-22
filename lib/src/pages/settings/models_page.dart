import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// r80: Settings → Recommendations → Models. Every job of the three models
/// with a switch of its own, how many threads each model gets for work you
/// wait on and for background work, and one switch that turns every model
/// off. A job switched off is never started: the model is not even opened
/// for it.
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  /// Tells a model its thread counts changed, so it reopens with them;
  /// replaced in tests.
  static void Function(ModelKind model) threadsChanged = _defaultThreadsChanged;

  static void _defaultThreadsChanged(ModelKind model) {
    switch (model) {
      case ModelKind.text:
        EncoderHandler.maybe?.threadsChanged();
      case ModelKind.look:
        LookModelHandler.maybe?.threadsChanged();
      case ModelKind.tagger:
        ImageTaggerHandler.maybe?.threadsChanged();
    }
  }

  /// r81: what the vectors take, by model; replaced in tests.
  static Future<({int text, int looks})> Function() vectorUsage = _defaultVectorUsage;

  /// r81: a new space for the vectors: the extra ones go now, and a smaller
  /// space also shrinks the file; replaced in tests.
  static Future<void> Function(int mb, {required bool smaller}) applyVectorSpace = _defaultApplyVectorSpace;

  static Future<({int text, int looks})> _defaultVectorUsage() => SettingsHandler.instance.dbHandler.vectorUsage();

  static Future<void> _defaultApplyVectorSpace(int mb, {required bool smaller}) async {
    final DBHandler db = SettingsHandler.instance.dbHandler;
    await db.pruneEmbeddings(maxBytes: mb * 1048576);
    if (smaller) await db.compactVectors();
  }

  static void resetForTests() {
    threadsChanged = _defaultThreadsChanged;
    vectorUsage = _defaultVectorUsage;
    applyVectorSpace = _defaultApplyVectorSpace;
  }

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  SettingsHandler get settings => SettingsHandler.instance;

  /// r81: what the vectors take now; null while it is read.
  ({int text, int looks})? _usage;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUsage());
  }

  Future<void> _loadUsage() async {
    try {
      final ({int text, int looks}) u = await ModelsPage.vectorUsage();
      if (mounted) setState(() => _usage = u);
    } catch (e) {
      Logger.Inst().log('models page: the space used by vectors could not be read: $e', 'ModelsPage', '_loadUsage', LogTypes.booruHandlerInfo);
    }
  }

  Future<void> _setSpace(int mb) async {
    final int before = settings.vectorSpaceMb;
    if (mb == before) return;
    await ModelTasks.setVectorSpace(mb);
    if (!mounted) return;
    setState(() => _applying = true);
    try {
      await ModelsPage.applyVectorSpace(mb, smaller: mb < before);
    } catch (e) {
      Logger.Inst().log('models page: the new space for vectors could not be applied: $e', 'ModelsPage', '_setSpace', LogTypes.exception);
    }
    if (!mounted) return;
    setState(() => _applying = false);
    await _loadUsage();
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  static const Map<ModelKind, String> _names = {
    ModelKind.text: 'Text model',
    ModelKind.look: 'Looks model',
    ModelKind.tagger: 'Image tagger',
  };

  static const Map<ModelKind, String> _about = {
    ModelKind.text: 'Reads titles and tags into meaning (the Encoder section).',
    ModelKind.look: 'Sees how a picture looks (the Looks model section).',
    ModelKind.tagger: 'Reads tags straight from a picture (the Image tagger section).',
  };

  /// Whether the model is downloaded, in words.
  String _downloaded(ModelKind model) {
    switch (model) {
      case ModelKind.text:
        final EncoderHandler? e = EncoderHandler.maybe;
        return e != null && e.status.value.state == EncoderState.ready ? 'Downloaded.' : 'Not downloaded.';
      case ModelKind.look:
        return (LookModelHandler.maybe?.isReady ?? false) ? 'Downloaded.' : 'Not downloaded.';
      case ModelKind.tagger:
        return (ImageTaggerHandler.maybe?.isReady ?? false) ? 'Downloaded.' : 'Not downloaded.';
    }
  }

  Future<void> _run(Future<void> Function() change) async {
    await change();
    if (mounted) setState(() {});
  }

  Future<void> _setThreads(ModelKind model, ModelUse use, int count) async {
    await ModelTasks.setThreads(model, use, count);
    ModelsPage.threadsChanged(model);
    if (mounted) setState(() {});
  }

  Widget _header(String title, String subtitle) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _task(ModelTask task, {required bool enabled}) => SettingsToggle(
    key: ValueKey('model-task-${task.key}'),
    value: ModelTasks.isSwitchedOn(task),
    enabled: enabled,
    onChanged: (bool v) => _run(() => ModelTasks.set(task, v)),
    title: task.title,
    subtitle: Text(task.description),
  );

  Widget _threads(ModelKind model, ModelUse use) {
    final int n = ModelTasks.threads(model, use);
    final String id = 'model-threads-${model.name}-${use.name}';
    final bool waiting = use == ModelUse.waiting;
    return ListTile(
      key: ValueKey('$id-row'),
      title: Text(waiting ? 'Threads while you wait' : 'Threads in the background'),
      subtitle: Text(
        waiting
            ? 'For You, boards, Posts like this, Try it: someone looks at the screen for the answer.'
            : 'Learning from your reactions, frames: nobody waits. Fewer threads leave the phone smoother.',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('$id-minus'),
            tooltip: 'One thread fewer',
            onPressed: n > 1 ? () => _setThreads(model, use, n - 1) : null,
            icon: const Icon(Symbols.remove_rounded),
          ),
          SizedBox(
            width: 28,
            child: Text('$n', key: ValueKey(id), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            key: ValueKey('$id-plus'),
            tooltip: 'One thread more',
            onPressed: n < ModelTasks.cores ? () => _setThreads(model, use, n + 1) : null,
            icon: const Icon(Symbols.add_rounded),
          ),
        ],
      ),
    );
  }

  /// r81: when a playing video's frames are taken, on For You or in the
  /// other tabs.
  Widget _frames({required bool forYou, required bool enabled}) {
    final ThemeData theme = Theme.of(context);
    final FrameMode mode = forYou ? settings.framesForYou : settings.framesOtherTabs;
    return Padding(
      key: ValueKey(forYou ? 'frames-foryou' : 'frames-other'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(forYou ? 'Frames on the For You page' : 'Frames in other tabs', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            forYou
                ? 'While it plays: after 2.5 s, then every 6 s (5 at most), as before. When you react: only when you favourite, download or add it to a collection.'
                : 'Searches, boards, Posts like this and every other tab. While it plays is how it was before; When you react waits for a favourite, a download or a collection.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<FrameMode>(
            segments: [
              for (final FrameMode m in FrameMode.values) ButtonSegment<FrameMode>(value: m, label: Text(m.label)),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: enabled ? (Set<FrameMode> s) => _run(() => ModelTasks.setFrameMode(forYou: forYou, mode: s.first)) : null,
          ),
        ],
      ),
    );
  }

  /// r81: the space the vectors may take, and what they take now.
  List<Widget> _vectors() {
    final int mb = settings.vectorSpaceMb;
    final ({int text, int looks})? u = _usage;
    return [
      _header(
        'Saved vectors',
        'What the text and looks models worked out for posts, kept in a database of their own (vectors.db) so nothing is read twice. '
            'Past the space set here, the least recently used go first. A backup can take them or leave them (the item "Vector cache").',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final int c in ModelTasks.vectorSpaceChoices)
              ChoiceChip(
                key: ValueKey('vector-space-$c'),
                label: Text(ModelTasks.spaceLabel(c)),
                selected: mb == c,
                onSelected: _applying ? null : (_) => _setSpace(c),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(
          u == null
              ? 'Reading the space used…'
              : 'Used: ${_mb(u.text + u.looks)} of ${ModelTasks.spaceLabel(mb)} (text ${_mb(u.text)}, looks ${_mb(u.looks)}).',
          key: const ValueKey('vector-space-used'),
        ),
      ),
      if (_applying)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: LinearProgressIndicator(),
        ),
    ];
  }

  List<Widget> _model(ModelKind model) {
    final bool allOff = settings.aiModelsOff;
    final bool on = ModelTasks.modelOn(model);
    return [
      _header(_names[model]!, '${_about[model]!} ${_downloaded(model)}'),
      SettingsToggle(
        key: ValueKey('model-use-${model.name}'),
        value: on,
        enabled: !allOff,
        onChanged: (bool v) => _run(() => ModelTasks.setModelOn(model, v)),
        title: 'Use the ${_names[model]!.toLowerCase()}',
        subtitle: const Text('The same switch as in its section of the Recommendations page.'),
      ),
      for (final ModelTask t in ModelTasks.of(model)) _task(t, enabled: !allOff && on),
      if (model == ModelKind.look) ...[
        SettingsToggle(
          key: const ValueKey('model-task-look.frames'),
          value: ModelTasks.framesOn,
          enabled: !allOff && on,
          onChanged: (bool v) => _run(() => ModelTasks.setFrames(v)),
          title: 'Frames from playing videos',
          subtitle: const Text('A video is judged by a few frames taken while it plays instead of its preview picture (the switch "Read frames from playing videos").'),
        ),
        // r81: when, per place.
        _frames(forYou: true, enabled: !allOff && on && ModelTasks.framesOn),
        _frames(forYou: false, enabled: !allOff && on && ModelTasks.framesOn),
        SettingsToggle(
          key: const ValueKey('model-task-look.remember'),
          value: ModelTasks.rememberLooks,
          enabled: !allOff && on,
          onChanged: (bool v) => _run(() => ModelTasks.setRememberLooks(v)),
          title: 'Remember the looks of posts you open',
          subtitle: const Text(
            'When you leave a post you looked at for 2.5 s or more, its look is saved, so For You, boards and the learner find it ready. '
            'A video keeps the average of its frames; a post without frames has its thumbnail read once, in the background.',
          ),
        ),
      ],
      if (model == ModelKind.tagger)
        SettingsToggle(
          key: const ValueKey('model-task-tagger.reactions'),
          value: ModelTasks.reactionsOn,
          enabled: !allOff && on,
          onChanged: (bool v) => _run(() => ModelTasks.setReactions(v)),
          title: 'Tags of what you react to',
          subtitle: const Text('A strong reaction on a post also learns the tags read from its picture (the switch "Tag reactions with the picture").'),
        ),
      _threads(model, ModelUse.waiting),
      _threads(model, ModelUse.background),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              "What each downloaded model does, job by job, and how many of the phone's ${ModelTasks.cores} cores it may use. "
              'A new thread count is used the next time the model opens; a model that is idle is closed at once so the next use picks it up.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          SettingsToggle(
            key: const ValueKey('models-all-off'),
            value: settings.aiModelsOff,
            onChanged: (bool v) => _run(() => ModelTasks.setAllOff(v)),
            title: 'All models off',
            subtitle: const Text('Nothing is loaded or run: the recommender goes by tags alone. The switches below are kept for when you turn this off again.'),
            leadingIcon: const Icon(Symbols.power_settings_new_rounded),
          ),
          for (final ModelKind m in ModelKind.values) ..._model(m),
          ..._vectors(),
        ],
      ),
    );
  }
}
