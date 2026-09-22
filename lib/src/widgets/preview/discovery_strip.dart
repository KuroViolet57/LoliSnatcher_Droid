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
///
/// Styling follows the Flow blueprint: small-caps section labels, compact
/// ring-bordered avatars and pill tags — no boxed panel around it.
class DiscoveryStrip extends StatelessWidget {
  const DiscoveryStrip({required this.tab, super.key});

  final SearchTab tab;

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _search(String query) {
    final handler = SearchHandler.instance;
    handler.searchTextController.text = query;
    handler.searchAction(query, null);
  }

  Widget _creatorTile(BuildContext context, CreatorInfo c) {
    final theme = Theme.of(context);
    final String? avatar = c.avatarUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _search(c.searchQuery),
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline, width: 2),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                child: Text(
                  c.displayName.isNotEmpty ? c.displayName.substring(0, 1).toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagPill(BuildContext context, String tag) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _search(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          tag.replaceAll('-', ' ').replaceAll('_', ' '),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFC9BFE0),
          ),
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (creators.isNotEmpty) ...[
                _sectionLabel(context, 'CREATORS'),
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: creators.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _creatorTile(context, creators[i]),
                  ),
                ),
              ],
              if (tags.isNotEmpty) ...[
                _sectionLabel(context, 'SIMILAR TAGS'),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 7),
                    itemBuilder: (context, i) => _tagPill(context, tags[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
