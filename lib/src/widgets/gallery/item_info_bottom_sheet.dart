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
    if (!widget.sheetController.isAttached) {
      // Should never happen with the stable Stack structure below, but guard
      // anyway — better silent than a runtime "Null check" exception.
      widget.extentNotifier.value = 0;
      return;
    }
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
        // Scrim fully opaque-ish by the time the sheet reaches its peek.
        final double dim = (extent / ItemInfoBottomSheet.peekSize).clamp(0.0, 1.0) * 0.55;
        final bool sheetClosed = extent <= 0.001;

        // Both children MUST stay at stable positions across rebuilds.
        // Earlier this branch used `if (extent > 0.001) ...scrim...` as the
        // first child, which shifted the sheet's index when extent crossed the
        // threshold. Without keys Flutter compared by position, so the sheet
        // got disposed-and-recreated, the in-flight animateTo was lost, and
        // the controller briefly detached — causing taps on the (just-then-
        // visible) scrim to fire _close on a null _attachedController and
        // video taps to be consumed by the oscillating scrim. Use opacity +
        // IgnorePointer to avoid the shift entirely.
        return Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('infoSheetScrim'),
              child: IgnorePointer(
                ignoring: sheetClosed,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
                ),
              ),
            ),
            Positioned.fill(
              key: const ValueKey('infoSheet'),
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
                    // RepaintBoundary isolates the sheet content's paint pass
                    // from the rest of the viewer (video, scrim, controls), so
                    // animating the sheet's extent doesn't force the heavy
                    // TagView to participate in every repaint.
                    // Clip.hardEdge instead of antiAlias halves clip cost per
                    // frame, which matters at 120Hz.
                    return RepaintBoundary(
                      child: Material(
                        color: theme.canvasColor.withValues(alpha: 0.94),
                        clipBehavior: Clip.hardEdge,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                        ),
                        // Always render the TagView so the sheet's scroll
                        // controller has clients. Without this the
                        // DraggableScrollableController reports isAttached=false
                        // and animateTo() silently does nothing.
                        child: ValueListenableBuilder<int>(
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
                        ),
                      ),
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
