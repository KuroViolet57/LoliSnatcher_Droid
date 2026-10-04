part of '../gallery_view_page.dart';

Widget slidePageTransition(
  BuildContext context,
  PreloadPageController pageController,
  Axis direction,
  int index,
  Widget? child,
) {
  double delta = 0;
  if (pageController.hasClients && pageController.position.haveDimensions) {
    final position = (pageController.page! - index).clamp(-1.0, 1.0);
    final viewport = pageController.position.viewportDimension;
    delta = position * viewport / 2;
  }
  return ClipRect(
    child: Transform.translate(
      offset: Offset(
        direction == Axis.horizontal ? delta : 0,
        direction == Axis.vertical ? delta : 0,
      ),
      child: child,
    ),
  );
}

/// Stiffer page-snap spring so swiping between posts settles quickly instead
/// of the default "buttery"/floaty glide. PreloadPageView resolves its
/// page-snap [spring] through the physics parent chain, so overriding [spring]
/// here is enough — we don't need to reimplement the ballistic simulation.
class _SnappyPageSpringPhysics extends ScrollPhysics {
  const _SnappyPageSpringPhysics({super.parent});

  @override
  _SnappyPageSpringPhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPageSpringPhysics(parent: buildParent(ancestor));
  }

  // Default page spring is roughly mass 0.5 / stiffness 100 / ratio 1.1.
  // Lighter + stiffer = a faster, snappier settle with no overshoot.
  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.32,
    stiffness: 230,
    ratio: 1.1,
  );
}
