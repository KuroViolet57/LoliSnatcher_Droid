import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/doujin_download_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/local_image_provider.dart';

/// Saved doujins, read from DISK: one entry per book folder (cover, title,
/// page count, source), opened in the reader against the local files. The
/// booru Downloads tab lists media only; doujins never appear there.
class DoujinDownloadsPage extends StatefulWidget {
  const DoujinDownloadsPage({super.key});

  @override
  State<DoujinDownloadsPage> createState() => _DoujinDownloadsPageState();
}

class _DoujinDownloadsPageState extends State<DoujinDownloadsPage> {
  final store = DoujinDownloadHandler.instance;
  late Future<List<DoujinDownloadEntry>> _entries = store.scan();
  String _root = '';

  @override
  void initState() {
    super.initState();
    store.describeRoot().then((r) {
      if (mounted) setState(() => _root = r);
    });
  }

  void _refresh() => setState(() => _entries = store.scan());

  Future<void> _open(DoujinDownloadEntry entry) async {
    await openLocalDoujinReader(
      context,
      pages: entry.toPageItems(),
      booru: store.booruFor(entry),
      galleryId: entry.serverId.isNotEmpty ? entry.serverId : entry.location,
      title: entry.title,
    );
  }

  Future<void> _delete(DoujinDownloadEntry entry) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this doujin?'),
        content: Text('Removes the folder and its ${entry.pageCount} pages from this device.\n\n${entry.title}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final bool ok = await store.delete(entry);
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(ok ? 'Deleted' : 'Could not delete the folder'),
      duration: const Duration(seconds: 2),
      sideColor: ok ? Colors.green : Colors.red,
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doujin downloads'),
        actions: [
          IconButton(
            tooltip: 'Rescan the download folder',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<DoujinDownloadEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No saved doujins.\n\nBooks saved from a detail page, a card menu or the reader land in\n$_root${DoujinDownloadHandler.folderName}/<source>_<id>/',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  'Read from ${_root.isEmpty ? 'the download folder' : _root}',
                  style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final e in entries) _tile(context, e),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, DoujinDownloadEntry entry) {
    final theme = Theme.of(context);
    final ImageProvider? cover = entry.cover.isEmpty ? null : localImageProviderFor(entry.cover);
    return ListTile(
      key: ValueKey('doujin-download-${entry.location}'),
      leading: SizedBox(
        width: 42,
        height: 58,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: cover == null
              ? const ColoredBox(color: Colors.black26)
              : Image(
                  image: cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                ),
        ),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        '${entry.pageCount} page${entry.pageCount == 1 ? '' : 's'} · ${entry.sourceName}'
        '${entry.isLoose ? ' · not grouped by book' : ''}',
        style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: entry.isLoose
          ? null
          : IconButton(
              tooltip: 'Delete from device',
              icon: const Icon(Symbols.delete_rounded, size: 20),
              onPressed: () => _delete(entry),
            ),
      onTap: () => _open(entry),
    );
  }
}
