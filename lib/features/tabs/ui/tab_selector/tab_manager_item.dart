part of '../tab_selector.dart';

class TabManagerItem extends StatelessWidget {
  const TabManagerItem({
    required this.tab,
    this.index,
    this.isCurrent = false,
    this.isFiltered = false,
    this.originalIndex,
    this.onTap,
    this.optionsWidgetBuilder,
    this.onOptionsTap,
    this.onCloseTap,
    this.filterText,
    super.key,
  }) : assert(
         !isFiltered || (index != null && originalIndex != null),
         'originalIndex must be provided if isFiltered is true',
       );

  final SearchTab tab;
  final int? index;
  final bool isCurrent;
  final bool isFiltered;
  final int? originalIndex;
  final VoidCallback? onTap;
  final Widget Function(BuildContext, VoidCallback?)? optionsWidgetBuilder;
  final VoidCallback? onOptionsTap;
  final VoidCallback? onCloseTap;
  final String? filterText;

  /// A doujin row is its cover (r39): taller than a search row, and the
  /// manager's list gives it that height (see [extentFor]).
  static const double rowHeight = 72 + 8;
  static const double doujinRowHeight = 104;
  static const double doujinCoverHeight = 76;

  static double extentFor(SearchTab tab) => TabRow.isDoujinTab(tab) ? doujinRowHeight : rowHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(13);
    final bool isDoujin = TabRow.isDoujinTab(tab);
    final String? cover = !isDoujin
        ? null
        : ((tab.doujinThumb?.isNotEmpty ?? false) ? tab.doujinThumb : tab.booruHandler.filteredFetched.firstOrNull?.thumbnailURL);
    final Color meta = theme.colorScheme.onSurfaceVariant;

    final Booru avatarBooru = tab.booruHandler is MergebooruHandler
        ? (tab.booruHandler as MergebooruHandler).booruList[0]
        : tab.booruHandler.booru;

    final List<String> booruNames = [
      avatarBooru.name ?? '',
      for (final Booru booru in (tab.secondaryBoorus.value ?? [])) booru.name ?? '',
    ];
    final String booruNamesStr = booruNames.where((n) => n.isNotEmpty).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Material(
        color: isCurrent ? theme.colorScheme.secondary.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: isCurrent ? theme.colorScheme.secondary : theme.colorScheme.outlineVariant,
            width: isCurrent ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                if (isDoujin)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: doujinCoverHeight * 0.75,
                      height: doujinCoverHeight,
                      child: (cover == null || cover.isEmpty)
                          ? const ColoredBox(color: Colors.black26)
                          : Image(
                              image: CustomNetworkImage(cover, withCache: SettingsHandler.instance.thumbnailCache, cacheFolder: 'thumbnails'),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                            ),
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 26, height: 26, child: BooruFavicon(avatarBooru, size: 26)),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The cover is drawn at the row's left instead (r39).
                      TabRow(tab: tab, filterText: filterText, doujinCoverHeight: 0),
                      const SizedBox(height: 2),
                      Obx(() {
                        final int totalCount = tab.booruHandler.totalCount.value;
                        final String countStr = totalCount > 0
                            ? totalCount.toFormattedString()
                            : (tab.booruHandler.filteredFetched.isNotEmpty ? '${tab.booruHandler.filteredFetched.length}+' : '—');
                        return Text(
                          '$booruNamesStr · $countStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: meta),
                        );
                      }),
                    ],
                  ),
                ),
                if (onOptionsTap != null || optionsWidgetBuilder != null) ...[
                  const SizedBox(width: 2),
                  optionsWidgetBuilder?.call(context, onOptionsTap) ??
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color: meta,
                        onPressed: onOptionsTap,
                        icon: const Icon(CupertinoIcons.slider_horizontal_3),
                      ),
                ],
                if (onCloseTap != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: meta,
                    onPressed: onCloseTap,
                    icon: const Icon(Symbols.close_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
