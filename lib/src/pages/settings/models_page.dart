import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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

  static void resetForTests() => threadsChanged = _defaultThreadsChanged;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  SettingsHandler get settings => SettingsHandler.instance;

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
      if (model == ModelKind.look)
        SettingsToggle(
          key: const ValueKey('model-task-look.frames'),
          value: ModelTasks.framesOn,
          enabled: !allOff && on,
          onChanged: (bool v) => _run(() => ModelTasks.setFrames(v)),
          title: 'Frames from playing videos',
          subtitle: const Text('A video is judged by a few frames taken while it plays instead of its preview picture (the switch "Read frames from playing videos").'),
        ),
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
        ],
      ),
    );
  }
}
