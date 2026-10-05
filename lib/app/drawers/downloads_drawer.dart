import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/app/drawers/drawer_quick_access.dart';
import 'package:lolisnatcher/features/downloads/logic/dd_controller.dart';
import 'package:lolisnatcher/features/downloads/ui/drawer/dd_selection_actions.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';

/// The pin drawer: pinned tags and quick access, plus the multi-select bar
/// when the current tab has posts selected. The download queue list stays
/// off this drawer. Snatching itself is unchanged.
class DownloadsDrawer extends StatefulWidget {
  const DownloadsDrawer({
    required this.toggleDrawer,
    super.key,
  });

  final VoidCallback toggleDrawer;

  @override
  State<DownloadsDrawer> createState() => _DownloadsDrawerState();
}

class _DownloadsDrawerState extends State<DownloadsDrawer> {
  late final DownloadsDrawerController _controller = DownloadsDrawerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Obx(() {
              if (searchHandler.tabs.isEmpty || searchHandler.currentSelected.isEmpty) {
                return const SizedBox.shrink();
              }
              return DDSelectionActions(
                controller: _controller,
                toggleDrawer: widget.toggleDrawer,
              );
            }),
            Expanded(child: DrawerQuickAccess(toggleDrawer: widget.toggleDrawer)),
          ],
        ),
      ),
    );
  }
}
