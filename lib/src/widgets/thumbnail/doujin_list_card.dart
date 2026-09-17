import 'package:flutter/material.dart';

import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/doujin_card_meta.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

/// A doujin feed row (r63): cover on the left, then the title, the uploader,
/// the tags, and what the gallery is - kind, language, page count.
///
/// The title and the tag block scroll sideways instead of being cut off, so a
/// long title can be read and every tag can be reached without opening the
/// gallery. Chosen per source: Source settings → Grid → Feed cards → List.
class DoujinListCard extends StatelessWidget {
  const DoujinListCard({
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
    this.height = defaultHeight,
    this.coverWidth = defaultCoverWidth,
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

  /// One row's height unless the source's settings say otherwise (r66), and
  /// the cover column's width (r69: a per-source setting too).
  static const double defaultHeight = 176;
  static const double defaultCoverWidth = 116;

  /// Adapt never squeezes the column below this.
  static const double minCoverWidth = 48;

  final double height;

  /// The cover column's width; for Adapt the widest it may get.
  final double coverWidth;

  /// The tag block is this many rows tall and scrolls sideways.
  static const int tagRows = 3;

  @override
  Widget build(BuildContext context) {
    PerfTrace.instance.built('DoujinListCard');
    final ThemeData theme = Theme.of(context);
    final DoujinDataHandler doujinData = DoujinDataHandler.instance..ensureLoaded();

    final String title = DoujinCardMeta.title(item);
    final String? language = DoujinCardMeta.language(item, handler);
    final String? category = DoujinCardMeta.category(item, handler);
    final int? pages = DoujinCardMeta.pages(item);
    final List<Tag> tags = DoujinCardMeta.cardTags(item, handler, isStarred: doujinData.isTagStarred);
    final bool isSelected = selectable && selectedIndex != null;

    return AutoScrollTag(
      highlightColor: Colors.red,
      key: ValueKey(index),
      controller: scrollController,
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Material(
          key: const ValueKey('doujin-list-card-surface'),
          // r66: a raised card - a shadow gives the row some volume instead of
          // reading as a flat block.
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.7),
          color: Color.alphaBlend(
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap == null ? null : () => onTap?.call(index),
            onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap?.call(index),
            onLongPress: onLongPress == null ? null : () => onLongPress?.call(index),
            onSecondaryTap: onSecondaryTap == null ? null : () => onSecondaryTap?.call(index),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: (isHighlighted || isSelected)
                    ? Border.all(color: theme.colorScheme.secondary, width: 2)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  key: const ValueKey('doujin-list-card-row'),
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cover(context, isSelected: isSelected),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _title(context, title),
                              if ((item.uploaderName ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    item.uploaderName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Expanded(child: _tagBlock(context, tags, doujinData)),
                              const SizedBox(height: 4),
                              _metaRow(context, category: category, language: language, pages: pages),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cover column, following the source's Cover display choice (r69):
  /// crop fills the column, fit shows the whole cover with bars, adapt gives
  /// the column the cover's own shape at the row height - the width setting
  /// is its cap, and a cover wider than the cap is cropped to it.
  Widget _cover(BuildContext context, {required bool isSelected}) {
    final ThemeData theme = Theme.of(context);

    Widget column({required double width, required BoxFit fit}) => SizedBox(
      key: const ValueKey('doujin-list-card-cover'),
      width: width,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: ThumbnailBuild(
          item: item,
          handler: handler,
          selectable: selectable,
          selectedIndex: isSelected ? selectedIndex : null,
          onSelected: onSelected == null ? null : () => onSelected!(index),
          fit: fit,
        ),
      ),
    );

    switch (SourceSettingsHandler.instance.coverDisplay(handler.booru)) {
      case 'fit':
        return column(width: coverWidth, fit: BoxFit.contain);
      case 'adapt':
        return ValueListenableBuilder<double?>(
          valueListenable: DoujinCoverAspects.instance.notifierFor(item.displayThumbnailURL),
          builder: (context, aspect, _) {
            final double wanted = height * (aspect ?? DoujinCoverAspects.provisional);
            final double width = wanted.clamp(minCoverWidth, coverWidth);
            // The column has the cover's exact shape: nothing to crop. Capped,
            // or not decoded yet: the cover fills what it has.
            final bool exact = aspect != null && wanted >= minCoverWidth && wanted <= coverWidth;
            return column(width: width, fit: exact ? BoxFit.contain : BoxFit.cover);
          },
        );
      default:
        return column(width: coverWidth, fit: BoxFit.cover);
    }
  }

  /// One line that scrolls sideways: long titles are read, not truncated.
  Widget _title(BuildContext context, String title) {
    return SizedBox(
      height: 34,
      child: SingleChildScrollView(
        key: const ValueKey('doujin-list-card-title'),
        scrollDirection: Axis.horizontal,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title.isEmpty ? '…' : title,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ),
      ),
    );
  }

  /// [tagRows] rows of chips that scroll sideways together.
  Widget _tagBlock(BuildContext context, List<Tag> tags, DoujinDataHandler doujinData) {
    if (tags.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'no tags yet',
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ),
      );
    }

    final int perRow = (tags.length / tagRows).ceil().clamp(1, tags.length);
    return SingleChildScrollView(
      key: const ValueKey('doujin-list-card-tags'),
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int row = 0; row < tagRows; row++)
            if (row * perRow < tags.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    for (final Tag tag in tags.skip(row * perRow).take(perRow))
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _chip(context, tag, isMarked: doujinData.isTagStarred(tag.fullString)),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Tag tag, {required bool isMarked}) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isMarked
            ? theme.colorScheme.primary.withValues(alpha: 0.28)
            : theme.colorScheme.onSurface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          tag.fullString,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isMarked ? FontWeight.w700 : FontWeight.w500,
            color: isMarked ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  /// What the gallery is: kind on the left, language and pages on the right.
  Widget _metaRow(
    BuildContext context, {
    required String? category,
    required String? language,
    required int? pages,
  }) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: [
        if (category != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onError,
                ),
              ),
            ),
          ),
        const Spacer(),
        if (language != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              language,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        if (pages != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '${pages}P',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }
}
