import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/animated_progress_indicator.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
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

    // Doujin cards: tags live UNDER the cover, never on the artwork, and
    // the cover's fit follows the per-source display setting.
    final bool isDoujinCard = handler.hasReader && SourceSettingsHandler.instance.gridTagStrip(handler.booru);
    final String coverDisplay = SourceSettingsHandler.instance.coverDisplay(handler.booru);
    final BoxFit? coverFit = isDoujinCard ? (coverDisplay == 'crop' ? BoxFit.cover : BoxFit.contain) : null;

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
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: showHighlightBorder
                    ? Border.all(
                        color: Theme.of(context).colorScheme.secondary,
                        width: defaultBorderWidth,
                      )
                    : null,
              ),
              child: InkWell(
                enableFeedback: true,
                borderRadius: BorderRadius.circular(14),
                highlightColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                splashColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                onTap: onTap == null ? null : () => onTap?.call(index),
                onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap?.call(index),
                onLongPress: onLongPress == null ? null : () => onLongPress?.call(index),
                onSecondaryTap: onSecondaryTap == null ? null : () => onSecondaryTap?.call(index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: isDoujinCard
                      ? Column(
                          children: [
                            Expanded(
                              child: ThumbnailBuild(
                                item: item,
                                handler: handler,
                                selectable: selectable,
                                selectedIndex: isSelected ? selectedIndex : null,
                                onSelected: onSelected == null ? null : () => onSelected!(index),
                                fit: coverFit,
                              ),
                            ),
                            _doujinFooter(context),
                          ],
                        )
                      : ThumbnailBuild(
                          item: item,
                          handler: handler,
                          selectable: selectable,
                          selectedIndex: isSelected ? selectedIndex : null,
                          onSelected: onSelected == null ? null : () => onSelected!(index),
                        ),
                ),
              ),
            ),
            // Gallery posts: the API describes only the cover, so mark cards
            // whose post holds several files. The count is backfilled in the
            // background from the site's own listing (see
            // PostFilesHandler.enrichCounts) and corrected to the exact media
            // count once the post is opened — hence the Obx, the badge can
            // arrive after this cell is already on screen.
            Obx(() {
              final int count = item.fileCountHint.value ?? 0;
              if (count <= 1) return const SizedBox.shrink();
              return Positioned(
                top: 6,
                left: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.66),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Symbols.burst_mode_rounded, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            //
            // Language badge stays on the cover's corner; the tag strip is
            // part of the card COLUMN below the artwork.
            if (isDoujinCard) ..._languageBadgeOverlay(context),
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
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Symbols.visibility_rounded,
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

  static const Map<String, String> _languageCodes = {
    'english': 'EN',
    'japanese': 'JP',
    'chinese': 'CH',
    'korean': 'KR',
  };

  List<Widget> _languageBadgeOverlay(BuildContext context) {
    String? language;
    for (final tag in item.tagsList) {
      if (handler.tagNamespace(tag.fullString) == 'language') {
        language ??= _languageCodes[tag.fullString];
      }
    }
    if (language == null) return const [];
    return [
      Positioned(
        top: 6,
        right: 6,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                language,
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The under-cover strip: up to 5 most relevant tags (favourited first,
  /// in gold) + the +N button that opens the full tag sheet.
  Widget _doujinFooter(BuildContext context) {
    final Set<String> markedTags = SettingsHandler.instance.markedTags.toSet();

    final List<Tag> marked = [];
    final List<Tag> rest = [];
    for (final tag in item.tagsList) {
      final String? ns = handler.tagNamespace(tag.fullString);
      if (ns == 'language' || ns == 'category') continue;
      (markedTags.contains(tag.fullString) ? marked : rest).add(tag);
    }
    // The site's counts double as relevance; favourites always lead.
    rest.sort((a, b) => b.count.compareTo(a.count));
    final List<Tag> shown = [...marked, ...rest].take(5).toList();
    final int more = item.tagsList.length - shown.length;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: shown.isEmpty
                  ? Text(
                      'no tags yet',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    )
                  : Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: [
                        for (final tag in shown) _miniTagChip(context, tag, isMarked: marked.contains(tag)),
                      ],
                    ),
            ),
            const SizedBox(width: 4),
            // The whole card opens the post; this small target on top of it
            // shows every tag instead.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showAllTagsSheet(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(
                    more > 0 ? '+$more' : '\u00b7\u00b7\u00b7',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniTagChip(BuildContext context, Tag tag, {required bool isMarked}) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isMarked ? const Color(0xFFB8860B).withValues(alpha: 0.85) : onSurface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMarked) ...[
              const Icon(Symbols.star_rounded, size: 10, color: Colors.white),
              const SizedBox(width: 2),
            ],
            Text(
              tag.fullString.replaceAll('_', ' '),
              style: TextStyle(
                color: isMarked ? Colors.white : onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Full tag list, grouped by the site's namespaces, without opening the
  /// post. Tapping a tag opens it as a background tab.
  void _showAllTagsSheet(BuildContext context) {
    final Set<String> markedTags = SettingsHandler.instance.markedTags.toSet();
    final sections = handler.tagNamespaceSections;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final Map<String, List<Tag>> byNs = {for (final s in sections) s.$1: <Tag>[]};
        final String fallback = sections.isNotEmpty ? sections.last.$1 : 'tag';
        for (final tag in item.tagsList) {
          final String ns = handler.tagNamespace(tag.fullString) ?? fallback;
          (byNs[ns] ?? byNs[fallback])?.add(tag);
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                Text(
                  '${item.tagsList.length} tags — tap one to open it in a new tab',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                for (final section in sections)
                  if (byNs[section.$1]?.isNotEmpty ?? false) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        section.$2,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in byNs[section.$1]!)
                          _sheetTagChip(sheetContext, tag, isMarked: markedTags.contains(tag.fullString)),
                      ],
                    ),
                  ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _sheetTagChip(BuildContext context, Tag tag, {required bool isMarked}) {
    final Color? typeColor = tag.tagType.getColour();
    final Color base = (typeColor == null || typeColor == Colors.transparent)
        ? Theme.of(context).colorScheme.onSurface
        : typeColor;
    return Material(
      color: isMarked ? const Color(0xFFB8860B).withValues(alpha: 0.35) : base.withValues(alpha: 0.14),
      shape: StadiumBorder(
        side: BorderSide(color: isMarked ? const Color(0xFFDAA520) : base.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          SearchHandler.instance.addTabByString(
            tag.fullString,
            customBooru: handler.booru,
            switchToNew: false,
          );
          FlashElements.showSnackbar(
            context: context,
            title: const Text('Added new tab', style: TextStyle(fontSize: 18)),
            content: Text(tag.fullString, style: const TextStyle(fontSize: 14)),
            duration: const Duration(seconds: 2),
            sideColor: Colors.green,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMarked) ...[
                const Icon(Symbols.star_rounded, size: 13, color: Color(0xFFDAA520)),
                const SizedBox(width: 3),
              ],
              Text(
                tag.fullString.replaceAll('_', ' '),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (tag.count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  tag.count.toFormattedString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
