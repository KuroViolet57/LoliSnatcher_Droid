part of '../main_search_query_editor_page.dart';

/// r37: a doujin source's browse filters as checkmarks. A single-choice
/// group replaces its term (tapping the chosen one clears it); a
/// multiple-choice group toggles; the source's default reads as checked
/// when the query names nothing.
class DoujinFiltersBlock extends StatelessWidget {
  const DoujinFiltersBlock({
    required this.spec,
    required this.query,
    required this.onQueryChanged,
    super.key,
  });

  final DoujinFilterSpec spec;
  final String query;
  final void Function(String query) onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return SearchSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Symbols.tune_rounded, size: 20),
                const SizedBox(width: 8),
                Text('Filters', style: context.theme.textTheme.bodyLarge),
              ],
            ),
          ),
          for (final DoujinFilterGroup g in spec.groups) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(g.label, style: context.theme.textTheme.labelLarge),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final DoujinFilterOption o in g.options) _chip(context, g, o)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, DoujinFilterGroup g, DoujinFilterOption o) {
    final List<String> chosen = DoujinFilters.selected(query, g.key, divider: g.divider);
    final bool selected = chosen.isEmpty
        ? (g.multi && g.defaultValues.isNotEmpty ? g.defaultValues.contains(o.value) : o.value == g.defaultValue)
        : chosen.contains(o.value);
    return FilterChip(
      // r45: the site default is '(default)', not 'none': danbooru's parent: and
      // child: groups also have a real `none` value, and the duplicate key
      // crashed the whole Filters card.
      key: ValueKey('doujin-filter-${g.key}-${o.value.isEmpty ? '(default)' : o.value}'),
      label: Text(o.label),
      selected: selected,
      showCheckmark: true,
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        final List<String> next;
        if (g.multi) {
          // Nothing chosen means the defaults: a tap starts from them.
          next = [...(chosen.isEmpty ? g.defaultValues : chosen)];
          if (!next.remove(o.value)) next.add(o.value);
        } else {
          next = chosen.contains(o.value) ? const [] : [o.value];
        }
        onQueryChanged(DoujinFilters.apply(query, g.key, next, divider: g.divider));
      },
    );
  }
}
