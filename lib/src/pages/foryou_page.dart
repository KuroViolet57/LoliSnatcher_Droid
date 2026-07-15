import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// Entry point for the "For You" recommender. Lets the user open the profile-
/// based feed, seed a feed from a typed tag, inspect / prune their taste
/// profile, and toggle behaviour tracking.
class ForYouPage extends StatefulWidget {
  const ForYouPage({super.key});

  @override
  State<ForYouPage> createState() => _ForYouPageState();
}

class _ForYouPageState extends State<ForYouPage> {
  final searchHandler = SearchHandler.instance;
  final settingsHandler = SettingsHandler.instance;

  final TextEditingController seedController = TextEditingController();
  List<MapEntry<String, double>> profile = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    seedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    profile = await InterestsHandler.instance.topTags(limit: 60);
    if (mounted) setState(() => loading = false);
  }

  void _openFeed({String seedQuery = ''}) {
    final booru = settingsHandler.ensureForYouBooru();
    searchHandler.addTabByString(seedQuery, customBooru: booru, switchToNew: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openSeeded() {
    final String tag = seedController.text.trim().toLowerCase().replaceAll(' ', '_');
    if (tag.isEmpty) {
      _openFeed();
      return;
    }
    _openFeed(seedQuery: 'seed:$tag');
  }

  Future<void> _resetProfile() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset taste profile?'),
        content: const Text('Forgets every tracked interest signal. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await InterestsHandler.instance.resetProfile();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double maxScore = profile.isEmpty ? 1 : profile.first.value.clamp(0.0001, double.infinity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('For You'),
        actions: [
          if (profile.isNotEmpty)
            IconButton(
              tooltip: 'Reset profile',
              icon: const Icon(Symbols.delete_sweep_rounded),
              onPressed: _resetProfile,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Symbols.auto_awesome_rounded, color: theme.colorScheme.secondary),
                      const SizedBox(width: 10),
                      Text(
                        'Recommendations',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pulls posts from your boorus based on what you tend to view, favourite, '
                    'collect and search. Everything is computed on-device.',
                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openFeed(),
                      icon: const Icon(Symbols.auto_awesome_rounded),
                      label: const Text('Open my For You feed'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Or recommend around a tag', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: seedController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _openSeeded(),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'e.g. burnice_white',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _openSeeded, child: const Text('Go')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Your taste profile', style: theme.textTheme.titleMedium),
              const Spacer(),
              Switch(
                value: settingsHandler.enableInterestTracking,
                onChanged: (v) {
                  settingsHandler.enableInterestTracking = v;
                  settingsHandler.saveSettings(restate: false);
                  setState(() {});
                },
              ),
            ],
          ),
          Text(
            settingsHandler.enableInterestTracking
                ? 'Tracking is on. Tap ✕ to forget a tag.'
                : 'Tracking is paused — the profile below is frozen.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (profile.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No signals yet. Browse, favourite, collect or preview some tags and they will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            )
          else
            ...profile.map((e) => _profileRow(context, e.key, e.value, maxScore)),
        ],
      ),
    );
  }

  Widget _profileRow(BuildContext context, String tag, double score, double maxScore) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tag.replaceAll('_', ' '), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (score / maxScore).clamp(0.02, 1),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Recommend around this',
            icon: const Icon(Symbols.auto_awesome_rounded, size: 18),
            onPressed: () => _openFeed(seedQuery: 'seed:$tag'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Forget',
            icon: const Icon(Symbols.close_rounded, size: 18),
            onPressed: () async {
              await InterestsHandler.instance.removeTag(tag);
              await _load();
            },
          ),
        ],
      ),
    );
  }
}
