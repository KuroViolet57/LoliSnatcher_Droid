import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_list_card.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_card_build.dart';

class GridBuilder extends StatelessWidget {
  const GridBuilder({
    required this.tab,
    required this.scrollController,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSelected,
    super.key,
  });

  final SearchTab tab;
  final AutoScrollController scrollController;
  final void Function(int)? onTap;
  final void Function(int)? onDoubleTap;
  final void Function(int)? onLongPress;
  final void Function(int)? onSecondaryTap;
  final void Function(int)? onSelected;

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // r63: doujin sources can trade the grid for a row per gallery.
    final bool listCards =
        tab.booruHandler.hasReader &&
        SourceSettingsHandler.instance.feedCardStyle(tab.booruHandler.booru) == 'list';
    if (listCards) {
      return ValueListenableBuilder(
        valueListenable: tab.booruHandler.filteredFetched,
        builder: (context, currentFetched, child) {
          // On the trace's timeline: every rebuild of the list rebuilds every
          // row it has built (2026-10-10).
          PerfTrace.instance.event('feed.list', '${currentFetched.length} items');
          final double cardHeight = SourceSettingsHandler.instance.listCardHeight(tab.booruHandler.booru).toDouble();
          final double coverWidth = SourceSettingsHandler.instance.listCoverWidth(tab.booruHandler.booru).toDouble();
          // Every row is the same height, so the list is laid out at that
          // fixed extent instead of measuring each row as it scrolls in
          // (2026-10-09).
          return SliverFixedExtentList.builder(
          itemExtent: DoujinListCard.rowExtent(cardHeight),
          addAutomaticKeepAlives: false,
          itemCount: currentFetched.length,
          itemBuilder: (BuildContext context, int index) => Obx(() {
            final BooruItem item = currentFetched[index];
            final bool hasSelected = tab.selected.isNotEmpty;
            final int selectedIndex = tab.selected.indexOf(item);
            final bool isSelected = selectedIndex != -1;

            return DoujinListCard(
              index: index,
              item: item,
              handler: tab.booruHandler,
              scrollController: scrollController,
              height: cardHeight,
              coverWidth: coverWidth,
              isHighlighted: ViewerHandler.instance.current.value?.key == item.key,
              selectedIndex: isSelected ? selectedIndex : null,
              onSelected: hasSelected ? onSelected : null,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              onLongPress: onLongPress,
              onSecondaryTap: onSecondaryTap,
            );
          }),
          );
        },
      );
    }

    final previewDisplay = (settingsHandler.previewDisplay.isStaggered && !tab.booruHandler.hasSizeData)
        ? settingsHandler.previewDisplayFallback
        : settingsHandler.previewDisplay;

    // Doujin sources can override the app-wide column counts.
    final int columnCount = context.isPortrait
        ? (tab.booruHandler.hasReader
                  ? SourceSettingsHandler.instance.columnsPortrait(tab.booruHandler.booru)
                  : null) ??
              settingsHandler.portraitColumns
        : (tab.booruHandler.hasReader
                  ? SourceSettingsHandler.instance.columnsLandscape(tab.booruHandler.booru)
                  : null) ??
              settingsHandler.landscapeColumns;

    return ValueListenableBuilder(
      valueListenable: tab.booruHandler.filteredFetched,
      builder: (context, currentFetched, child) => SliverGrid.builder(
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false, // ThumbnailCardBuild has its own RepaintBoundary
        itemCount: currentFetched.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          childAspectRatio: previewDisplay.isSquare ? 1 : 9 / 16,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemBuilder: (BuildContext context, int index) {
          return GridTile(
            child: Obx(() {
              final BooruItem item = currentFetched[index];

              final bool hasSelected = tab.selected.isNotEmpty;
              final selectedIndex = tab.selected.indexOf(item);
              final bool isSelected = selectedIndex != -1;
              final bool isHighlighted = ViewerHandler.instance.current.value?.key == item.key;

              return ThumbnailCardBuild(
                index: index,
                item: item,
                handler: tab.booruHandler,
                scrollController: scrollController,
                isHighlighted: isHighlighted,
                selectable: true,
                selectedIndex: isSelected ? selectedIndex : null,
                onSelected: hasSelected ? onSelected : null,
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                onLongPress: onLongPress,
                onSecondaryTap: onSecondaryTap,
              );
            }),
          );
        },
      ),
    );
  }
}
