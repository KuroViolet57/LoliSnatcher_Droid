import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

class TabRow extends StatelessWidget {
  const TabRow({
    required this.tab,
    this.color,
    this.fontWeight,
    this.withFavicon = true,
    this.withColoredTags = true,
    this.filterText,
    this.isExpanded = true,
    super.key,
  });

  final SearchTab tab;
  final Color? color;
  final FontWeight? fontWeight;
  final bool withFavicon;
  final bool withColoredTags;
  final String? filterText;
  final bool isExpanded;

  /// A tab that IS a doujin: a real detail-page tab (or a legacy id: search
  /// on a doujin source, which SearchTab.isDoujinDetail also recognizes).
  static bool isDoujinTab(SearchTab tab) => tab.isDoujinDetail;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final String rawTagsStr = tab.tags;

        // Doujin tabs: the gallery's COVER + title stand in for favicon +
        // query text, in every tab list that renders through this row. The
        // persisted tab fields let the cover/title render straight after a
        // restart, before the tab has fetched anything.
        final bool isDoujin = isDoujinTab(tab);
        final BooruItem? doujin = isDoujin && tab.booruHandler.filteredFetched.isNotEmpty
            ? tab.booruHandler.filteredFetched.first
            : null;
        final String? doujinThumbUrl = isDoujin
            ? ((doujin?.thumbnailURL.isNotEmpty ?? false) ? doujin!.thumbnailURL : tab.doujinThumb)
            : null;
        String? doujinTitle;
        if (isDoujin) {
          doujinTitle = doujin == null
              ? null
              : (doujin.description ?? '')
                    .split('\n')
                    .firstWhere((l) => l.trim().isNotEmpty, orElse: rawTagsStr.trim);
          if (doujinTitle == null || doujinTitle.trim().isEmpty || doujinTitle.trim() == rawTagsStr.trim()) {
            if (tab.doujinTitle?.isNotEmpty ?? false) doujinTitle = tab.doujinTitle;
          }
        }

        final String tagText =
            doujinTitle ?? (rawTagsStr.trim().isEmpty ? context.loc.tabs.empty : rawTagsStr).trim();

        final bool hasItems = tab.booruHandler.filteredFetched.isNotEmpty;

        final textColor = color ?? (tab.tags.isEmpty ? Colors.grey : null) ?? Theme.of(context).colorScheme.onSurface;

        Widget marquee = MarqueeText(
          key: ValueKey(tagText),
          text: tagText,
          isExpanded: isExpanded,
          style: TextStyle(
            fontSize: 16,
            fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
            fontWeight: fontWeight ?? FontWeight.normal,
            color: textColor,
          ),
        );

        // Doujin tabs show a plain title — never tag-coloured spans.
        if (!isDoujin && tab.tags.trim().isNotEmpty) {
          if (filterText?.isNotEmpty == true) {
            final List<TextSpan> spans = [];
            final List<String> split = tagText.split(filterText!);

            for (int i = 0; i < split.length; i++) {
              final spanStyle = TextStyle(
                fontSize: 16,
                fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
                fontWeight: fontWeight ?? FontWeight.normal,
                color: textColor,
              );

              spans.add(
                TextSpan(
                  text: split[i],
                  style: spanStyle,
                ),
              );
              if (i < split.length - 1) {
                spans.add(
                  TextSpan(
                    text: filterText,
                    style: spanStyle.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                    ),
                  ),
                );
              }
            }

            marquee = MarqueeText.rich(
              key: ValueKey(tagText),
              textSpan: TextSpan(
                children: spans,
              ),
              isExpanded: isExpanded,
              style: TextStyle(
                fontSize: 16,
                fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
                fontWeight: fontWeight ?? FontWeight.normal,
                color: textColor,
              ),
            );
          } else if (withColoredTags && !DoujinDataHandler.isDoujinBooru(tab.selectedBooru.value)) {
            // Tag colours come from the shared BOORU tag store — a doujin
            // search tab shows plain text rather than a booru's colouring of
            // a coinciding tag name.
            final List<TextSpan> spans = [];
            final List<String> split = tagText.trim().split(' ');

            for (int i = 0; i < split.length; i++) {
              String tag = split[i].trim();
              final String prefix = (tag.startsWith('-') || tag.startsWith('~')) ? tag.substring(0, 1) : '';
              if (prefix.isNotEmpty) {
                tag = tag.substring(1);
              }

              final int? booruNumber = int.tryParse(tag.split('#').firstOrNull ?? '');
              if (booruNumber != null) {
                tag = tag.split('#').sublist(1).join('#');
              }

              final metaTags = tab.booruHandler.availableMetaTags();
              final MetaTag? metaTag = metaTags.firstWhereOrNull((p) => p.tagParser(tag).isNotEmpty);
              final bool isMetaTag = metaTag != null;

              // Per-tab booru: two tabs can show the same tag string on
              // sites that classify it differently.
              final tagData = TagHandler.instance.getTagFor(tag, tab.selectedBooru.value);

              final bool isColored = !tagData.tagType.isNone || isMetaTag;

              final Color usedColor =
                  (isColored ? (isMetaTag ? Colors.pink : tagData.tagType.getColour()) : null) ?? textColor;

              final spanStyle = TextStyle(
                fontSize: 16,
                fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
                fontWeight: fontWeight ?? FontWeight.normal,
                color: usedColor,
                backgroundColor: isColored ? usedColor.withValues(alpha: 0.1) : null,
              );

              if (prefix.isNotEmpty) {
                spans.add(
                  TextSpan(
                    text: prefix == '-' ? '—' : prefix,
                    style: spanStyle.copyWith(
                      color: prefix == '-'
                          ? Colors.redAccent
                          : prefix == '~'
                          ? Colors.purpleAccent
                          : Colors.transparent,
                    ),
                  ),
                );
              }

              if (booruNumber != null) {
                spans.add(
                  TextSpan(
                    text: '$booruNumber#',
                    style: spanStyle.copyWith(
                      color: spanStyle.color?.withValues(alpha: 0.5),
                    ),
                  ),
                );
              }

              spans.add(
                TextSpan(
                  // add non-breaking space to the end of italics to hide text overflowing the bgColor,
                  text: '$tag${(hasItems || !isColored) ? '' : '\u{00A0}'}',
                  style: spanStyle,
                ),
              );
              if (i < split.length - 1) {
                spans.add(
                  TextSpan(
                    text: ' ',
                    style: spanStyle.copyWith(
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                );
              }
            }

            marquee = MarqueeText.rich(
              key: ValueKey(tagText),
              textSpan: TextSpan(
                children: spans,
              ),
              isExpanded: isExpanded,
              style: TextStyle(
                fontSize: 16,
                fontStyle: hasItems ? FontStyle.normal : FontStyle.italic,
                fontWeight: fontWeight ?? FontWeight.normal,
                color: textColor,
              ),
            );
          }
        }

        return Row(
          children: [
            if (isDoujin) ...[
              // Cover thumbnail marks the tab as a doujin at a glance.
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 24,
                  height: 32,
                  child: (doujinThumbUrl == null || doujinThumbUrl.isEmpty)
                      ? const ColoredBox(color: Colors.black26)
                      : Image(
                          image: CustomNetworkImage(
                            doujinThumbUrl,
                            withCache: SettingsHandler.instance.thumbnailCache,
                            cacheFolder: 'thumbnails',
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                        ),
                ),
              ),
              const SizedBox(width: 6),
            ] else if (withFavicon) ...[
              ValueListenableBuilder(
                valueListenable: tab.selectedBooru,
                builder: (context, selectedBooru, child) {
                  if (selectedBooru.faviconURL == null) {
                    return const Icon(
                      CupertinoIcons.question,
                      size: 20,
                    );
                  }

                  return RepaintBoundary(
                    child: BooruFavicon(
                      selectedBooru,
                      color: color,
                    ),
                  );
                },
              ),
              //
              const SizedBox(width: 4),
            ],
            // Pool tabs are otherwise indistinguishable from a tag search, and
            // several open at once gets confusing. Deliberately RED (the
            // theme's error role, so it survives theme switches and stays
            // legible either way) to read as a type marker at a glance.
            // Compact and non-flexing: the marquee keeps all remaining width.
            if (tab.isPool) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.75),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'pool',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            marquee,
          ],
        );
      },
    );
  }
}
