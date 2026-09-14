import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Downloaded model', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'A small text-embedding model from Hugging Face (ONNX) that reads titles and tags for the learner '
              'arrives in the next build; the learner above needs no download and is already at work.',
            ),
          ),
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
