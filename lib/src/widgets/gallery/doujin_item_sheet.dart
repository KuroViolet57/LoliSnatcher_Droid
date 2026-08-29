import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

/// Long-press context menu for a doujin card in the Related / Recommended
/// strips (and anywhere else a strip card wants one): open the detail page,
/// read straight away, favourite, bookmark, save, copy the link.
Future<void> showDoujinItemSheet(
  BuildContext context, {
  required SearchTab tab,
  required int index,
}) async {
  if (index < 0 || index >= tab.booruHandler.filteredFetched.length) return;
  final BooruItem item = tab.booruHandler.filteredFetched[index];
  final Booru booru = tab.booruHandler.booru;
  final String title =
      (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => item.postURL);

  await showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SizedBox(
                width: 42,
                height: 58,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Thumbnail(item: item, booru: booru, isStandalone: true, useHero: false),
                ),
              ),
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.info_rounded),
              title: const Text('Open detail page'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DoujinDetailPage(tab: tab, index: index)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Symbols.menu_book_rounded),
              title: const Text('Read now'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                // Straight to the reader — load the book first if needed.
                if (!ReaderHandler.instance.hasBook(item)) {
                  await tab.booruHandler.loadItem(item: item, withCapcthaCheck: true);
                }
                if (!context.mounted) return;
                await openDoujinReader(context, item: item, booru: booru);
              },
            ),
            ListTile(
              leading: Icon(
                Symbols.favorite_rounded,
                fill: item.isFavourite.value == true ? 1 : 0,
                color: item.isFavourite.value == true ? const Color(0xFFF0708A) : null,
              ),
              title: Text(item.isFavourite.value == true ? 'Unfavourite' : 'Favourite'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                // Doujin favourites: doujin store + account sync, one path.
                final result = await DoujinDataHandler.instance.toggleFavouriteSynced(item, tab.booruHandler);
                if (result.syncAttempted && context.mounted) {
                  FlashElements.showSnackbar(
                    context: context,
                    title: Text(result.message ?? (result.syncOk ? 'Synced' : 'Sync failed')),
                    duration: const Duration(seconds: 2),
                    sideColor: result.syncOk ? Colors.green : Colors.red,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                BookmarkHandler.instance.isBookmarked(item) ? Symbols.bookmark_rounded : Symbols.bookmark_add_rounded,
                fill: BookmarkHandler.instance.isBookmarked(item) ? 1 : 0,
              ),
              title: Text(BookmarkHandler.instance.isBookmarked(item) ? 'Remove bookmark' : 'Bookmark (local)'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                BookmarkHandler.instance.toggle(item, booru);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.download_rounded),
              title: const Text('Save all pages'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (!ReaderHandler.instance.hasBook(item)) {
                  await tab.booruHandler.loadItem(item: item, withCapcthaCheck: true);
                }
                final pages = ReaderHandler.instance.pagesFor(item);
                if (pages == null || pages.isEmpty) return;
                SnatchHandler.instance.queue(pages, booru, SettingsHandler.instance.snatchCooldown, false);
                if (!context.mounted) return;
                FlashElements.showSnackbar(
                  context: context,
                  title: Text('Saving all ${pages.length} pages...'),
                  duration: const Duration(seconds: 2),
                  sideColor: Colors.green,
                );
              },
            ),
            ListTile(
              leading: const Icon(Symbols.content_copy_rounded),
              title: const Text('Copy link'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: item.postURL));
              },
            ),
          ],
        ),
      );
    },
  );
}
