import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
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
    required this.openSize,
    this.detailsBuilder,
    super.key,
  });

  final SearchTab tab;
  // The viewer's authoritative current-page notifier (updated by the
  // PreloadPageView's onPageChanged). The sheet mirrors the post the viewer is
  // showing — reusing this avoids a second, fragile pageController listener.
  final ValueNotifier<int> currentPage;
  final DraggableScrollableController sheetController;
  final ValueNotifier<double> extentNotifier;

  /// Height (as a fraction of the screen) the sheet opens AND locks at —
  /// derived from the user's "size in thirds" setting. maxChildSize == this so
  /// the sheet stops here and its content scrolls in place instead of needing
  /// to be over-dragged bigger.
  final double openSize;

  /// Builds a post's details; [TagView] when null (tests pass a stand-in).
  @visibleForTesting
  final Widget Function(BuildContext context, BooruItem item, ScrollController scrollController)? detailsBuilder;

  /// r56: whether the sheet builds the details of the post on screen: always
  /// with the switch off, otherwise while it is open, or for the post whose
  /// details were built while it was open.
  static bool showDetails({
    required bool onOpenOnly,
    required bool isOpen,
    required String current,
    required String? detailsFor,
  }) => !onOpenOnly || isOpen || detailsFor == current;

  @override
  State<ItemInfoBottomSheet> createState() => _ItemInfoBottomSheetState();
}

class _ItemInfoBottomSheetState extends State<ItemInfoBottomSheet> {
  /// r56: the sheet is open at all (extent above zero). It changes only when
  /// the sheet opens or closes, so the content is not rebuilt on every frame
  /// of a drag.
  final ValueNotifier<bool> isOpen = ValueNotifier(false);

  /// The post whose details were built while the sheet was open: they stay
  /// while it closes, so reopening on the same post does not load it again.
  String? detailsFor;

  @override
  void initState() {
    super.initState();
    widget.extentNotifier.addListener(onExtent);
    onExtent();
  }

  @override
  void didUpdateWidget(covariant ItemInfoBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extentNotifier != widget.extentNotifier) {
      oldWidget.extentNotifier.removeListener(onExtent);
      widget.extentNotifier.addListener(onExtent);
      onExtent();
    }
  }

  @override
  void dispose() {
    widget.extentNotifier.removeListener(onExtent);
    isOpen.dispose();
    super.dispose();
  }

  void onExtent() => isOpen.value = widget.extentNotifier.value > 0;

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
                  // Lock the sheet at the chosen open size — content scrolls
                  // inside it rather than the sheet growing past it.
                  maxChildSize: widget.openSize,
                  snap: true,
                  builder: (context, scrollController) {
                    // RepaintBoundary isolates the sheet content's paint pass
                    // from the rest of the viewer (video, controls), so
                    // animating the sheet's extent doesn't force the heavy
                    // TagView to participate in every repaint.
                    return RepaintBoundary(
                      child: Material(
                        // Fully opaque + square top corners so nothing shows
                        // behind it and there's no rounded-corner gap.
                        color: theme.canvasColor,
                        clipBehavior: Clip.hardEdge,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        // Always render a scrollable on the sheet's scroll
                        // controller so it has clients. Without this the
                        // DraggableScrollableController reports isAttached=false
                        // and animateTo() silently does nothing. The TagView
                        // itself is built once the sheet opens (r56).
                        child: ListenableBuilder(
                          listenable: Listenable.merge([widget.currentPage, isOpen]),
                          builder: (context, _) {
                            final int page = widget.currentPage.value;
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
                            final BooruItem item = items[page];
                            if (isOpen.value) detailsFor = item.fileURL;
                            if (!ItemInfoBottomSheet.showDetails(
                              onOpenOnly: ModularUi.isOn(ModularUi.viewerDetailsOnOpen),
                              isOpen: isOpen.value,
                              current: item.fileURL,
                              detailsFor: detailsFor,
                            )) {
                              // Closed: nothing heavy, and no request to the
                              // site, but still a scrollable on the controller.
                              return ListView(
                                controller: scrollController,
                                children: const [SizedBox(height: 1)],
                              );
                            }
                            // Key on the item so a swipe to a new post forces
                            // a fresh TagView (belt-and-suspenders alongside
                            // TagView's own didUpdateWidget).
                            return KeyedSubtree(
                              key: ValueKey(item.fileURL),
                              child:
                                  widget.detailsBuilder?.call(context, item, scrollController) ??
                                  TagView(
                                    item: item,
                                    handler: widget.tab.booruHandler,
                                    scrollController: scrollController,
                                  ),
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
