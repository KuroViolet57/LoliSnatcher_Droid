part of '../main_search_query_editor_page.dart';

Future<bool?> showPinnedTagsReorderDialog(
  BuildContext context,
  List<PinnedTag> initialTags,
) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PinnedTagsReorderDialog(initialTags: initialTags),
  );
}

class PinnedTagsReorderDialog extends StatefulWidget {
  const PinnedTagsReorderDialog({
    required this.initialTags,
    super.key,
  });

  final List<PinnedTag> initialTags;

  @override
  State<PinnedTagsReorderDialog> createState() => _PinnedTagsReorderDialogState();
}

class _PinnedTagsReorderDialogState extends State<PinnedTagsReorderDialog> {
  final settingsHandler = SettingsHandler.instance;
  final tagHandler = TagHandler.instance;

  late List<PinnedTag> tags;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    tags = List.from(widget.initialTags);
  }

  Future<void> saveOrder() async {
    setState(() => saving = true);
    await settingsHandler.dbHandler.updatePinnedTagsOrder(tags);
    setState(() => saving = false);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      onClosing: () {},
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 32,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Text(
              context.loc.pinnedTags.reorderPinnedTags,
              style: context.theme.textTheme.headlineMedium,
            ),
            SizedBox(
              width: double.maxFinite,
              height: min((tags.length * 72) + 16, MediaQuery.sizeOf(context).height * 0.5),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: tags.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = tags.removeAt(oldIndex);
                    tags.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final pinnedTag = tags[index];
                  final tagColor = tagHandler.colourForDisplay(pinnedTag.tagName, SearchHandler.instance.tabs.isEmpty ? null : SearchHandler.instance.currentBooru);
                  final bool isMultiword = pinnedTag.tagName.split(' ').length > 1;

                  return ListTile(
                    key: ValueKey(pinnedTag.id),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Symbols.drag_handle_rounded),
                        ),
                        const SizedBox(width: 8),
                        if (!pinnedTag.isGlobal)
                          BooruFavicon(
                            settingsHandler.booruList.value.firstWhere(
                              (b) =>
                                  b.type == pinnedTag.booruType &&
                                  (b.type?.isFavouritesOrDownloads == true || b.name == pinnedTag.booruName),
                              orElse: Booru.unknown,
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      isMultiword ? pinnedTag.tagName : pinnedTag.tagName.replaceAll('_', ' '),
                      style: TextStyle(color: tagColor),
                    ),
                    subtitle: Text(pinnedTag.booruName ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Symbols.delete_rounded),
                      onPressed: () => showUnpinTagDialog(
                        context,
                        pinnedTag.tagName,
                        pinnedTag,
                        () {
                          setState(() {
                            tags.removeAt(index);
                          });
                          if (tags.isEmpty && mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.maxFinite,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  const CancelButton(),
                  ElevatedButton.icon(
                    onPressed: saving ? null : saveOrder,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.check_rounded),
                    label: Text(saving ? context.loc.pinnedTags.saving : context.loc.save),
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

Future<bool?> showPinnedTagsManagerDialog(
  BuildContext context, {
  required Booru currentBooru,
  required void Function(String tag) onTagTap,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PinnedTagsManagerDialog(
      currentBooru: currentBooru,
      onTagTap: onTagTap,
    ),
  );
}

class PinnedTagsManagerDialog extends StatefulWidget {
  const PinnedTagsManagerDialog({
    required this.currentBooru,
    required this.onTagTap,
    super.key,
  });

  final Booru currentBooru;
  final void Function(String tag) onTagTap;

  @override
  State<PinnedTagsManagerDialog> createState() => _PinnedTagsManagerDialogState();
}

class _PinnedTagsManagerDialogState extends State<PinnedTagsManagerDialog> {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;

  List<PinnedTag> allTags = [];
  List<PinnedTag> filteredTags = [];
  bool loading = true;
  bool hasChanges = false;
  PinnedTagsSortMode sortMode = PinnedTagsSortMode.custom;

  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    searchController.addListener(_onSearchChanged);
    init();
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _applyFilter();
  }

  Future<void> init() async {
    loading = true;
    if (mounted) setState(() {});

    final booru = searchHandler.currentBooru;
    if (DoujinDataHandler.isDoujinBooru(booru)) {
      // Doujin tabs: pins come from the doujin store only.
      allTags = doujinPinsAsPinnedTags(booru);
    } else {
      allTags = await settingsHandler.dbHandler.getPinnedTags(
        booruType: booru.type?.name,
        booruName: booru.name,
      );
      // Follows are stored as labelled pins but have their own screen.
      allTags.removeWhere(FollowedArtistsHandler.isFollowPin);
    }

    _applySorting();
    _applyFilter();
    loading = false;
    if (mounted) setState(() {});
  }

  void _applySorting() {
    switch (sortMode) {
      case PinnedTagsSortMode.custom:
        allTags.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        break;
      case PinnedTagsSortMode.alphabetical:
        allTags.sort((a, b) => a.tagName.toLowerCase().compareTo(b.tagName.toLowerCase()));
        break;
      case PinnedTagsSortMode.reverseAlphabetical:
        allTags.sort((a, b) => b.tagName.toLowerCase().compareTo(a.tagName.toLowerCase()));
        break;
    }
    _applyFilter();
  }

  void _applyFilter() {
    final query = searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      filteredTags = List.from(allTags);
    } else {
      // Search in both tag name and labels
      filteredTags = allTags.where((tag) {
        final matchesName = tag.tagName.toLowerCase().contains(query);
        final matchesLabel = tag.labels.any((l) => l.toLowerCase().contains(query));
        return matchesName || matchesLabel;
      }).toList();
    }
    if (mounted) setState(() {});
  }

  void _cycleSortMode() {
    sortMode = PinnedTagsSortMode.values[(sortMode.index + 1) % PinnedTagsSortMode.values.length];
    _applySorting();
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

  Future<void> _deleteTag(PinnedTag tag) async {
    await showUnpinTagDialog(
      context,
      tag.tagName,
      tag,
      () {
        allTags.removeWhere((t) => t.id == tag.id);
        _applyFilter();
        hasChanges = true;
      },
    );
  }

  Future<void> _editTagLabels(PinnedTag tag) async {
    // Doujin pins (sentinel id) have no labels to edit.
    if (tag.id == -1) return;
    // Collect all unique labels from all tags
    final existingLabels = <String>{};
    for (final t in allTags) {
      existingLabels.addAll(t.labels);
    }
    final sortedLabels = existingLabels.toList()..sort();

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => EditLabelsDialog(
        currentLabels: tag.labels,
        existingLabels: sortedLabels,
      ),
    );

    if (result != null) {
      await settingsHandler.dbHandler.updatePinnedTagLabels(tag.id, result);

      // Update local state
      final index = allTags.indexWhere((t) => t.id == tag.id);
      if (index != -1) {
        allTags[index] = allTags[index].copyWith(labels: result, clearLabels: result.isEmpty);
      }
      _applyFilter();
      hasChanges = true;
    }
  }

  Future<void> _openReorderDialog() async {
    // Doujin pins keep their pin order; the reorder dialog writes to the DB.
    if (allTags.any((t) => t.id == -1)) return;
    final result = await showPinnedTagsReorderDialog(context, allTags);
    if (result == true) {
      hasChanges = true;
      await init();
    }
  }

  Future<void> _addManualTag() async {
    final existingLabels = allTags.expand((t) => t.labels).toSet().toList()..sort();

    final result = await showModalBottomSheet<ManualPinTagDialogResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ManualPinTagDialog(
        currentBooru: widget.currentBooru,
        existingLabels: existingLabels,
      ),
    );

    if (result != null) {
      if (DoujinDataHandler.isDoujinBooru(widget.currentBooru)) {
        DoujinDataHandler.instance.addPin(
          result.tagName,
          widget.currentBooru,
          global: !result.pinForCurrentBooru,
        );
      } else {
        await settingsHandler.dbHandler.addPinnedTag(
          result.tagName,
          booruType: result.pinForCurrentBooru ? widget.currentBooru.type?.name : null,
          booruName: result.pinForCurrentBooru ? widget.currentBooru.name : null,
          labels: result.labels,
        );
      }
      hasChanges = true;
      await init();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.loc.pinnedTags.pinnedTags,
                      style: context.theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${allTags.length}',
                    style: context.theme.textTheme.titleSmall?.copyWith(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(hasChanges),
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
            // Search and actions bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 4,
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: context.loc.search,
                        prefixIcon: const Icon(Symbols.search_rounded),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Symbols.clear_rounded),
                                onPressed: searchController.clear,
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
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
                  if (allTags.length > 1)
                    IconButton(
                      onPressed: _openReorderDialog,
                      icon: const Icon(Symbols.reorder_rounded),
                      tooltip: context.loc.pinnedTags.reorder,
                    ),
                  IconButton(
                    onPressed: _addManualTag,
                    icon: const Icon(Symbols.add_rounded),
                    tooltip: context.loc.pinnedTags.addTagManually,
                  ),
                ],
              ),
            ),
            // Tags list
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredTags.isEmpty
                  ? Center(
                      child: Text(
                        searchController.text.isNotEmpty
                            ? context.loc.pinnedTags.noTagsMatchSearch
                            : context.loc.pinnedTags.noPinnedTagsYet,
                        style: context.theme.textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filteredTags.length,
                      itemBuilder: (context, index) {
                        final pinnedTag = filteredTags[index];
                        final tagColor = tagHandler.colourForDisplay(pinnedTag.tagName, widget.currentBooru);
                        final bool isMultiword = pinnedTag.tagName.split(' ').length > 1;

                        final scopeText = pinnedTag.isGlobal ? null : '${pinnedTag.booruName ?? ''} '.trim();
                        final labelText = pinnedTag.labels.isNotEmpty ? pinnedTag.labels.join(', ') : null;
                        final List<String> subtitleParts = [
                          ?scopeText,
                          if (labelText != null && labelText.isNotEmpty) '[$labelText]',
                        ];

                        return ListTile(
                          leading: pinnedTag.isGlobal
                              ? null
                              : BooruFavicon(
                                  settingsHandler.booruList.value.firstWhere(
                                    (b) =>
                                        b.type == pinnedTag.booruType &&
                                        (b.type?.isFavouritesOrDownloads == true || b.name == pinnedTag.booruName),
                                    orElse: Booru.unknown,
                                  ),
                                ),
                          title: Text(
                            isMultiword ? pinnedTag.tagName : pinnedTag.tagName.replaceAll('_', ' '),
                            style: TextStyle(color: tagColor),
                          ),
                          subtitle: Text(
                            style: context.theme.textTheme.bodySmall,
                            subtitleParts.join(''),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  pinnedTag.labels.isNotEmpty ? Symbols.label_rounded : Symbols.label_rounded,
                                  size: 20,
                                ),
                                tooltip: context.loc.pinnedTags.editLabels,
                                onPressed: () => _editTagLabels(pinnedTag),
                              ),
                              IconButton(
                                icon: const Icon(Symbols.delete_rounded),
                                tooltip: context.loc.pinnedTags.unpin,
                                onPressed: () => _deleteTag(pinnedTag),
                              ),
                            ],
                          ),
                          onTap: () {
                            widget.onTagTap(pinnedTag.tagName);
                            Navigator.of(context).pop(hasChanges);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
