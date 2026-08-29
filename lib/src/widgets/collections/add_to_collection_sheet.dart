import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/collection_info.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Bottom sheet to add/remove posts to/from collections.
///
/// For a single post it shows a checklist reflecting current membership
/// (toggling adds/removes). For multiple posts it adds the whole batch to
/// whichever collection is tapped. A "New collection" row creates one inline.
Future<void> showAddToCollectionSheet(
  BuildContext context,
  List<BooruItem> items,
) async {
  if (items.isEmpty) return;
  // Per-ITEM routing: doujin items go to DOUJIN collections (doujinData.json),
  // booru items to the booru Collection tables — regardless of which tab or
  // viewer they came from (merge tabs / floating previews included). A mixed
  // batch shows both sheets, one after the other.
  final List<BooruItem> doujinItems = [
    for (final i in items)
      if (DoujinDataHandler.isDoujinItem(i)) i,
  ];
  final List<BooruItem> booruItems = [
    for (final i in items)
      if (!DoujinDataHandler.isDoujinItem(i)) i,
  ];
  if (doujinItems.isNotEmpty) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddToDoujinCollectionSheet(
        items: doujinItems,
        booru: DoujinDataHandler.doujinBooruForItem(doujinItems.first),
      ),
    );
  }
  if (booruItems.isNotEmpty && context.mounted) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddToCollectionSheet(items: booruItems),
    );
  }
}

/// The doujin twin of the sheet below, backed by [DoujinDataHandler] only.
class _AddToDoujinCollectionSheet extends StatefulWidget {
  const _AddToDoujinCollectionSheet({required this.items, required this.booru});

  final List<BooruItem> items;
  final Booru? booru;

  @override
  State<_AddToDoujinCollectionSheet> createState() => _AddToDoujinCollectionSheetState();
}

class _AddToDoujinCollectionSheetState extends State<_AddToDoujinCollectionSheet> {
  final store = DoujinDataHandler.instance..ensureLoaded();

  bool get isSingle => widget.items.length == 1;

  Future<void> _createNew() async {
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
    if (name == null || name.trim().isEmpty) return;
    final collection = store.createCollection(name.trim());
    _addAllTo(collection);
  }

  void _addAllTo(DoujinCollection collection) {
    for (final item in widget.items) {
      store.addToCollection(collection, item, widget.booru);
    }
    if (mounted) Navigator.of(context).pop();
    FlashElements.showSnackbar(
      title: Text('Added to "${collection.name}"'),
      duration: const Duration(seconds: 2),
      sideColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              isSingle ? 'Add to doujin collection' : 'Add ${widget.items.length} doujins to collection',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            leading: const Icon(Symbols.create_new_folder_rounded),
            title: const Text('New collection'),
            onTap: _createNew,
          ),
          for (final c in store.collections)
            ListTile(
              leading: Icon(
                isSingle && store.collectionContains(c, widget.items.first)
                    ? Symbols.check_circle_rounded
                    : Symbols.folder_rounded,
              ),
              title: Text(c.name),
              subtitle: Text('${c.items.length} doujins'),
              onTap: () {
                if (isSingle && store.collectionContains(c, widget.items.first)) {
                  // toggle off for a single item
                  store.removeFromCollection(c, widget.items.first);
                  Navigator.of(context).pop();
                  return;
                }
                _addAllTo(c);
              },
            ),
        ],
      ),
    );
  }
}

class _AddToCollectionSheet extends StatefulWidget {
  const _AddToCollectionSheet({required this.items});

  final List<BooruItem> items;

  @override
  State<_AddToCollectionSheet> createState() => _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends State<_AddToCollectionSheet> {
  final dbHandler = SettingsHandler.instance.dbHandler;

  List<CollectionInfo> collections = [];
  Set<int> memberOf = {};
  bool loading = true;

  bool get isSingle => widget.items.length == 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    collections = await dbHandler.getCollections();
    if (isSingle) {
      memberOf = await dbHandler.getCollectionsForItem(widget.items.first.postURL);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _toggleSingle(CollectionInfo c) async {
    final bool isMember = memberOf.contains(c.id);
    if (isMember) {
      await dbHandler.removeItemsFromCollection(c.id, [widget.items.first.postURL]);
    } else {
      await dbHandler.addItemsToCollection(c.id, widget.items);
      InterestsHandler.instance.onItemsCollected(widget.items);
    }
    await _load();
    SettingsHandler.instance.ensureCollectionsBooru();
  }

  Future<void> _addBatch(CollectionInfo c) async {
    final int added = await dbHandler.addItemsToCollection(c.id, widget.items);
    InterestsHandler.instance.onItemsCollected(widget.items);
    SettingsHandler.instance.ensureCollectionsBooru();
    if (!mounted) return;
    Navigator.of(context).pop();
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Added $added to "${c.name}"', style: const TextStyle(fontSize: 18)),
      leadingIcon: Symbols.playlist_add_check_rounded,
      sideColor: Colors.green,
    );
  }

  Future<void> _createCollection() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(title: 'New collection'),
    );
    if (name == null || name.trim().isEmpty) return;
    final int? id = await dbHandler.createCollection(name);
    if (id == null) return;
    final int added = await dbHandler.addItemsToCollection(id, widget.items);
    InterestsHandler.instance.onItemsCollected(widget.items);
    SettingsHandler.instance.ensureCollectionsBooru();
    if (!mounted) return;
    if (isSingle) {
      await _load();
    } else {
      Navigator.of(context).pop();
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: Text('Added $added to "$name"', style: const TextStyle(fontSize: 18)),
        leadingIcon: Symbols.playlist_add_check_rounded,
        sideColor: Colors.green,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  const Icon(Symbols.collections_bookmark_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isSingle ? 'Add to collection' : 'Add ${widget.items.length} to collection',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: loading
                  ? const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Symbols.add_rounded, color: Colors.green),
                          title: const Text('New collection'),
                          onTap: _createCollection,
                        ),
                        if (collections.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No collections yet — create one above.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          ),
                        for (final c in collections)
                          if (isSingle)
                            CheckboxListTile(
                              value: memberOf.contains(c.id),
                              secondary: const Icon(Symbols.folder_rounded),
                              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${c.itemCount}'),
                              onChanged: (_) => _toggleSingle(c),
                            )
                          else
                            ListTile(
                              leading: const Icon(Symbols.folder_rounded),
                              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${c.itemCount}'),
                              trailing: const Icon(Symbols.add_rounded),
                              onTap: () => _addBatch(c),
                            ),
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small text-entry dialog reused for creating / renaming collections.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Collection name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Public wrapper so other screens (e.g. the Collections page) can reuse the
/// same name dialog for create/rename.
Future<String?> showCollectionNameDialog(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initial: initial),
  );
}
