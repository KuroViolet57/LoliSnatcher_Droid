import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// The doujin-only library screens: favourites, history, collections,
/// followed artists and saved searches — all reading exclusively from
/// [DoujinDataHandler]. No booru store is ever touched from here.

/// Resolves which doujin booru config an entry belongs to, for reopening it.
Booru? _booruForHost(String host, {Booru? fallback}) {
  for (final b in SettingsHandler.instance.booruList) {
    if (DoujinDataHandler.isDoujinBooru(b) && DoujinDataHandler.hostOf(b) == host) return b;
  }
  if (fallback != null && DoujinDataHandler.isDoujinBooru(fallback)) return fallback;
  for (final b in SettingsHandler.instance.booruList) {
    if (DoujinDataHandler.isDoujinBooru(b)) return b;
  }
  return null;
}

void _openEntry(BuildContext context, DoujinEntry entry, {Booru? fallback}) {
  if (entry.serverId.isEmpty) return;
  final Booru? booru = _booruForHost(entry.booruHost, fallback: fallback);
  if (booru == null) return;
  SearchHandler.instance.addTabByString('id:${entry.serverId}', customBooru: booru, switchToNew: true);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Widget _entryTile(
  BuildContext context,
  DoujinEntry entry, {
  Booru? fallback,
  VoidCallback? onDelete,
}) {
  final tile = ListTile(
    leading: SizedBox(
      width: 42,
      height: 58,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: entry.thumbnailURL.isEmpty
            ? const ColoredBox(color: Colors.black26)
            : Image(
                image: CustomNetworkImage(
                  entry.thumbnailURL,
                  withCache: SettingsHandler.instance.thumbnailCache,
                  cacheFolder: 'thumbnails',
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
              ),
      ),
    ),
    title: Text(
      entry.title.isEmpty ? entry.postURL : entry.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13.5),
    ),
    subtitle: Text(
      '${entry.booruHost} · ${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(entry.addedAt))}',
      style: const TextStyle(fontSize: 11.5),
    ),
    onTap: entry.serverId.isEmpty ? null : () => _openEntry(context, entry, fallback: fallback),
  );
  if (onDelete == null) return tile;
  return Dismissible(
    key: ValueKey('doujin-entry-${entry.postURL}'),
    direction: DismissDirection.endToStart,
    background: Container(
      color: Colors.red.withValues(alpha: 0.7),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Symbols.delete_rounded, color: Colors.white),
    ),
    onDismissed: (_) => onDelete(),
    child: tile,
  );
}

Widget _emptyNote(String text) => Padding(
  padding: const EdgeInsets.all(24),
  child: Center(child: Text(text, textAlign: TextAlign.center)),
);

/// ── Favourites ──
class DoujinFavouritesListPage extends StatelessWidget {
  const DoujinFavouritesListPage({this.booru, super.key});

  final Booru? booru;

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    return Scaffold(
      appBar: AppBar(title: const Text('Doujin favourites')),
      body: Obx(() {
        // touch the map so Obx tracks it
        final int count = store.favourites.length;
        final entries = store.favouritesList();
        if (count == 0) {
          return _emptyNote('No doujin favourites yet — use the heart on a doujin card or detail page.');
        }
        return ListView(
          children: [
            for (final e in entries)
              _entryTile(
                context,
                e,
                fallback: booru,
                onDelete: () {
                  store.favourites.remove(e.postURL);
                  store.save();
                },
              ),
          ],
        );
      }),
    );
  }
}

/// ── History ──
class DoujinHistoryPage extends StatelessWidget {
  const DoujinHistoryPage({this.booru, super.key});

  final Booru? booru;

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doujin history'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Symbols.delete_sweep_rounded),
            onPressed: () async {
              final bool? confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear doujin history?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear')),
                  ],
                ),
              );
              if (confirmed == true) store.clearHistory();
            },
          ),
        ],
      ),
      body: Obx(() {
        if (store.history.isEmpty) {
          return _emptyNote('Doujins you open will show up here.');
        }
        return ListView(
          children: [for (final e in store.history) _entryTile(context, e, fallback: booru)],
        );
      }),
    );
  }
}

/// ── Collections ──
class DoujinCollectionsPage extends StatelessWidget {
  const DoujinCollectionsPage({this.booru, super.key});

  final Booru? booru;

  Future<void> _createCollection(BuildContext context, DoujinDataHandler store) async {
    final controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New doujin collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      store.createCollection(name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    return Scaffold(
      appBar: AppBar(title: const Text('Doujin collections')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createCollection(context, store),
        child: const Icon(Symbols.add_rounded),
      ),
      body: Obx(() {
        if (store.collections.isEmpty) {
          return _emptyNote('No doujin collections yet — the bookmark button files doujins into one.');
        }
        return ListView(
          children: [
            for (final c in store.collections)
              ListTile(
                leading: const Icon(Symbols.folder_rounded, color: Color(0xFF93AECC)),
                title: Text(c.name),
                subtitle: Text('${c.items.length} doujins'),
                trailing: IconButton(
                  tooltip: 'Delete collection',
                  icon: const Icon(Symbols.delete_rounded),
                  onPressed: () async {
                    final bool? confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Delete "${c.name}"?'),
                        content: const Text('The doujins themselves are not affected.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirmed == true) store.deleteCollection(c.id);
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DoujinCollectionDetailPage(collectionId: c.id, booru: booru),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class DoujinCollectionDetailPage extends StatelessWidget {
  const DoujinCollectionDetailPage({required this.collectionId, this.booru, super.key});

  final int collectionId;
  final Booru? booru;

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    return Obx(() {
      // depend on the list so removals rebuild
      store.collections.length;
      final collection = store.collectionById(collectionId);
      return Scaffold(
        appBar: AppBar(title: Text(collection?.name ?? 'Collection')),
        body: collection == null || collection.items.isEmpty
            ? _emptyNote('Nothing in this collection yet.')
            : ListView(
                children: [
                  for (final e in collection.items.reversed)
                    _entryTile(
                      context,
                      e,
                      fallback: booru,
                      onDelete: () {
                        collection.items.removeWhere((x) => x.postURL == e.postURL);
                        store.collections.assignAll(store.collections.toList());
                        store.save();
                      },
                    ),
                ],
              ),
      );
    });
  }
}

/// ── Followed artists ──
class DoujinFollowedPage extends StatelessWidget {
  const DoujinFollowedPage({this.booru, super.key});

  final Booru? booru;

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    return Scaffold(
      appBar: AppBar(title: const Text('Followed doujin artists')),
      body: Obx(() {
        if (store.followed.isEmpty) {
          return _emptyNote('Follow an artist from a doujin tag menu to keep them here.');
        }
        return ListView(
          children: [
            for (final f in store.followed)
              ListTile(
                leading: const Icon(Symbols.artist_rounded, color: Color(0xFFB9A0E8)),
                title: Text(f.tag.replaceAll('_', ' ')),
                subtitle: Text(f.booruHost),
                trailing: IconButton(
                  tooltip: 'Unfollow',
                  icon: const Icon(Symbols.close_rounded),
                  onPressed: () {
                    final Booru? b = _booruForHost(f.booruHost, fallback: booru);
                    store.toggleFollow(f.tag, b);
                  },
                ),
                onTap: () {
                  final Booru? b = _booruForHost(f.booruHost, fallback: booru);
                  if (b == null) return;
                  SearchHandler.instance.addTabByString('artist:"${f.tag}"', customBooru: b, switchToNew: true);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
          ],
        );
      }),
    );
  }
}

/// ── Saved searches ──
class DoujinSavedSearchesPage extends StatefulWidget {
  const DoujinSavedSearchesPage({this.booru, super.key});

  final Booru? booru;

  @override
  State<DoujinSavedSearchesPage> createState() => _DoujinSavedSearchesPageState();
}

class _DoujinSavedSearchesPageState extends State<DoujinSavedSearchesPage> {
  /// null = Global (all sources).
  String? _scope;

  @override
  Widget build(BuildContext context) {
    final store = DoujinDataHandler.instance..ensureLoaded();
    final List<Booru> sources = [
      for (final b in SettingsHandler.instance.booruList)
        if (DoujinDataHandler.isDoujinBooru(b)) b,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Doujin saved searches')),
      body: Column(
        children: [
          // Source scoper: Global shows every doujin saved search, a source
          // chip narrows to that source only.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Global'),
                    selected: _scope == null,
                    onSelected: (_) => setState(() => _scope = null),
                  ),
                ),
                for (final b in sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(b.name ?? DoujinDataHandler.hostOf(b)),
                      selected: _scope == DoujinDataHandler.hostOf(b),
                      onSelected: (_) => setState(() => _scope = DoujinDataHandler.hostOf(b)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Obx(() {
              store.savedSearches.length;
              final entries = store.savedSearchesFor(_scope);
              if (entries.isEmpty) {
                return _emptyNote('No saved searches ${_scope == null ? 'yet' : 'for this source'} — save one from the search bar menu on a doujin tab.');
              }
              return ListView(
                children: [
                  for (final s in entries)
                    Dismissible(
                      key: ValueKey('doujin-saved-search-${s.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red.withValues(alpha: 0.7),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Symbols.delete_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) => store.deleteSavedSearch(s.id),
                      child: ListTile(
                        leading: const Icon(Symbols.bookmark_rounded, color: Color(0xFFE8C46B)),
                        title: Text(s.name.isEmpty ? s.query : s.name),
                        subtitle: Text('${s.query.isEmpty ? '(no tags)' : s.query} · ${s.booruHost}'),
                        onTap: () {
                          final Booru? b = _booruForHost(s.booruHost, fallback: widget.booru);
                          if (b == null) return;
                          SearchHandler.instance.addTabByString(s.query, customBooru: b, switchToNew: true);
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
