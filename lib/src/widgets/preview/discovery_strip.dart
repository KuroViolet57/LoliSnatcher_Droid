import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/creator_info.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

/// A header strip shown above search results: the creators behind the current
/// results and related/similar tags — mirroring a site's own tag page.
///
/// It's booru-agnostic: it renders whatever the active handler put in
/// `relatedCreators` / `relatedTags` (empty for handlers that don't populate
/// them, in which case the strip is invisible). It rebuilds whenever the tab's
/// results change by listening to `filteredFetched`.
class DiscoveryStrip extends StatelessWidget {
  const DiscoveryStrip({required this.tab, super.key});

  final SearchTab tab;

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Row(
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              // onSurface reads clearly in any theme (colorScheme.primary was
              // nearly invisible on some dark themes).
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2))),
        ],
      ),
    );
  }

  void _search(String query) {
    final handler = SearchHandler.instance;
    handler.searchTextController.text = query;
    handler.searchAction(query, null);
  }

  Widget _creatorTile(BuildContext context, CreatorInfo c) {
    final String? avatar = c.avatarUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _search(c.searchQuery),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
              child: Text(
                c.displayName.isNotEmpty ? c.displayName.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = tab.booruHandler;

    return ValueListenableBuilder(
      valueListenable: handler.filteredFetched,
      builder: (context, _, _) {
        final creators = handler.relatedCreators;
        final tags = handler.relatedTags;
        if (creators.isEmpty && tags.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (creators.isNotEmpty) ...[
                _sectionLabel(context, 'Creators in these results'),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: creators.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _creatorTile(context, creators[i]),
                  ),
                ),
              ],
              if (creators.isNotEmpty && tags.isNotEmpty) const SizedBox(height: 10),
              if (tags.isNotEmpty) ...[
                _sectionLabel(context, 'Similar tags'),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final t in tags)
                      ActionChip(
                        label: Text(t.replaceAll('-', ' ').replaceAll('_', ' ')),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _search(t),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
