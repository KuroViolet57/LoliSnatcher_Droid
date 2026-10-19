part of '../tag_view.dart';

/// A header-only widget that, when tapped, expands inline to show a
/// [TagContentPreview] grid for the given query against the given booru.
///
/// Lazy on purpose: we DON'T mount the underlying TagContentPreview until
/// the user explicitly opts in, so opening the drawer doesn't fire a
/// (potentially slow / metered) request per related section, and scrolling
/// past the related-grids region stays cheap.
class _CollapsibleRelatedPreview extends StatefulWidget {
  const _CollapsibleRelatedPreview({
    required this.title,
    required this.icon,
    required this.booru,
    required this.query,
    required this.parentTab,
    super.key,
  });

  final String title;
  final IconData icon;
  final Booru booru;
  final String query;
  final SearchTab? parentTab;

  @override
  State<_CollapsibleRelatedPreview> createState() => _CollapsibleRelatedPreviewState();
}

class _CollapsibleRelatedPreviewState extends State<_CollapsibleRelatedPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(widget.icon),
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Open in floating window',
                icon: Icon(
                  Symbols.picture_in_picture_alt_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                onPressed: () {
                  FloatingPreviewHandler.instance.open(
                    tag: widget.query,
                    booru: widget.booru,
                  );
                },
              ),
              Icon(_expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
            ],
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TagContentPreview(
              tag: widget.query,
              boorus: [widget.booru],
              parentTab: widget.parentTab,
              compact: true,
              // No compactTitle here: the wrapper above already shows the
              // section header, so let TagContentPreview render its default
              // "Preview" sub-label so we don't get a duplicate title.
            ),
          ),
      ],
    );
  }
}
