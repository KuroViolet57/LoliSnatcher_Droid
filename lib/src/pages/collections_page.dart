import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/collection_info.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/collections/add_to_collection_sheet.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Browses saved-post collections (albums). Each card opens the collection as
/// a tab powered by `CollectionsHandler` (so the full grid + viewer + search
/// + multi-select pipeline is reused). Create / rename / delete live here.
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  final dbHandler = SettingsHandler.instance.dbHandler;
  final searchHandler = SearchHandler.instance;

  List<CollectionInfo> collections = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    collections = await dbHandler.getCollections();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _create() async {
    final String? name = await showCollectionNameDialog(context, title: 'New collection');
    if (name == null || name.trim().isEmpty) return;
    await dbHandler.createCollection(name);
    SettingsHandler.instance.ensureCollectionsBooru();
    await _load();
  }

  Future<void> _rename(CollectionInfo c) async {
    final String? name = await showCollectionNameDialog(context, title: 'Rename collection', initial: c.name);
    if (name == null || name.trim().isEmpty) return;
    await dbHandler.renameCollection(c.id, name);
    await _load();
  }

  Future<void> _delete(CollectionInfo c) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: Text(
          c.itemCount > 0
              ? 'This removes the collection and unlinks its ${c.itemCount} posts. '
                    'The posts stay in any other collection / favourites.'
              : 'This removes the empty collection.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await dbHandler.deleteCollection(c.id);
    await _load();
  }

  void _open(CollectionInfo c) {
    if (c.itemCount == 0) {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: const Text('This collection is empty', style: TextStyle(fontSize: 18)),
        leadingIcon: Icons.info_outline,
        sideColor: Colors.blue,
      );
      return;
    }
    final booru = SettingsHandler.instance.ensureCollectionsBooru();
    searchHandler.addTabByString(
      'collection:${c.id}',
      customBooru: booru,
      switchToNew: true,
    );
    // Back out to the main grid so the freshly-opened tab is shown.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showCardMenu(CollectionInfo c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(context).pop();
                _open(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(context).pop();
                _rename(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.of(context).pop();
                _delete(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New collection',
            onPressed: _create,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : collections.isEmpty
          ? _buildEmpty(context)
          : RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: collections.length,
                itemBuilder: (context, i) => _CollectionCard(
                  info: collections[i],
                  onTap: () => _open(collections[i]),
                  onLongPress: () => _showCardMenu(collections[i]),
                  onMenu: () => _showCardMenu(collections[i]),
                ),
              ),
            ),
      floatingActionButton: collections.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_bookmark_outlined, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No collections yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Group posts into albums. Long-press a post (or use the ⋮ / info panel) to add it to a collection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create collection'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.info,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
  });

  final CollectionInfo info;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(context),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                        onPressed: onMenu,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${info.itemCount} ${info.itemCount == 1 ? 'post' : 'posts'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final theme = Theme.of(context);
    final Widget fallback = ColoredBox(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Center(
        child: Text(
          info.name.isNotEmpty ? info.name.characters.first.toUpperCase() : '?',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
    final String? url = info.coverThumbnailURL;
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: {'User-Agent': Tools.browserUserAgent},
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: theme.colorScheme.surfaceContainerHigh,
          child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      },
    );
  }
}
