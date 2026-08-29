import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// The doujin drawer's "Favourite tags" screen: every tag you MARKED (the
/// gold star), as chips — tap opens the tag on this doujin source, the star
/// button unmarks it. This replaced a mislink to the tag browser.
class DoujinFavouriteTagsPage extends StatefulWidget {
  const DoujinFavouriteTagsPage({required this.booru, super.key});

  final Booru booru;

  @override
  State<DoujinFavouriteTagsPage> createState() => _DoujinFavouriteTagsPageState();
}

class _DoujinFavouriteTagsPageState extends State<DoujinFavouriteTagsPage> {
  final settingsHandler = SettingsHandler.instance;
  final TextEditingController filterController = TextEditingController();

  @override
  void dispose() {
    filterController.dispose();
    super.dispose();
  }

  void _openTag(String tag) {
    final String placement = SourceSettingsHandler.instance.tabPlacement(widget.booru);
    SearchHandler.instance.addTabByString(
      tag,
      customBooru: widget.booru,
      addMode: placement == 'next' ? TabAddMode.next : TabAddMode.end,
      switchToNew: true,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _unmark(String tag) {
    settingsHandler.removeTagFromList('marked', tag);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String filter = filterController.text.trim().toLowerCase();
    final List<String> marked = settingsHandler.markedTags.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final List<String> shown = [
      for (final t in marked)
        if (filter.isEmpty || t.toLowerCase().contains(filter)) t,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Favourite tags')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: TextField(
              controller: filterController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter tags',
                prefixIcon: const Icon(Symbols.search_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${shown.length} marked tags — tap one to search it on ${widget.booru.name ?? 'this source'}, star to unmark',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No marked tags yet — star a tag from its menu to keep it here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in shown)
                          Material(
                            color: const Color(0xFFB8860B).withValues(alpha: 0.25),
                            shape: const StadiumBorder(
                              side: BorderSide(color: Color(0xFFDAA520)),
                            ),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: () => _openTag(tag),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tag.replaceAll('_', ' '),
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _unmark(tag),
                                      child: const Padding(
                                        padding: EdgeInsets.all(3),
                                        child: Icon(Symbols.star_rounded, size: 17, fill: 1, color: Color(0xFFDAA520)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
