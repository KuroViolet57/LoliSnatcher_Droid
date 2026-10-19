part of '../main_search_query_editor_page.dart';

class SuggestionsMainContent extends StatefulWidget {
  const SuggestionsMainContent({
    required this.onMetatagSelect,
    required this.onTagTap,
    this.onInsertTerm,
    this.booru,
    this.hideHistory = false,
    this.hidePopular = false,
    this.hidePinned = false,
    this.queryText,
    this.onQueryReplaced,
    super.key,
  });

  final void Function(AddMetatagBottomSheetResult result) onMetatagSelect;
  final void Function(String tag) onTagTap;

  /// Where a term picked in the tag builder (inside the Metatags card) goes.
  final void Function(String term)? onInsertTerm;

  /// The source the Metatags card builds for; null follows the current tab.
  final Booru? booru;
  final bool hideHistory;
  final bool hidePopular;
  final bool hidePinned;

  /// The whole query as it stands, and where a rewritten one goes: the
  /// doujin Filters card (r37) reads and replaces terms in it.
  final String Function()? queryText;
  final void Function(String query)? onQueryReplaced;

  @override
  State<SuggestionsMainContent> createState() => _SuggestionsMainContentState();
}

class _SuggestionsMainContentState extends State<SuggestionsMainContent> with _EditorSourceMixin {
  final ScrollController scrollController = ScrollController();

  @override
  Booru? get ownBooru => widget.booru;

  final GlobalKey<_PinnedTagsBlockState> _pinnedTagsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bool isReverse = SettingsHandler.instance.useTopSearchbarInput;

    // Ordered by how often each section is actually reached for:
    // recent searches first, then the user's own pinned tags, then
    // site-wide popular tags, then the metatags, then the tag builder.
    // r41: History, Pinned tags and Popular tags are Modular UI switches
    // (off by default) for every source, boorus and doujins alike; r37 hid
    // them on doujin sources only. A switched-off block is never built.
    // Any source that declares filters shows them (r40: FurAffinity too).
    // r43: booru sources show their site's own sort/order and rating choices
    // (a Modular UI switch), with the source's saved defaults checked.
    final DoujinFilterSpec? siteFilters = sourceHandler.hasReader || ModularUi.isOn(ModularUi.searchSiteFilters) ? sourceHandler.siteFilters : null;
    final DoujinFilterSpec? filters = widget.queryText != null && widget.onQueryReplaced != null && siteFilters != null
        ? SourceSettingsHandler.withDefaults(siteFilters, SourceSettingsHandler.instance.settingsFor(sourceBooru).defaultFilters ?? '')
        : null;
    List<Widget> blocks = [
      if (filters != null)
        DoujinFiltersBlock(
          spec: filters,
          query: widget.queryText!(),
          onQueryChanged: (String q) {
            widget.onQueryReplaced!(q);
            setState(() {});
          },
        ),
      if (!widget.hideHistory && ModularUi.isOn(ModularUi.searchHistory))
        HistoryBlock(
          delay: const Duration(milliseconds: 10),
          onTagApply: widget.onTagTap,
        ),
      //
      if (!widget.hidePinned && ModularUi.isOn(ModularUi.searchPinned))
        PinnedTagsBlock(
          key: _pinnedTagsKey,
          onTagTap: widget.onTagTap,
          onTagLongTap: (tagName, pinnedTag) async {
            await showUnpinTagDialog(context, tagName, pinnedTag, () {});
            await _pinnedTagsKey.currentState?.init();
          },
        ),
      //
      if (!widget.hidePopular && ModularUi.isOn(ModularUi.searchPopular))
        PopularTagsBlock(
          onTagTap: widget.onTagTap,
          delay: const Duration(milliseconds: 20),
        ),
      //
      MetatagsBlock(
        onSelect: widget.onMetatagSelect,
        booru: widget.booru,
      ),
      //
      if (widget.onInsertTerm != null)
        TagBuilderBlock(
          booru: widget.booru,
          onInsertTerm: widget.onInsertTerm!,
        ),
      //
      const SizedBox(height: 16),
    ];

    if (isReverse) {
      blocks = blocks.reversed.toList();
    }

    return Column(
      spacing: 10,
      children: blocks,
    );
  }
}

/// Card wrapper that gives each query-editor section (history, pinned,
/// popular, metatags) its own visually distinct rounded surface, so the
/// page reads as organized groups instead of one continuous wall of chips.
class SearchSectionCard extends StatelessWidget {
  const SearchSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.theme.dividerColor.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}
