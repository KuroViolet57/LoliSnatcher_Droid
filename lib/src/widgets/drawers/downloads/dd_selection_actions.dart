import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_download_handler.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/pages/doujin_downloads_page.dart';
import 'package:lolisnatcher/src/pages/snatcher_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/collections/add_to_collection_sheet.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';

class DDSelectionActions extends StatelessWidget {
  const DDSelectionActions({
    required this.controller,
    required this.toggleDrawer,
    super.key,
  });

  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;

  @override
  Widget build(BuildContext context) {
    final searchHandler = controller.searchHandler;

    return Obx(() {
      final selected = searchHandler.currentSelected;
      if (selected.isNotEmpty) {
        final int favSelectedCount = selected.where((item) => item.isFavourite.value == true).length;
        final int unfavSelectedCount = selected.where((item) => item.isFavourite.value == false).length;
        final bool hasFavsSelected = favSelectedCount > 0;
        final bool isAllSelectedFavs = selected.length == favSelectedCount;

        final int downloadsSelectedCount = selected.where((item) => item.isSnatched.value == true).length;
        final bool hasDownloadsSelected = downloadsSelectedCount > 0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsButton(
              name: '${context.loc.settings.downloads.snatchSelected} (${selected.length.toFormattedString()})',
              icon: const Icon(Symbols.download_rounded),
              action: () => controller.onStartSnatching(context, false),
              onLongPress: () => controller.onStartSnatching(context, true),
              drawTopBorder: true,
            ),
            if (hasDownloadsSelected)
              SettingsButton(
                name:
                    '${context.loc.settings.downloads.removeSnatchedStatusFromSelected} (${downloadsSelectedCount.toFormattedString()})',
                icon: const Icon(Symbols.file_download_off_rounded),
                action: controller.removeSnatchedStatusFromSelected,
              ),
            if (!isAllSelectedFavs)
              SettingsButton(
                name: '${context.loc.settings.downloads.favouriteSelected} (${unfavSelectedCount.toFormattedString()})',
                icon: const Icon(Symbols.favorite_rounded, color: Colors.red),
                action: controller.favouriteSelected,
              ),
            if (hasFavsSelected)
              SettingsButton(
                name: '${context.loc.settings.downloads.unfavouriteSelected} (${favSelectedCount.toFormattedString()})',
                icon: const Icon(Symbols.favorite_border_rounded),
                action: controller.unfavouriteSelected,
              ),
            if (controller.settingsHandler.dbEnabled)
              SettingsButton(
                name: 'Add to collection (${selected.length.toFormattedString()})',
                icon: const Icon(Symbols.collections_bookmark_rounded),
                action: () {
                  toggleDrawer();
                  showAddToCollectionSheet(context, [...selected]);
                },
              ),
            SettingsButton(
              name: context.loc.settings.downloads.clearSelected,
              icon: const Icon(Symbols.delete_forever_rounded),
              action: () => searchHandler.currentTab.selected.clear(),
            ),
          ],
        );
      } else {
        return SettingsButton(
          name: context.loc.selectAll,
          icon: const Icon(Symbols.select_all_rounded),
          action: () => searchHandler.currentTab.selected.addAll(
            searchHandler.currentFetched,
          ),
          drawTopBorder: true,
        );
      }
    });
  }
}

class DDNavigationButtons extends StatelessWidget {
  const DDNavigationButtons({
    required this.controller,
    required this.toggleDrawer,
    super.key,
  });

  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;

  @override
  Widget build(BuildContext context) {
    final searchHandler = controller.searchHandler;
    final settingsHandler = controller.settingsHandler;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsButton(
          name: context.loc.snatcher.title,
          icon: const Icon(Symbols.download_rounded),
          page: () => const SnatcherPage(),
        ),
        SettingsButton(
          name: context.loc.snatcher.snatchingHistory,
          icon: const Icon(Symbols.file_download_rounded),
          action: () {
            final Booru? downloadsBooru = settingsHandler.booruList.firstWhereOrNull(
              (booru) => booru.type?.isDownloads == true,
            );
            final bool hasDownloads = downloadsBooru != null;

            if (!hasDownloads) {
              return;
            }

            searchHandler.addTabByString(
              '',
              switchToNew: true,
              customBooru: downloadsBooru,
            );
            toggleDrawer();
          },
        ),
        // Doujins are folders of pages, not media rows: their own surface,
        // read from the download folder.
        SettingsButton(
          name: 'Doujin downloads',
          subtitle: const Text('Saved books, read from the download folder'),
          icon: const Icon(Symbols.menu_book_rounded),
          page: () => const DoujinDownloadsPage(),
        ),
        SettingsButton(
          name: 'Check downloads against disk',
          subtitle: const Text('Finds media entries whose file is no longer there'),
          icon: const Icon(Symbols.fact_check_rounded),
          action: () => _auditDownloads(context),
        ),
      ],
    );
  }

  Future<void> _auditDownloads(BuildContext context) async {
    FlashElements.showSnackbar(
      context: context,
      title: const Text('Checking downloads against the folder…'),
      duration: const Duration(seconds: 2),
      sideColor: Colors.blue,
    );
    final reconciler = DownloadsReconciler.instance;
    final result = await reconciler.audit(customConditions: DownloadsHandler.doujinExclusionConditions());
    final String root = await DoujinDownloadHandler.instance.describeRoot();
    if (!context.mounted) return;
    if (result.problem != null) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Could not check the download folder'),
        content: Text(result.problem!),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
      return;
    }
    if (result.missing == 0) {
      FlashElements.showSnackbar(
        context: context,
        title: Text('All ${result.scanned} media downloads have a file'),
        content: Text('Checked under $root${result.unknown > 0 ? '\n${result.unknown} could not be checked (no matching booru config).' : ''}'),
        duration: const Duration(seconds: 4),
        sideColor: Colors.green,
      );
      return;
    }
    final bool? forget = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${result.missing} of ${result.scanned} downloads have no file'),
        content: Text(
          'Their files are not under\n$root\n\n'
          'Forgetting removes them from the Downloads list; the posts are not touched and can be saved again.'
          '${result.unknown > 0 ? '\n\n${result.unknown} entries could not be checked (no matching booru config) and are left alone.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Forget ${result.missing}')),
        ],
      ),
    );
    if (forget != true || !context.mounted) return;
    final int changed = await reconciler.forgetMissing();
    if (!context.mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text('Forgot $changed entries'),
      content: const Text('Reload the Downloads tab to see the list without them.'),
      duration: const Duration(seconds: 3),
      sideColor: Colors.green,
    );
  }
}
