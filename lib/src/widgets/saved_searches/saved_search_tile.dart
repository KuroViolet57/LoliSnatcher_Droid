import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/saved_search.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

// Single-row representation of a SavedSearch.
// Tap → open in a new tab (respecting defaultTabAddMode).
// Kebab → menu: open with different booru / rename / delete.
class SavedSearchTile extends StatelessWidget {
  const SavedSearchTile({required this.entry, super.key});

  final SavedSearch entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (entry.booru.isNotEmpty) entry.booru,
      if (entry.secondaryBoorus.isNotEmpty) '+ ${entry.secondaryBoorus.join(", ")}',
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        title: Text(
          entry.displayLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(
                subtitleParts.join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        leading: Icon(Symbols.bookmark_rounded, color: theme.colorScheme.secondary),
        onTap: () => _openDefault(context),
        trailing: PopupMenuButton<_TileAction>(
          icon: const Icon(Symbols.more_vert_rounded),
          onSelected: (action) => _handle(context, action),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _TileAction.openInOther,
              child: ListTile(
                dense: true,
                leading: Icon(Symbols.open_in_new_rounded),
                title: Text('Open in another booru'),
              ),
            ),
            PopupMenuItem(
              value: _TileAction.rename,
              child: ListTile(
                dense: true,
                leading: Icon(Symbols.edit_rounded),
                title: Text('Rename'),
              ),
            ),
            PopupMenuItem(
              value: _TileAction.delete,
              child: ListTile(
                dense: true,
                leading: Icon(Symbols.delete_rounded),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDefault(BuildContext context) {
    SearchHandler.instance.openSavedSearch(entry);
    Navigator.of(context).maybePop();
  }

  Future<void> _handle(BuildContext context, _TileAction action) async {
    switch (action) {
      case _TileAction.openInOther:
        await _openInOther(context);
        break;
      case _TileAction.rename:
        await _rename(context);
        break;
      case _TileAction.delete:
        await _delete(context);
        break;
    }
  }

  Future<void> _openInOther(BuildContext context) async {
    final boorus = SettingsHandler.instance.booruList;
    if (boorus.isEmpty) return;
    final Booru? picked = await showDialog<Booru?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Open with which booru?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(ctx).width,
                height: 52,
                child: SettingsBooruDropdown(
                  value: null,
                  items: boorus,
                  onChanged: (Booru? b) {
                    if (b == null) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.of(ctx).pop(b);
                    });
                  },
                  title: 'Booru',
                  contentPadding: EdgeInsets.zero,
                  titleAsLabel: true,
                  drawBottomBorder: false,
                ),
              ),
              const CancelButton(withIcon: true),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    SearchHandler.instance.openSavedSearch(entry, customBooru: picked);
    if (context.mounted) unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _rename(BuildContext context) async {
    final id = entry.id;
    if (id == null) return;
    final controller = TextEditingController(text: entry.name);
    final String? name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await SearchHandler.instance.renameSavedSearch(id, name.trim());
  }

  Future<void> _delete(BuildContext context) async {
    final id = entry.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved search?'),
        content: Text(entry.displayLabel),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SearchHandler.instance.deleteSavedSearch(id);
  }
}

enum _TileAction { openInOther, rename, delete }
