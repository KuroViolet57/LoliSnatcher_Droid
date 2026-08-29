import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/floating_preview_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

/// The doujin item context menu — a CENTERED popup (not a bottom sheet),
/// opened by long-pressing a doujin card anywhere (feed, strips, floating
/// windows). Ordering is fixed by design:
///   Open in new tab · Preview · Read now · Open in group · Favourite ·
///   Bookmark · Save all pages · Copy link
/// (no "Open detail page" — tapping the card does that already).
Future<void> showDoujinItemMenu(
  BuildContext context, {
  required SearchTab tab,
  required int index,
}) async {
  if (index < 0 || index >= tab.booruHandler.filteredFetched.length) return;
  final BooruItem item = tab.booruHandler.filteredFetched[index];
  final Booru booru = tab.booruHandler.booru;
  final String title =
      (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => item.postURL);
  // The heart label must reflect the DOUJIN store, never a stale flag.
  item.isFavourite.value = DoujinDataHandler.instance.isFavourite(item);

  await showDialog(
    context: context,
    builder: (dialogContext) {
      Widget row({
        required Key key,
        required IconData icon,
        required String label,
        required VoidCallback onTap,
        Color? iconColor,
        double? iconFill,
      }) {
        return ListTile(
          key: key,
          dense: true,
          leading: Icon(icon, color: iconColor, fill: iconFill),
          title: Text(label),
          onTap: onTap,
        );
      }

      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
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
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                const Divider(height: 1),
                row(
                  key: const Key('doujin-menu-new-tab'),
                  icon: Symbols.tab_new_right_rounded,
                  label: 'Open in new tab',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    final String placement = SourceSettingsHandler.instance.tabPlacement(booru);
                    SearchHandler.instance.addTabByString(
                      'id:${item.serverId}',
                      customBooru: booru,
                      addMode: placement == 'next' ? TabAddMode.next : TabAddMode.end,
                      switchToNew: false,
                    );
                    FlashElements.showSnackbar(
                      context: context,
                      title: const Text('Added new tab', style: TextStyle(fontSize: 18)),
                      content: Text(title, style: const TextStyle(fontSize: 14)),
                      duration: const Duration(seconds: 2),
                      sideColor: Colors.green,
                    );
                  },
                ),
                row(
                  key: const Key('doujin-menu-preview'),
                  icon: Symbols.picture_in_picture_rounded,
                  label: 'Preview',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    FloatingPreviewHandler.instance.openDoujinPreview(item: item, booru: booru);
                  },
                ),
                row(
                  key: const Key('doujin-menu-read'),
                  icon: Symbols.menu_book_rounded,
                  label: 'Read now',
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    if (!ReaderHandler.instance.hasBook(item)) {
                      await tab.booruHandler.loadItem(item: item, withCapcthaCheck: true);
                    }
                    if (!context.mounted) return;
                    await openDoujinReader(context, item: item, booru: booru);
                  },
                ),
                row(
                  key: const Key('doujin-menu-group'),
                  icon: Symbols.folder_open_rounded,
                  label: 'Open in group',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    showOpenTagInGroupSheet(context, 'id:${item.serverId}', booru);
                  },
                ),
                row(
                  key: const Key('doujin-menu-favourite'),
                  icon: Symbols.favorite_rounded,
                  iconColor: item.isFavourite.value == true ? const Color(0xFFF0708A) : null,
                  iconFill: item.isFavourite.value == true ? 1 : 0,
                  label: item.isFavourite.value == true ? 'Unfavourite' : 'Favourite',
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    // The ONE doujin favourite path: doujin store + account sync.
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
                row(
                  key: const Key('doujin-menu-bookmark'),
                  icon: BookmarkHandler.instance.isBookmarked(item)
                      ? Symbols.bookmark_rounded
                      : Symbols.bookmark_add_rounded,
                  iconFill: BookmarkHandler.instance.isBookmarked(item) ? 1 : 0,
                  label: BookmarkHandler.instance.isBookmarked(item) ? 'Remove bookmark' : 'Bookmark',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    BookmarkHandler.instance.toggle(item, booru);
                  },
                ),
                row(
                  key: const Key('doujin-menu-save'),
                  icon: Symbols.download_rounded,
                  label: 'Save all pages',
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
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
                row(
                  key: const Key('doujin-menu-copy'),
                  icon: Symbols.content_copy_rounded,
                  label: 'Copy link',
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    await Clipboard.setData(ClipboardData(text: item.postURL));
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
