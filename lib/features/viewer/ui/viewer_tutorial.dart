import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/gen/strings.g.dart';

/// Whether the first-open viewer hint should be on screen.
///
/// [enabled] is Settings → Viewer → Show viewer hints. Closing the hint
/// turns that setting off, so the next open stays quiet until it is on again.
bool viewerTutorialIsShown(bool enabled) => enabled;

class ViewerTutorial extends StatefulWidget {
  const ViewerTutorial({
    required this.shown,
    required this.onDismiss,
    super.key,
  });

  final bool shown;
  final VoidCallback onDismiss;

  @override
  State<ViewerTutorial> createState() => _ViewerTutorialState();
}

class _ViewerTutorialState extends State<ViewerTutorial> {
  bool _closed = false;

  @override
  void didUpdateWidget(ViewerTutorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown && !oldWidget.shown) {
      _closed = false;
    }
  }

  void _dismiss() {
    setState(() => _closed = true);
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!viewerTutorialIsShown(widget.shown) || _closed) {
      return const SizedBox.shrink();
    }

    // Opaque so a tap on the scrim does not also reach the picture.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.66),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Symbols.image_rounded, color: Colors.white, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        context.loc.viewer.tutorial.images,
                        style: const TextStyle(color: Colors.white, fontSize: 28),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  context.loc.viewer.tutorial.tapLongTapToggleImmersive,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  context.loc.viewer.tutorial.doubleTapFitScreen,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: _dismiss,
                    child: Text(
                      context.loc.close,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
