import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

/// One row of a side drawer: icon, label, optional count, chevron. Shared
/// by the pinned-tags drawer's quick access and the kemono sidebar so the
/// two read as one family.
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.count,
    this.subtitle,
    this.enabled = true,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? count;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color ink = enabled ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: enabled ? (iconColor ?? theme.colorScheme.secondary) : theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (count != null) ...[
              Text(
                count!,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
            ],
            trailing ?? Icon(Symbols.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The small uppercase label above a group of [DrawerRow]s.
class DrawerSectionLabel extends StatelessWidget {
  const DrawerSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
