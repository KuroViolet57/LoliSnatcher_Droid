import 'package:flutter/material.dart';

import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_card_meta.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_build.dart';

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

  /// Space above and below each card inside its row.
  static const double verticalGap = 3;

  /// A whole feed row, card plus its gaps: the feed lays rows out at this
  /// fixed extent instead of measuring each one while scrolling (2026-10-09).
  static double rowExtent(double height) => height + 2 * verticalGap;

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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: verticalGap),
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
                              Expanded(child: _tagBlock(context, tags)),
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
  Widget _tagBlock(BuildContext context, List<Tag> tags) {
    if (tags.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'no tags yet',
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ),
      );
    }

    return _TagBlock(tags: tags, chip: _chip);
  }

  static Widget _chip(BuildContext context, Tag tag, {required bool isMarked}) {
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

/// The list card's tag block (2026-10-09, "very laggy" when scrolling).
///
/// Every chip of every row used to be built as the row scrolled in, though
/// only the first few fit beside the cover. Until the block is touched, each
/// row now stops at the screen's width - measured as if every letter were
/// far narrower than any real one, so a row never stops short of the visible
/// edge. The first touch (before any drag can move it) builds the rest, so
/// the block scrolls exactly as before.
class _TagBlock extends StatefulWidget {
  const _TagBlock({required this.tags, required this.chip});

  final List<Tag> tags;
  final Widget Function(BuildContext context, Tag tag, {required bool isMarked}) chip;

  /// Narrower than any letter at the chip's 10.5 px (Roboto's 'i' is ~2.9).
  static const double minCharWidth = 2.5;

  /// The chip's own padding plus the gap after it.
  static const double chipChrome = 6 + 6 + 3;

  @override
  State<_TagBlock> createState() => _TagBlockState();
}

class _TagBlockState extends State<_TagBlock> {
  bool _all = false;

  /// The chips of one row that can be visible before the block is scrolled.
  Iterable<Tag> _visiblePart(Iterable<Tag> row, double budget) sync* {
    double used = 0;
    for (final Tag tag in row) {
      if (used > budget) return;
      yield tag;
      used += tag.fullString.length * _TagBlock.minCharWidth + _TagBlock.chipChrome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Tag> tags = widget.tags;
    final DoujinDataHandler doujinData = DoujinDataHandler.instance;
    final int perRow = (tags.length / DoujinListCard.tagRows).ceil().clamp(1, tags.length);
    final double budget = MediaQuery.sizeOf(context).width;
    return Listener(
      onPointerDown: _all ? null : (_) => setState(() => _all = true),
      child: SingleChildScrollView(
        key: const ValueKey('doujin-list-card-tags'),
        scrollDirection: Axis.horizontal,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int row = 0; row < DoujinListCard.tagRows; row++)
              if (row * perRow < tags.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      for (final Tag tag in _all
                          ? tags.skip(row * perRow).take(perRow)
                          : _visiblePart(tags.skip(row * perRow).take(perRow), budget))
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: widget.chip(context, tag, isMarked: doujinData.isTagStarred(tag.fullString)),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
