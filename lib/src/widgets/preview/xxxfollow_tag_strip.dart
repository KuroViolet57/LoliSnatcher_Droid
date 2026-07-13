import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/boorus/xxxfollow_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

/// A header strip shown above xxxfollow results: the creators that appear in
/// the current tag, and similar tags — mirroring the site's own tag page.
///
/// The data comes from the last `post/search/tag` response the handler parsed
/// (`lastCreators` / `lastRelatedTags`). It rebuilds whenever the tab's results
/// change (i.e. after each search) by listening to `filteredFetched`.
class XXXFollowTagStrip extends StatelessWidget {
  const XXXFollowTagStrip({required this.tab, super.key});

  final SearchTab tab;

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Row(
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
        ],
      ),
    );
  }

  void _search(String query) {
    final handler = SearchHandler.instance;
    handler.searchTextController.text = query;
    handler.searchAction(query, null);
  }

  Widget _creatorTile(BuildContext context, XXXFollowCreator c) {
    final String? avatar = c.avatarUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _search(c.username),
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
    if (handler is! XXXFollowHandler) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: handler.filteredFetched,
      builder: (context, _, _) {
        final creators = handler.lastCreators;
        final tags = handler.lastRelatedTags;
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
                _sectionLabel(context, 'Creators in this tag'),
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
                        label: Text(t.replaceAll('-', ' ')),
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
