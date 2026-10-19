import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/settings/ui/settings_page.dart';
import 'package:lolisnatcher/features/downloads/ui/snatcher_page.dart';
import 'package:lolisnatcher/core/platform/get_perms.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/kaomoji/kaomoji.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/app/shells/desktop/desktop_image_listener.dart';
import 'package:lolisnatcher/core/ui/resizable_split_view.dart';
import 'package:lolisnatcher/features/viewer/ui/info/tag_view.dart';
import 'package:lolisnatcher/features/feed/ui/media_previews.dart';
import 'package:lolisnatcher/features/feed/ui/search/main_search_bar.dart';
import 'package:lolisnatcher/features/tabs/ui/widgets/tab_booru_selector.dart';
import 'package:lolisnatcher/features/tabs/ui/tab_buttons.dart';
import 'package:lolisnatcher/features/tabs/ui/tab_selector.dart';

class DesktopHome extends StatelessWidget {
  const DesktopHome({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchHandler searchHandler = SearchHandler.instance;
    final SnatchHandler snatchHandler = SnatchHandler.instance;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 60,
        actions: [
          // Obx(() {
          //   if (settingsHandler.booruList.isNotEmpty && searchHandler.tabs.isNotEmpty) {
          //     return const DesktopTabs();
          //   } else {
          //     return const SizedBox.shrink();
          //   }
          // }),
          Obx(() {
            if (settingsHandler.booruList.isNotEmpty && searchHandler.tabs.isNotEmpty) {
              // return const SizedBox(width: 5);
              return const Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(width: 15),
                    MainSearchBarWithActions('desktop'),
                    Expanded(flex: 1, child: TabBooruSelector()),
                    Expanded(flex: 2, child: TabSelector()),
                    Expanded(flex: 2, child: TabButtons(false, WrapAlignment.start)),
                  ],
                ),
              );
            } else {
              return const SizedBox.shrink();
            }
          }),
          Obx(() {
            if (settingsHandler.booruList.isNotEmpty && searchHandler.tabs.isNotEmpty) {
              return SettingsButton(
                name: context.loc.desktopHome.snatcher,
                icon: const Icon(Symbols.download_rounded),
                iconOnly: true,
                page: () => const SnatcherPage(),
              );
            } else {
              return const SizedBox.shrink();
            }
          }),
          Obx(() {
            if (settingsHandler.booruList.isEmpty || searchHandler.tabs.isEmpty) {
              return Center(child: Text(context.loc.desktopHome.addBoorusInSettings));
            } else {
              return const SizedBox.shrink();
            }
          }),
          SettingsButton(
            name: context.loc.desktopHome.settings,
            icon: const Icon(Symbols.settings_rounded),
            iconOnly: true,
            page: () => const SettingsPage(),
          ),
          Obx(() {
            if (searchHandler.tabs.isNotEmpty && searchHandler.currentSelected.isNotEmpty) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SettingsButton(
                    name: context.loc.desktopHome.save,
                    icon: const Icon(Symbols.save_rounded),
                    iconOnly: true,
                    action: () async {
                      if (!await setPermissions()) return;

                      // call a function to save the currently viewed image when the save button is pressed
                      if (searchHandler.currentSelected.isNotEmpty) {
                        snatchHandler.queue(
                          searchHandler.currentSelected,
                          searchHandler.currentBooru,
                          settingsHandler.snatchCooldown,
                          false,
                        );
                        if (settingsHandler.favouriteOnSnatch) {
                          await searchHandler.currentTab.updateFavForMultipleItems(
                            searchHandler.currentSelected,
                            newValue: true,
                            skipSnatching: true,
                          );
                        }
                        searchHandler.currentTab.selected.clear();
                      } else {
                        FlashElements.showSnackbar(
                          context: context,
                          title: Text(context.loc.desktopHome.noItemsSelected, style: const TextStyle(fontSize: 20)),
                          overrideLeadingIconWidget: const Kaomoji(
                            category: KaomojiCategory.dissatisfaction,
                            style: TextStyle(fontSize: 18),
                          ),
                        );
                      }
                    },
                  ),
                  if (searchHandler.currentSelected.isNotEmpty)
                    Positioned(
                      right: 2,
                      bottom: 5,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Text(
                              '${searchHandler.currentSelected.length}',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            } else {
              return const SizedBox.shrink();
            }
          }),
        ],
      ),
      body: Center(
        child: ResizableSplitView(
          firstChild: ResizableSplitView(
            firstChild: const MediaPreviews(),
            secondChild: const DesktopTagListener(),
            startRatio: 0.66,
            minRatio: 0.33,
            maxRatio: 1,
            direction: SplitDirection.vertical,
            onRatioChange: (double newRatio) {
              // TODO save to settings, but debounce the saving to file
            },
          ),
          secondChild: Obx(
            () => searchHandler.tabs.isEmpty
                ? const SizedBox.shrink()
                : DesktopImageListener(
                    searchHandler.currentTab,
                  ),
          ),
          startRatio: 0.33,
          minRatio: 0.2,
          maxRatio: 0.8,
          onRatioChange: (double newRatio) {
            // TODO save to settings, but debounce the saving to file
          },
        ),
      ),
    );
  }
}

class DesktopTagListener extends StatelessWidget {
  const DesktopTagListener({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;

    return Obx(() {
      if (searchHandler.tabs.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
        ),
        child: Obx(
          () {
            final item = searchHandler.currentTab.itemWithKey(ViewerHandler.instance.current.value?.key);

            if (item == null) {
              return const SizedBox.shrink();
            }

            return TagView(
              item: item,
              handler: searchHandler.currentBooruHandler,
            );
          },
        ),
      );
    });
  }
}
