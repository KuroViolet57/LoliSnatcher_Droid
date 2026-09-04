import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/drawer_refresh.dart';
import 'package:lolisnatcher/src/handlers/followed_artists_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/pages/collections_page.dart';
import 'package:lolisnatcher/src/pages/doujin_library_pages.dart';
import 'package:lolisnatcher/src/pages/followed_artists_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/source_settings_page.dart';
import 'package:lolisnatcher/src/pages/settings/tags_filters_page.dart';
import 'package:lolisnatcher/src/widgets/drawers/drawer_row.dart';
import 'package:lolisnatcher/src/widgets/saved_searches/saved_searches_page.dart';

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
  int _followedCount = 0;
  int _historyCount = 0;
  Worker? _tabWorker;

  void _onRefreshRequested() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    // Re-scope the pinned list when the active tab (and so the booru) changes.
    _tabWorker = ever(searchHandler.index, (_) => _load());
    // ...and re-read whenever anything says the drawer content may be stale:
    // the drawer being opened, a page opened from it closing again, or a
    // doujin-store write. These counts come from async DB queries, so they
    // can't observe their source directly.
    DrawerRefresh.tick.addListener(_onRefreshRequested);
  }

  @override
  void dispose() {
    _tabWorker?.dispose();
    DrawerRefresh.tick.removeListener(_onRefreshRequested);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Booru? current = searchHandler.tabs.isNotEmpty ? searchHandler.currentBooru : null;

      // Doujin tabs read ONLY the doujin store — booru pins/counts must never
      // show up here, even global ones.
      if (DoujinDataHandler.isDoujinBooru(current)) {
        final store = DoujinDataHandler.instance..ensureLoaded();
        final pinned = [
          for (final p in store.pinsFor(current))
            PinnedTag(
              id: -1,
              tagName: p.tag,
              pinnedAt: p.addedAt,
              labels: p.booruHost == null ? const ['all doujins'] : const [],
            ),
        ];
        if (mounted) {
          setState(() {
            _pinned = pinned;
            _favCount = store.favourites.length;
            _collectionCount = store.collections.length;
            _followedCount = store.followed.length;
            _historyCount = store.history.length;
          });
        }
        return;
      }

      // Global pins + the ones scoped to the currently active booru only.
      final pinned = current == null
          ? await settingsHandler.dbHandler.getAllPinnedTags()
          : await settingsHandler.dbHandler.getPinnedTags(
              booruType: current.type?.name,
              booruName: current.name,
            );
      // Follows live in the same table but have their own screen — keep them
      // out of the pinned list here.
      pinned.removeWhere(FollowedArtistsHandler.isFollowPin);
      int fav = 0;
      int col = 0;
      int followed = 0;
      try {
        fav = await settingsHandler.dbHandler.searchDBCount('');
      } catch (_) {}
      try {
        col = (await settingsHandler.dbHandler.getCollections()).length;
      } catch (_) {}
      try {
        followed = (await FollowedArtistsHandler.listFollowed()).length;
      } catch (_) {}
      int history = 0;
      try {
        history = await settingsHandler.dbHandler.countViewedPosts('');
      } catch (_) {}
      if (mounted) {
        setState(() {
          _pinned = pinned;
          _favCount = fav;
          _collectionCount = col;
          _followedCount = followed;
          _historyCount = history;
        });
      }
    } catch (_) {}
  }

  void _addTagAndClose(String tag) {
    searchHandler.addTagToSearch(tag);
    widget.toggleDrawer();
  }

  Future<void> _openPage(Widget page) async {
    widget.toggleDrawer();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    // Whatever the user did in there (deleted favourites, pinned a tag)
    // changed what this drawer shows.
    if (mounted) await _load();
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

  // Opens the viewing history as a tab on the virtual History booru — full
  // grid/search/viewer for free, same pattern as the Favourites entry.
  void _openHistory() {
    final Booru history = settingsHandler.ensureHistoryBooru();
    widget.toggleDrawer();
    searchHandler.addTabByString('', customBooru: history, switchToNew: true);
  }

  // Opens the per-booru blacklist of the CURRENTLY ACTIVE booru (the editor
  // page hosts the per-booru blacklist section), not a fixed one.
  void _openCurrentBooruBlacklist() {
    final Booru? current = searchHandler.tabs.isNotEmpty ? searchHandler.currentBooru : null;
    if (current == null) return;
    _openPage(BooruEdit(current));
  }

  Widget _pinnedRow(PinnedTag pt) {
    // The shared tag store is a booru system — a doujin pin must not get a
    // booru's colour for a coinciding tag name.
    final bool isDoujin =
        searchHandler.tabs.isNotEmpty && DoujinDataHandler.isDoujinBooru(searchHandler.currentBooru);
    final Color dot =
        (isDoujin ? null : tagHandler.getTag(pt.tagName).getColour()) ?? const Color(0xFF8A80A0);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _addTagAndClose(pt.tagName),
      // Long-press: add the tag AND run the search right away.
      onLongPress: () {
        ServiceHandler.vibrate();
        searchHandler.addTagToSearch(pt.tagName);
        searchHandler.searchAction(searchHandler.searchTextController.text, null);
        widget.toggleDrawer();
      },
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
            Icon(Symbols.add_rounded, size: 18, color: Theme.of(context).colorScheme.secondary),
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
    String? subtitle,
  }) => DrawerRow(icon: icon, iconColor: iconColor, label: label, onTap: onTap, count: count, subtitle: subtitle);

  Widget _sectionLabel(String text) => DrawerSectionLabel(text);

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
                Icon(Symbols.push_pin_rounded, size: 18, color: theme.colorScheme.secondary),
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
                  icon: const Icon(Symbols.close_rounded),
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
          ..._quickAccessRows(),
        ],
      ),
    );
  }

  List<Widget> _quickAccessRows() {
    final Booru? current = searchHandler.tabs.isNotEmpty ? searchHandler.currentBooru : null;

    // On a doujin tab every entry points at the doujin store's screens; on a
    // booru tab at the booru ones. The two never mix.
    if (DoujinDataHandler.isDoujinBooru(current)) {
      final store = DoujinDataHandler.instance..ensureLoaded();
      final int globalBlacklistCount = SourceSettingsHandler.instance.tagBlacklist(null).length;
      return [
        _quickAccessRow(
          icon: Symbols.block_rounded,
          iconColor: const Color(0xFFE5766B),
          label: 'Doujin blacklist',
          count: globalBlacklistCount > 0 ? '$globalBlacklistCount tags' : null,
          onTap: () => _openPage(const SourceSettingsPage()),
        ),
        _quickAccessRow(
          icon: Symbols.visibility_off_rounded,
          iconColor: const Color(0xFFE5766B),
          label: '${current!.name} blacklist',
          onTap: () => _openPage(SourceSettingsPage(booru: current)),
        ),
        _quickAccessRow(
          icon: Symbols.favorite_rounded,
          iconColor: const Color(0xFFF0708A),
          label: 'Favorites',
          count: _favCount > 0 ? '$_favCount' : null,
          onTap: () => _openPage(DoujinFavouritesListPage(booru: current)),
        ),
        _quickAccessRow(
          icon: Symbols.history_rounded,
          iconColor: const Color(0xFF8FBFD4),
          label: 'History',
          count: _historyCount > 0 ? '$_historyCount' : null,
          onTap: () => _openPage(DoujinHistoryPage(booru: current)),
        ),
        _quickAccessRow(
          icon: Symbols.artist_rounded,
          iconColor: const Color(0xFFB9A0E8),
          label: 'Followed artists',
          count: _followedCount > 0 ? '$_followedCount' : null,
          onTap: () => _openPage(DoujinFollowedPage(booru: current)),
        ),
        _quickAccessRow(
          icon: Symbols.bookmark_rounded,
          iconColor: const Color(0xFFE8C46B),
          label: 'Saved searches',
          count: '${store.savedSearches.length} kept',
          onTap: () => _openPage(DoujinSavedSearchesPage(booru: current)),
        ),
        _quickAccessRow(
          icon: Symbols.folder_rounded,
          iconColor: const Color(0xFF93AECC),
          label: 'Collections',
          count: _collectionCount > 0 ? '$_collectionCount sets' : null,
          onTap: () => _openPage(DoujinCollectionsPage(booru: current)),
        ),
      ];
    }

    return [
      // The way back to kemono's own sidebar, which replaced this drawer on
      // Kemono tabs until its bottom row switched to this one.
      if (current?.type?.isKemono ?? false)
        _quickAccessRow(
          icon: Symbols.swap_horiz_rounded,
          iconColor: const Color(0xFF8FBFD4),
          label: 'Use the kemono sidebar',
          subtitle: 'Artists, posts, favorites, DMs',
          onTap: () {
            settingsHandler.kemonoSidebar.value = true;
            settingsHandler.saveSettings(restate: false);
          },
        ),
      _quickAccessRow(
        icon: Symbols.block_rounded,
        iconColor: const Color(0xFFE5766B),
        label: 'Global blacklist',
        count: '${settingsHandler.hiddenTags.length} tags',
        onTap: () => _openPage(const TagsFiltersPage()),
      ),
      if (current != null)
        _quickAccessRow(
          icon: Symbols.visibility_off_rounded,
          iconColor: const Color(0xFFE5766B),
          label: '${current.name} blacklist',
          onTap: _openCurrentBooruBlacklist,
        ),
      _quickAccessRow(
        icon: Symbols.favorite_rounded,
        iconColor: const Color(0xFFF0708A),
        label: 'Favorites',
        count: _favCount > 0 ? '$_favCount' : null,
        onTap: _openFavourites,
      ),
      _quickAccessRow(
        icon: Symbols.history_rounded,
        iconColor: const Color(0xFF8FBFD4),
        label: 'History',
        count: _historyCount > 0 ? '$_historyCount' : null,
        onTap: _openHistory,
      ),
      _quickAccessRow(
        icon: Symbols.artist_rounded,
        iconColor: const Color(0xFFB9A0E8),
        label: 'Followed artists',
        count: _followedCount > 0 ? '$_followedCount' : null,
        onTap: () => _openPage(const FollowedArtistsPage()),
      ),
      _quickAccessRow(
        icon: Symbols.bookmark_rounded,
        iconColor: const Color(0xFFE8C46B),
        label: 'Saved searches',
        count: '${searchHandler.savedSearches.length} kept',
        onTap: () => _openPage(const SavedSearchesPage()),
      ),
      _quickAccessRow(
        icon: Symbols.folder_rounded,
        iconColor: const Color(0xFF93AECC),
        label: 'Collections',
        count: _collectionCount > 0 ? '$_collectionCount sets' : null,
        onTap: () => _openPage(const CollectionsPage()),
      ),
    ];
  }
}
