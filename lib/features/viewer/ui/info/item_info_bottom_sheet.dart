import 'package:flutter/material.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/info_sheet_body.dart';
import 'package:lolisnatcher/features/viewer/ui/info/tag_view.dart';

/// Opens the bottom info sheet to [size] in one motion.
///
/// When the sheet still shows its placeholder, the tag view replaces it on
/// the next frame. That swap detaches the sheet's scroll position, and the
/// SDK's DraggableScrollableController disposes its running animations on
/// detach (`onPositionDetached = _disposeAnimationControllers`), which used to
/// stop the first open a few pixels up. So the animation starts only after
/// the frame that did the swap.
void openInfoSheet({
  required DraggableScrollableController controller,
  required InfoSheetContentGate gate,
  required double size,
  Duration duration = const Duration(milliseconds: 300),
}) {
  final bool swapsContent = !gate.live.value;
  gate.requestOpen();

  void animate() {
    if (!controller.isAttached) return;
    controller.animateTo(size, duration: duration, curve: Curves.easeOutCubic);
  }

  if (!swapsContent && controller.isAttached) {
    animate();
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) => animate());
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// The sheet itself, without the post lookup: a [DraggableScrollableSheet]
/// whose body is a placeholder list until [gate] goes live, then
/// [liveBuilder]'s content.
///
/// The body listens to [gate], never to the extent: the extent changes every
/// frame while the sheet moves, and rebuilding the tag view per frame is what
/// made the swipe up stutter.
class InfoSheetFrame extends StatelessWidget {
  const InfoSheetFrame({
    required this.sheetController,
    required this.extentNotifier,
    required this.gate,
    required this.openSize,
    required this.liveBuilder,
    super.key,
  });

  final DraggableScrollableController sheetController;
  final ValueNotifier<double> extentNotifier;
  final InfoSheetContentGate gate;
  final double openSize;
  final Widget Function(BuildContext context, ScrollController scrollController) liveBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        extentNotifier.value = notification.extent;
        gate.onExtent(notification.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: sheetController,
        initialChildSize: 0,
        minChildSize: 0,
        maxChildSize: openSize,
        snap: true,
        builder: (context, scrollController) {
          return RepaintBoundary(
            child: Material(
              color: theme.canvasColor,
              clipBehavior: Clip.hardEdge,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              // A shut sheet still needs a scrollable, or the controller
              // reports isAttached=false and animateTo() does nothing.
              child: ValueListenableBuilder<bool>(
                valueListenable: gate.live,
                builder: (context, live, _) {
                  if (!live) {
                    return ListView(
                      controller: scrollController,
                      children: const [SizedBox(height: 80)],
                    );
                  }
                  return liveBuilder(context, scrollController);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Boorusama-style bottom info sheet — replaces the right-side ItemInfoDrawer
/// when the matching setting is on. The post info (tags + metadata) lives in a
/// [DraggableScrollableSheet] that the user drags up from the bottom edge (or
/// opens via the appbar info button).
///
/// State is intentionally externalised: the host page owns the
/// [DraggableScrollableController] (so it can open the sheet), the
/// [extentNotifier] (so it can resize the viewer and intercept the back
/// button) and the [gate] (so it can build the tag view before opening).
class ItemInfoBottomSheet extends StatefulWidget {
  const ItemInfoBottomSheet({
    required this.tab,
    required this.currentPage,
    required this.sheetController,
    required this.extentNotifier,
    required this.gate,
    required this.openSize,
    super.key,
  });

  final SearchTab tab;
  // The viewer's authoritative current-page notifier (updated by the
  // PreloadPageView's onPageChanged). The sheet mirrors the post the viewer is
  // showing — reusing this avoids a second, fragile pageController listener.
  final ValueNotifier<int> currentPage;
  final DraggableScrollableController sheetController;
  final ValueNotifier<double> extentNotifier;
  final InfoSheetContentGate gate;

  /// Height (as a fraction of the screen) the sheet opens AND locks at —
  /// derived from the user's "size in thirds" setting. maxChildSize == this so
  /// the sheet stops here and its content scrolls in place instead of needing
  /// to be over-dragged bigger.
  final double openSize;

  @override
  State<ItemInfoBottomSheet> createState() => _ItemInfoBottomSheetState();
}

class _ItemInfoBottomSheetState extends State<ItemInfoBottomSheet> with TraceLifecycle {
  @override
  Widget build(BuildContext context) {
    // No scrim: in the split layout the player stays visible (and bright) in
    // the top third, the sheet occupies the bottom — nothing to dim behind.
    return InfoSheetFrame(
      sheetController: widget.sheetController,
      extentNotifier: widget.extentNotifier,
      gate: widget.gate,
      openSize: widget.openSize,
      liveBuilder: (context, scrollController) {
        return ValueListenableBuilder<int>(
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
              // Key on the item so a swipe to a new post forces a fresh
              // TagView (belt-and-suspenders alongside TagView's own
              // didUpdateWidget).
              key: ValueKey(items[page].fileURL),
              item: items[page],
              handler: widget.tab.booruHandler,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}
