import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// One doujin tag chip. Gesture routing follows the doujin "Tag chip tap"
/// setting: one gesture opens the (centered) tag menu, the other opens the
/// tag as a BACKGROUND tab — long-press always does whichever tap doesn't.
/// (Cards keep the opposite scheme: tap opens, long-press menus.)
class DoujinTagChip extends StatelessWidget {
  const DoujinTagChip({
    required this.tag,
    required this.booru,
    required this.onOpenMenu,
    this.isMarked = false,
    super.key,
  });

  final Tag tag;
  final Booru booru;
  final VoidCallback onOpenMenu;
  final bool isMarked;

  void _openAsBackgroundTab(BuildContext context) {
    final String placement = SourceSettingsHandler.instance.tabPlacement(booru);
    SearchHandler.instance.addTabByString(
      tag.fullString,
      customBooru: booru,
      addMode: placement == 'next' ? TabAddMode.next : TabAddMode.end,
      switchToNew: false,
    );
    FlashElements.showSnackbar(
      context: context,
      title: const Text('Added new tab', style: TextStyle(fontSize: 18)),
      content: Text(tag.fullString, style: const TextStyle(fontSize: 14)),
      duration: const Duration(seconds: 2),
      sideColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color? typeColor = tag.tagType.getColour();
    final Color base = (typeColor == null || typeColor == Colors.transparent)
        ? Theme.of(context).colorScheme.onSurface
        : typeColor;
    final bool tapOpensTab = SourceSettingsHandler.instance.tagChipTap(booru) == 'newtab';

    return Material(
      color: isMarked ? const Color(0xFFB8860B).withValues(alpha: 0.3) : base.withValues(alpha: 0.13),
      shape: StadiumBorder(
        side: BorderSide(color: isMarked ? const Color(0xFFDAA520) : base.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => tapOpensTab ? _openAsBackgroundTab(context) : onOpenMenu(),
        onLongPress: () => tapOpensTab ? onOpenMenu() : _openAsBackgroundTab(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMarked) ...[
                const Icon(Symbols.star_rounded, size: 13, color: Color(0xFFDAA520)),
                const SizedBox(width: 3),
              ],
              Text(
                tag.fullString.replaceAll('_', ' '),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (tag.count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  tag.count.toFormattedString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
