import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/pages/collections_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/tags_filters_page.dart';
import 'package:lolisnatcher/src/widgets/history/history.dart';

/// The left ("Pinned tags") sidebar: pinned tags at the top (tap = add to the
/// current search) and a Quick access section at the bottom (blacklists,
/// favourites, saved searches, collections).
class DrawerQuickAccess extends StatefulWidget {
  const DrawerQuickAccess({required this.toggleDrawer, super.key});

  final VoidCallback toggleDrawer;

  @override
  State<DrawerQuickAccess> createState() => _DrawerQuickAccessState();
}

class _DrawerQuickAccessState extends State<DrawerQuickAccess> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  List<PinnedTag> _pinned = [];
  int _favCount = 0;
  int _collectionCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pinned = await settingsHandler.dbHandler.getAllPinnedTags();
      int fav = 0;
      int col = 0;
      try {
        fav = await settingsHandler.dbHandler.searchDBCount('');
      } catch (_) {}
      try {
        col = (await settingsHandler.dbHandler.getCollections()).length;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _pinned = pinned;
          _favCount = fav;
          _collectionCount = col;
        });
      }
    } catch (_) {}
  }

  void _addTagAndClose(String tag) {
    searchHandler.addTagToSearch(tag);
    widget.toggleDrawer();
  }

  void _openPage(Widget page) {
    widget.toggleDrawer();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Booru? _virtual(bool Function(dynamic) test) {
    for (final b in settingsHandler.booruList) {
      final t = b.type;
      if (t != null && test(t)) return b;
    }
    return null;
  }

  void _openFavourites() {
    final fav = _virtual((t) => t.isFavourites);
    if (fav == null) return;
    widget.toggleDrawer();
    searchHandler.addTabByString('', customBooru: fav, switchToNew: true);
  }

  void _openForYouBlacklist() {
    final booru = settingsHandler.ensureForYouBooru();
    _openPage(BooruEdit(booru));
  }

  Widget _pinnedRow(PinnedTag pt) {
    final Color dot = tagHandler.getTag(pt.tagName).getColour() ?? const Color(0xFF8A80A0);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _addTagAndClose(pt.tagName),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pt.tagName.replaceAll('_', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            for (final label in pt.labels.take(2)) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.secondary),
          ],
        ),
      ),
    );
  }

  Widget _quickAccessRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    String? count,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (count != null) ...[
              Text(
                count,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text(
                  'Pinned tags',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.toggleDrawer,
                ),
              ],
            ),
          ),
          // pinned tags (scrolls; pushes quick access to the bottom)
          Expanded(
            child: _pinned.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'No pinned tags yet. Pin a tag from its menu to keep it here.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [for (final pt in _pinned) _pinnedRow(pt)],
                  ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _sectionLabel('QUICK ACCESS'),
          _quickAccessRow(
            icon: Icons.block,
            iconColor: const Color(0xFFE5766B),
            label: 'Global blacklist',
            count: '${settingsHandler.hiddenTags.length} tags',
            onTap: () => _openPage(const TagsFiltersPage()),
          ),
          _quickAccessRow(
            icon: Icons.visibility_off_outlined,
            iconColor: const Color(0xFFE5766B),
            label: 'For You blacklist',
            onTap: _openForYouBlacklist,
          ),
          _quickAccessRow(
            icon: Icons.favorite,
            iconColor: const Color(0xFFF0708A),
            label: 'Favorites',
            count: _favCount > 0 ? '$_favCount' : null,
            onTap: _openFavourites,
          ),
          _quickAccessRow(
            icon: Icons.bookmark_outline,
            iconColor: const Color(0xFFE8C46B),
            label: 'Saved searches',
            count: '${searchHandler.savedSearches.length} kept',
            onTap: () => _openPage(const HistoryList()),
          ),
          _quickAccessRow(
            icon: Icons.folder_outlined,
            iconColor: const Color(0xFF93AECC),
            label: 'Collections',
            count: _collectionCount > 0 ? '$_collectionCount sets' : null,
            onTap: () => _openPage(const CollectionsPage()),
          ),
        ],
      ),
    );
  }
}
