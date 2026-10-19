part of '../floating_tag_preview_window.dart';

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
