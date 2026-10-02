import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/explain_button.dart';
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

  /// r86: the providers this build's ONNX Runtime has; replaced in tests.
  static Future<List<String>> Function() availableProviders = _defaultAvailableProviders;

  static Future<List<String>> _defaultAvailableProviders() async =>
      [for (final OrtProvider p in await OnnxRuntime().getAvailableProviders()) p.name];

  /// r87: the looks model's full-precision picture half (the NPU's): there
  /// yet, its size, and fetching it; replaced in tests.
  static bool Function() lookNpuReady = _defaultLookNpuReady;
  static int? Function() lookNpuBytes = _defaultLookNpuBytes;
  static Future<bool> Function(void Function(double progress) progress) downloadLookNpu = _defaultDownloadLookNpu;

  static bool _defaultLookNpuReady() => LookModelHandler.maybe?.hasNpuFile ?? false;
  static int? _defaultLookNpuBytes() => LookModelHandler.maybe?.npuImageBytes;
  static Future<bool> _defaultDownloadLookNpu(void Function(double progress) progress) async =>
      await LookModelHandler.maybe?.downloadNpuFile(onProgress: progress) ?? false;

  static void resetForTests() {
    threadsChanged = _defaultThreadsChanged;
    vectorUsage = _defaultVectorUsage;
    applyVectorSpace = _defaultApplyVectorSpace;
    availableProviders = _defaultAvailableProviders;
    lookNpuReady = _defaultLookNpuReady;
    lookNpuBytes = _defaultLookNpuBytes;
    downloadLookNpu = _defaultDownloadLookNpu;
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
    // r86: the timings the explain windows show.
    unawaited(ModelTimings.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }));
    // r87: a change made elsewhere (a download that finished) is shown.
    ModelTasks.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ModelTasks.revision.removeListener(_onRevision);
    super.dispose();
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

  // ── r86: run on, picture decoding ──

  static const Map<ModelAccelerator, String> _runOnText = {
    ModelAccelerator.cpu:
        "ONNX Runtime's own code on the phone's processor, with the thread counts below. Works with every model and is how the app ran "
        'before r86. More threads finish sooner but warm the phone and can make scrolling stutter.',
    ModelAccelerator.xnnpack:
        "Google's CPU library, often quicker than the default for convolutions and big matrix sums - mostly the tagger. It runs its share on "
        'the thread counts below (its own pool, as ONNX Runtime recommends). The text and looks models are int8 files, which it barely helps.',
    ModelAccelerator.nnapi:
        "Android's route to the phone's GPU or NPU, through the chip maker's driver. Android 15 marked it as old, but it still works. The "
        'driver takes the parts it can, at full precision, and the CPU does the rest; the int8 text and looks models fall back to the CPU almost '
        'entirely. Opening the model takes longer while the driver prepares it. Worth a try on the tagger.',
    ModelAccelerator.npu:
        "The phone's NPU (the Snapdragon's Hexagon), through Qualcomm's QNN library: the model runs at 16-bit precision on hardware made for "
        'it - usually many times faster than the CPU, and far cooler. The first opening compiles the model for the NPU (seconds, up to about a '
        'minute for the tagger) and keeps the compiled copy next to the model, so later openings are quick. Parts the NPU cannot run stay on '
        'the CPU (the log says "NPU + CPU"); if it refuses the model, the CPU runs it. The looks model needs its full-precision picture half '
        'for this, fetched when you pick it; its words stay on the CPU.',
  };

  static String _mbOf(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  /// r87: the NPU for the looks model needs its full-precision picture half.
  Future<bool> _npuFileReady() async {
    if (ModelsPage.lookNpuReady()) return true;
    final int? bytes = ModelsPage.lookNpuBytes();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('The NPU needs another file'),
        content: Text(
          'The NPU runs the full-precision picture half of the looks model '
          '(${bytes == null ? 'its size is not known for this model' : _mbOf(bytes)}); the 8-bit one the app has uses steps the NPU does not have. '
          'Download it now?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Download')),
        ],
      ),
    );
    if (go != true || !mounted) return false;
    final ValueNotifier<double> progress = ValueNotifier(0);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Downloading the picture half'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, double v, _) => LinearProgressIndicator(value: v > 0 ? v : null),
          ),
        ),
      ),
    );
    final bool ok = await ModelsPage.downloadLookNpu((double v) => progress.value = v);
    if (mounted) Navigator.of(context).pop();
    progress.dispose();
    return ok;
  }

  Future<void> _setRunOn(ModelKind model, ModelAccelerator a) async {
    if (model == ModelKind.look && a == ModelAccelerator.npu && !await _npuFileReady()) return;
    await ModelTasks.setRunOn(model, a);
    ModelsPage.threadsChanged(model);
    if (mounted) setState(() {});
  }

  Widget _runOn(ModelKind model) {
    final ThemeData theme = Theme.of(context);
    final ModelAccelerator now = ModelTasks.runOn(model);
    return Padding(
      key: ValueKey('model-runon-${model.name}-row'),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Run on', style: TextStyle(fontWeight: FontWeight.w600))),
              ExplainButton(
                key: ValueKey('model-runon-${model.name}-explain'),
                title: 'Run on: ${_names[model]!}',
                intro: 'What the ${_names[model]!.toLowerCase()} runs on. Times are the model alone (not the picture preparation), as this phone measured them.',
                choices: () => [
                  for (final ModelAccelerator a in ModelAccelerator.choicesFor(model))
                    ExplainChoice(
                      name: a == ModelAccelerator.cpu ? '${a.label} (as before)' : a.label,
                      text: _runOnText[a]!,
                      timing: [
                        ModelTimings.words(ModelTimings.instance.run(model, a), unit: 'run'),
                        if (ModelTimings.instance.open(model, a) != null)
                          'Opening the model: ${ModelTimings.instance.open(model, a)!.averageMs} ms on average.',
                      ].join(' '),
                    ),
                ],
                footer:
                    'A new choice is used the next time the model opens; an idle model is closed at once. When a choice refuses the model, '
                    'the CPU runs it and the log says so ("refused").'
                    '${model == ModelKind.text ? " The NPU is not offered here: the text model's inputs change length with every text, and the NPU needs fixed sizes." : ''}',
                note: () async {
                  try {
                    final List<String> names = [...await ModelsPage.availableProviders()]..sort();
                    return 'Available in this build: ${names.join(', ')}.';
                  } catch (_) {
                    return null;
                  }
                },
              ),
            ],
          ),
          Text(
            'The CPU is how it ran before. Applies the next time the model opens.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ModelAccelerator>(
            key: ValueKey('model-runon-${model.name}'),
            segments: [
              for (final ModelAccelerator a in ModelAccelerator.choicesFor(model)) ButtonSegment<ModelAccelerator>(value: a, label: Text(a.label)),
            ],
            selected: {now},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ModelAccelerator> s) => _setRunOn(model, s.first),
          ),
        ],
      ),
    );
  }

  static const Map<PictureDecoder, String> _decoderText = {
    PictureDecoder.phone:
        "Android's own decoders (through Flutter's engine) shrink the picture while decoding it, to twice what the model needs; the app then "
        'pads, crops and resizes it as before. Much faster on big files and lighter on memory. What the model sees differs very slightly from '
        'before, so a picture read again may get a slightly different look or tag scores.',
    PictureDecoder.dart:
        "The app's own decoder, written in Dart: it reads the whole file at full size before shrinking it - about 1 s for a 4 MB picture on "
        "this phone (log of 2 October). Exactly what earlier builds did. Also used for any file the phone cannot read; the tagger's log line "
        'names the decoder used.',
  };

  Widget _pictureDecoder() {
    final ThemeData theme = Theme.of(context);
    return Padding(
      key: const ValueKey('picture-decoder-row'),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Picture decoding', style: TextStyle(fontWeight: FontWeight.w600))),
              ExplainButton(
                key: const ValueKey('picture-decoder-explain'),
                title: 'Picture decoding',
                intro:
                    'Who turns a picture file into the pixels the looks model and the tagger read (and the frames of playing videos). '
                    'Times are the whole preparation of one picture, as this phone measured them.',
                choices: () => [
                  for (final PictureDecoder d in PictureDecoder.values)
                    ExplainChoice(
                      name: d.label,
                      text: _decoderText[d]!,
                      timing: ModelTimings.words(ModelTimings.instance.decode(d), unit: 'picture'),
                    ),
                ],
              ),
            ],
          ),
          Text(
            'For the looks model, the tagger and video frames. The phone is new in r86; As before is how it worked until then.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PictureDecoder>(
            key: const ValueKey('picture-decoder'),
            segments: [
              for (final PictureDecoder d in PictureDecoder.values) ButtonSegment<PictureDecoder>(value: d, label: Text(d.label)),
            ],
            selected: {ModelTasks.pictureDecoder},
            showSelectedIcon: false,
            onSelectionChanged: (Set<PictureDecoder> s) => _run(() => ModelTasks.setPictureDecoder(s.first)),
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
      // r86: what the model runs on.
      _runOn(model),
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
          // r86: who decodes the models' pictures.
          _pictureDecoder(),
          for (final ModelKind m in ModelKind.values) ..._model(m),
          ..._vectors(),
        ],
      ),
    );
  }
}
