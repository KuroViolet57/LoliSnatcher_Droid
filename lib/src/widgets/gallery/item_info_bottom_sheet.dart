import 'package:flutter/material.dart';

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
    required this.currentPage,
    required this.sheetController,
    required this.extentNotifier,
    super.key,
  });

  final SearchTab tab;
  // The viewer's authoritative current-page notifier (updated by the
  // PreloadPageView's onPageChanged). The sheet mirrors the post the viewer is
  // showing — reusing this avoids a second, fragile pageController listener.
  final ValueNotifier<int> currentPage;
  final DraggableScrollableController sheetController;
  final ValueNotifier<double> extentNotifier;

  /// Height (as a fraction of the screen) the sheet snaps to when opened — the
  /// Boorusama "2/3 sheet, 1/3 player" split.
  static const double peekSize = 0.66;

  /// Maximum height the sheet can be dragged to (player shrinks further).
  static const double expandedSize = 0.9;

  @override
  State<ItemInfoBottomSheet> createState() => _ItemInfoBottomSheetState();
}

class _ItemInfoBottomSheetState extends State<ItemInfoBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // No scrim: in the split layout the player stays visible (and bright) in
    // the top third, the sheet occupies the bottom — nothing to dim behind.
    return NotificationListener<DraggableScrollableNotification>(
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
                          valueListenable: widget.currentPage,
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
                              // Key on the item so a swipe to a new post forces
                              // a fresh TagView (belt-and-suspenders alongside
                              // TagView's own didUpdateWidget).
                              key: ValueKey(items[page].fileURL),
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
    );
  }
}
