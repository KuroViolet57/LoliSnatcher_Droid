import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/photo_picker.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Settings → Recommendations (r33): the two switches of the on-device
/// recommender, what each world's model has learned, and a way to forget it.
class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

  /// r74: how Try it gets a picture and its tags. Replaced in tests.
  static Future<Uint8List?> Function()? pickImageBytes = _defaultPickImageBytes;
  static Future<TaggerResult> Function(Uint8List bytes)? tagImage = _defaultTagImage;

  /// r77: a picture picked before Android ended the app (it is ended more
  /// easily while the picker is in front and the models hold memory);
  /// image_picker keeps it until asked. Null when there is none. Replaced in
  /// tests.
  static Future<Uint8List?> Function() lostPick = _defaultLostPick;

  static void resetForTests() {
    pickImageBytes = _defaultPickImageBytes;
    tagImage = _defaultTagImage;
    lostPick = _defaultLostPick;
  }

  static Future<Uint8List?> _defaultLostPick() async {
    if (!Platform.isAndroid) return null;
    final LostDataResponse lost = await ImagePicker().retrieveLostData();
    final XFile? file = lost.isEmpty ? null : lost.file;
    return file == null ? null : await file.readAsBytes();
  }

  static Future<Uint8List?> _defaultPickImageBytes() async {
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 92);
    return file == null ? null : await file.readAsBytes();
  }

  static Future<TaggerResult> _defaultTagImage(Uint8List bytes) => ImageTaggerHandler.instance.tag(bytes);

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final Map<RecommenderWorld, RecommenderReport?> reports = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    for (final RecommenderWorld world in RecommenderWorld.values) {
      reports[world] = await RecommenderHandler.maybe?.report(world);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _reset(RecommenderWorld world) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget the ${world.name} model?'),
        content: const Text('Every logged interaction and every learned weight of this world is deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RecommenderHandler.maybe?.reset(world);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          SettingsToggle(
            key: const ValueKey('ai-recommendations-toggle'),
            value: settingsHandler.aiRecommendations,
            onChanged: (bool v) {
              setState(() => settingsHandler.aiRecommendations = v);
              settingsHandler.saveSettings(restate: false);
            },
            title: 'AI recommendations',
            subtitle: const Text(
              'The on-device model orders and seeds every recommendation surface: both For You feeds, '
              'the Suggested strip, the doujin Recommended strip. Off = the classic ordering.',
            ),
            leadingIcon: const Icon(Symbols.auto_awesome_rounded),
          ),
          SettingsToggle(
            key: const ValueKey('ai-learning-toggle'),
            value: settingsHandler.aiLearning,
            onChanged: (bool v) {
              setState(() => settingsHandler.aiLearning = v);
              settingsHandler.saveSettings(restate: false);
            },
            title: 'AI learning',
            subtitle: const Text(
              'The model keeps learning from what you view, read, favourite, collect, search and skip. '
              'Independent of the switch above: it can learn while the classic ordering is shown, '
              'and a frozen model keeps recommending.',
            ),
            leadingIcon: const Icon(Symbols.school_rounded),
          ),
          if (!settingsHandler.dbEnabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'The database is off: nothing can be learned until it is enabled (Settings → Database).',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          for (final RecommenderWorld world in RecommenderWorld.values) _reportCard(context, world),
          _EncoderSection(onChanged: _load),
          const _LookSection(),
          const _TaggerSection(),
          const _BoardsSection(),
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, RecommenderWorld world) {
    final theme = Theme.of(context);
    final RecommenderReport? r = reports[world];
    final bool learned = r != null && r.updates > 0;
    final String title = world == RecommenderWorld.booru ? 'Booru model' : 'Doujin model';
    return Card(
      key: ValueKey('recommender-report-${world.name}'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForYouPage(world: world))),
                  icon: const Icon(Symbols.auto_awesome_rounded, size: 18),
                  label: const Text('For You'),
                ),
                if (learned)
                  IconButton(
                    tooltip: 'Forget everything learned',
                    icon: const Icon(Symbols.delete_sweep_rounded),
                    onPressed: () => _reset(world),
                  ),
              ],
            ),
            if (loading)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (!learned)
              Text(
                'Nothing learned yet. ${world == RecommenderWorld.booru ? 'View, favourite or search some posts' : 'Read, favourite or search some galleries'} and it starts here.',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              )
            else ...[
              Text(
                '${r.events} interactions · ${r.updates} learning steps'
                '${r.lastUpdate == null ? '' : ' · last ${DateFormat('dd MMM HH:mm').format(r.lastUpdate!)}'}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              if (r.tasteCount > 0)
                Text(
                  'encoder: ${r.tasteCount} liked ${r.tasteCount == 1 ? 'item' : 'items'} shaped the taste centroid',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              const SizedBox(height: 10),
              _featureList(context, world, 'Likes', r.liked, theme.colorScheme.primary),
              const SizedBox(height: 8),
              _featureList(context, world, 'Dislikes', r.disliked, theme.colorScheme.error),
              const SizedBox(height: 6),
              Text('Tap a tag to ask for more of it, less of it, or to forget it.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _featureList(BuildContext context, RecommenderWorld world, String label, List<({String name, double weight})> rows, Color color) {
    return _FeatureList(label: label, rows: rows, color: color, world: world, onChanged: _load);
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.label, required this.rows, required this.color, required this.world, required this.onChanged});

  final String label;
  final List<({String name, double weight})> rows;
  final Color color;
  final RecommenderWorld world;
  final Future<void> Function() onChanged;

  /// r75: a tapped tag can be asked for more, for less, or forgotten.
  Future<void> _actions(BuildContext context, String name) async {
    final String? how = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(ItemFeatures.describe(name), style: const TextStyle(fontWeight: FontWeight.w700))),
            ListTile(key: const ValueKey('feature-more'), leading: const Icon(Symbols.thumb_up_rounded), title: const Text('More of this'), onTap: () => Navigator.pop(context, 'more')),
            ListTile(key: const ValueKey('feature-less'), leading: const Icon(Symbols.thumb_down_rounded), title: const Text('Less of this'), onTap: () => Navigator.pop(context, 'less')),
            ListTile(key: const ValueKey('feature-forget'), leading: const Icon(Symbols.delete_rounded), title: const Text('Forget it'), onTap: () => Navigator.pop(context, 'forget')),
          ],
        ),
      ),
    );
    if (how == null) return;
    await RecommenderHandler.instance.adjust(world, name, how: how);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return Text('$label: none yet', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final row in rows)
              ActionChip(
                key: ValueKey('feature-${row.name}'),
                label: Text(ItemFeatures.describe(row.name), style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: color.withValues(alpha: 0.4)),
                onPressed: () => _actions(context, row.name),
              ),
          ],
        ),
      ],
    );
  }
}

/// r34: the downloadable sentence encoder — which one, its state, the
/// download and the switch that lets its vectors into the learner.
class _EncoderSection extends StatefulWidget {
  const _EncoderSection({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  State<_EncoderSection> createState() => _EncoderSectionState();
}

class _EncoderSectionState extends State<_EncoderSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;

  @override
  void initState() {
    super.initState();
    final String current = settings.encoderModel.trim();
    if (EncoderPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = EncoderPreset.english.id;
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(EncoderStatus s) {
    switch (s.state) {
      case EncoderState.none:
        return 'No encoder downloaded. The learner reads tags alone.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case EncoderState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case EncoderState.ready:
        return 'Ready: ${s.repo} · ${s.dim} dimensions · ${_mb(s.bytes)} MB'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case EncoderState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(EncoderHandler encoder) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await encoder.download(setting);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Encoder download failed', style: TextStyle(fontSize: 18)),
        content: Text(encoder.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EncoderHandler? encoder = EncoderHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Downloaded encoder', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "A small sentence model from Hugging Face (ONNX) that reads each item's title and tags into a vector. "
            'Its components become features of the learner above, so two things that were never seen together but read alike '
            'can be liked alike. The model itself never learns — it understands language; the learner learns you.',
            style: muted,
          ),
          if (encoder == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The encoder is not available in this build.'))
          else
            ValueListenableBuilder<EncoderStatus>(
              valueListenable: encoder.status,
              builder: (context, status, _) {
                final bool downloading = status.state == EncoderState.downloading;
                final bool ready = status.state == EncoderState.ready;
                final EncoderPreset? preset = EncoderPreset.byId(choice);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('encoder-status'),
                      style: TextStyle(color: status.state == EncoderState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('encoder-cancel'), onPressed: encoder.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final EncoderPreset p in EncoderPreset.values)
                          ChoiceChip(
                            key: ValueKey('encoder-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('encoder-preset-custom'),
                          label: const Text('Custom repo'),
                          selected: choice == 'custom',
                          onSelected: downloading ? null : (_) => setState(() => choice = 'custom'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (preset != null)
                      Text(preset.description, style: muted)
                    else
                      TextField(
                        key: const ValueKey('encoder-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model — needs onnx/model_quantized.onnx, vocab.txt (WordPiece), tokenizer_config.json, config.json',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('encoder-download'),
                          onPressed: downloading || chosenSetting.isEmpty ? null : () => _download(encoder),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(ready && settings.encoderModel == chosenSetting ? 'Download again' : 'Download'),
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('encoder-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await encoder.delete();
                                    await widget.onChanged();
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                    Text('Models come from huggingface.co; download over Wi-Fi.', style: muted),
                    SettingsToggle(
                      key: const ValueKey('ai-encoder-toggle'),
                      value: settings.aiEncoder,
                      onChanged: (bool v) {
                        setState(() => settings.aiEncoder = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the encoder',
                      subtitle: Text(
                        ready
                            ? 'Its vectors join the features the learner sees. Off = the downloaded model is kept but not read.'
                            : 'Takes effect once an encoder is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.psychology_rounded),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// r75: the downloadable looks model — which one, its state, the download
/// and the switch.
class _LookSection extends StatefulWidget {
  const _LookSection();

  @override
  State<_LookSection> createState() => _LookSectionState();
}

class _LookSectionState extends State<_LookSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;

  @override
  void initState() {
    super.initState();
    final String current = settings.lookModel.trim();
    if (LookPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = LookPreset.s0.id;
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(LookStatus s) {
    switch (s.state) {
      case LookState.none:
        return 'No looks model downloaded. Posts are ordered by their tags alone.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case LookState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case LookState.ready:
        return 'Ready: ${s.repo} · ${_mb(s.bytes)} MB · ${s.inputSize} px'
            '${s.dim > 0 ? ' · ${s.dim} numbers' : ''}'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case LookState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(LookModelHandler look) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await look.download(setting);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Looks model download failed', style: TextStyle(fontSize: 18)),
        content: Text(look.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LookModelHandler? look = LookModelHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Looks model', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A small model from Hugging Face (MobileCLIP, ONNX) that turns a picture, or a sentence, into numbers, so pictures that look alike sit close together. '
            '"Posts like this" and boards order their results by it, and For You learns from what the pictures look like, not only from their tags. Everything runs on the phone.',
            style: muted,
          ),
          if (look == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The looks model is not available in this build.'))
          else
            ValueListenableBuilder<LookStatus>(
              valueListenable: look.status,
              builder: (context, status, _) {
                final bool downloading = status.state == LookState.downloading;
                final bool ready = status.state == LookState.ready;
                final LookPreset? preset = LookPreset.byId(choice);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('look-status'),
                      style: TextStyle(color: status.state == LookState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('look-cancel'), onPressed: look.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final LookPreset p in LookPreset.values)
                          ChoiceChip(
                            key: ValueKey('look-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('look-preset-custom'),
                          label: const Text('Custom repo'),
                          selected: choice == 'custom',
                          onSelected: downloading ? null : (_) => setState(() => choice = 'custom'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (preset != null)
                      Text(preset.description, style: muted)
                    else
                      TextField(
                        key: const ValueKey('look-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model — a CLIP export with onnx/vision_model_quantized.onnx, onnx/text_model_quantized.onnx, tokenizer.json',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('look-download'),
                          onPressed: downloading || chosenSetting.isEmpty ? null : () => _download(look),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(ready && settings.lookModel == chosenSetting ? 'Download again' : 'Download'),
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('look-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await look.delete();
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                    Text('Models come from huggingface.co; download over Wi-Fi. Thumbnails are read once and remembered.', style: muted),
                    SettingsToggle(
                      key: const ValueKey('ai-look-toggle'),
                      value: settings.aiLook,
                      onChanged: (bool v) {
                        setState(() => settings.aiLook = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the looks model',
                      subtitle: Text(
                        ready
                            ? 'Boards, Posts like this and For You read pictures with it. Off = the downloaded model is kept but not read.'
                            : 'Takes effect once a model is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.visibility_rounded),
                    ),
                    // r76: frames from the playing video.
                    SettingsToggle(
                      key: const ValueKey('look-video-frames-toggle'),
                      value: settings.videoFrames,
                      onChanged: (bool v) {
                        setState(() => settings.videoFrames = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Read frames from playing videos',
                      subtitle: const Text(
                        'While a video plays in the media_kit player, a few pictures of what is on screen are read, and the video is judged by them instead of its preview picture: For You, Posts like this, boards and tagging your reactions. Off = the preview picture, as before.',
                      ),
                      leadingIcon: const Icon(Symbols.movie_rounded),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// r74: the downloadable image tagger — which one, its state, the download,
/// Try it on a picture, and the two switches.
class _TaggerSection extends StatefulWidget {
  const _TaggerSection();

  @override
  State<_TaggerSection> createState() => _TaggerSectionState();
}

class _TaggerSectionState extends State<_TaggerSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;
  TaggerResult? tried;
  String tryError = '';

  /// r77: a neutral note (nothing came back from the picker - a cancel looks
  /// the same), not an error.
  String tryNote = '';
  bool trying = false;

  @override
  void initState() {
    super.initState();
    final String current = settings.imageTaggerModel.trim();
    if (TaggerPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = TaggerPreset.wdVit.id;
    }
    unawaited(_recoverLostPick());
  }

  /// r77: a Try it whose picture came back after Android had ended the app
  /// is finished now instead of being lost without a word.
  Future<void> _recoverLostPick() async {
    Uint8List? bytes;
    try {
      bytes = await RecommendationsPage.lostPick();
    } catch (_) {
      return;
    }
    if (bytes == null || !mounted) return;
    Logger.Inst().log('tagger: Try it - a picture picked before the app was restarted came back (${bytes.length ~/ 1024} KB)', 'RecommendationsPage', '_recoverLostPick', LogTypes.booruHandlerInfo);
    await _readPicked(bytes);
  }

  Future<void> _readPicked(Uint8List bytes) async {
    if (trying) return;
    setState(() {
      trying = true;
      tryError = '';
      tryNote = '';
      tried = null;
    });
    try {
      final TaggerResult? r = await RecommendationsPage.tagImage?.call(bytes);
      if (mounted) setState(() => tried = r);
    } catch (e) {
      Logger.Inst().log('tagger: Try it failed: $e', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      if (mounted) setState(() => tryError = 'Could not read the picture: $e');
    } finally {
      if (mounted) setState(() => trying = false);
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(TaggerStatus s) {
    switch (s.state) {
      case TaggerState.none:
        return 'No image tagger downloaded. Boards read a reference image through SauceNAO only.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case TaggerState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case TaggerState.ready:
        return 'Ready: ${s.repo} · ${s.tagCount} tags · ${s.inputSize} px · ${_mb(s.bytes)} MB'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case TaggerState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(ImageTaggerHandler tagger) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await tagger.download(setting);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Image tagger download failed', style: TextStyle(fontSize: 18)),
        content: Text(tagger.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _tryIt() async {
    if (trying) return;
    setState(() {
      trying = true;
      tryError = '';
      tryNote = '';
      tried = null;
    });
    try {
      // r77: how long the picker was open tells an instant automatic
      // cancel from a person who cancelled.
      final Stopwatch open = Stopwatch()..start();
      final Uint8List? bytes = await RecommendationsPage.pickImageBytes?.call();
      final String openFor = '${(open.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, ${PhotoPicker.systemPickerOn ? "Android's photo picker" : 'the default picker'}';
      if (bytes == null) {
        // r77: said, not swallowed - on 19 Sep the phone showed nothing and
        // logged nothing.
        Logger.Inst().log('tagger: Try it - no picture came back from the picker (open $openFor)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
        if (mounted) setState(() => tryNote = 'No picture came back from the picker.');
        return;
      }
      Logger.Inst().log('tagger: Try it on a picture of ${bytes.length ~/ 1024} KB (picker open $openFor)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      final TaggerResult? r = await RecommendationsPage.tagImage?.call(bytes);
      if (mounted) setState(() => tried = r);
    } catch (e) {
      Logger.Inst().log('tagger: Try it failed: $e', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      if (mounted) setState(() => tryError = 'Could not read the picture: $e');
    } finally {
      if (mounted) setState(() => trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ImageTaggerHandler? tagger = ImageTaggerHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image tagger', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A booru tagger from Hugging Face (ONNX) that reads tags straight from the pixels, on the phone: general tags, characters and a rating in the danbooru spelling. '
            "A board's reference image is read with it (no SauceNAO key needed), and, with the switch below, so is the thumbnail of a post you react to.",
            style: muted,
          ),
          if (tagger == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The image tagger is not available in this build.'))
          else
            ValueListenableBuilder<TaggerStatus>(
              valueListenable: tagger.status,
              builder: (context, status, _) {
                final bool downloading = status.state == TaggerState.downloading;
                final bool ready = status.state == TaggerState.ready;
                final TaggerPreset? preset = TaggerPreset.byId(choice);
                final TaggerResult? r = tried;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('tagger-status'),
                      style: TextStyle(color: status.state == TaggerState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('tagger-cancel'), onPressed: tagger.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final TaggerPreset p in TaggerPreset.values)
                          ChoiceChip(
                            key: ValueKey('tagger-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('tagger-preset-custom'),
                          label: const Text('Custom repo'),
                          selected: choice == 'custom',
                          onSelected: downloading ? null : (_) => setState(() => choice = 'custom'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (preset != null)
                      Text(preset.description, style: muted)
                    else
                      TextField(
                        key: const ValueKey('tagger-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model — needs model.onnx (one picture in, one score per tag out) and selected_tags.csv',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('tagger-download'),
                          onPressed: downloading || chosenSetting.isEmpty ? null : () => _download(tagger),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(ready && settings.imageTaggerModel == chosenSetting ? 'Download again' : 'Download'),
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('tagger-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await tagger.delete();
                                    if (mounted) setState(() => tried = null);
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                        OutlinedButton.icon(
                          key: const ValueKey('tagger-try'),
                          onPressed: ready && !trying ? _tryIt : null,
                          icon: const Icon(Symbols.image_search_rounded),
                          label: Text(trying ? 'Reading…' : 'Try it on a picture'),
                        ),
                      ],
                    ),
                    Text('Models come from huggingface.co; download over Wi-Fi. The model is opened on first use and closed after two idle minutes.', style: muted),
                    if (tryError.isNotEmpty || tryNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tryError.isNotEmpty ? tryError : tryNote,
                          key: const ValueKey('tagger-try-message'),
                          style: tryError.isNotEmpty ? TextStyle(color: theme.colorScheme.error) : muted,
                        ),
                      ),
                    if (r != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${r.count} tags in ${r.totalMs} ms (decode ${r.decodeMs} ms, model ${r.modelMs} ms, ${r.provider}) · rating ${r.rating} ${(r.ratingConfidence * 100).round()}%',
                        key: const ValueKey('tagger-try-result'),
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final PixelTag p in r.all)
                            Chip(
                              avatar: p.character ? const Icon(Symbols.person_rounded, size: 16) : null,
                              label: Text('${p.tag} ${(p.confidence * 100).round()}%'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    SettingsToggle(
                      key: const ValueKey('ai-tagger-toggle'),
                      value: settings.aiImageTagger,
                      onChanged: (bool v) {
                        setState(() => settings.aiImageTagger = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the image tagger',
                      subtitle: Text(
                        ready ? 'Boards read their reference image with it. Off = the downloaded model is kept but not read.' : 'Takes effect once a tagger is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.image_search_rounded),
                    ),
                    SettingsToggle(
                      key: const ValueKey('tagger-reactions-toggle'),
                      value: settings.taggerOnReactions,
                      onChanged: (bool v) {
                        setState(() => settings.taggerOnReactions = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Tag reactions with the picture',
                      subtitle: const Text(
                        "A favourite, a snatch, a collection, a finished video or Not interested on a booru post also reads its thumbnail (for a video, the preview frame the site chose), about a second each in the background. The tags join the site's tags for the learner. It does not change how a disliked post shares the blame between its tags.",
                      ),
                      leadingIcon: const Icon(Symbols.thumbs_up_down_rounded),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Boards (r73): the SauceNAO key the reference-image search runs on.
class _BoardsSection extends StatefulWidget {
  const _BoardsSection();

  @override
  State<_BoardsSection> createState() => _BoardsSectionState();
}

class _BoardsSectionState extends State<_BoardsSection> {
  final BoardsHandler store = BoardsHandler.instance;
  late final TextEditingController key;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    key = TextEditingController(text: store.sauceNaoApiKey);
    store.load().then((_) {
      if (mounted && key.text.isEmpty && store.sauceNaoApiKey.isNotEmpty) setState(() => key.text = store.sauceNaoApiKey);
    });
  }

  @override
  void dispose() {
    // A key pasted and left at once must not be lost with the timer.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(store.setSauceNaoApiKey(key.text));
    }
    key.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => store.setSauceNaoApiKey(value));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boards', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'A board\'s reference image is looked up on SauceNAO, which needs your own API key (free: saucenao.com → Register → API). Without a key, image boards fall back to e621\'s own search and to the description.',
              style: muted,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('saucenao-key'),
              controller: key,
              decoration: const InputDecoration(labelText: 'SauceNAO API key', isDense: true),
              onChanged: _changed,
            ),
          ],
        ),
      ),
    );
  }
}
