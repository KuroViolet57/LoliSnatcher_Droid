part of '../tag_view.dart';

Future<void> showRelatedTabsDialog(
  BuildContext context,
  String tag,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _RelatedTabsDialog(tag),
  );
}

class _RelatedTabsDialog extends StatefulWidget {
  const _RelatedTabsDialog(
    this.tag,
  );

  final String tag;

  @override
  State<_RelatedTabsDialog> createState() => _RelatedTabsDialogState();
}

class _RelatedTabsDialogState extends State<_RelatedTabsDialog> {
  final searchHandler = SearchHandler.instance;

  List<(int, SearchTab)> tabsWithOnlyTag = [], tabsWithOnlyTagDifferentBooru = [], tabsContainingTag = [];

  HasTabWithTagResult selectedType = HasTabWithTagResult.noTag;

  @override
  void initState() {
    super.initState();

    tabsWithOnlyTag = searchHandler.getTabsWithOnlyTag(widget.tag);
    tabsWithOnlyTagDifferentBooru = searchHandler.getTabsWithOnlyTagDifferentBooru(widget.tag);
    tabsContainingTag = searchHandler.getTabsContainingTag(widget.tag);

    selectedType = HasTabWithTagResult.noTag;
    if (tabsWithOnlyTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTag;
    } else if (tabsWithOnlyTagDifferentBooru.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTagDifferentBooru;
    } else if (tabsContainingTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.containsTag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listItems = switch (selectedType) {
      .onlyTag => tabsWithOnlyTag,
      .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru,
      .containsTag => tabsContainingTag,
      _ => <(int, SearchTab)>[],
    };

    return SettingsDialog(
      scrollable: false,
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          LoliDropdown(
            value: selectedType,
            onChanged: (newType) {
              setState(() => selectedType = newType ?? HasTabWithTagResult.noTag);
            },
            items: [
              if (tabsWithOnlyTag.isNotEmpty) HasTabWithTagResult.onlyTag,
              if (tabsWithOnlyTagDifferentBooru.isNotEmpty) HasTabWithTagResult.onlyTagDifferentBooru,
              if (tabsContainingTag.isNotEmpty) HasTabWithTagResult.containsTag,
            ],
            itemBuilder: (v) => ListTile(
              leading: Icon(
                Symbols.circle_rounded,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(
                '${v?.locName(context) ?? ''} (${switch (v) {
                  .onlyTag => tabsWithOnlyTag.length,
                  .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru.length,
                  .containsTag => tabsContainingTag.length,
                  _ => 0,
                }})',
              ),
            ),
            selectedItemBuilder: (v) => ListTile(
              leading: Icon(
                Symbols.circle_rounded,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(v?.locName(context) ?? ''),
            ),
            labelText: context.loc.tagView.relatedTabs,
          ),
          Container(
            width: double.maxFinite,
            height: (listItems.length * 80.0).clamp(0, MediaQuery.sizeOf(context).height * 0.66) + 32,
            decoration: const BoxDecoration(),
            child: ListView.builder(
              itemCount: listItems.length,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemBuilder: (context, index) {
                final (tabIndex, tab) = listItems[index];
                return TabManagerItem(
                  tab: tab,
                  index: index,
                  isFiltered: true,
                  originalIndex: tabIndex,
                  onTap: () async {
                    await ServiceHandler.vibrate();
                    if (SettingsHandler.instance.appMode.value.isMobile) {
                      NavigationTrace.closing('tab list: switched tab', () => Navigator.of(context).popUntil((r) => r.isFirst)); // exit viewer
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      searchHandler.changeTabIndex(tabIndex);
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      actionButtons: const [CloseDialogButton(withIcon: true)],
    );
  }
}
