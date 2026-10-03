import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_timings.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_availability.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_options.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/model_page.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/explain_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Settings → Recommendations & AI → Models (r80; r88 an overview). What all
/// three models share: one switch for all of them, who decodes the pictures,
/// the space for saved vectors - and a card per model that opens the model's
/// own page ([ModelPage]: its download, its jobs, what it runs on).
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  /// Tells a model its thread counts (or what it runs on) changed, so it
  /// reopens with them; replaced in tests.
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

  /// r87: the looks model's full-precision picture half (the NPU's): there
  /// yet, its size, and fetching it; replaced in tests.
  static bool Function() lookNpuReady = _defaultLookNpuReady;
  static int? Function() lookNpuBytes = _defaultLookNpuBytes;
  static Future<bool> Function(void Function(double progress) progress) downloadLookNpu = _defaultDownloadLookNpu;

  /// r89: the file a model opens on the NPU (the looks model's
  /// full-precision picture half, the tagger's model), for the line under
  /// Run on that says which compiled copy it has; null for the text model or
  /// when the file is not there.
  static String? Function(ModelKind kind) npuModelPath = _defaultNpuModelPath;

  static String? _defaultNpuModelPath(ModelKind kind) {
    final String? path = switch (kind) {
      ModelKind.look => LookModelHandler.maybe?.npuImagePath,
      ModelKind.tagger => ImageTaggerHandler.maybe == null
          ? null
          : '${ImageTaggerHandler.instance.dirFor(SettingsHandler.instance.imageTaggerModel)}${ImageTaggerHandler.modelFileName}',
      ModelKind.text => null,
    };
    try {
      return path != null && File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  static bool _defaultLookNpuReady() => LookModelHandler.maybe?.hasNpuFile ?? false;
  static int? _defaultLookNpuBytes() => LookModelHandler.maybe?.npuImageBytes;
  static Future<bool> _defaultDownloadLookNpu(void Function(double progress) progress) async =>
      await LookModelHandler.maybe?.downloadNpuFile(onProgress: progress) ?? false;

  static void resetForTests() {
    threadsChanged = _defaultThreadsChanged;
    vectorUsage = _defaultVectorUsage;
    applyVectorSpace = _defaultApplyVectorSpace;
    lookNpuReady = _defaultLookNpuReady;
    lookNpuBytes = _defaultLookNpuBytes;
    downloadLookNpu = _defaultDownloadLookNpu;
    npuModelPath = _defaultNpuModelPath;
  }

  static const Map<ModelKind, String> names = {
    ModelKind.text: 'Text model',
    ModelKind.look: 'Looks model',
    ModelKind.tagger: 'Image tagger',
  };

  static const Map<ModelKind, String> about = {
    ModelKind.text: 'Reads titles and tags into meaning, so posts that are about the same thing sit together.',
    ModelKind.look: 'Sees how a picture looks, so pictures that look alike sit together (For You, Posts like this, boards).',
    ModelKind.tagger: 'Reads tags straight from a picture (boards, Try it, the tags of what you react to).',
  };

  /// Whether [model] is downloaded, in words.
  static bool downloaded(ModelKind model) => switch (model) {
    ModelKind.text => EncoderHandler.maybe?.status.value.state == EncoderState.ready,
    ModelKind.look => LookModelHandler.maybe?.isReady ?? false,
    ModelKind.tagger => ImageTaggerHandler.maybe?.isReady ?? false,
  };

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
    // r86: the timings the explain windows show; r88: what this build has.
    unawaited(ModelTimings.instance.ensureLoaded().then((_) => _refresh()));
    unawaited(OnnxAvailability.load().then((_) => _refresh()));
    // r87: a change made elsewhere (a download that finished) is shown.
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

  Future<void> _run(Future<void> Function() change) async {
    await change();
    if (mounted) setState(() {});
  }

  /// One line on a model's card: downloaded, on, what it runs on, its jobs.
  String _summary(ModelKind model) {
    final ModelAccelerator chosen = ModelTasks.runOn(model);
    final (:ModelAccelerator used, :String? refused) = actualAccelerator(model);
    final String runs = chosen == used
        ? 'runs on ${used.label}'
        : 'runs on ${used.label} (${chosen.label} ${refused != null ? 'refused it' : 'chosen'}, see its page)';
    if (!ModelsPage.downloaded(model)) return 'Not downloaded - open to download it · $runs.';
    if (settings.aiModelsOff) return 'Downloaded · every model is off (above).';
    if (!ModelTasks.modelOn(model)) return 'Downloaded · switched off · $runs.';
    final List<ModelTask> tasks = ModelTasks.of(model);
    final int on = tasks.where(ModelTasks.isSwitchedOn).length;
    return 'Downloaded · $runs · $on of ${tasks.length} jobs on.';
  }

  static const Map<PictureDecoder, String> _decoderText = {
    PictureDecoder.phone:
        "Android's own decoders (through Flutter's engine) shrink the picture while decoding it, to twice what the model needs; the app then "
        'pads, crops and resizes it as before. Much faster than "As before" on big files, and lighter on memory. What the models see differs very '
        'slightly from before. The default since r86.',
    PictureDecoder.phoneFast:
        "The phone decodes straight to the model's own size; the app only pads or crops, with no resize of its own - most of the time "
        '"The phone" still takes (360-600 ms for a 200 KB picture in your log of 2 October) is that resize. The fastest; what the models see is a '
        'little further from before than with "The phone" (the phone does the whole resize).',
    PictureDecoder.dart:
        "The app's own decoder, written in Dart: it reads the whole file at full size before shrinking it - about 1 s for a 4 MB picture on "
        "this phone. Exactly what builds before r86 did. Also used for any file the phone cannot read; the tagger's log line names the decoder used.",
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
                footer: 'Recommended: "Straight to size" when the tags and lookalikes still feel right to you, else "The phone".',
              ),
            ],
          ),
          Text(
            'For the looks model, the tagger and video frames. "As before" is how it worked until r86.',
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

  /// r81: the space the vectors may take, and what they take now.
  List<Widget> _vectors() {
    final int mb = settings.vectorSpaceMb;
    final ({int text, int looks})? u = _usage;
    return [
      const SettingsPart(key: ValueKey('models-part-vectors'),
        title: 'Saved vectors',
        subtitle:
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

  static const Map<ModelKind, IconData> _icons = {
    ModelKind.text: Symbols.text_fields_rounded,
    ModelKind.look: Symbols.image_search_rounded,
    ModelKind.tagger: Symbols.sell_rounded,
  };

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
              'Three small AI models run on the phone, each downloaded on its own. Tap one for its page: its download, what it does for you '
              "job by job, and what it runs on (the processor's cores or the NPU) - with this phone's timings.",
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          SettingsToggle(
            key: const ValueKey('models-all-off'),
            value: settings.aiModelsOff,
            onChanged: (bool v) => _run(() => ModelTasks.setAllOff(v)),
            title: 'All models off',
            subtitle: const Text('Nothing is loaded or run: the recommender goes by tags alone. Each model keeps its own settings for when you turn this off again.'),
            leadingIcon: const Icon(Symbols.power_settings_new_rounded),
          ),
          const SettingsPart(key: ValueKey('models-part-models'), title: 'The models'),
          for (final ModelKind m in ModelKind.values)
            SettingsButton(
              key: ValueKey('model-card-${m.name}'),
              name: ModelsPage.names[m]!,
              subtitle: Text('${ModelsPage.about[m]!}\n${_summary(m)}'),
              icon: Icon(_icons[m]),
              action: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ModelPage(kind: m)));
                _refresh();
              },
            ),
          const SettingsPart(key: ValueKey('models-part-shared'),
            title: 'Shared by the picture models',
            subtitle: 'The looks model and the image tagger both read pictures; this is how the pictures are prepared for them.',
          ),
          _pictureDecoder(),
          ..._vectors(),
        ],
      ),
    );
  }
}
