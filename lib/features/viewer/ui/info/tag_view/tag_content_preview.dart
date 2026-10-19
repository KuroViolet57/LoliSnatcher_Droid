part of '../tag_view.dart';

class TagContentPreview extends StatefulWidget {
  TagContentPreview({
    required this.tag,
    required this.boorus,
    required this.parentTab,
    this.readOnly = false,
    this.compact = false,
    this.compactTitle,
    this.onEffectiveTagChanged,
    this.hideWhenEmpty = false,
    this.header,
    this.suggestFor,
    this.suggestBoorus,
    this.showDoujinNewTabButton = true,
    super.key,
  }) : assert(
         boorus.isNotEmpty,
         'boorus must not be empty',
       );

  final String tag;
  final List<Booru> boorus;
  final SearchTab? parentTab;
  final bool readOnly;

  // Reports the strip's current effective query (base tag + any active
  // "videos / GIFs only" filter) so an enclosing widget's own "open in
  // new tab" button can carry the same filter the strip is showing.
  final ValueChanged<String>? onEffectiveTagChanged;

  // When true, the preview renders with minimal chrome (no booru dropdown,
  // no refresh/close icons, no "open in new tab" cluster) and eagerly
  // loads on init. Used inline inside the post-details drawer.
  final bool compact;
  // Optional override for the "Preview" header — e.g. "More from artist X".
  final String? compactTitle;

  // When true, the whole strip (and [header], if any) collapses to nothing
  // once the search comes back empty — used by the hub pages so boorus that
  // don't know the tag don't waste a "Nothing found" row of screen space.
  final bool hideWhenEmpty;

  // Optional widget rendered above the strip (e.g. the hub's favicon+name
  // row). Lives inside the preview so it collapses together with it when
  // [hideWhenEmpty] kicks in.
  final Widget? header;

  // When set, this strip stops being a single tag search and becomes the
  // blended suggestion feed for that post: several different facet queries
  // (character / franchise-minus-character / artist / act / style) fetched in
  // parallel and interleaved under per-facet quotas and per-artist,
  // per-character caps. See SuggestionHandler / SuggestionEngine.
  final BooruItem? suggestFor;

  /// r76: the query a new tab gets from this strip. A Suggested strip's
  /// placeholder tag means nothing to a site, so its tab carries the post
  /// for the same suggestion loader instead.
  static String newTabQuery({required String effectiveTag, BooruItem? suggestFor, String? filter, List<Booru>? boorus}) {
    if (suggestFor == null) return effectiveTag;
    return SuggestionHandler.queryFor(suggestFor, filter: filter ?? '', boorus: boorus);
  }

  // Cross-booru discovery: when set (and longer than one), the facets are
  // spread across these boorus with tag spellings translated per site.
  final List<Booru>? suggestBoorus;

  // Doujin strips replace the booru chip with a lone open-in-new-tab button.
  // Callers that render that action in their own section header (the detail
  // page puts it beside the chevron) set this false so the strip doesn't
  // spend a whole row on it.
  final bool showDoujinNewTabButton;

  // ── strip cell geometry ────────────────────────────────────────────────
  // The strip's height is DERIVED from the card height rather than written
  // out separately. The two had drifted: when the doujin strips' header row
  // was moved into the section title, the cards stayed at their old size and
  // the reclaimed height simply became a gap.

  static const double stripCardWidth = 148;

  /// Card height when the strip still carries a header row of its own (the
  /// booru source chip).
  static const double stripCardBaseHeight = 220;

  /// What the removed header row was worth. Strips without that row give the
  /// height back to the cards - a taller cover, since the cover is the
  /// flexible part of the cell and the title sits under it at a fixed size.
  static const double stripReclaimedHeight = 38;

  /// The ListView's own vertical padding inside the strip.
  static const double stripListPadding = 26;

  static double stripCardHeight({required bool hasHeaderRow}) =>
      hasHeaderRow ? stripCardBaseHeight : stripCardBaseHeight + stripReclaimedHeight;

  static double stripHeight({required bool hasHeaderRow}) =>
      stripCardHeight(hasHeaderRow: hasHeaderRow) + stripListPadding;

  @override
  State<TagContentPreview> createState() => _TagContentPreviewState();
}

class _TagContentPreviewState extends State<TagContentPreview> with AutomaticKeepAliveClientMixin {

  /// Whether this strip draws a header row of its own above the cards. Doujin
  /// strips whose host renders the open-in-new-tab action in its own section
  /// header (the detail page) have none, and the cards take that height back.
  bool get _stripHasHeaderRow => !(tab?.booruHandler.hasReader == true && !widget.showDoujinNewTabButton);

  // Hub strips stay alive off-screen: without this, scrolling a hub unmounts
  // strips and they re-fetch (and re-collapse) when scrolled back — janky.
  @override
  bool get wantKeepAlive => widget.compact;

  final settingsHandler = SettingsHandler.instance;
  final viewerHandler = ViewerHandler.instance;

  // Whether this strip has EVER shown results. A strip that once had posts
  // must not collapse just because a later filter cycle (e.g. gif on a booru
  // with no gifs for the tag) comes back empty.
  bool _hadResults = false;
  // Bounded auto-pagination: some boorus return thin/empty early pages for
  // rare tags — keep fetching a few pages until there's something to show.
  int _autoPagesFetched = 0;

  final AutoScrollController scrollController = AutoScrollController();

  Booru? selectedBooru;

  SearchTab? tab;
  bool loading = false;
  bool isLastPage = false;
  String errorString = '';

  // Cross-booru alias translation: when the strip is switched to a booru
  // other than the one the tag was written for, the tag is resolved to that
  // booru's own spelling via TagAliasResolver (e.g. `burnice` →
  // `burnice_white_(zenless_zone_zero)`). null = no translation active.
  String? resolvedQuery;
  Map<String, String> resolvedTerms = {};

  // Header "videos / GIFs only" filter. -1 means off; otherwise it's an
  // index into the active booru's `animatedPreviewFilters` list, which the
  // button cycles through (off → [0] → [1] → … → off).
  int animatedFilterIndex = -1;

  // The list of filter fragments for the active booru (e.g. a single
  // `animated|video` stop on OR boorus, or `video`/`webm`/`animated` on
  // realbooru). Falls back to a single OR stop before the handler exists.
  List<String> get _animatedFilters =>
      tab?.booruHandler.animatedPreviewFilters ?? const ['animated|video'];

  // The currently applied filter fragment, or null when off / out of range
  // (the latter can happen briefly after switching to a booru with a
  // shorter filter list).
  String? get _activeAnimatedFilter =>
      (animatedFilterIndex >= 0 && animatedFilterIndex < _animatedFilters.length)
      ? _animatedFilters[animatedFilterIndex]
      : null;

  // The actual query sent to the booru handler — `widget.tag` (translated to
  // the selected booru's spelling when a resolution is active) plus any
  // per-strip filter the user toggled in the header.
  String get _effectiveTag {
    final String base = resolvedQuery ?? widget.tag;
    final filter = _activeAnimatedFilter;
    return filter == null ? base : '$base $filter';
  }

  // The booru this strip's tag was originally written for.
  Booru? get _originBooru =>
      widget.parentTab?.selectedBooru.value ?? (widget.boorus.isNotEmpty ? widget.boorus.first : null);

  // Translates the tag for the selected booru when it differs from the origin
  // booru. Failures (or nothing to translate) leave the original query.
  Future<void> _maybeResolveAliases() async {
    resolvedQuery = null;
    resolvedTerms = {};
    final Booru? origin = _originBooru;
    final Booru? target = selectedBooru;
    if (origin == null || target == null) return;
    if (origin.name == target.name && origin.type == target.type) return;
    try {
      final res = await TagAliasResolver.resolveQuery(widget.tag, target);
      if (res.changed) {
        resolvedQuery = res.query;
        resolvedTerms = res.perTerm;
      }
    } catch (_) {}
  }

  // Whether the booru currently powering this strip understands
  // cross-booru OR (so we can collapse the cycle to a single
  // "animated|video" stop instead of stepping through both).
  // Tooltip describing the current filter state and what the next tap does.
  String get _animatedButtonTooltip {
    final filters = _animatedFilters;
    final active = _activeAnimatedFilter;
    if (active == null) {
      // Off → first tap applies filters[0]. Label it for clarity.
      final first = filters.isNotEmpty ? filters.first : 'animated|video';
      return first.contains('|') ? 'Videos / GIFs only' : 'Filter: $first';
    }
    final bool isLast = animatedFilterIndex >= filters.length - 1;
    final String label = active.contains('|') ? 'videos / GIFs' : active;
    return isLast ? 'Filter: $label — tap to clear' : 'Filter: $label — tap for next';
  }

  final ValueNotifier<int> viewedIndex = ValueNotifier(-1);

  bool get isSingleBooru => widget.boorus.length == 1;

  final String previewId = const Uuid().v4();

  @override
  void initState() {
    super.initState();

    viewerHandler.addTagPreview(
      widget.parentTab?.id,
      previewId,
      widget.tag,
    );

    if (isSingleBooru) {
      selectedBooru = widget.boorus.first;
    }

    // Compact mode is used inline (no booru dropdown to wait on), so kick
    // off the first fetch as soon as the widget mounts.
    if (widget.compact && selectedBooru != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadPreview();
      });
    }
  }

  Future<void> loadPreview({
    bool refresh = false,
    bool retry = false,
  }) async {
    if (selectedBooru == null) {
      return;
    }

    if (refresh || tab == null) {
      _autoPagesFetched = 0;
      await _maybeResolveAliases();
      if (!mounted) return;
      tab = SearchTab(
        selectedBooru!,
        null,
        _effectiveTag,
        customHandler: widget.suggestFor == null
            ? null
            : SuggestionHandler(
                selectedBooru!,
                30,
                sourceItem: widget.suggestFor!,
                targetBoorus: widget.suggestBoorus,
                // The header's videos/GIFs toggle. Suggestions are built from
                // the source post, not from _effectiveTag, so without this the
                // toggle was assembled into a string nothing ever read.
                extraFilter: _activeAnimatedFilter ?? '',
              ),
      );
      // Preview strips are throwaway mini-searches. Don't let them write the
      // previewed booru's tag types into the shared store — otherwise
      // previewing a tag on a different booru re-colours the current booru's
      // tags and the resulting rebuild resets this strip's selected booru.
      tab!.booruHandler.storeTagsGlobally = false;
      loading = false;
      isLastPage = false;
      errorString = '';
      setState(() {});
    }

    if (loading) {
      return;
    }

    if (retry) {
      errorString = '';
      tab!.booruHandler.errorString = '';

      isLastPage = false;
      tab!.booruHandler.locked = false;
      tab!.booruHandler.pageNum--;
    }

    if (isLastPage || errorString.isNotEmpty) {
      return;
    }

    if (tab!.booruHandler.locked == false) {
      loading = true;
      tab!.booruHandler.pageNum++;
    }
    setState(() {});

    await tab!.booruHandler.search(_effectiveTag, null);
    // r77: the strip may be gone by now (a closed hub page, 19 Sep 14:23:53:
    // "Null check operator used on a null value" in setState).
    if (!mounted) return;

    if (tab!.booruHandler.locked && !isLastPage) {
      isLastPage = true;
      setState(() {});
    }

    if (tab!.booruHandler.errorString.isNotEmpty) {
      errorString = tab!.booruHandler.errorString;
      if (!mounted) return;
      setState(() {});
    }

    if (tab!.booruHandler.totalCount.value == 0) {
      unawaited(tab!.booruHandler.searchCount(_effectiveTag));
    }

    if (tab!.booruHandler.filteredFetched.isNotEmpty) {
      _hadResults = true;
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      loading = false;
      setState(() {});
    });
    if (!mounted) return;
    setState(() {});

    // Thin/empty early pages (rare tags on some boorus): auto-fetch a few
    // more pages so the strip doesn't claim "nothing found" (or show 3
    // thumbs) when the tag actually has posts further in.
    final BooruHandler handlerRef = tab!.booruHandler;
    if (!isLastPage &&
        errorString.isEmpty &&
        handlerRef.filteredFetched.length < 10 &&
        _autoPagesFetched < 4) {
      _autoPagesFetched++;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && tab?.booruHandler == handlerRef) {
          loadPreview();
        }
      });
    }
  }

  Future<void> onPreviewTap(int index) async {
    // Doujin strips: a card tap opens the DETAIL PAGE, never the old image
    // viewer flow.
    if (tab!.booruHandler.hasReader) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DoujinDetailPage(tab: tab!, index: index)),
      );
      return;
    }
    viewedIndex.value = index;
    final viewerKey = GlobalKey(debugLabel: 'viewer-${tab!.tags.replaceAll(' ', '_')}');
    ViewerHandler.instance.addViewer(viewerKey);
    await Navigator.of(context).push(
      PageRouteBuilder(
        // r77: named like the feed's viewer, so its close is logged too.
        settings: const RouteSettings(name: ViewerCloseObserver.viewerRoute),
        pageBuilder: (_, _, _) => GalleryViewPage(
          key: viewerKey,
          tab: tab!,
          initialIndex: index,
          canSelect: false,
          readOnly: widget.readOnly,
          onPageChanged: (page) async {
            viewedIndex.value = page;
            await scrollController.scrollToIndex(
              page,
              duration: const Duration(milliseconds: 10),
              preferPosition: AutoScrollPosition.begin,
            );
          },
        ),
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        barrierColor: Colors.black26,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return const ZoomPageTransitionsBuilder().buildTransitions(
            MaterialPageRoute(
              builder: (_) => const SizedBox.shrink(),
            ),
            context,
            animation,
            secondaryAnimation,
            child,
          );
        },
      ),
    );
    viewedIndex.value = -1;
  }

  Future<void> onPreviewDoubleTap(int index) async {
    if (widget.readOnly) return;

    await tab?.toggleItemFavourite(index);
  }

  Future<void> onPreviewSecondaryTap(int index) async {
    if (tab == null) {
      return;
    }

    final BooruItem item = tab!.booruHandler.filteredFetched[index];
    await Clipboard.setData(ClipboardData(text: Uri.encodeFull(item.fileURL)));
    FlashElements.showSnackbar(
      duration: const Duration(seconds: 2),
      title: Text(context.loc.tagView.copiedFileURL, style: const TextStyle(fontSize: 20)),
      content: Text(Uri.encodeFull(item.fileURL), style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.content_copy_rounded,
      sideColor: Colors.green,
    );
  }

  Future<void> showTagPreviewsListDialog() async {
    if (widget.parentTab == null) return;

    await showDialog(
      context: context,
      builder: (_) => _TagPreviewsListDialog(widget.parentTab!.id),
    );
  }

  @override
  void dispose() {
    viewerHandler.removeTagPreview(
      widget.parentTab?.id,
      previewId,
    );
    super.dispose();
  }

  // Opens the LoliDropdown booru picker programmatically — used by the
  // chip-arrow button. Mirrors what SettingsBooruDropdown did before.
  Future<void> _openBooruPicker(BuildContext context) async {
    final dropdown = LoliDropdown<Booru?>(
      value: selectedBooru,
      onChanged: (v) {
        setState(() {
          selectedBooru = v;
        });
        loadPreview(refresh: true);
      },
      items: [...settingsHandler.booruList],
      labelText: context.loc.booru,
      itemBuilder: (b) => b == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TabBooruSelectorItem(booru: b),
            ),
      selectedItemBuilder: (b) => b == null
          ? Text(context.loc.tagView.selectBooruToLoad)
          : TabBooruSelectorItem(booru: b),
      searchable: settingsHandler.booruList.length > 5,
      searchCheck: (s, b) =>
          (b?.name?.toLowerCase().contains(s) ?? true) ||
          (b?.type?.name.toLowerCase().contains(s) ?? true),
    );
    await dropdown.showDialog(context);
  }

  // Advances the "videos / GIFs only" filter to the next stop in the
  // active booru's `animatedPreviewFilters` list and reloads the strip.
  // Walks off → [0] → [1] → … → off. A single-entry list (most OR boorus)
  // behaves as a plain on/off toggle; realbooru steps through
  // video → webm → animated.
  void _toggleAnimatedOnly() {
    setState(() {
      final int next = animatedFilterIndex + 1;
      animatedFilterIndex = next < _animatedFilters.length ? next : -1;
    });
    widget.onEffectiveTagChanged?.call(_effectiveTag);
    loadPreview(refresh: true);
  }

  // The "open this tag in a new tab" action — extracted so it can be reused
  // from the chip's icon button.
  String get _newTabQuery => TagContentPreview.newTabQuery(
    effectiveTag: _effectiveTag,
    suggestFor: widget.suggestFor,
    filter: _activeAnimatedFilter,
    boorus: widget.suggestBoorus,
  );

  void _openInNewTab(BuildContext context) {
    final defaultMode = settingsHandler.defaultTabAddMode == 'next' ? TabAddMode.next : TabAddMode.end;
    SearchHandler.instance.addTabByString(
      _newTabQuery,
      customBooru: selectedBooru,
      addMode: defaultMode,
      group: SearchHandler.inheritGroup,
    );

    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.tagView.addedNewTab,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(_effectiveTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
      primaryActionBuilder: (context, controller) {
        return Row(
          children: [
            IconButton(
              onPressed: () {
                ServiceHandler.vibrate();
                if (settingsHandler.appMode.value.isMobile) {
                  NavigationTrace.closing('new tab notice: go to the tab', () => Navigator.of(context).popUntil((r) => r.isFirst));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  SearchHandler.instance.changeTabIndex(
                    SearchHandler.instance.tabs.length - 1,
                  );
                });
                controller.dismiss();
              },
              icon: Icon(
                Symbols.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => controller.dismiss(),
              icon: Icon(Symbols.close_rounded, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openInNewTabLongPress(BuildContext context) async {
    await ServiceHandler.vibrate();

    final TabAddMode? chosenMode = await showDialog<TabAddMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Open new tab'),
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Symbols.vertical_align_bottom_rounded),
                title: const Text('Open at end of tab list'),
                onTap: () => Navigator.of(dialogContext).pop(TabAddMode.end),
              ),
              ListTile(
                leading: const Icon(Symbols.tab_rounded),
                title: const Text('Open next to current tab'),
                onTap: () => Navigator.of(dialogContext).pop(TabAddMode.next),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (chosenMode == null) return;

    SearchHandler.instance.addTabByString(
      _newTabQuery,
      customBooru: selectedBooru,
      addMode: chosenMode,
      switchToNew: false,
      group: SearchHandler.inheritGroup,
    );

    if (!context.mounted) return;
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.tagView.addedNewTab,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(_effectiveTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );
  }

  /// Boorusama-style chip that replaces the old preview header + standalone
  /// booru dropdown. Layout: favicon, booru name, video filter, new-tab,
  /// picker arrow. The chip surface is non-tappable — the arrow is the only
  /// way to open the booru picker, so the inline action buttons aren't
  /// swallowed by a wrapping button.
  /// The rehomed open-in-new-tab action for doujin strips — the only piece
  /// of the booru chip that still makes sense there.
  Widget _buildDoujinStripNewTabButton(BuildContext context) {
    final hasTabResult = SearchHandler.instance.hasTabWithTag(
      _effectiveTag,
      customBooru: selectedBooru,
    );
    return IconButton(
      tooltip: 'Open in a new tab',
      visualDensity: VisualDensity.compact,
      icon: Stack(
        children: [
          const Icon(Symbols.fiber_new_rounded),
          if (hasTabResult.hasTagInAnyForm)
            Positioned(
              right: 0,
              top: 0,
              child: Icon(
                Symbols.circle_rounded,
                size: 6,
                color: hasTabResult.color(context),
              ),
            ),
        ],
      ),
      onPressed: () => _openInNewTab(context),
      onLongPress: () => _openInNewTabLongPress(context),
    );
  }

  Widget _buildBooruChip(BuildContext context) {
    final boo = selectedBooru;
    final theme = Theme.of(context);
    final hasTabResult = SearchHandler.instance.hasTabWithTag(
      _effectiveTag,
      customBooru: selectedBooru,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          if (boo != null) ...[
            BooruFavicon(boo),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                boo.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            // Alias translation indicator: this booru spells the tag
            // differently, show what the strip is actually searching.
            if (resolvedTerms.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '→ ${resolvedTerms.values.map((t) => t.replaceAll('_', ' ')).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ] else
            Flexible(
              child: Text(
                context.loc.tagView.selectBooruToLoad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(width: 4),
          // Hidden when the booru has no way to express "animated" — an empty
          // filter list means the site profile checked and there is nothing
          // real to search for, so the button would only append dead tags.
          if (_animatedFilters.isNotEmpty)
          IconButton(
            tooltip: _animatedButtonTooltip,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _activeAnimatedFilter == null ? Symbols.movie_rounded : Symbols.movie_rounded,
              color: _activeAnimatedFilter == null ? null : theme.colorScheme.secondary,
            ),
            onPressed: _toggleAnimatedOnly,
          ),
          IconButton(
            tooltip: 'Open in a new tab',
            visualDensity: VisualDensity.compact,
            icon: Stack(
              children: [
                const Icon(Symbols.fiber_new_rounded),
                if (hasTabResult.hasTagInAnyForm)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Symbols.circle_rounded,
                      size: 6,
                      color: hasTabResult.color(context),
                    ),
                  ),
              ],
            ),
            onPressed: () => _openInNewTab(context),
            onLongPress: () => _openInNewTabLongPress(context),
          ),
          IconButton(
            tooltip: 'Pick booru',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.arrow_drop_down_rounded),
            onPressed: () => _openBooruPicker(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Search finished (not loading, no error) with zero results — the tag
    // simply doesn't exist on this booru. With hideWhenEmpty the whole strip
    // (header included) collapses instead of wasting a "Nothing found" row.
    final bool isKnownEmpty =
        tab != null && !loading && errorString.isEmpty && tab!.booruHandler.filteredFetched.isEmpty;
    if (widget.hideWhenEmpty && isKnownEmpty && !_hadResults) {
      return const AnimatedSize(
        duration: Duration(milliseconds: 200),
        child: SizedBox.shrink(),
      );
    }

    final Widget strip = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: tab == null
            ? (widget.compact
                  // Compact path: auto-loads in initState, so this "no tab"
                  // state is just a brief one-frame placeholder. Keep it
                  // small and label-less so it doesn't conflict with the
                  // section header rendered above.
                  ? const SizedBox(height: 32)
                  : ListTile(
                leading: Icon(
                  Symbols.search_rounded,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(widget.compactTitle ?? context.loc.tagView.preview),
                trailing: widget.parentTab == null
                    ? null
                    : IconButton(
                        icon: const Icon(Symbols.list_rounded),
                        onPressed: showTagPreviewsListDialog,
                      ),
                subtitle: isSingleBooru
                    ? null
                    : Container(
                        width: context.mediaSize.width,
                        height: 52,
                        margin: const EdgeInsets.only(top: 8),
                        child: SettingsBooruDropdown(
                          title: context.loc.booru,
                          placeholder: context.loc.tagView.selectBooruToLoad,
                          value: selectedBooru,
                          items: isSingleBooru ? settingsHandler.booruList : widget.boorus,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            selectedBooru = value;
                            loadPreview(refresh: true);
                          },
                          titleAsLabel: true,
                          drawBottomBorder: false,
                        ),
                      ),
                onTap: isSingleBooru ? loadPreview : null,
              ))
            : ((tab!.booruHandler.filteredFetched.isEmpty && (loading || errorString.isNotEmpty))
                  ? ListTile(
                      leading: Icon(
                        loading ? Symbols.search_rounded : Symbols.restart_alt_rounded,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      trailing: loading
                          ? const CircularProgressIndicator()
                          : (widget.parentTab == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Symbols.list_rounded),
                                    onPressed: showTagPreviewsListDialog,
                                  )),
                      title: loading
                          ? Text(context.loc.tagView.previewIsLoading)
                          : Text(context.loc.tagView.failedToLoadPreview),
                      subtitle: errorString.isNotEmpty ? Text(context.loc.tagView.tapToTryAgain) : null,
                      onTap: errorString.isNotEmpty ? () => loadPreview(refresh: true) : null,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Boorusama-style chip — replaces the old Preview
                        // header + standalone booru dropdown. Shown for BOTH
                        // compact (tag-chevron / "More from artist X") and
                        // non-compact paths, because the original booru
                        // dropdown was present in both too.
                        // Doujin strips are source-locked (related/recommend
                        // only exist on their own site), so the source-picker
                        // chip is noise there — keep just the open-in-new-tab
                        // button, rehomed to the strip's corner.
                        if (tab!.booruHandler.hasReader)
                          // ...unless the host renders it in its own header
                          // (see showDoujinNewTabButton), in which case the
                          // strip adds no vertical space at all here.
                          widget.showDoujinNewTabButton
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildDoujinStripNewTabButton(context),
                                  ),
                                )
                              : const SizedBox.shrink()
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                            child: _buildBooruChip(context),
                          ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: TagContentPreview.stripHeight(hasHeaderRow: _stripHasHeaderRow),
                          width: MediaQuery.sizeOf(context).width,
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: (notif) {
                              final bool isNotAtStart = notif.metrics.pixels > 0;
                              final bool isAtOrNearEdge =
                                  notif.metrics.atEdge ||
                                  notif.metrics.pixels >
                                      (notif.metrics.maxScrollExtent - (notif.metrics.extentInside * 2));

                              if (widget.compact) {
                                // In the inline / compact strip: only paginate
                                // when the user actively scrolls near the right
                                // edge of the horizontal list. The original
                                // "screen not filled → load more" branch would
                                // fire infinitely because a horizontal strip
                                // on a phone rarely overflows the viewport.
                                if (!loading && isNotAtStart && isAtOrNearEdge) {
                                  loadPreview();
                                }
                                return true;
                              }

                              final bool isScreenFilled =
                                  notif.metrics.extentBefore != 0 || notif.metrics.extentAfter != 0;

                              if (!loading) {
                                if (!isScreenFilled || (isNotAtStart && isAtOrNearEdge)) {
                                  loadPreview();
                                }
                              }

                              return true;
                            },
                            child: Scrollbar(
                              controller: scrollController,
                              interactive: true,
                              thickness: 6,
                              thumbVisibility: true,
                              child: Listener(
                                onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
                                child: FadingEdgeScrollView.fromScrollView(
                                  child: ListView.builder(
                                    controller: scrollController,
                                    shrinkWrap: true,
                                    scrollDirection: Axis.horizontal,
                                    itemCount: tab!.booruHandler.filteredFetched.isEmpty
                                        ? 1
                                        : tab!.booruHandler.filteredFetched.length +
                                              ((loading || errorString.isNotEmpty) ? 1 : 0),
                                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                                    itemBuilder: (context, index) {
                                      if (tab!.booruHandler.filteredFetched.isEmpty) {
                                        return Center(
                                          child: Column(
                                            // mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Kaomoji(
                                                category: KaomojiCategory.indifference,
                                                style: TextStyle(fontSize: 24),
                                              ),
                                              Text(
                                                context.loc.nothingFound,
                                                style: const TextStyle(fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      if (loading && index == tab!.booruHandler.filteredFetched.length) {
                                        return const Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 32),
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      }

                                      if (errorString.isNotEmpty && index == tab!.booruHandler.filteredFetched.length) {
                                        return Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            margin: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surface,
                                              border: Border.all(color: Theme.of(context).dividerColor),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              spacing: 8,
                                              children: [
                                                const Icon(
                                                  Symbols.error_rounded,
                                                  size: 30,
                                                ),
                                                Text(
                                                  context.loc.tagView.failedToLoadPreviewPage,
                                                  style: const TextStyle(fontSize: 16),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    loadPreview(retry: true);
                                                  },
                                                  child: Text(context.loc.tagView.tryAgain),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      return Material(
                                        color: Colors.transparent,
                                        child: Container(
                                          padding: const EdgeInsets.only(right: 8),
                                          height: TagContentPreview.stripCardHeight(
                                            hasHeaderRow: _stripHasHeaderRow,
                                          ),
                                          width: TagContentPreview.stripCardWidth,
                                          child: ValueListenableBuilder(
                                            valueListenable: viewedIndex,
                                            builder: (context, viewedIndex, _) {
                                              return ThumbnailCardBuild(
                                                index: index,
                                                item: tab!.booruHandler.filteredFetched[index],
                                                handler: tab!.booruHandler,
                                                scrollController: scrollController,
                                                isHighlighted: viewedIndex == index,
                                                selectable: false,
                                                // Strips render the compact
                                                // doujin cell: cover + badge
                                                // + title, no tag strip.
                                                stripMode: true,
                                                onTap: onPreviewTap,
                                                onDoubleTap: onPreviewDoubleTap,
                                                // Doujin strips get the full item context menu; other
                                                // sources keep the old no-op (select doesn't fit here).
                                                onLongPress: tab!.booruHandler.hasReader
                                                    ? (i) => showDoujinItemMenu(context, tab: tab!, index: i)
                                                    : null,
                                                onSecondaryTap: onPreviewSecondaryTap,
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    )),
      ),
    );

    if (widget.header == null) {
      return strip;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.header!,
        strip,
      ],
    );
  }
}

class _TagPreviewsListDialog extends StatelessWidget {
  const _TagPreviewsListDialog(
    this.tabId,
  );

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final viewerHandler = ViewerHandler.instance;
    final searchHandler = SearchHandler.instance;

    final list = viewerHandler.tagPreviewsHistory[tabId] ?? [];
    final controllers = List.generate(list.length, (_) => ScrollController());
    // scroll to end of each stack history item
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   for (final c in controllers) {
    //     c.jumpTo(c.position.maxScrollExtent);
    //   }
    // });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              //
              Text(
                context.loc.tagView.tagPreviews,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              //
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, entryIndex) {
                    final entry = list[list.length - entryIndex - 1];
                    final bool isActive = entry == list.last;
                    final bool isSecondsToLast = list.length > 1 && entry == list[list.length - 2];

                    if (entry.isEmpty) return const SizedBox.shrink();

                    bool matchesCurrentState = true;
                    final currentState = viewerHandler.currentTagPreviewState(tabId).map((e) => e.value).toList();
                    entry.forEachIndexed((i, e) {
                      if (i >= currentState.length || currentState[i] != e.value) {
                        matchesCurrentState = false;
                        return;
                      }
                    });

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isActive || isSecondsToLast)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              isActive ? context.loc.tagView.currentState : context.loc.tagView.history,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        //
                        Material(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            shape: Border(
                              top: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                            ),
                            trailing: (isActive || matchesCurrentState)
                                ? null
                                : IconButton(
                                    icon: const Icon(Symbols.history_rounded),
                                    onPressed: () async {
                                      Navigator.of(context).pop();

                                      final state = viewerHandler.currentTagPreviewState(tabId);

                                      entry.forEachIndexed((index, e) async {
                                        final tag = e.value;

                                        // skip if tag already in stack
                                        if (state.all((e) => e.value != tag)) {
                                          unawaited(
                                            showTagDialog(
                                              context: context,
                                              tag: tag,
                                              handler: searchHandler.currentBooruHandler,
                                              isHidden: tagHiddenForHandler(tag, searchHandler.currentBooruHandler),
                                              isMarked: tagMarkedForHandler(tag, searchHandler.currentBooruHandler),
                                              isInSearch:
                                                  searchHandler.searchTextController.text
                                                      .toLowerCase()
                                                      .split(' ')
                                                      .indexWhere(
                                                        (t) =>
                                                            t == tag.toLowerCase() ||
                                                            t == '-${tag.toLowerCase()}' ||
                                                            t == '~${tag.toLowerCase()}' ||
                                                            RegExp(
                                                              r'^(?:-|~)?\d+#(?:-|~)?' + tag.regexpEscape() + r'$',
                                                            ).hasMatch(t),
                                                      ) !=
                                                  -1,
                                              hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                              onUpdate: () {},
                                            ),
                                          );
                                          await Future.delayed(const Duration(milliseconds: 50));
                                        }
                                      });
                                    },
                                  ),
                            title: SizedBox(
                              height: 40,
                              width: double.maxFinite,
                              child: FadingEdgeScrollView.fromScrollView(
                                child: ListView(
                                  controller: controllers[entryIndex],
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  children: [
                                    ...entry.mapWithIndex(
                                      (e, i) {
                                        final tag = e.value;
                                        final bool isLast = i == entry.length - 1;

                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            MainSearchTagChip(
                                              tag: tag,
                                              booru: searchHandler.currentBooru,
                                              isSelected: isActive && isLast,
                                              onTap: () {
                                                if (isActive) {
                                                  // close everything up to this tag
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    // r79: stops at the viewer too - with this
                                                    // tag's dialog already gone it fell through
                                                    // to the feed.
                                                    NavigationTrace.closing(
                                                      'tag previews breadcrumb',
                                                      () => Navigator.of(context).popUntil(
                                                        (route) => NavigationTrace.tagDialogOrViewer(route, tag),
                                                      ),
                                                    );
                                                  });
                                                } else {
                                                  // open dialog for this tag
                                                  Navigator.of(context).pop();
                                                  unawaited(
                                                    showTagDialog(
                                                      context: context,
                                                      tag: tag,
                                                      handler: searchHandler.currentBooruHandler,
                                                      isHidden: tagHiddenForHandler(tag, searchHandler.currentBooruHandler),
                                                      isMarked: tagMarkedForHandler(tag, searchHandler.currentBooruHandler),
                                                      isInSearch:
                                                          searchHandler.searchTextController.text
                                                              .toLowerCase()
                                                              .split(' ')
                                                              .indexWhere(
                                                                (t) =>
                                                                    t == tag.toLowerCase() ||
                                                                    t == '-${tag.toLowerCase()}' ||
                                                                    t == '~${tag.toLowerCase()}' ||
                                                                    RegExp(
                                                                      r'^(?:-|~)?\d+#(?:-|~)?' +
                                                                          tag.regexpEscape() +
                                                                          r'$',
                                                                    ).hasMatch(t),
                                                              ) !=
                                                          -1,
                                                      hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                                      onUpdate: () {},
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                            if (!isLast)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 4),
                                                child: Icon(
                                                  Symbols.arrow_forward_rounded,
                                                  size: 14,
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              //
              ListTile(
                leading: Icon(
                  Symbols.cancel_rounded,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(context.loc.close),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              //
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
