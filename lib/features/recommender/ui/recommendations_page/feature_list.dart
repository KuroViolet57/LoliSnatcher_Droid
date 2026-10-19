part of '../recommendations_page.dart';

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
