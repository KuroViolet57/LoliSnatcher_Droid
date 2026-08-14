import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/history/history.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// The Flow browse floating search bar: a blurred pill hugging the bottom with
/// a search icon, the current query (tap → Query Editor), a history button,
/// a save-search button, and the accent submit arrow.
class FlowSearchBar extends StatefulWidget {
  const FlowSearchBar({super.key});

  static const double height = 54;

  @override
  State<FlowSearchBar> createState() => _FlowSearchBarState();
}

class _FlowSearchBarState extends State<FlowSearchBar> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  @override
  void initState() {
    super.initState();
    searchHandler.searchTextController.addListener(_onChanged);
  }

  @override
  void dispose() {
    searchHandler.searchTextController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MainSearchQueryEditorPage(
          subTag: 'bottom',
          autoFocus: settingsHandler.autofocusSearchbar,
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryList()),
    );
  }

  Future<void> _saveSearch() async {
    await ServiceHandler.vibrate(duration: 25);
    final String text = searchHandler.searchTextController.text.trim();
    if (text.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Nothing to save', style: TextStyle(fontSize: 18)),
        content: const Text('Type some tags first.'),
        leadingIcon: Symbols.info_rounded,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final int? id = await searchHandler.addCurrentTabAsSavedSearch();
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(id != null ? 'Search saved' : 'Already saved', style: const TextStyle(fontSize: 18)),
      content: Text(text),
      leadingIcon: Symbols.bookmark_added_rounded,
      leadingIconColor: Colors.green,
      duration: const Duration(seconds: 2),
    );
  }

  void _removeTag(String tag) {
    ServiceHandler.vibrate(duration: 20);
    searchHandler.removeTagFromSearch(tag);
    searchHandler.searchAction(searchHandler.searchTextController.text, null);
  }

  // Current query shown as removable, type-coloured chips (fixed height,
  // vertically centred, horizontally scrollable). Tap a chip (or any empty
  // space around the chips) to open the editor; the ✕ removes that tag and
  // re-runs the search.
  //
  // The scroll view shrink-wraps to the chips so the empty space to their
  // right belongs to the outer GestureDetector — a tap handler behind a
  // scrollable loses the gesture arena, so the empty area must not be part
  // of the scrollable itself.
  Widget _chips() {
    final List<String> tags = searchHandler.searchTextControllerTags;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openEditor,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < tags.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                _chip(context, tags[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String tag) {
    // Strip a leading -/~ (exclude / or) for colour lookup + display prefix.
    final bool isExclude = tag.startsWith('-');
    final bool isOr = tag.startsWith('~');
    final String bare = tag.replaceFirst(RegExp('^[-~]'), '');
    Color color =
        TagHandler.instance
            .getTagFor(bare, searchHandler.tabs.isEmpty ? null : searchHandler.currentBooru)
            .getColour() ??
        const Color(0xFF8A80A0);
    if (isExclude) color = const Color(0xFFE5766B);
    final Color textColor = Color.lerp(color, Colors.white, context.isLight ? 0.0 : 0.35)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openEditor,
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isExclude || isOr)
              Text(
                isExclude ? '−' : '~',
                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            Flexible(
              child: Text(
                bare.replaceAll('_', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 3),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _removeTag(tag),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Symbols.close_rounded, size: 14, color: textColor.withValues(alpha: 0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String query = searchHandler.searchTextController.text.trim();
    final bool hasQuery = query.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(27),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: FlowSearchBar.height,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1622).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: const Color(0xFF2E2940)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.only(left: 18, right: 7),
          child: Row(
            children: [
              // Tapping the magnifier RUNS the current query (the rest of
              // the pill opens the editor).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  searchHandler.searchTextController.clearComposing();
                  searchHandler.searchAction(searchHandler.searchTextController.text, null);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Symbols.search_rounded, size: 21, color: Color(0xFF8A80A0)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: hasQuery
                    ? _chips()
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openEditor,
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Add tags — try artist:…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF8A80A0),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
              IconButton(
                tooltip: 'Search history',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.history_rounded, size: 21, color: Color(0xFFB5AEC4)),
                onPressed: _openHistory,
              ),
              IconButton(
                tooltip: 'Save search',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.bookmark_add_rounded, size: 21, color: Color(0xFFB5AEC4)),
                onPressed: _saveSearch,
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: _openEditor,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Symbols.arrow_forward_rounded,
                    size: 20,
                    color: theme.colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
