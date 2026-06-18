import 'package:flutter/material.dart';

import 'package:preload_page_view/preload_page_view.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';

/// Boorusama-style bottom info sheet — replaces the right-side ItemInfoDrawer
/// when the matching setting is on. The post info (tags + metadata) lives in a
/// [DraggableScrollableSheet] that the user drags up from the bottom edge (or
/// opens via the appbar info button). The image dims behind it as it expands.
///
/// State is intentionally externalised: the host page owns the
/// [DraggableScrollableController] (so it can open the sheet) and the
/// [extentNotifier] (so it can dim/scrim and intercept the back button).
class ItemInfoBottomSheet extends StatefulWidget {
  const ItemInfoBottomSheet({
    required this.tab,
    required this.pageController,
    required this.sheetController,
    required this.extentNotifier,
    super.key,
  });

  final SearchTab tab;
  final PreloadPageController pageController;
  final DraggableScrollableController sheetController;
  final ValueNotifier<double> extentNotifier;

  /// Height (as a fraction of the screen) the sheet snaps to when first opened.
  static const double peekSize = 0.55;

  /// Maximum height the sheet can be dragged to.
  static const double expandedSize = 0.92;

  @override
  State<ItemInfoBottomSheet> createState() => _ItemInfoBottomSheetState();
}

class _ItemInfoBottomSheetState extends State<ItemInfoBottomSheet> {
  final ValueNotifier<int> page = ValueNotifier(0);

  // Defer building (and thus tag-loading) the heavy TagView until the sheet has
  // been opened at least once — mirrors the side drawer's lazy behaviour.
  bool _everOpened = false;

  @override
  void initState() {
    super.initState();
    page.value = widget.pageController.page?.round() ?? 0;
    widget.pageController.addListener(_pageListener);
  }

  void _pageListener() {
    page.value = widget.pageController.page?.round() ?? 0;
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_pageListener);
    page.dispose();
    super.dispose();
  }

  void _close() {
    widget.sheetController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<double>(
      valueListenable: widget.extentNotifier,
      builder: (context, extent, _) {
        if (extent > 0.001 && !_everOpened) {
          _everOpened = true;
        }
        // Scrim fully opaque-ish by the time the sheet reaches its peek.
        final double dim = (extent / ItemInfoBottomSheet.peekSize).clamp(0.0, 1.0) * 0.55;

        return Stack(
          children: [
            if (extent > 0.001)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
                ),
              ),
            Positioned.fill(
              child: NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  widget.extentNotifier.value = notification.extent;
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: widget.sheetController,
                  initialChildSize: 0,
                  minChildSize: 0,
                  maxChildSize: ItemInfoBottomSheet.expandedSize,
                  snap: true,
                  snapSizes: const [ItemInfoBottomSheet.peekSize],
                  builder: (context, scrollController) {
                    return Material(
                      color: theme.canvasColor.withValues(alpha: 0.94),
                      clipBehavior: Clip.antiAlias,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      child: _everOpened
                          ? ValueListenableBuilder<int>(
                              valueListenable: page,
                              builder: (context, page, _) {
                                final items = widget.tab.booruHandler.filteredFetched;
                                if (items.isEmpty || page >= items.length) {
                                  return ListView(
                                    controller: scrollController,
                                    children: [
                                      const SizedBox(height: 80),
                                      Center(child: Text(context.loc.galleryView.noItemSelected)),
                                    ],
                                  );
                                }
                                return TagView(
                                  item: items[page],
                                  handler: widget.tab.booruHandler,
                                  scrollController: scrollController,
                                );
                              },
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
