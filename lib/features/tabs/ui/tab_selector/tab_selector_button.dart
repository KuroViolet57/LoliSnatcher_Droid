part of '../tab_selector.dart';

class TabSelector extends StatelessWidget {
  const TabSelector({
    this.withBorder = true,
    this.countOnTop = false,
    this.color,
    super.key,
  });

  final bool withBorder;
  final bool countOnTop;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    const double radius = 10;

    final SearchHandler searchHandler = SearchHandler.instance;
    final SettingsHandler settingsHandler = SettingsHandler.instance;
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

      final currentTab = searchHandler.currentTab;
      final totalTabs = searchHandler.total;
      final currentTabIndex = searchHandler.currentIndex;

      final theme = Theme.of(context);
      final inputDecoration = theme.inputDecorationTheme;

      final EdgeInsetsGeometry margin = withBorder
          ? const EdgeInsets.fromLTRB(5, 8, 5, 8)
          : const EdgeInsets.fromLTRB(0, 16, 0, 0);
      const EdgeInsetsGeometry contentPadding = EdgeInsets.symmetric(horizontal: 16);

      final dropdown = LoliDropdown(
        value: currentTab.selectedBooru.value,
        onChanged: (Booru? newValue) {
          if (searchHandler.currentBooru != newValue) {
            // if not already selected
            searchHandler.searchAction(searchHandler.searchTextController.text, newValue);
          }
        },
        expandableByScroll: true,
        searchable: settingsHandler.booruList.length > 5,
        searchCheck: (searchText, item) =>
            (item.name?.toLowerCase().contains(searchText) ?? true) ||
            (item.type?.name.toLowerCase().contains(searchText) ?? true),
        items: settingsHandler.booruList,
        itemExtent: 54,
        itemBuilder: (item) {
          final bool isCurrent = currentTab.selectedBooru.value == item;

          if (item == null) {
            return const SizedBox.shrink();
          }

          return Container(
            padding: settingsHandler.appMode.value.isDesktop
                ? const EdgeInsets.all(5)
                : const EdgeInsets.only(left: 16, right: 16),
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
      );

      return Padding(
        padding: margin,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            height: MainAppBar.height,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      InputDecorator(
                        decoration: InputDecoration(
                          label: Obx(() {
                            final totalCount = currentTab.booruHandler.totalCount.value;

                            return RichText(
                              text: TextSpan(
                                style: inputDecoration.labelStyle?.copyWith(
                                  color: color ?? inputDecoration.labelStyle?.color,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        '${context.loc.tabs.tab} | ${(currentTabIndex + 1).toFormattedString()}/${totalTabs.toFormattedString()}',
                                  ),
                                  if (totalCount > 0 && countOnTop) ...[
                                    const TextSpan(text: ' | '),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                        child: Icon(
                                          Symbols.image_rounded,
                                          size: inputDecoration.labelStyle?.fontSize ?? 12,
                                          color: color ?? inputDecoration.labelStyle?.color,
                                        ),
                                      ),
                                    ),
                                    TextSpan(
                                      text: totalCount.toFormattedString(),
                                    ),
                                  ],
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                          labelStyle: inputDecoration.labelStyle?.copyWith(
                            color: color ?? inputDecoration.labelStyle?.color,
                          ),
                          contentPadding: contentPadding,
                          border: inputDecoration.border?.copyWith(
                            borderSide: BorderSide(
                              color: withBorder
                                  ? (inputDecoration.border?.borderSide.color ?? Colors.transparent)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          enabledBorder: inputDecoration.enabledBorder?.copyWith(
                            borderSide: BorderSide(
                              color: withBorder
                                  ? (inputDecoration.enabledBorder?.borderSide.color ?? Colors.transparent)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          focusedBorder: inputDecoration.focusedBorder?.copyWith(
                            borderSide: BorderSide(
                              color: withBorder
                                  ? (inputDecoration.focusedBorder?.borderSide.color ?? Colors.transparent)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      //
                      if (!countOnTop)
                        Positioned(
                          bottom: -8,
                          left: 16,
                          child: Obx(() {
                            final totalCount = currentTab.booruHandler.totalCount.value;
                            if (totalCount > 0) {
                              final usedColor = (color ?? inputDecoration.labelStyle?.color)?.darken(0.2);
                              return IgnorePointer(
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: Icon(
                                        Symbols.image_rounded,
                                        size: 14,
                                        color: usedColor,
                                      ),
                                    ),
                                    //
                                    Text(
                                      totalCount.toFormattedString(),
                                      style: inputDecoration.labelStyle?.copyWith(
                                        fontSize: 12,
                                        color: usedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return const SizedBox.shrink();
                          }),
                        ),
                    ],
                  ),
                ),
                //
                Positioned.fill(
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: withBorder
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(radius),
                                  bottomLeft: Radius.circular(radius),
                                )
                              : null,
                          onTap: () => dropdown.showDialog(context),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 12,
                              left: 16,
                              right: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                BooruFavicon(searchHandler.currentBooru),
                                Icon(
                                  Symbols.arrow_drop_down_rounded,
                                  color: color ?? theme.iconTheme.color,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      //
                      Container(
                        margin: const EdgeInsets.only(
                          top: 12,
                          bottom: 12,
                        ),
                        height: double.infinity,
                        width: 2,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      //
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: withBorder
                                ? const BorderRadius.only(
                                    topRight: Radius.circular(radius),
                                    bottomRight: Radius.circular(radius),
                                  )
                                : null,
                            onTap: () {
                              SettingsPageOpen(
                                context: context,
                                page: (_) => const TabManagerPage(),
                              ).open();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        TabRow(
                                          tab: currentTab,
                                          color: color,
                                          withFavicon: false,
                                        ),
                                        MarqueeText(
                                          text: [
                                            if (currentTab.booruHandler is MergebooruHandler)
                                              (currentTab.booruHandler as MergebooruHandler).booruList[0].name ?? ''
                                            else
                                              currentTab.booruHandler.booru.name ?? '',
                                            //
                                            for (final booru in (currentTab.secondaryBoorus.value ?? <Booru>[]))
                                              booru.name ?? '',
                                          ].join(', '),
                                          style: inputDecoration.labelStyle?.copyWith(
                                            fontSize: 14,
                                            color: color?.withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Symbols.arrow_drop_down_rounded,
                                    color: color ?? theme.iconTheme.color,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
