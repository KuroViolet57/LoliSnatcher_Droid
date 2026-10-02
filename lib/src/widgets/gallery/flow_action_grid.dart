import 'dart:math' as math;

import 'package:flutter/material.dart';

/// r79: the actions that joined Favorite / Save / Collect / Details in a
/// post's info sheet. They were full-width rows under that block; now they
/// are buttons in it (Settings > Modular UI > Viewer brings the rows back).
enum FlowExtra { comments, elsewhere, board, similar, recommend }

class FlowExtras {
  const FlowExtras._();

  /// Which extra buttons a post gets, each under its old row's condition:
  /// Comments where the source has comments; the four discovery buttons on
  /// booru posts only; Similar needs a picture; Recommend needs seed tags.
  static List<FlowExtra> of({
    required bool doujin,
    required bool comments,
    required bool hasPicture,
    required bool recommend,
  }) => [
    if (comments) FlowExtra.comments,
    if (!doujin) FlowExtra.elsewhere,
    if (!doujin) FlowExtra.board,
    if (!doujin && hasPicture) FlowExtra.similar,
    if (!doujin && recommend) FlowExtra.recommend,
  ];

  /// One word each.
  static String labelOf(FlowExtra e) {
    switch (e) {
      case FlowExtra.comments:
        return 'Comments';
      case FlowExtra.elsewhere:
        return 'Elsewhere';
      case FlowExtra.board:
        return 'Board';
      case FlowExtra.similar:
        return 'Similar';
      case FlowExtra.recommend:
        return 'Recommend';
    }
  }
}

/// One button of the block: an icon over one word.
class FlowActionTile extends StatelessWidget {
  const FlowActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color on = activeColor ?? theme.colorScheme.secondary;
    final Color fg = active ? on : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // fill is the Material Symbols variable-font axis — without it
            // the "active" state renders the same outline glyph.
            Icon(icon, size: 22, color: fg, fill: active ? 1 : 0),
            const SizedBox(height: 3),
            // r79: five to a row - a long word shrinks a little rather than
            // spill over (the side drawer is narrower, the font may be larger).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? on : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded block of post actions: up to five a row, at most two rows,
/// every tile one width (the last row is padded with empty slots).
class FlowActionGrid extends StatelessWidget {
  const FlowActionGrid({required this.tiles, super.key});

  final List<Widget> tiles;

  /// (rows, columns) for [count] tiles: 4 -> one row of 4 (as before r79),
  /// 5 -> 1x5, 6 -> 2x3, 7 and 8 -> 2x4, 9 -> 2x5.
  static (int, int) shapeFor(int count) {
    if (count <= 5) return (1, math.max(count, 1));
    final int rows = (count / 5).ceil();
    return (rows, (count / rows).ceil());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (int rows, int columns) = shapeFor(tiles.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int r = 0; r < rows; r++)
              Row(
                children: [
                  for (int c = 0; c < columns; c++)
                    Expanded(
                      child: r * columns + c < tiles.length ? tiles[r * columns + c] : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
