part of '../tag_browser_page.dart';

/// One tag row.
///
/// The border carries the point of the whole screen: solid means this booru
/// said so itself, dashed means the type was borrowed from somewhere else and
/// might be wrong here, and a thick accent border means you set it and it is
/// never going to be overwritten.
class _TagRowTile extends StatelessWidget {
  const _TagRowTile({
    required this.entry,
    required this.booru,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenBackground,
    super.key,
  });

  final BooruTagEntry entry;
  final Booru booru;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (TagType type, TagTypeOrigin origin) = BooruTagStore.resolve(
      entry.name,
      booru,
      snapshotRow: entry,
    );
    final Color accent = type.getColour() ?? theme.colorScheme.onSurfaceVariant;

    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: type.isNone ? Colors.transparent : accent,
              border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      type.isNone ? 'general' : type.locName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${origin.label}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (entry.count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${_formatCount(entry.count)}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (origin.isManual)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Symbols.lock_rounded, size: 15, color: theme.colorScheme.secondary),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Open in background tab',
            icon: const Icon(Symbols.tab_new_right_rounded, size: 20),
            onPressed: onOpenBackground,
          ),
        ],
      ),
    );

    final BorderRadius radius = BorderRadius.circular(12);
    final Widget body = Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: origin.isInferred
          ? CustomPaint(
              painter: _DashedBorderPainter(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                radius: 12,
              ),
              child: body,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: origin.isManual
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.outlineVariant,
                  width: origin.isManual ? 1.8 : 1,
                ),
              ),
              child: body,
            ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

/// Dashed rounded outline — the "this is a guess" marker.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const double dash = 5;
    const double gap = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
