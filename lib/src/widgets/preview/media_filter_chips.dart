import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';

/// Flow filter chips (All / Images / Video / Sound) shown above the grid for
/// the local feeds (Favourites / Downloads / Collections). Sets the handler's
/// media filter and re-filters the fetched list in place.
class MediaFilterChips extends StatefulWidget {
  const MediaFilterChips({required this.tab, super.key});

  final SearchTab tab;

  @override
  State<MediaFilterChips> createState() => _MediaFilterChipsState();
}

class _MediaFilterChipsState extends State<MediaFilterChips> {
  static const List<({String value, String label, IconData icon})> _filters = [
    (value: 'all', label: 'All', icon: Symbols.apps_rounded),
    (value: 'image', label: 'Images', icon: Symbols.image_rounded),
    (value: 'video', label: 'Video', icon: Symbols.videocam_rounded),
    (value: 'sound', label: 'Sound', icon: Symbols.volume_up_rounded),
  ];

  void _select(String value) {
    final handler = widget.tab.booruHandler;
    if (handler.mediaFilter == value) return;
    handler.mediaFilter = value;
    handler.filterFetched();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String active = widget.tab.booruHandler.mediaFilter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final f = _filters[i];
            final bool isActive = f.value == active;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _select(f.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? theme.colorScheme.secondary : theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: isActive ? theme.colorScheme.secondary : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      f.icon,
                      size: 15,
                      color: isActive ? theme.colorScheme.onSecondary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isActive ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
