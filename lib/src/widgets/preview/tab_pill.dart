import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/preview/flow_tab_carousel.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// The tab pill (r38, experimental — Settings → User interface): a small
/// floating pill in the feed that says where you are ("3/4527", with the
/// tab's cover) and is the quickest way to the tabs wherever the feed is
/// scrolled: tap for the tab strip in a sheet, swipe left or right to move
/// one tab over, long-press for the full tab manager. Borrowed from the
/// phone browsers' tab-count buttons and their swipe-the-address-bar tab
/// switching.
class TabPill extends StatelessWidget {
  const TabPill({super.key});

  static Future<void> openStrip(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: FlowTabCarousel(large: true, onPicked: () => Navigator.of(ctx).maybePop()),
        ),
      ),
    );
  }

  void _step(int delta) {
    final SearchHandler searchHandler = SearchHandler.instance;
    final int next = (searchHandler.currentIndex + delta).clamp(0, searchHandler.total - 1);
    if (next == searchHandler.currentIndex) return;
    ServiceHandler.vibrate(duration: 20);
    searchHandler.changeTabIndex(next, byUser: true);
  }

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;
    final ThemeData theme = Theme.of(context);
    return Obx(() {
      searchHandler.index.value;
      searchHandler.tabId.value;
      final List<SearchTab> tabs = searchHandler.tabs;
      if (tabs.isEmpty) return const SizedBox.shrink();
      final int index = searchHandler.currentIndex.clamp(0, tabs.length - 1);
      final SearchTab tab = tabs[index];
      final String? cover = FlowTabCarousel.coverUrlOf(tab);
      return GestureDetector(
        key: const ValueKey('tab-pill'),
        behavior: HitTestBehavior.opaque,
        onTap: () => openStrip(context),
        onLongPress: () {
          ServiceHandler.vibrate(duration: 30);
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TabManagerPage()));
        },
        onHorizontalDragEnd: (DragEndDetails d) {
          final double v = d.primaryVelocity ?? 0;
          if (v > 200) {
            _step(-1);
          } else if (v < -200) {
            _step(1);
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: ThemeHandler.flowSurface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ThemeHandler.flowBorderSoft),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: cover == null
                      ? BooruFavicon(tab.selectedBooru.value, size: 28)
                      : Image(
                          image: CustomNetworkImage(cover, withCache: SettingsHandler.instance.thumbnailCache, cacheFolder: 'thumbnails'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => BooruFavicon(tab.selectedBooru.value, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${index + 1}/${tabs.length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 4),
              Icon(Symbols.tab_rounded, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ],
          ),
        ),
      );
    });
  }
}
