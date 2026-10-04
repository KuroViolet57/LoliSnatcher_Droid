part of '../booru_edit_page.dart';

/// Inline editor for the per-booru blacklist list. Renders below the
/// "Ignore global blacklist" toggle on the Booru edit page. Entries follow
/// the same e621-style line syntax as the global blacklist.
class _PerBooruBlacklistEditor extends StatelessWidget {
  const _PerBooruBlacklistEditor({
    required this.booruName,
    required this.onChanged,
  });

  final String? booruName;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (booruName == null || booruName!.isEmpty) {
      return const SizedBox.shrink();
    }
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<String> entries = settingsHandler.hiddenTagsForBooru(booruName).toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hidden tag lines for this booru',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.help_rounded),
                tooltip: 'Blacklist syntax',
                onPressed: () => _showHelp(context),
              ),
              IconButton(
                icon: const Icon(Symbols.add_rounded),
                tooltip: 'Add line',
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => TagsFiltersAddDialog(
                      tagFilterType: 'per-booru hidden',
                      onAdd: (String line) {
                        settingsHandler.addTagToBooruHiddenList(booruName!, line);
                      },
                    ),
                  );
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No per-booru lines yet. Tap + to add one, or use "Only on this booru" '
                'when blacklisting a tag from a post.',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...entries.map(
              (String line) => _PerBooruBlacklistRow(
                line: line,
                onRemove: () {
                  settingsHandler.removeTagFromBooruHiddenList(booruName!, line);
                  onChanged();
                },
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Blacklist syntax'),
        content: const SingleChildScrollView(
          child: Text(
            'Each entry is a line. A post on this booru is hidden if any line matches.\n\n'
            'Within a line, tokens are separated by spaces and combined with AND:\n'
            '  male solo  → hides posts with BOTH male AND solo.\n\n'
            'Prefix a token with - to require its absence:\n'
            '  fox -wolf -lion  → fox posts that have NEITHER wolf NOR lion.\n'
            '  -female  → posts WITHOUT the female tag.\n\n'
            'Prefix tokens with ~ for OR:\n'
            '  ~wolf ~lion  → posts that have EITHER wolf OR lion.\n'
            '  male ~wolf ~lion -fox  → male AND (wolf OR lion) AND NO fox.\n\n'
            'Metatags work too:\n'
            '  rating:e  rating:q  rating:s\n'
            '  score:<0   score:>=100   score:50..100\n'
            '  id:1234   width:>2000   filesize:>5mb\n'
            '  username:someone   userid:1234\n\n'
            'Lines starting with # are comments and ignored.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PerBooruBlacklistRow extends StatelessWidget {
  const _PerBooruBlacklistRow({
    required this.line,
    required this.onRemove,
  });

  final String line;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.delete_rounded, size: 20),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
