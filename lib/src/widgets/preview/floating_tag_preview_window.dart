import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide ContextExt;
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/floating_preview_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/pages/tag_hub_page.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tag_alias_resolver.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

/// Renders every live floating preview window. Inserted once into the
/// navigator's root overlay by [FloatingPreviewHandler].
///
/// Windows whose owner route isn't on top stay mounted but [Offstage], so
/// their fetched results / scroll position / filters survive while the user
/// dives into a result and come back exactly as left when the route above
/// pops.
class FloatingPreviewOverlayStack extends StatelessWidget {
  const FloatingPreviewOverlayStack({super.key});

  @override
  Widget build(BuildContext context) {
    final handler = FloatingPreviewHandler.instance;

    return ListenableBuilder(
      listenable: handler,
      builder: (context, _) {
        if (handler.entries.isEmpty) {
          return const SizedBox.shrink();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in handler.entries)
              Offstage(
                key: ValueKey('floating-preview-${entry.id}'),
                offstage: !handler.isEntryVisible(entry),
                child: TickerMode(
                  enabled: handler.isEntryVisible(entry),
                  child: FloatingTagPreviewWindow(entry: entry),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Boorusama-style floating, draggable, resizable tag-preview window.
///
/// - drag the title bar to move, drag the bottom-right corner to resize;
///   the rect is persisted (as screen fractions, so rotation keeps it sane)
///   in settings.json — which also puts it in backup/restore.
/// - the grid paginates infinitely (scroll near the bottom loads the next
///   page), and tapping a result opens the full viewer which pages through
///   the same result set, auto-fetching more as the user swipes on.
/// - can be minimized into a small draggable pill.
class FloatingTagPreviewWindow extends StatefulWidget {
  const FloatingTagPreviewWindow({required this.entry, super.key});

  final FloatingPreviewEntry entry;

  @override
  State<FloatingTagPreviewWindow> createState() => _FloatingTagPreviewWindowState();
}

class _FloatingTagPreviewWindowState extends State<FloatingTagPreviewWindow> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  final AutoScrollController scrollController = AutoScrollController();
  final ValueNotifier<int> viewedIndex = ValueNotifier(-1);

  late Booru selectedBooru = widget.entry.booru;

  SearchTab? tab;
  bool loading = false;
  bool isLastPage = false;
  String errorString = '';

  // Header "videos / GIFs only" filter — same cycle semantics as the inline
  // strips: -1 = off, otherwise an index into animatedPreviewFilters.
  int animatedFilterIndex = -1;

  bool minimized = false;
  Offset? pillPos;

  // Extra tags typed into the window's own search box, AND-ed onto the tag
  // the window was opened for.
  final TextEditingController extraTagsController = TextEditingController();
  String extraTags = '';

  // In-window booru picker panel. Rendered inside the window's own Stack (not
  // as a navigator dialog) so it floats ABOVE the window instead of opening
  // behind it in the page below the overlay.
  bool booruPickerOpen = false;
  final TextEditingController booruFilterController = TextEditingController();

  // Window rect as fractions of the screen (position + size), so the stored
  // value stays meaningful across rotations and devices.
  double? fx, fy, fw, fh;

  static const double _minWidthPx = 230;
  static const double _minHeightPx = 280;

  List<String> get _animatedFilters => tab?.booruHandler.animatedPreviewFilters ?? const ['animated|video'];

  String? get _activeAnimatedFilter =>
      (animatedFilterIndex >= 0 && animatedFilterIndex < _animatedFilters.length)
      ? _animatedFilters[animatedFilterIndex]
      : null;

  // Cross-booru tag unification: when the previewed tag returns nothing on the
  // selected booru, it's re-resolved to that booru's own spelling (e.g.
  // burnice_white -> burnice_white_(zenless_zone_zero)) and the preview retried.
  String? _resolvedBaseTag;
  bool _aliasTried = false;
  String? _aliasNote;

  String get _baseTag {
    final String core = _resolvedBaseTag ?? widget.entry.tag;
    final String extra = extraTags.trim();
    return extra.isEmpty ? core : '$core $extra';
  }

  String get _effectiveTag {
    final filter = _activeAnimatedFilter;
    return filter == null ? _baseTag : '$_baseTag $filter';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loadPreview();
      }
    });
  }

  @override
  void dispose() {
    viewedIndex.dispose();
    scrollController.dispose();
    extraTagsController.dispose();
    booruFilterController.dispose();
    super.dispose();
  }

  void _applyExtraTags() {
    final String next = extraTagsController.text.trim();
    if (next == extraTags.trim()) return;
    setState(() {
      extraTags = next;
      animatedFilterIndex = -1;
      _aliasTried = false;
    });
    loadPreview(refresh: true);
  }

  Future<void> loadPreview({
    bool refresh = false,
    bool retry = false,
  }) async {
    if (refresh || tab == null) {
      tab = SearchTab(
        selectedBooru,
        null,
        _effectiveTag,
      );
      // Throwaway mini-search: don't let it write tag types into the shared
      // store (previewing on another booru would re-colour the current one).
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
    if (!mounted) return;

    if (tab!.booruHandler.locked && !isLastPage) {
      isLastPage = true;
    }
    if (tab!.booruHandler.errorString.isNotEmpty) {
      errorString = tab!.booruHandler.errorString;
    }
    if (tab!.booruHandler.totalCount.value == 0) {
      unawaited(tab!.booruHandler.searchCount(_effectiveTag));
    }

    loading = false;
    setState(() {});

    // Empty result + not yet remapped: try resolving the tag to this booru's
    // own spelling and reload once.
    if (!_aliasTried &&
        _resolvedBaseTag == null &&
        errorString.isEmpty &&
        tab!.booruHandler.filteredFetched.isEmpty) {
      _aliasTried = true;
      final String? resolved = await TagAliasResolver.resolve(widget.entry.tag, selectedBooru);
      if (!mounted) return;
      if (resolved != null && resolved.isNotEmpty && resolved != widget.entry.tag.trim().toLowerCase()) {
        setState(() {
          _resolvedBaseTag = resolved;
          _aliasNote = resolved;
        });
        return loadPreview(refresh: true);
      }
    }

    // If the freshly loaded page doesn't overflow the (possibly huge) window,
    // keep fetching so the grid actually fills up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillIfNotScrollable());
  }

  void _fillIfNotScrollable() {
    if (!mounted || loading || isLastPage || errorString.isNotEmpty) return;
    if (tab == null || tab!.booruHandler.filteredFetched.isEmpty) return;
    if (!scrollController.hasClients) return;
    final pos = scrollController.position;
    if (pos.maxScrollExtent <= 0) {
      loadPreview();
    }
  }

  void _toggleAnimatedOnly() {
    setState(() {
      final int next = animatedFilterIndex + 1;
      animatedFilterIndex = next < _animatedFilters.length ? next : -1;
    });
    loadPreview(refresh: true);
  }

  String get _animatedButtonTooltip {
    final active = _activeAnimatedFilter;
    if (active == null) {
      final first = _animatedFilters.isNotEmpty ? _animatedFilters.first : 'animated|video';
      return first.contains('|') ? 'Videos / GIFs only' : 'Filter: $first';
    }
    final bool isLast = animatedFilterIndex >= _animatedFilters.length - 1;
    final String label = active.contains('|') ? 'videos / GIFs' : active;
    return isLast ? 'Filter: $label — tap to clear' : 'Filter: $label — tap for next';
  }

  //
  // Rect handling

  void _initFractions(Size screen) {
    if (fx != null) return;

    final List<String> parts = settingsHandler.previewWindowRect.split(',');
    if (parts.length == 4) {
      final vals = parts.map(double.tryParse).toList();
      if (vals.every((v) => v != null)) {
        fx = vals[0]!.clamp(0.0, 0.95);
        fy = vals[1]!.clamp(0.0, 0.95);
        fw = vals[2]!.clamp(0.15, 1.0);
        fh = vals[3]!.clamp(0.15, 1.0);
        return;
      }
    }

    // Default: a big bottom-docked window (Boorusama-style).
    fw = min(0.94, 480 / screen.width);
    fh = 0.58;
    fx = (1 - fw!) / 2;
    fy = 1 - fh! - 0.03;
  }

  double _clampSafe(double v, double lo, double hi) => hi <= lo ? lo : v.clamp(lo, hi);

  Rect _pxRect(Size screen, EdgeInsets pad) {
    final double w = _clampSafe(fw! * screen.width, _minWidthPx, screen.width - 8);
    final double h = _clampSafe(fh! * screen.height, _minHeightPx, screen.height - pad.top - pad.bottom - 16);
    final double x = _clampSafe(fx! * screen.width, 4, screen.width - w - 4);
    final double y = _clampSafe(fy! * screen.height, pad.top + 4, screen.height - h - pad.bottom - 4);
    return Rect.fromLTWH(x, y, w, h);
  }

  void _persistRect() {
    settingsHandler.previewWindowRect =
        '${fx!.toStringAsFixed(4)},${fy!.toStringAsFixed(4)},${fw!.toStringAsFixed(4)},${fh!.toStringAsFixed(4)}';
    unawaited(settingsHandler.saveSettings(restate: false));
  }

  //
  // Actions

  void _openBooruPicker() {
    setState(() {
      booruFilterController.clear();
      booruPickerOpen = true;
    });
  }

  void _pickBooru(Booru b) {
    setState(() {
      selectedBooru = b;
      animatedFilterIndex = -1;
      booruPickerOpen = false;
      // Different booru -> re-resolve the tag's spelling for it.
      _resolvedBaseTag = null;
      _aliasTried = false;
      _aliasNote = null;
    });
    loadPreview(refresh: true);
  }

  void _openInNewTab() {
    final TabAddMode addMode = settingsHandler.defaultTabAddMode == 'next' ? TabAddMode.next : TabAddMode.end;
    searchHandler.addTabByString(
      _effectiveTag,
      customBooru: selectedBooru,
      addMode: addMode,
    );
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(context.loc.tagView.addedNewTab, style: const TextStyle(fontSize: 20)),
      content: Text(_effectiveTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );
  }

  void _maybeLoadMoreForViewer(int page) {
    if (loading || isLastPage || errorString.isNotEmpty || tab == null) return;
    if (page >= tab!.booruHandler.filteredFetched.length - 4) {
      loadPreview();
    }
  }

  Future<void> _onThumbTap(int index) async {
    if (tab == null) return;

    viewedIndex.value = index;
    final viewerKey = GlobalKey(debugLabel: 'viewer-floating-${widget.entry.id}');
    ViewerHandler.instance.addViewer(viewerKey);
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => GalleryViewPage(
          key: viewerKey,
          tab: tab!,
          initialIndex: index,
          canSelect: false,
          onPageChanged: (page) async {
            viewedIndex.value = page;
            // Endless swiping: fetch the next page when nearing the end of
            // what's loaded so the viewer never runs out until the booru does.
            _maybeLoadMoreForViewer(page);
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

  Future<void> _onThumbDoubleTap(int index) async {
    await tab?.toggleItemFavourite(index);
  }

  //
  // Build

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    _initFractions(screen);

    if (minimized) {
      return _buildPill(context, screen, pad);
    }

    final Rect rect = _pxRect(screen, pad);
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            color: theme.colorScheme.surface,
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildTitleBar(context, screen),
                    _buildBooruRow(context),
                    _buildSearchRow(context),
                    if (_aliasNote != null) _buildAliasBanner(context),
                    Expanded(child: _buildGrid(context, rect.width)),
                  ],
                ),
                // In-window booru picker — floats above the grid so it can't
                // hide behind the window like a navigator dialog would.
                if (booruPickerOpen) _buildBooruPickerPanel(context),
                // Resize grip
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        fw = (fw! + details.delta.dx / screen.width).clamp(_minWidthPx / screen.width, 1.0);
                        fh = (fh! + details.delta.dy / screen.height).clamp(_minHeightPx / screen.height, 1.0);
                      });
                    },
                    onPanEnd: (_) => _persistRect(),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.bottomRight,
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Symbols.south_east_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar(BuildContext context, Size screen) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          fx = (fx! + details.delta.dx / screen.width).clamp(0.0, 1.0);
          fy = (fy! + details.delta.dy / screen.height).clamp(0.0, 1.0);
        });
      },
      onPanEnd: (_) => _persistRect(),
      child: Container(
        height: 42,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            Icon(
              Symbols.drag_indicator_rounded,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.entry.tag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Minimize',
              icon: const Icon(Symbols.remove_rounded, size: 20),
              onPressed: () => setState(() => minimized = true),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.loc.close,
              icon: const Icon(Symbols.close_rounded, size: 20),
              onPressed: () => FloatingPreviewHandler.instance.close(widget.entry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBooruRow(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _openBooruPicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BooruFavicon(selectedBooru),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        selectedBooru.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Icon(Symbols.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (tab != null)
            Obx(() {
              final int count = tab!.booruHandler.totalCount.value;
              if (count <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  count.toFormattedString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              );
            }),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _animatedButtonTooltip,
            icon: Icon(
              _activeAnimatedFilter == null ? Symbols.movie_rounded : Symbols.movie_rounded,
              size: 20,
              color: _activeAnimatedFilter == null ? null : theme.colorScheme.secondary,
            ),
            onPressed: _toggleAnimatedOnly,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Open in a new tab',
            icon: const Icon(Symbols.fiber_new_rounded, size: 20),
            onPressed: _openInNewTab,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Tag hub',
            icon: const Icon(Symbols.hub_rounded, size: 20),
            onPressed: () {
              // The window's Offstage logic parks it while the hub page is on
              // top and restores it (state intact) when the page pops.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TagHubPage(
                    tag: widget.entry.tag,
                    originBooru: widget.entry.booru,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // Shown when the tag was auto-remapped to this booru's own spelling.
  Widget _buildAliasBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Symbols.sync_alt_rounded, size: 15, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Matched on ${selectedBooru.name}: ${_aliasNote!.replaceAll('_', ' ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // Slim search box to AND extra tags onto the previewed tag without leaving
  // the window.
  Widget _buildSearchRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: extraTagsController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _applyExtraTags(),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: 'Add tags to this preview…',
            hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Symbols.search_rounded, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            suffixIcon: ValueListenableBuilder(
              valueListenable: extraTagsController,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.clear_rounded, size: 16),
                  onPressed: () {
                    extraTagsController.clear();
                    _applyExtraTags();
                  },
                );
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ),
    );
  }

  // Booru picker rendered inside the window (an overlay above the grid). A
  // navigator dialog would open on the page BELOW the root overlay the window
  // lives in, so it would appear behind the window — hence this in-window list.
  Widget _buildBooruPickerPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      // sit below the title bar so the window stays draggable/closable
      top: 42,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => booruPickerOpen = false),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.35),
          child: GestureDetector(
            onTap: () {}, // swallow taps on the panel itself
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: [
                          Text('Preview booru', style: theme.textTheme.titleSmall),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Symbols.close_rounded, size: 20),
                            onPressed: () => setState(() => booruPickerOpen = false),
                          ),
                        ],
                      ),
                    ),
                    if (settingsHandler.booruList.length > 6)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: SizedBox(
                          height: 38,
                          child: TextField(
                            controller: booruFilterController,
                            style: const TextStyle(fontSize: 13),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Filter boorus…',
                              prefixIcon: const Icon(Symbols.search_rounded, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ),
                      ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final b in settingsHandler.booruList.where(_booruMatchesFilter))
                            ListTile(
                              dense: true,
                              leading: BooruFavicon(b),
                              title: Text(b.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                b.type?.name ?? '',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: b == selectedBooru ? const Icon(Symbols.check_rounded, size: 18) : null,
                              onTap: () => _pickBooru(b),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _booruMatchesFilter(Booru b) {
    final String q = booruFilterController.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (b.name?.toLowerCase().contains(q) ?? false) || (b.type?.name.toLowerCase().contains(q) ?? false);
  }

  Widget _buildGrid(BuildContext context, double width) {
    if (tab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final int columns = max(2, (width / 130).floor());

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notif) {
        final bool isNotAtStart = notif.metrics.pixels > 0;
        final bool isAtOrNearEdge =
            notif.metrics.atEdge ||
            notif.metrics.pixels > (notif.metrics.maxScrollExtent - (notif.metrics.extentInside * 1.5));
        if (!loading && isNotAtStart && isAtOrNearEdge) {
          loadPreview();
        }
        return true;
      },
      child: ValueListenableBuilder(
        valueListenable: tab!.booruHandler.filteredFetched,
        builder: (context, fetched, _) {
          if (fetched.isEmpty) {
            if (loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (errorString.isNotEmpty) {
              return _buildError(context);
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Kaomoji(
                    category: KaomojiCategory.indifference,
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(context.loc.nothingFound, style: const TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return Scrollbar(
            controller: scrollController,
            interactive: true,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(8),
                  sliver: SliverGrid.builder(
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemCount: fetched.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 9 / 13,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemBuilder: (context, index) {
                      return ValueListenableBuilder(
                        valueListenable: viewedIndex,
                        builder: (context, viewedIndexVal, _) {
                          return ThumbnailCardBuild(
                            index: index,
                            item: fetched[index],
                            handler: tab!.booruHandler,
                            scrollController: scrollController,
                            isHighlighted: viewedIndexVal == index,
                            selectable: false,
                            onTap: _onThumbTap,
                            onDoubleTap: _onThumbDoubleTap,
                          );
                        },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : (errorString.isNotEmpty
                              ? _buildError(context)
                              : (isLastPage
                                    ? Center(
                                        child: Text(
                                          context.loc.nothingFound,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink())),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.error_rounded, size: 26),
          const SizedBox(height: 6),
          Text(
            context.loc.tagView.failedToLoadPreviewPage,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: () => loadPreview(retry: true),
            child: Text(context.loc.tagView.tryAgain),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(BuildContext context, Size screen, EdgeInsets pad) {
    final theme = Theme.of(context);
    // Stagger the default position by this window's slot so several minimized
    // pills don't stack on the exact same spot.
    final int slot = FloatingPreviewHandler.instance.entries.indexOf(widget.entry).clamp(0, 5);
    final Offset pos =
        pillPos ??
        Offset(
          screen.width - 68,
          (screen.height * 0.55 + slot * 64).clamp(pad.top + 8, screen.height - 72),
        );

    return Stack(
      children: [
        Positioned(
          left: _clampSafe(pos.dx, 4, screen.width - 60),
          top: _clampSafe(pos.dy, pad.top + 4, screen.height - 60 - pad.bottom),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                pillPos = (pillPos ?? pos) + details.delta;
              });
            },
            onTap: () => setState(() => minimized = false),
            onLongPress: () => FloatingPreviewHandler.instance.close(widget.entry),
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              color: theme.colorScheme.secondaryContainer,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    BooruFavicon(selectedBooru, size: 24),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Icon(
                        Symbols.open_in_full_rounded,
                        size: 12,
                        color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
