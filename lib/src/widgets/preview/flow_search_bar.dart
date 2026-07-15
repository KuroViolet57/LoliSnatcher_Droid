import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/history/history.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_tag_chip.dart';

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
        leadingIcon: Icons.info_outline,
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
      leadingIcon: Icons.bookmark_added,
      leadingIconColor: Colors.green,
      duration: const Duration(seconds: 2),
    );
  }

  void _removeTag(String tag) {
    ServiceHandler.vibrate(duration: 20);
    searchHandler.removeTagFromSearch(tag);
    searchHandler.searchAction(searchHandler.searchTextController.text, null);
  }

  // Current query shown as removable, type-coloured chips (horizontally
  // scrollable). Tap a chip to open the editor; the ✕ removes that tag and
  // re-runs the search.
  Widget _chips() {
    final List<String> tags = searchHandler.searchTextControllerTags;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tags.length,
      separatorBuilder: (_, _) => const SizedBox(width: 5),
      itemBuilder: (context, i) {
        final String tag = tags[i];
        return Center(
          child: MainSearchTagChip(
            tag: tag,
            tab: searchHandler.currentTab,
            onTap: _openEditor,
            onDeleteTap: () => _removeTag(tag),
          ),
        );
      },
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
              const Icon(Icons.search, size: 21, color: Color(0xFF8A80A0)),
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
                icon: const Icon(Icons.history, size: 21, color: Color(0xFFB5AEC4)),
                onPressed: _openHistory,
              ),
              IconButton(
                tooltip: 'Save search',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.bookmark_add_outlined, size: 21, color: Color(0xFFB5AEC4)),
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
                    Icons.arrow_forward,
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
