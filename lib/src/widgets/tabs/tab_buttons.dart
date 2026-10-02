import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/add_new_tab_dialog.dart';
import 'package:lolisnatcher/src/widgets/dialogs/page_number_dialog.dart';
import 'package:lolisnatcher/src/widgets/history/history.dart';

class TabButtons extends StatelessWidget {
  const TabButtons(
    this.withArrows,
    this.alignment, {
    super.key,
  });

  final bool withArrows;
  final WrapAlignment? alignment;

  Future<dynamic> showHistory(BuildContext context) {
    return SettingsPageOpen(
      context: context,
      page: (_) => const HistoryList(),
    ).open();
  }

  Future<void> showLongTapAddDialog(BuildContext context) async {
    await ServiceHandler.vibrate();
    await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      page: (_) => const AddNewTabDialog(),
    ).open();
  }

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;

    final Color iconColor = Theme.of(context).colorScheme.secondary;

    return Obx(() {
      if (searchHandler.tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      // Prev tab
      final Widget leftArrow = IconButton(
        icon: const Icon(Symbols.arrow_upward_rounded),
        color: iconColor,
        onPressed: () {
          // switch to the prev tab, loop if reached the first
          if ((searchHandler.currentIndex - 1) < 0) {
            searchHandler.changeTabIndex(searchHandler.total - 1, byUser: true);
          } else {
            searchHandler.changeTabIndex(searchHandler.currentIndex - 1, byUser: true);
          }
        },
      );

      // Next tab
      final Widget rightArrow = IconButton(
        icon: const Icon(Symbols.arrow_downward_rounded),
        color: iconColor,
        onPressed: () {
          // switch to the next tab, loop if reached the last
          if ((searchHandler.currentIndex + 1) > (searchHandler.total - 1)) {
            searchHandler.changeTabIndex(0, byUser: true);
          } else {
            searchHandler.changeTabIndex(searchHandler.currentIndex + 1, byUser: true);
          }
        },
      );

      // Remove current tab
      final Widget removeButton = IconButton(
        icon: const Icon(Symbols.remove_circle_rounded),
        color: iconColor,
        // Remove selected searchtab from list and apply nearest to search bar
        onPressed: searchHandler.removeTabAt,
      );

      // Add new tab
      // Tap and long-press live on the SAME widget on purpose. This used to be
      // a GestureDetector wrapped around an IconButton, and the long-press
      // never reached the picker: IconButton builds its own InkResponse, whose
      // tap recognizer is the innermost entry in the gesture arena, so the
      // ancestor detector lost the contest under real touch input. InkResponse
      // handles both gestures itself, so there is no arena to lose.
      final Widget addButton = InkResponse(
        onTap: () {
          final String defaultText = searchHandler.currentBooru.defTags?.isNotEmpty == true
              ? searchHandler.currentBooru.defTags!
              : SettingsHandler.instance.defTags;
          // add new tab to the list end and switch to it
          searchHandler.searchTextController.text = defaultText;
          searchHandler.addTabByString(defaultText, switchToNew: true);
        },
        onLongPress: () => showLongTapAddDialog(context),
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Symbols.add_circle_rounded,
            color: iconColor,
          ),
        ),
      );

      // Show search history
      final Widget historyButton = IconButton(
        icon: const Icon(Symbols.history_rounded),
        color: iconColor,
        onPressed: () async {
          await showHistory(context);
        },
      );

      // Show page number dialog
      final Widget pageNumberNutton = IconButton(
        icon: const Icon(Symbols.format_list_numbered_rounded),
        color: iconColor,
        onPressed: () {
          SettingsPageOpen(
            context: context,
            asBottomSheet: true,
            page: (_) => const PageNumberDialog(),
          ).open();
        },
      );

      // For thin screens, show buttons in 2 rows
      if (MediaQuery.sizeOf(context).width < 370) {
        return Column(
          children: [
            Wrap(
              alignment: alignment ?? WrapAlignment.spaceEvenly,
              children: [
                if (withArrows) leftArrow,
                removeButton,
                addButton,
                if (withArrows) rightArrow,
              ],
            ),
            Wrap(
              alignment: alignment ?? WrapAlignment.spaceEvenly,
              children: [
                historyButton,
                pageNumberNutton,
              ],
            ),
          ],
        );
      }

      return Wrap(
        alignment: alignment ?? WrapAlignment.spaceEvenly,
        children: [
          if (withArrows) leftArrow,
          removeButton,
          historyButton,
          pageNumberNutton,
          addButton,
          if (withArrows) rightArrow,
        ],
      );
    });
  }
}
