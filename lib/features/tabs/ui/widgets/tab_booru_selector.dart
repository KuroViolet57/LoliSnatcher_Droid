import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/booru_selector_item.dart';
import 'package:lolisnatcher/core/ui/loli_dropdown.dart';

class TabBooruSelector extends StatelessWidget {
  const TabBooruSelector({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchHandler searchHandler = SearchHandler.instance;

    return Obx(() {
      // no boorus
      if (settingsHandler.booruList.isEmpty) {
        return Center(
          child: Text(context.loc.tabs.addBoorusInSettings),
        );
      }

      // no tabs
      if (searchHandler.tabs.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }

      Booru? selectedBooru = searchHandler.currentBooru;
      // protection from exceptions when somehow selected booru is not on the list
      if (!settingsHandler.booruList.contains(selectedBooru)) {
        selectedBooru = null;
      }

      final bool isDesktop = settingsHandler.appMode.value.isDesktop;
      final EdgeInsetsGeometry margin = isDesktop
          ? const EdgeInsets.fromLTRB(2, 5, 2, 2)
          : const EdgeInsets.fromLTRB(5, 8, 5, 8);

      return Padding(
        padding: margin,
        child: LoliDropdown(
          value: selectedBooru,
          onChanged: (Booru? newValue) {
            if (searchHandler.currentBooru != newValue) {
              // if not already selected
              searchHandler.searchAction(searchHandler.searchTextController.text, newValue);
            }
          },
          expandableByScroll: true,
          items: settingsHandler.booruList,
          itemExtent: 54,
          itemBuilder: (item) {
            final bool isCurrent = selectedBooru == item;

            if (item == null) {
              return const SizedBox.shrink();
            }

            return Container(
              padding: isDesktop ? const EdgeInsets.all(5) : const EdgeInsets.only(left: 16, right: 16),
              height: 54,
              decoration: isCurrent
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    )
                  : null,
              child: TabBooruSelectorItem(booru: item),
            );
          },
          selectedItemBuilder: (value) {
            if (value == null) {
              return Text(context.loc.tabs.selectABooru);
            }

            return TabBooruSelectorItem(booru: value);
          },
          labelText: context.loc.booru,
        ),
      );
    });
  }
}
