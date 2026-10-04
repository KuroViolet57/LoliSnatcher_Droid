part of '../main_search_query_editor_page.dart';

class PinnedTagsBlock extends StatefulWidget {
  const PinnedTagsBlock({
    required this.onTagTap,
    required this.onTagLongTap,
    super.key,
  });

  final void Function(String tag) onTagTap;
  final void Function(String tag, PinnedTag pinnedTag) onTagLongTap;

  @override
  State<PinnedTagsBlock> createState() => _PinnedTagsBlockState();
}

enum PinnedTagsSortMode { custom, alphabetical, reverseAlphabetical }

class _PinnedTagsBlockState extends State<PinnedTagsBlock> {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;

  List<PinnedTag> allPinnedTags = [];
  List<PinnedTag> filteredPinnedTags = [];
  List<String> availableLabels = [];
  String? selectedLabel;
  bool loading = true;
  PinnedTagsSortMode sortMode = PinnedTagsSortMode.custom;

  final scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    loading = true;
    if (mounted) setState(() {});

    final booru = searchHandler.currentBooru;
    if (DoujinDataHandler.isDoujinBooru(booru)) {
      // Doujin tabs: pins come from the doujin store only.
      allPinnedTags = doujinPinsAsPinnedTags(booru);
    } else {
      allPinnedTags = await settingsHandler.dbHandler.getPinnedTags(
        booruType: booru.type?.name,
        booruName: booru.name,
      );
      // Follows are stored as labelled pins but have their own screen.
      allPinnedTags.removeWhere(FollowedArtistsHandler.isFollowPin);
    }

    // r52: pins hidden on this source (the pinned tags page) are left out here.
    allPinnedTags = PinnedTagVisibility.visible(allPinnedTags, booru);

    // Get unique labels from all tags
    final labelsSet = <String>{};
    for (final t in allPinnedTags) {
      labelsSet.addAll(t.labels);
    }
    availableLabels = labelsSet.toList()..sort();

    // Validate selected label still exists
    if (selectedLabel != null && !availableLabels.contains(selectedLabel)) {
      selectedLabel = null;
    }

    _applyFiltersAndSorting();
    loading = false;
    if (mounted) setState(() {});
  }

  void _applyFiltersAndSorting() {
    // Apply label filter
    if (selectedLabel != null) {
      filteredPinnedTags = allPinnedTags.where((t) => t.hasLabel(selectedLabel!)).toList();
    } else {
      filteredPinnedTags = List.from(allPinnedTags);
    }

    // Apply sorting
    switch (sortMode) {
      case PinnedTagsSortMode.custom:
        // Already sorted by sortOrder from DB
        break;
      case PinnedTagsSortMode.alphabetical:
        filteredPinnedTags.sort((a, b) => a.tagName.toLowerCase().compareTo(b.tagName.toLowerCase()));
        break;
      case PinnedTagsSortMode.reverseAlphabetical:
        filteredPinnedTags.sort((a, b) => b.tagName.toLowerCase().compareTo(a.tagName.toLowerCase()));
        break;
    }
  }

  void _cycleSortMode() {
    setState(() {
      sortMode = PinnedTagsSortMode.values[(sortMode.index + 1) % PinnedTagsSortMode.values.length];
      _applyFiltersAndSorting();
    });
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _selectLabel(String? label) {
    setState(() {
      selectedLabel = label;
      _applyFiltersAndSorting();
    });
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  IconData get _sortIcon => switch (sortMode) {
    PinnedTagsSortMode.custom => Symbols.sort_rounded,
    PinnedTagsSortMode.alphabetical => Symbols.sort_by_alpha_rounded,
    PinnedTagsSortMode.reverseAlphabetical => Symbols.sort_by_alpha_rounded,
  };

  String get _sortTooltip => switch (sortMode) {
    PinnedTagsSortMode.custom => 'Custom order',
    PinnedTagsSortMode.alphabetical => 'A-Z',
    PinnedTagsSortMode.reverseAlphabetical => 'Z-A',
  };

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!settingsHandler.dbEnabled) {
      return const SizedBox.shrink();
    }

    return SearchSectionCard(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () {
              scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(
                  Symbols.push_pin_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.loc.pinnedTags.pinnedTags,
                    textAlign: TextAlign.left,
                    style: context.theme.textTheme.bodyLarge,
                  ),
                ),
                if (availableLabels.isNotEmpty)
                  PopupMenuButton<String?>(
                    onSelected: _selectLabel,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selectedLabel ?? context.loc.pinnedTags.all,
                            style: context.theme.textTheme.bodyLarge,
                          ),
                          const Icon(Symbols.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: null,
                        onTap: () => _selectLabel(null),
                        child: Row(
                          children: [
                            if (selectedLabel == null) const Icon(Symbols.check_rounded, size: 18) else const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(context.loc.pinnedTags.all),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      ...availableLabels.map(
                        (label) => PopupMenuItem(
                          value: label,
                          child: Row(
                            children: [
                              if (selectedLabel == label)
                                const Icon(Symbols.check_rounded, size: 18)
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(label),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(width: 8),
                if (allPinnedTags.length > 1)
                  IconButton(
                    onPressed: _cycleSortMode,
                    icon: Stack(
                      children: [
                        Icon(_sortIcon),
                        if (sortMode == PinnedTagsSortMode.reverseAlphabetical)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Icon(
                              Symbols.arrow_downward_rounded,
                              size: 10,
                              color: context.theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    tooltip: _sortTooltip,
                  ),
                IconButton(
                  onPressed: () async {
                    await showPinnedTagsManagerDialog(
                      context,
                      currentBooru: searchHandler.currentBooru,
                      onTagTap: widget.onTagTap,
                    );
                    // Always refresh after closing the dialog since changes might have been made
                    await init();
                  },
                  icon: const Icon(Symbols.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 50,
          child: Listener(
            onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
            child: FadingEdgeScrollView.fromScrollView(
              child: ListView.builder(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredPinnedTags.isEmpty ? 1 : filteredPinnedTags.length,
                itemBuilder: (BuildContext context, int index) {
                  if (filteredPinnedTags.isEmpty) {
                    if (loading) {
                      return GestureDetector(
                        onTap: init,
                        child: const Align(
                          alignment: Alignment.center,
                          child: SizedBox.square(
                            dimension: 30,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      );
                    }

                    return Row(
                      spacing: 8,
                      children: [
                        const Kaomoji(
                          category: .indifference,
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          context.loc.pinnedTags.noPinnedTagsYet,
                          style: context.theme.textTheme.bodyLarge,
                        ),
                      ],
                    );
                  }

                  final pinnedTag = filteredPinnedTags[index];
                  final tagColor = tagHandler.colourForDisplay(pinnedTag.tagName, SearchHandler.instance.tabs.isEmpty ? null : SearchHandler.instance.currentBooru);
                  final bool isMultiword = pinnedTag.tagName.split(' ').length > 1;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => widget.onTagLongTap(pinnedTag.tagName, pinnedTag),
                      child: InputChip(
                        avatar: pinnedTag.isGlobal
                            ? null
                            : BooruFavicon(
                                settingsHandler.booruList.value.firstWhere(
                                  (b) =>
                                      b.type == pinnedTag.booruType &&
                                      (b.type?.isFavouritesOrDownloads == true || b.name == pinnedTag.booruName),
                                  orElse: Booru.unknown,
                                ),
                              ),
                        label: Text(
                          isMultiword ? pinnedTag.tagName : pinnedTag.tagName.replaceAll('_', ' '),
                          style: TextStyle(color: tagColor),
                        ),
                        onPressed: () => widget.onTagTap(pinnedTag.tagName),
                        onDeleted: () => widget.onTagLongTap(pinnedTag.tagName, pinnedTag),
                        deleteIcon: const Icon(Symbols.more_vert_rounded, size: 18),
                        deleteButtonTooltipMessage: '',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
