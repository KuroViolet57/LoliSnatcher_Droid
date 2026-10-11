import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/features/collections/ui/add_to_collection_sheet.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/features/downloads/logic/dd_controller.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';

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
