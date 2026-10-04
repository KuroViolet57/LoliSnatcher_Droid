part of '../main_search_query_editor_page.dart';

class HistoryBlock extends StatefulWidget {
  const HistoryBlock({
    this.delay = Duration.zero,
    this.onTagApply,
    super.key,
  });

  final Duration delay;
  final void Function(String tag)? onTagApply;

  @override
  State<HistoryBlock> createState() => _HistoryBlockState();
}

class _HistoryBlockState extends State<HistoryBlock> {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;

  List<HistoryItem> history = [];
  bool loading = true;

  final scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    Future.delayed(widget.delay, init);
  }

  Future<void> init() async {
    loading = true;
    setState(() {});
    history = await SearchHistoryStore.latest();
    loading = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> showHistoryEntryActions(Widget row, HistoryItem entry, Booru? booru) async {
    await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      page: (_) {
        return SettingsBottomSheet(
          contentItems: [
            const SizedBox(width: double.maxFinite),
            Align(alignment: Alignment.center, child: row),
            const SizedBox(height: 10),
            Text(
              context.loc.history.lastSearchWithDate(date: formatDate(entry.timestamp)),
              textAlign: TextAlign.center,
            ),
            //
            const SizedBox(height: 20),
            if (widget.onTagApply != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onTagApply?.call(entry.searchText);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Symbols.add_rounded),
                  label: Text(context.loc.tabs.filters.apply),
                ),
              ),
            //
            ElevatedButton.icon(
              onPressed: () {
                if (booru != null) {
                  searchHandler.searchTextController.text = entry.searchText;
                  searchHandler.searchAction(entry.searchText, booru);
                } else {
                  FlashElements.showSnackbar(
                    title: Text(context.loc.history.unknownBooruType, style: const TextStyle(fontSize: 20)),
                    leadingIcon: Symbols.warning_amber_rounded,
                    leadingIconColor: Colors.red,
                    sideColor: Colors.red,
                  );
                  return;
                }

                Navigator.of(context).popUntil(ModalRoute.withName('/'));
              },
              icon: const Icon(Symbols.open_in_browser_rounded),
              label: Text(context.loc.open),
            ),
            //
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                if (booru != null) {
                  searchHandler.searchTextController.text = entry.searchText;
                  searchHandler.addTabByString(
                    entry.searchText,
                    customBooru: booru,
                    switchToNew: true,
                  );
                } else {
                  FlashElements.showSnackbar(
                    title: Text(context.loc.history.unknownBooruType, style: const TextStyle(fontSize: 20)),
                    leadingIcon: Symbols.warning_amber_rounded,
                    leadingIconColor: Colors.red,
                    sideColor: Colors.red,
                  );
                  return;
                }

                Navigator.of(context).popUntil(ModalRoute.withName('/'));
              },
              icon: const Icon(Symbols.add_circle_rounded),
              label: Text(context.loc.openInNewTab),
            ),
            //
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: entry.searchText));
                FlashElements.showSnackbar(
                  duration: const Duration(seconds: 2),
                  title: Text(context.loc.copied, style: const TextStyle(fontSize: 20)),
                  content: Text(entry.searchText, style: const TextStyle(fontSize: 16)),
                  leadingIcon: Symbols.content_copy_rounded,
                  sideColor: Colors.green,
                );
                Navigator.of(context).pop();
              },
              icon: const Icon(Symbols.content_copy_rounded),
              label: Text(context.loc.copy),
            ),
          ],
        );
      },
    ).open();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!settingsHandler.dbEnabled || (history.isEmpty && !loading)) {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Symbols.history_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.loc.searchBar.history,
                    style: context.theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    SettingsPageOpen(
                      context: context,
                      page: (_) => const HistoryList(),
                    ).open();
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
                itemCount: (history.isEmpty && loading) ? 1 : history.length,
                itemBuilder: (BuildContext context, int index) {
                  if (history.isEmpty) {
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

                  final item = history[index];
                  final booru = settingsHandler.booruList.value.firstWhere(
                    (b) =>
                        b.type == item.booruType &&
                        (b.type?.isFavouritesOrDownloads == true || b.name == item.booruName),
                    orElse: Booru.unknown,
                  );

                  const favIcon = Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Symbols.favorite_rounded,
                      color: Colors.red,
                      size: 16,
                    ),
                  );

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      avatar: BooruFavicon(booru),
                      onPressed: () => showHistoryEntryActions(
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BooruFavicon(booru),
                              const SizedBox(width: 8),
                              Flexible(child: Text(item.searchText)),
                              if (item.isFavourite) favIcon,
                            ],
                          ),
                        ),
                        item,
                        // A source that is gone (Booru.unknown) gets the
                        // "unknown booru type" notice, not a tab on nothing.
                        booru.name == null ? null : booru,
                      ),
                      label: Text(item.searchText),
                      onDeleted: item.isFavourite ? () {} : null,
                      deleteIcon: item.isFavourite ? favIcon : null,
                      deleteButtonTooltipMessage: '',
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
