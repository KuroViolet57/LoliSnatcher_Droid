import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// The doujin drawer's Favourites area: the LOCAL bookmarks list plus quick
/// entries into the account favourites feed and the app's own favourites.
class DoujinFavouritesPage extends StatefulWidget {
  const DoujinFavouritesPage({required this.booru, super.key});

  final Booru booru;

  @override
  State<DoujinFavouritesPage> createState() => _DoujinFavouritesPageState();
}

class _DoujinFavouritesPageState extends State<DoujinFavouritesPage> {
  final searchHandler = SearchHandler.instance;

  void _openTab(String query) {
    searchHandler.addTabByString(query, customBooru: widget.booru, switchToNew: true);
    // Back to the grid so the new tab is visible.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final List<DoujinBookmark> bookmarks = BookmarkHandler.instance.all();
    final bool hasKey = widget.booru.apiKey?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Doujin favourites')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Symbols.favorite_rounded, color: Color(0xFFF0708A)),
            title: const Text('Account favourites'),
            subtitle: Text(
              hasKey
                  ? 'Your favourites on ${widget.booru.name ?? 'the site'}, as a feed'
                  : 'Needs your API key (Settings → Doujin → source → Account)',
            ),
            enabled: hasKey,
            onTap: () => _openTab('favorites:me'),
          ),
          ListTile(
            leading: const Icon(Symbols.favorite_border_rounded),
            title: const Text('Local favourites'),
            subtitle: const Text("The app's own favourites (every source, incl. doujins)"),
            enabled: SettingsHandler.instance.dbEnabled,
            onTap: () {
              final favourites = SettingsHandler.instance.booruList
                  .where((b) => b.type?.isFavourites ?? false)
                  .toList();
              if (favourites.isEmpty) return;
              searchHandler.addTabByString('', customBooru: favourites.first, switchToNew: true);
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'BOOKMARKS · ${bookmarks.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          if (bookmarks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nothing bookmarked yet — use the bookmark button on a doujin\'s detail page.'),
            ),
          for (final bookmark in bookmarks)
            Dismissible(
              key: ValueKey('bookmark-${bookmark.postURL}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red.withValues(alpha: 0.7),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Symbols.delete_rounded, color: Colors.white),
              ),
              onDismissed: (_) {
                BookmarkHandler.instance.remove(bookmark.postURL);
                setState(() {});
              },
              child: ListTile(
                leading: SizedBox(
                  width: 42,
                  height: 58,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: bookmark.thumbnailURL.isEmpty
                        ? const ColoredBox(color: Colors.black26)
                        : Image(
                            image: CustomNetworkImage(
                              bookmark.thumbnailURL,
                              withCache: SettingsHandler.instance.thumbnailCache,
                              cacheFolder: 'thumbnails',
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                          ),
                  ),
                ),
                title: Text(
                  bookmark.title.isEmpty ? bookmark.postURL : bookmark.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                subtitle: Text(
                  '${bookmark.booruHost} · ${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(bookmark.addedAt))}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                // id:<n> opens the exact gallery as its own tab; the detail
                // page is then one tap on the card.
                onTap: bookmark.serverId.isEmpty ? null : () => _openTab('id:${bookmark.serverId}'),
              ),
            ),
        ],
      ),
    );
  }
}
