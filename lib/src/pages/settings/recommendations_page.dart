import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Settings → Recommendations (r33): the two switches of the on-device
/// recommender, what each world's model has learned, and a way to forget it.
class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

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
              _featureList(context, 'Likes', r.liked, theme.colorScheme.primary),
              const SizedBox(height: 8),
              _featureList(context, 'Dislikes', r.disliked, theme.colorScheme.error),
            ],
          ],
        ),
      ),
    );
  }

  Widget _featureList(BuildContext context, String label, List<({String name, double weight})> rows, Color color) {
    return _FeatureList(label: label, rows: rows, color: color);
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.label, required this.rows, required this.color});

  final String label;
  final List<({String name, double weight})> rows;
  final Color color;

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
              Chip(
                label: Text(ItemFeatures.describe(row.name), style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: color.withValues(alpha: 0.4)),
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
