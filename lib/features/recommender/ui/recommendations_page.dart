import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/features/recommender/logic/model_tasks.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/platform/photo_picker.dart';
import 'package:lolisnatcher/core/platform/picker_watch.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/encoder_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/image_tagger_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/look_model_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/item_features.dart';
import 'package:lolisnatcher/features/recommender/logic/recommender_handler.dart';
import 'package:lolisnatcher/features/boards/logic/boards_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/recommender/ui/foryou_page.dart';
import 'package:lolisnatcher/features/recommender/ui/models_page.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';

part 'recommendations_page/feature_list.dart';
part 'recommendations_page/encoder_section.dart';
part 'recommendations_page/look_section.dart';
part 'recommendations_page/tagger_section.dart';
part 'recommendations_page/boards_section.dart';

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
          // r80: every job of every model, its threads, and all models off.
          // r88: each model's download and switches live on its own page there.
          SettingsButton(
            key: const ValueKey('models-page'),
            name: 'Models',
            subtitle: Text(
              settingsHandler.aiModelsOff
                  ? 'All models are off.'
                  : 'The text model, the looks model and the image tagger: download, what they do, what they run on.',
            ),
            icon: const Icon(Symbols.tune_rounded),
            action: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsPage()));
              if (mounted) setState(() {});
            },
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
