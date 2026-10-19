part of '../main_search_query_editor_page.dart';

class PopularTagsBlock extends StatefulWidget {
  const PopularTagsBlock({
    required this.onTagTap,
    this.delay = Duration.zero,
    super.key,
  });

  final void Function(String tag) onTagTap;
  final Duration delay;

  @override
  State<PopularTagsBlock> createState() => _PopularTagsBlockState();
}

class _PopularTagsBlockState extends State<PopularTagsBlock> {
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;
  final scrollController = ScrollController();

  List<TagSuggestion> popularTags = [];
  bool loading = true;
  bool failed = false;
  CancelToken? cancelToken;

  @override
  void initState() {
    super.initState();

    Future.delayed(widget.delay, loadPopularTags);
  }

  Future<void> loadPopularTags() async {
    if (!searchHandler.currentBooruHandler.hasTagSuggestions) {
      loading = false;
      if (mounted) setState(() {});
      return;
    }

    loading = true;
    failed = false;
    if (mounted) setState(() {});

    // TODO: Replace with actual popular tags API
    // For now, loads results from empty query
    cancelToken?.cancel();
    cancelToken = CancelToken();
    final res = await searchHandler.currentBooruHandler.getTagSuggestions(
      '',
      cancelToken: cancelToken,
    );
    res.fold(
      (e) {
        loading = false;
        failed = true;
        if (mounted) setState(() {});
      },
      (data) {
        loading = false;
        failed = false;
        popularTags = data;
        if (mounted) setState(() {});

        for (final tag in popularTags.where((t) => !t.type.isNone)) {
          searchHandler.currentBooruHandler.addTagsWithType([tag.tag], tag.type);
        }
      },
    );
  }

  @override
  void dispose() {
    cancelToken?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!searchHandler.currentBooruHandler.hasTagSuggestions) {
      return const SizedBox.shrink();
    }

    return SearchSectionCard(
      child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Symbols.trending_up_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.loc.searchBar.popular,
                    style: context.theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 8),
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (failed)
                  IconButton(
                    onPressed: loadPopularTags,
                    icon: const Icon(Symbols.refresh_rounded),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (loading)
          const SizedBox(height: 50)
        else if (failed)
          SizedBox(
            height: 50,
            child: Center(
              child: TextButton.icon(
                onPressed: loadPopularTags,
                icon: const Icon(Symbols.refresh_rounded),
                label: Text(context.loc.retry),
              ),
            ),
          )
        else if (popularTags.isEmpty)
          SizedBox(
            height: 50,
            child: Center(
              child: Text(
                context.loc.searchBar.noSuggestionsFound,
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  color: context.theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
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
                  itemCount: popularTags.length,
                  itemBuilder: (BuildContext context, int index) {
                    final tag = popularTags[index];
                    final tagColor = tagHandler.colourForDisplay(
                      tag.tag,
                      searchHandler.currentBooru,
                      ownType: tag.type,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: RichText(
                          // richtext to align texts with different height
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: tag.tag.replaceAll('_', ' '),
                                style: context.theme.textTheme.labelLarge?.copyWith(
                                  color: tagColor,
                                ),
                              ),
                              if (tag.count > 0) ...[
                                TextSpan(text: ' ' * 3),
                                TextSpan(
                                  text: tag.count.toShortString(),
                                  style: context.theme.textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                        onPressed: () => widget.onTagTap(tag.tag),
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
