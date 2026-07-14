import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/widgets/drawers/downloads/drawer_quick_access.dart';

/// The left drawer. Previously the snatch/download queue; now a navigation
/// panel (quick-access shortcuts, pinned tags, recent searches). Downloading
/// itself is unaffected — only this queue UI was removed from the drawer.
class DownloadsDrawer extends StatelessWidget {
  const DownloadsDrawer({
    required this.toggleDrawer,
    super.key,
  });

  final VoidCallback toggleDrawer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: DrawerQuickAccess(toggleDrawer: toggleDrawer),
      ),
    );
  }
}
