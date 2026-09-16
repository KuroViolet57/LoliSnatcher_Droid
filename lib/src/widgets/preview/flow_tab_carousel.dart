import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/add_new_tab_dialog.dart';
import 'package:lolisnatcher/src/widgets/dialogs/page_number_dialog.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// Compact "N tabs" pill (stacks icon + count) that opens the All-Tabs manager.
/// Used as the browse app-bar title, replacing the old inline tab switcher.
class TabsCountPill extends StatelessWidget {
  const TabsCountPill({super.key});

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;
    final accent = Theme.of(context).colorScheme.secondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TabManagerPage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: ThemeHandler.flowSurface,
            border: Border.all(color: ThemeHandler.flowBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.layers_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Obx(
                () => Text(
                  '${searchHandler.tabs.length} tabs',
                  style: const TextStyle(
                    color: Color(0xFFCDBAF0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent "new tab" button for the browse app bar (the Flow equivalent of
/// the old sidebar add-tab button). One tap opens a fresh tab in the current
/// booru — honouring the "New tab position" setting — and switches to it; a
/// long press opens the full Add-new-tab sheet (choose booru + tags, etc.).
class NewTabButton extends StatelessWidget {
  const NewTabButton({super.key});

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;
    final accent = Theme.of(context).colorScheme.secondary;
    // Tap and long-press MUST live on the same widget. This was a
    // GestureDetector wrapped around an IconButton, and the long press never
    // fired: IconButton builds its own InkResponse, whose tap recognizer is
    // the innermost entry in the gesture arena, so the ancestor detector
    // loses the contest under real touch input. (Same trap as the sidebar
    // add-tab button, and as the viewer toolbar in the 2.5.0 hotfix — if you
    // ever see GestureDetector wrapped around an IconButton, it is a bug.)
    // InkResponse handles both itself, so there is no arena to lose.
    return Tooltip(
      message: 'New tab (hold to choose booru)',
      child: InkResponse(
        onTap: searchHandler.addNewTabRespectingSetting,
        onLongPress: () {
          ServiceHandler.vibrate();
          SettingsPageOpen(
            context: context,
            asBottomSheet: true,
            page: (_) => const AddNewTabDialog(),
          ).open();
        },
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Symbols.add_circle_rounded, color: accent),
        ),
      ),
    );
  }
}

/// Compact "Page N" pill shown next to [TabsCountPill] in the browse app bar.
/// Tapping opens the page-number sheet (jump to / prefetch a specific page) —
/// restoring the old UI's page changer. Only meaningful for page-based boorus;
/// hidden while no page is loaded yet (pageNum == -1).
class PageIndicatorPill extends StatelessWidget {
  const PageIndicatorPill({super.key});

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;
    final accent = Theme.of(context).colorScheme.secondary;
    return Obx(() {
      final int page = searchHandler.pageNum.value;
      if (searchHandler.tabs.isEmpty || page < 0) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => SettingsPageOpen(
          context: context,
          asBottomSheet: true,
          page: (_) => const PageNumberDialog(),
        ).open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: ThemeHandler.flowSurface,
            border: Border.all(color: ThemeHandler.flowBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.format_list_numbered_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'Pg ${page + 1}',
                style: const TextStyle(
                  color: Color(0xFFCDBAF0),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The "Flow" browse header: tabs shown as horizontally-swipeable cards. The
/// active tab is a wide gradient card (booru + query + edit + status); the
/// others peek as compact cards; a dashed card at the end adds a new tab. Dots
/// below indicate position. Reads [SearchHandler] reactively.
class FlowTabCarousel extends StatefulWidget {
  const FlowTabCarousel({this.large = false, this.onPicked, super.key});

  /// Taller cards with bigger covers (the tab pill's sheet).
  final bool large;

  /// Called after a card was picked (a sheet closes itself).
  final VoidCallback? onPicked;

  /// Cards built since the counter was reset — the test's guard against a
  /// strip that builds every card to reach a far tab.
  @visibleForTesting
  static int cardsBuilt = 0;

  /// What a card shows for a tab: a doujin tab's saved cover, else the
  /// first loaded item's thumbnail; null when there is nothing yet.
  static String? coverUrlOf(SearchTab tab) {
    final String? persisted = tab.doujinThumb;
    if (persisted != null && persisted.isNotEmpty) return persisted;
    for (final item in tab.booruHandler.filteredFetched) {
      if (item.thumbnailURL.isNotEmpty) return item.thumbnailURL;
    }
    return null;
  }

  /// The tabs of the current tab's section (r40), as indexes into [tabs]:
  /// the doujin tabs from a doujin tab, the others from the rest — the
  /// tab manager's own split. The cards and the tab pill show only these.
  static List<int> sectionIndexes(List<SearchTab> tabs, int active) {
    if (tabs.isEmpty) return const [];
    final bool doujin = tabs[active.clamp(0, tabs.length - 1)].booruHandler.hasReader;
    return [
      for (int i = 0; i < tabs.length; i++)
        if (tabs[i].booruHandler.hasReader == doujin) i,
    ];
  }

  @override
  State<FlowTabCarousel> createState() => _FlowTabCarouselState();
}

class _FlowTabCarouselState extends State<FlowTabCarousel> with TraceLifecycle {
  final SearchHandler searchHandler = SearchHandler.instance;
  final ScrollController _scroll = ScrollController();
  int _lastActive = -1;

  double get cardHeight => widget.large ? 132 : 92;
  double get activeWidth => widget.large ? 320 : 280;
  double get peekWidth => widget.large ? 220 : 180;
  static const double _addWidth = 54;
  static const double _gap = 10;
  static const double _vPad = 11;

  /// The cover's width: the card's inner height at a book's proportions.
  double get coverWidth => (cardHeight - _vPad * 2) * 0.72;

  /// [child] with the tab's cover at its left, full height; [child] alone
  /// when the tab has none yet. (r38 put the cover in the query line, which
  /// overflowed the card on a phone.)
  Widget _withCover(SearchTab tab, Widget child) {
    final String? url = FlowTabCarousel.coverUrlOf(tab);
    if (url == null) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: coverWidth,
            child: Image(
              image: CustomNetworkImage(url, withCache: SettingsHandler.instance.thumbnailCache, cacheFolder: 'thumbnails'),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MainSearchQueryEditorPage()),
    );
  }

  void _newTab() {
    ServiceHandler.vibrate(duration: 30);
    searchHandler.addNewTabRespectingSetting();
  }

  Widget _activeCard(SearchTab tab) {
    final theme = Theme.of(context);
    final booru = tab.selectedBooru.value;
    final String query = tab.tags.trim().isEmpty ? 'everything' : tab.tags.trim();
    final bool hasCover = FlowTabCarousel.coverUrlOf(tab) != null;
    return GestureDetector(
      onTap: _openEditor,
      child: Container(
        width: activeWidth,
        padding: EdgeInsets.fromLTRB(hasCover ? _vPad : 16, _vPad, 12, _vPad),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF221C2E), Color(0xFF171320)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF3A3050)),
        ),
        child: _withCover(
          tab,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _avatar(booru, 18),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      booru.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF9C93AE), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(() {
                    final int count = tab.booruHandler.totalCount.value;
                    final int loaded = tab.booruHandler.filteredFetched.length;
                    return Text(
                      count > 0 ? _fmt(count) : (loaded > 0 ? _fmt(loaded) : ''),
                      style: const TextStyle(color: Color(0xFF9C93AE), fontSize: 11.5, fontWeight: FontWeight.w600),
                    );
                  }),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFF2EDFA), fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Symbols.edit_rounded, size: 16, color: theme.colorScheme.secondary),
                  ),
                ],
              ),
              Obx(() {
                final bool loading = searchHandler.isLoading.value && searchHandler.currentTab.id == tab.id;
                return Text(
                  loading ? 'loading · tap query to edit' : 'tap query to edit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF736A85), fontSize: 10.5, fontWeight: FontWeight.w600),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peekCard(SearchTab tab, int index) {
    final booru = tab.selectedBooru.value;
    final String query = tab.tags.trim().isEmpty ? 'everything' : tab.tags.trim();
    final bool hasCover = FlowTabCarousel.coverUrlOf(tab) != null;
    return GestureDetector(
      onTap: () {
        searchHandler.changeTabIndex(index, byUser: true);
        widget.onPicked?.call();
      },
      child: Container(
        width: peekWidth,
        padding: EdgeInsets.fromLTRB(hasCover ? _vPad : 14, _vPad, 12, _vPad),
        decoration: BoxDecoration(
          color: ThemeHandler.flowSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ThemeHandler.flowBorderSoft),
        ),
        child: _withCover(
          tab,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _avatar(booru, 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      booru.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF736A85), fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Text(
                query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC9BFE0), fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              Obx(() {
                final int count = tab.booruHandler.totalCount.value;
                final int loaded = tab.booruHandler.filteredFetched.length;
                final String label = count > 0 ? '${_fmt(count)} results' : (loaded > 0 ? '${_fmt(loaded)} loaded' : 'not loaded');
                return Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF736A85), fontSize: 10.5, fontWeight: FontWeight.w600),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addCard() {
    return GestureDetector(
      onTap: _newTab,
      child: Container(
        width: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF35304A), width: 1.5, style: BorderStyle.solid),
        ),
        child: const Center(
          child: Icon(Symbols.add_rounded, size: 22, color: Color(0xFF736A85)),
        ),
      ),
    );
  }

  Widget _avatar(Booru booru, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.32),
      child: SizedBox(
        width: size,
        height: size,
        child: BooruFavicon(booru, size: size),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return n.toString();
  }

  Widget _dots(int total, int active) {
    const int maxDots = 7;
    final int show = total > maxDots ? maxDots : total;
    // Map the active tab's absolute position into the small dot window so the
    // elongated dot tracks progress through the whole list.
    final int activeDot = (total <= 1)
        ? 0
        : ((active / (total - 1)) * (show - 1)).round().clamp(0, show - 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(show, (i) {
        final bool isActive = i == activeDot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: isActive ? 16 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).colorScheme.secondary : const Color(0xFF35304A),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      searchHandler.index.value;
      searchHandler.tabId.value;
      final List<SearchTab> allTabs = searchHandler.tabs;
      if (allTabs.isEmpty) return const SizedBox.shrink();
      final int current = searchHandler.currentIndex.clamp(0, allTabs.length - 1);
      // Only the current tab's section (r40): from a doujin tab, the doujin
      // tabs. Positions below are within the section; keys and taps use
      // the tab's own index.
      final List<int> section = FlowTabCarousel.sectionIndexes(allTabs, current);
      final List<SearchTab> tabs = [for (final int i in section) allTabs[i]];
      final int active = section.indexOf(current);

      // Every tab has a card (r38): the active one is wide and leads the
      // view when it changes; the earlier tabs are a scroll to the right
      // away, the later ones follow, then the "add" card.
      if (active != _lastActive) {
        _lastActive = active;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          final double target = active * (peekWidth + _gap);
          _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
        });
      }
      return Column(
        children: [
          SizedBox(
            height: cardHeight,
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tabs.length + 1,
              // Fixed widths (r39). With varying widths the list had to build
              // every card before a far tab to find where it was: thousands of
              // cards on each tab switch, each starting a favicon request.
              itemExtentBuilder: (int i, _) {
                if (i > tabs.length) return null;
                if (i == tabs.length) return _addWidth + _gap;
                return (i == active ? activeWidth : peekWidth) + _gap;
              },
              itemBuilder: (context, i) {
                FlowTabCarousel.cardsBuilt++;
                if (i == tabs.length) return Padding(padding: const EdgeInsets.only(right: _gap), child: _addCard());
                final tab = tabs[i];
                return KeyedSubtree(
                  key: ValueKey('flow-card-${section[i]}'),
                  child: Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: i == active ? _activeCard(tab) : _peekCard(tab, section[i]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _dots(tabs.length, active),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}
