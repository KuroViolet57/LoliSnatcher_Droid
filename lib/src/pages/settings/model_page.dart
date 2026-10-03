import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_availability.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/models_page.dart';
import 'package:lolisnatcher/src/pages/settings/recommendations_page.dart';
import 'package:lolisnatcher/src/widgets/common/explain_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// r88: one model's page (Settings → Recommendations & AI → Models → a
/// card), in three parts with clear titles: the model itself (download,
/// size, on/off), what it does for you job by job, and its speed (what it
/// runs on, its thread counts) - each number with an explanation, a
/// recommendation and this phone's timings. Every switch is here once.
class ModelPage extends StatefulWidget {
  const ModelPage({required this.kind, super.key});

  final ModelKind kind;

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage> {
  SettingsHandler get settings => SettingsHandler.instance;
  ModelKind get kind => widget.kind;
  String get name => ModelsPage.names[kind]!;

  @override
  void initState() {
    super.initState();
    unawaited(ModelTimings.instance.ensureLoaded().then((_) => _refresh()));
    unawaited(OnnxAvailability.load().then((_) => _refresh()));
    ModelTasks.revision.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ModelTasks.revision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() change) async {
    await change();
    _refresh();
  }

  bool get _jobsEnabled => !settings.aiModelsOff && ModelTasks.modelOn(kind);

  TextStyle get _muted => TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));

  // ── the model ──

  Widget _section() => switch (kind) {
    ModelKind.text => EncoderModelSection(onChanged: () async => _refresh()),
    ModelKind.look => const LookModelSection(),
    ModelKind.tagger => const TaggerModelSection(),
  };

  // ── what it does ──

  Widget _task(ModelTask task) => SettingsToggle(
    key: ValueKey('model-task-${task.key}'),
    value: ModelTasks.isSwitchedOn(task),
    enabled: _jobsEnabled,
    onChanged: (bool v) => _run(() => ModelTasks.set(task, v)),
    title: task.title,
    subtitle: Text(task.description),
  );

  /// r81: when a playing video's frames are taken, on For You or in the
  /// other tabs.
  Widget _frames({required bool forYou, required bool enabled}) {
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
            style: _muted,
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

  List<Widget> _jobs() => [
    for (final ModelTask t in ModelTasks.of(kind)) _task(t),
    if (kind == ModelKind.look) ...[
      SettingsToggle(
        key: const ValueKey('model-task-look.frames'),
        value: ModelTasks.framesOn,
        enabled: _jobsEnabled,
        onChanged: (bool v) => _run(() => ModelTasks.setFrames(v)),
        title: 'Read frames from playing videos',
        subtitle: const Text(
          'While a video plays in the media_kit player, a few pictures of what is on screen are read, and the video is judged by them instead of '
          'its preview picture: For You, Posts like this, boards and tagging your reactions. Off = the preview picture, as before.',
        ),
        leadingIcon: const Icon(Symbols.movie_rounded),
      ),
      _frames(forYou: true, enabled: _jobsEnabled && ModelTasks.framesOn),
      _frames(forYou: false, enabled: _jobsEnabled && ModelTasks.framesOn),
      SettingsToggle(
        key: const ValueKey('model-task-look.remember'),
        value: ModelTasks.rememberLooks,
        enabled: _jobsEnabled,
        onChanged: (bool v) => _run(() => ModelTasks.setRememberLooks(v)),
        title: 'Remember the looks of posts you open',
        subtitle: const Text(
          'When you leave a post you looked at for 2.5 s or more, its look is saved, so For You, boards and the learner find it ready. '
          'A video keeps the average of its frames; a post without frames has its thumbnail read once, in the background.',
        ),
      ),
    ],
    if (kind == ModelKind.tagger)
      SettingsToggle(
        key: const ValueKey('model-task-tagger.reactions'),
        value: ModelTasks.reactionsOn,
        enabled: _jobsEnabled,
        onChanged: (bool v) => _run(() => ModelTasks.setReactions(v)),
        title: 'Tag reactions with the picture',
        subtitle: const Text(
          'A favourite, a snatch, a collection, a finished video or Not interested on a booru post also reads its thumbnail (for a video, the '
          "preview frame the site chose), in the background. The tags join the site's tags for the learner.",
        ),
        leadingIcon: const Icon(Symbols.thumbs_up_down_rounded),
      ),
  ];

  // ── speed: run on ──

  static const Map<ModelAccelerator, String> _runOnText = {
    ModelAccelerator.cpu:
        "ONNX Runtime's own code on the phone's processor, with the thread counts below. Works with every model and is how the app ran "
        'before r86. More threads finish sooner but warm the phone and can make scrolling stutter.',
    ModelAccelerator.xnnpack:
        "Google's CPU library, often quicker than the default for convolutions and big matrix sums - mostly the tagger. It runs its share on "
        'the thread counts below. The text and looks models are int8 files, which it barely helps.',
    ModelAccelerator.nnapi:
        "Android's route to the phone's GPU or NPU, through the chip maker's driver. Android 15 marked it as old, but it still works. The "
        'driver takes the parts it can, at full precision, and the CPU does the rest. Opening the model takes longer while the driver prepares it.',
    ModelAccelerator.npu:
        "The phone's NPU (the Snapdragon's Hexagon), through Qualcomm's QNN library: the model runs at 16-bit precision on hardware made for "
        'it - many times faster than the CPU and far cooler (the tagger: about 150 ms a picture on your phone, against 1.8 s on 4 CPU threads). '
        'The first opening compiles the model and keeps the compiled copy, so later openings take under a second: the whole model when the '
        'NPU can take all of it ("NPU" in the log), else a copy that leaves the parts it cannot run to the CPU ("NPU + CPU") - the line '
        'under Run on says which. If it fails while running, that picture is read on the CPU; a whole-model copy that fails is replaced by '
        'the other kind at the next opening, and after two failures the model stays on the CPU until you pick NPU again. The looks model '
        'needs its full-precision picture half for this, fetched when you pick it.',
  };

  static String _mbOf(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  static const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// r89: which compiled NPU copy the model has (npuCopyState), one line.
  String _npuCopyWords(String modelPath) {
    final ({bool? whole, DateTime? compiled, bool wholeFailed}) state = npuCopyState(modelPath);
    final DateTime? at = state.compiled;
    final String when = at == null ? '' : ' (compiled ${at.day} ${_months[at.month - 1]})';
    return switch (state.whole) {
      true => 'On the NPU: the whole model$when.',
      false => 'On the NPU: some parts on the CPU$when${state.wholeFailed ? ' - the whole model failed here' : ''}.',
      null => 'Not compiled yet: the next opening compiles it for the NPU (seconds to a minute), the whole model first.',
    };
  }

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

  Future<void> _setRunOn(ModelAccelerator a) async {
    if (kind == ModelKind.look && a == ModelAccelerator.npu && !await _npuFileReady()) return;
    await ModelTasks.setRunOn(kind, a);
    ModelsPage.threadsChanged(kind);
    _refresh();
  }

  String _openingWords(ModelAccelerator a) {
    final TimingStat? open = ModelTimings.instance.open(kind, a);
    return open == null ? '' : ' Opening the model: ${open.averageMs} ms on average.';
  }

  String? _fastestWords() {
    final f = ModelTimings.instance.fastest(kind);
    if (f == null) return null;
    return 'Fastest on this phone so far: ${f.accelerator.label}${f.threads == null ? '' : ' with ${f.threads} threads'}, '
        '${f.averageMs} ms per run - recommended unless it heats the phone or fails.';
  }

  Widget _runOn() {
    final List<ModelAccelerator> choices = OnnxAvailability.choicesFor(kind);
    final ModelAccelerator chosen = ModelTasks.runOn(kind);
    final ModelAccelerator selected = choices.contains(chosen) ? chosen : ModelAccelerator.cpu;
    final ({int count, String reason})? failed = ModelTimings.instance.npuFailures(kind);
    final String? refused = actualAccelerator(kind).refused;
    final String? npuFile = chosen == ModelAccelerator.npu ? ModelsPage.npuModelPath(kind) : null;
    return Padding(
      key: ValueKey('model-runon-${kind.name}-row'),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Run on', style: TextStyle(fontWeight: FontWeight.w600))),
              ExplainButton(
                key: ValueKey('model-runon-${kind.name}-explain'),
                title: 'Run on: $name',
                intro: 'What the ${name.toLowerCase()} runs on. Times are the model alone (not the picture preparation), as this phone measured them.',
                choices: () => [
                  for (final ModelAccelerator a in ModelAccelerator.choicesFor(kind))
                    ExplainChoice(
                      name: '${a.label}${a == ModelAccelerator.cpu ? ' (as before)' : ''}${OnnxAvailability.has(a) ? '' : ' - not in this build'}',
                      text: _runOnText[a]!,
                      timing: '${ModelTimings.words(ModelTimings.instance.run(kind, a), unit: 'run')}${_openingWords(a)}',
                    ),
                ],
                footer: [
                  ?_fastestWords(),
                  'A new choice is used the next time the model opens; an idle model is closed at once. When a choice refuses the model, the CPU runs it and the log says so ("refused").',
                  if (kind == ModelKind.text) "The NPU is not offered here: the text model's inputs change length with every text, and the NPU needs fixed sizes.",
                ].join('\n\n'),
                note: () async {
                  final Set<String>? names = OnnxAvailability.providers;
                  return names == null ? null : 'Available in this build: ${([...names]..sort()).join(', ')}.';
                },
              ),
            ],
          ),
          Text('The CPU is how it ran before. Applies the next time the model opens.', style: _muted),
          const SizedBox(height: 8),
          SegmentedButton<ModelAccelerator>(
            key: ValueKey('model-runon-${kind.name}'),
            segments: [
              for (final ModelAccelerator a in choices) ButtonSegment<ModelAccelerator>(value: a, label: Text(a.label)),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ModelAccelerator> s) => _setRunOn(s.first),
          ),
          if (chosen != selected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${chosen.label} was chosen, but this build does not have it: the CPU runs the model.', style: _muted),
            ),
          if (chosen == ModelAccelerator.npu && npuFile != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_npuCopyWords(npuFile), key: ValueKey('model-npu-copy-${kind.name}'), style: _muted),
            ),
          if (refused != null)
            Padding(
              key: ValueKey('model-${chosen.name}-refused-${kind.name}'),
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${chosen.label} refused this model when it last opened, so the CPU runs it; ${chosen.label} is asked again each time the '
                'model opens.\n$refused',
                style: _muted.copyWith(color: Colors.orange),
              ),
            ),
          if (failed != null && chosen == ModelAccelerator.npu)
            Padding(
              key: ValueKey('model-npu-failed-${kind.name}'),
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The NPU failed ${failed.count == 1 ? 'once' : '${failed.count} times'} while running this model'
                '${failed.count >= 2 ? ', so it runs on the CPU now. Tap CPU, then NPU, to give it another chance.' : '; the picture was read on the CPU.'}'
                '\n${npuErrorWords(failed.reason)}',
                style: _muted.copyWith(color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  // ── speed: threads ──

  static const Map<String, String> _recommended = {
    'text.waiting': '1 or 2. A text takes tens of milliseconds (25-70 ms in your log); more threads barely help.',
    'text.background': '1. Nobody waits for these, and one thread keeps the phone smooth.',
    'look.waiting':
        '2 on the CPU - a thumbnail takes well under a second and more threads add little; or the NPU (Run on) when it works for you.',
    'look.background': '1. Frames and reactions are read while you scroll and watch; one thread keeps that smooth.',
    'tagger.waiting':
        'The NPU (Run on): about 150 ms a picture on your phone. On the CPU: 4 - on your phone 4 threads took 1.8 s, 2 threads 2.6 s.',
    'tagger.background': 'The NPU, or 2 on the CPU - reactions are tagged in the background, and 2 threads leave room for scrolling and video.',
  };

  String _measuredWords() {
    final ModelTimings t = ModelTimings.instance;
    final List<String> lines = [];
    for (final ModelAccelerator a in ModelAccelerator.values) {
      for (final int threads in t.threadsMeasured(kind, a)) {
        final TimingStat s = t.run(kind, a, threads: threads)!;
        lines.add('${a.label}, $threads thread${threads == 1 ? '' : 's'}: ${s.averageMs} ms on average (${s.runs} run${s.runs == 1 ? '' : 's'})');
      }
    }
    return lines.isEmpty ? 'Nothing measured yet: use the model a few times with different counts, then look here again.' : lines.join('\n');
  }

  Future<void> _setThreads(ModelUse use, int count) async {
    await ModelTasks.setThreads(kind, use, count);
    ModelsPage.threadsChanged(kind);
    _refresh();
  }

  Widget _threads(ModelUse use) {
    final int n = ModelTasks.threads(kind, use);
    final String id = 'model-threads-${kind.name}-${use.name}';
    final bool waiting = use == ModelUse.waiting;
    final String title = waiting ? 'Threads while you wait' : 'Threads in the background';
    return ListTile(
      key: ValueKey('$id-row'),
      title: Row(
        children: [
          Flexible(child: Text(title)),
          ExplainButton(
            key: ValueKey('$id-explain'),
            title: '$title: $name',
            choices: () => [
              ExplainChoice(
                name: 'What the number does',
                text:
                    "How many of the processor's cores the model may use at once for one ${kind == ModelKind.text ? 'text' : 'picture'}. "
                    '${waiting ? 'This count is for work someone looks at the screen for: For You, boards, Posts like this, Try it.' : 'This count is for work nobody waits for: learning from your reactions, video frames.'} '
                    'More threads split the work, so it finishes sooner - until the fast cores are used up.',
              ),
              ExplainChoice(
                name: 'What it costs',
                text:
                    'Each thread keeps a core busy: more threads mean more heat and battery, and scrolling or a playing video can stutter while the '
                    'model works. This phone has ${ModelTasks.cores} cores; phones mix fast and slow ones (an S24 Ultra has 1 very fast, 5 fast '
                    'and 2 slow), so past about 4 the gain is small. A new count is used the next time the model opens.',
              ),
              if (kind != ModelKind.text)
                const ExplainChoice(
                  name: 'On the NPU',
                  text: 'Run on NPU does the work on the NPU; these threads then only matter for the parts it leaves to the CPU.',
                ),
              ExplainChoice(name: 'Recommended', text: _recommended['${kind.name}.${use.name}']!),
              ExplainChoice(name: 'Measured on this phone', text: _measuredWords()),
            ],
          ),
        ],
      ),
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
            onPressed: n > 1 ? () => _setThreads(use, n - 1) : null,
            icon: const Icon(Symbols.remove_rounded),
          ),
          SizedBox(
            width: 28,
            child: Text('$n', key: ValueKey(id), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            key: ValueKey('$id-plus'),
            tooltip: 'One thread more',
            onPressed: n < ModelTasks.cores ? () => _setThreads(use, n + 1) : null,
            icon: const Icon(Symbols.add_rounded),
          ),
        ],
      ),
    );
  }

  // ── the page ──

  String _status() {
    if (!ModelsPage.downloaded(kind)) return 'Not downloaded yet - the Model part below downloads it.';
    final ModelAccelerator chosen = ModelTasks.runOn(kind);
    final (:ModelAccelerator used, :String? refused) = actualAccelerator(kind);
    final String on = settings.aiModelsOff
        ? 'Every model is off (Models page).'
        : ModelTasks.modelOn(kind)
        ? 'On.'
        : 'Switched off (Model part).';
    return 'Downloaded. $on Runs on ${used.label}${chosen == used ? '' : ' (${chosen.label} ${refused != null ? 'refused it' : 'chosen'})'}.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ModelsPage.about[kind]!),
                const SizedBox(height: 4),
                Text(_status(), key: ValueKey('model-page-status-${kind.name}'), style: _muted),
              ],
            ),
          ),
          SettingsPart(key: ValueKey('model-part-${kind.name}-model'),
            title: 'Model',
            subtitle: 'Download it, pick its size, switch it on or off.',
          ),
          _section(),
          SettingsPart(key: ValueKey('model-part-${kind.name}-jobs'),
            title: 'What it does',
            subtitle: 'Each job can be switched off on its own; a job that is off never opens the model.',
          ),
          ..._jobs(),
          SettingsPart(key: ValueKey('model-part-${kind.name}-speed'),
            title: 'Speed',
            subtitle: 'What it runs on and how many cores it may use. The (i) buttons explain each, with what this phone measured.',
          ),
          _runOn(),
          _threads(ModelUse.waiting),
          _threads(ModelUse.background),
        ],
      ),
    );
  }
}
