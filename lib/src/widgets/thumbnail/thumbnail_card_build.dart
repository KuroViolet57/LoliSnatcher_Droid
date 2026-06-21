import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/widgets/common/animated_progress_indicator.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

class ThumbnailCardBuild extends StatelessWidget {
  const ThumbnailCardBuild({
    required this.index,
    required this.item,
    required this.handler,
    required this.scrollController,
    this.isHighlighted = false,
    this.selectable = true,
    this.selectedIndex,
    this.onSelected,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    super.key,
  });

  final int index;
  final BooruItem item;
  final BooruHandler handler;
  final AutoScrollController scrollController;
  final bool isHighlighted;
  final bool selectable;
  final int? selectedIndex;
  final void Function(int)? onSelected;
  final void Function(int)? onTap;
  final void Function(int)? onDoubleTap;
  final void Function(int)? onLongPress;
  final void Function(int)? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final snatchHandler = SnatchHandler.instance;

    final bool isSelected = selectable && selectedIndex != null;
    final bool showHighlightBorder = isHighlighted || isSelected;
    final double defaultBorderWidth = max(2, MediaQuery.devicePixelRatioOf(context));

    return AutoScrollTag(
      highlightColor: Colors.red,
      key: ValueKey(index),
      controller: scrollController,
      index: index,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: showHighlightBorder
                    ? Border.all(
                        color: Theme.of(context).colorScheme.secondary,
                        width: defaultBorderWidth,
                      )
                    : null,
              ),
              child: InkWell(
                enableFeedback: true,
                borderRadius: BorderRadius.circular(4),
                highlightColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                splashColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                onTap: onTap == null ? null : () => onTap?.call(index),
                onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap?.call(index),
                onLongPress: onLongPress == null ? null : () => onLongPress?.call(index),
                onSecondaryTap: onSecondaryTap == null ? null : () => onSecondaryTap?.call(index),
                child: ThumbnailBuild(
                  item: item,
                  handler: handler,
                  selectable: selectable,
                  selectedIndex: isSelected ? selectedIndex : null,
                  onSelected: onSelected == null ? null : () => onSelected!(index),
                ),
              ),
            ),
            //
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  snatchHandler.current,
                  snatchHandler.queueProgress,
                  snatchHandler.total,
                  snatchHandler.received,
                ]),
                builder: (context, _) {
                  final current = snatchHandler.current.value;
                  final queueProgress = snatchHandler.queueProgress.value;
                  final total = snatchHandler.total.value;

                  final bool isCurrentlyBeingSnatched = current?.booruItems[queueProgress] == item && total != 0;

                  if (isCurrentlyBeingSnatched) {
                    return AnimatedProgressIndicator(
                      value: snatchHandler.currentProgress,
                      animationDuration: const Duration(milliseconds: 50),
                      indicatorStyle: IndicatorStyle.square,
                      valueColor: Theme.of(context).progressIndicatorTheme.color,
                      strokeWidth: defaultBorderWidth * 3,
                      borderRadius: 10,
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
            //
            // Dim overlay for already-viewed posts. Gated on the setting, and
            // reactive to item.isSeen so a post dims the moment you return
            // from viewing it. Ignores pointer events so taps still pass
            // through to the card.
            if (SettingsHandler.instance.dimSeenPosts)
              Positioned.fill(
                child: IgnorePointer(
                  child: Obx(() {
                    final bool seen =
                        item.isSeen.value || SearchHandler.instance.isPostSeen(item);
                    if (!seen) return const SizedBox.shrink();
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.visibility,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
