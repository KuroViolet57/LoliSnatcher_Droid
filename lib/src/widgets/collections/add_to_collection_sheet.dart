import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/collection_info.dart';
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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddToCollectionSheet(items: items),
  );
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
    }
    await _load();
    SettingsHandler.instance.ensureCollectionsBooru();
  }

  Future<void> _addBatch(CollectionInfo c) async {
    final int added = await dbHandler.addItemsToCollection(c.id, widget.items);
    SettingsHandler.instance.ensureCollectionsBooru();
    if (!mounted) return;
    Navigator.of(context).pop();
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Added $added to "${c.name}"', style: const TextStyle(fontSize: 18)),
      leadingIcon: Icons.playlist_add_check,
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
        leadingIcon: Icons.playlist_add_check,
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
                  const Icon(Icons.collections_bookmark_outlined),
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
                          leading: const Icon(Icons.add, color: Colors.green),
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
                              secondary: const Icon(Icons.folder_outlined),
                              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${c.itemCount}'),
                              onChanged: (_) => _toggleSingle(c),
                            )
                          else
                            ListTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${c.itemCount}'),
                              trailing: const Icon(Icons.add),
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
