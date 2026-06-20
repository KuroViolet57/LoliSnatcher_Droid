import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/preview/query_editor_core.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';

// Per-booru tag override editor shown when a tab is in merge mode.
// One small field per participating booru (primary + secondaries). Empty
// fields inherit the main search bar's tags; non-empty fields are sent only
// to that one child handler. Each field gets its own QueryEditorController so
// tag autocomplete is sourced from the matching child booru, not the global
// current handler — that's the whole point of letting the user write a
// different tag per site.
class TabPerBooruTagOverrides extends StatelessWidget {
  const TabPerBooruTagOverrides({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;

    return Obx(() {
      if (searchHandler.tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      final secondaries = searchHandler.currentSecondaryBoorus.value ?? const <Booru>[];
      if (secondaries.isEmpty) {
        return const SizedBox.shrink();
      }

      final List<Booru> participants = [searchHandler.currentBooru, ...secondaries];
      final SearchTab tab = searchHandler.currentTab;

      return Padding(
        padding: const EdgeInsets.fromLTRB(5, 0, 5, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Per-booru tag overrides',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'Leave a field empty to use the main search tags.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final booru in participants)
              _OverrideRow(
                // Re-key per booru name + tab id so swapping the tab rebuilds
                // the row with the right initial value and a fresh controller.
                key: ValueKey('${tab.id}::${booru.name ?? ''}'),
                booru: booru,
                tab: tab,
              ),
          ],
        ),
      );
    });
  }
}

class _OverrideRow extends StatefulWidget {
  const _OverrideRow({required this.booru, required this.tab, super.key});

  final Booru booru;
  final SearchTab tab;

  @override
  State<_OverrideRow> createState() => _OverrideRowState();
}

class _OverrideRowState extends State<_OverrideRow> {
  late final QueryEditorController qec;

  String get _booruKey => widget.booru.name ?? '';
  String get _cleanedInput => qec.suggestionTextControllerRawInput;

  @override
  void initState() {
    super.initState();
    qec = QueryEditorController(onUpdate: _onQecUpdate, booru: widget.booru);
    qec.initialize();
    final initial = widget.tab.tagOverrides[_booruKey] ?? '';
    if (initial.isNotEmpty) {
      qec.suggestionTextController.text = initial;
    }
    qec.suggestionTextController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    qec.suggestionTextController.removeListener(_onTextChanged);
    qec.dispose();
    super.dispose();
  }

  void _onQecUpdate() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    final value = qec.suggestionTextController.text;
    final key = _booruKey;
    if (key.isEmpty) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      widget.tab.tagOverrides.remove(key);
    } else {
      widget.tab.tagOverrides[key] = value;
    }
  }

  void _onSubmitted(String _) {
    // Same as tapping the main search button: SearchHandler reads the main bar
    // text and rebuilds the tab carrying the latest overrides forward.
    final searchHandler = SearchHandler.instance;
    searchHandler.searchAction(searchHandler.searchTextController.text, null);
  }

  // Replaces the last word being typed with the chosen suggestion and a
  // trailing space, mirroring how the main editor inserts a tag.
  void _onSuggestionTap(TagSuggestion tag) {
    final String current = qec.suggestionTextController.text;
    final int cutoff = current.lastIndexOf(' ');
    final String prefix = cutoff < 0 ? '' : current.substring(0, cutoff + 1);
    qec.suggestionTextController.text = '$prefix${tag.tag} ';
    qec.suggestionTextController.selection = TextSelection.collapsed(
      offset: qec.suggestionTextController.text.length,
    );
    qec.suggestedTags = [];
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 130),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: TabBooruSelectorItem(booru: widget.booru, compact: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: qec.suggestionTextController,
                  focusNode: qec.suggestionTextFocusNode,
                  onSubmitted: _onSubmitted,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: SearchHandler.instance.currentTab.tags.isEmpty
                        ? 'Tags for this booru'
                        : SearchHandler.instance.currentTab.tags,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          _SuggestionsPanel(
            qec: qec,
            onTap: _onSuggestionTap,
            cleanedInput: _cleanedInput,
          ),
        ],
      ),
    );
  }
}

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.qec,
    required this.onTap,
    required this.cleanedInput,
  });

  final QueryEditorController qec;
  final void Function(TagSuggestion) onTap;
  final String cleanedInput;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: qec.suggestionTextFocusNodeHasFocus,
      builder: (context, hasFocus, _) {
        // Only show the panel while the field is focused; otherwise a stale
        // suggestion list would sit under every override row in the drawer.
        if (!hasFocus) return const SizedBox.shrink();
        if (cleanedInput.isEmpty) return const SizedBox.shrink();

        if (qec.loading) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(0, 6, 0, 0),
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        }

        if (qec.failed) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
            child: InkWell(
              onTap: () => qec.runSearch(instant: true),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Failed to load suggestions (tap to retry)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            ),
          );
        }

        final List<TagSuggestion> tags = qec.suggestedTags;
        if (tags.isEmpty) return const SizedBox.shrink();

        final TagHandler tagHandler = TagHandler.instance;
        final int visibleCount = tags.length > 6 ? 6 : tags.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: visibleCount,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              itemBuilder: (context, index) {
                final tag = tags[index];
                final tagColor = tagHandler.getTag(tag.tag).getColour();
                return InkWell(
                  onTap: () => onTap(tag),
                  child: Container(
                    color: tagColor?.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        if (tag.icon != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: tag.icon,
                          ),
                        Expanded(child: TagSuggestionText(tag: tag)),
                        if (tag.count > 0)
                          Text(
                            _formatCount(tag.count),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      },
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
