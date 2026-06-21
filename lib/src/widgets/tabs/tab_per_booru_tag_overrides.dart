import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';

// Per-booru tag override editor shown when a tab is in merge mode.
// One row per participating booru (primary + secondaries). Each row holds:
//   - a text field for that booru's extra/override tags
//   - a small "Inherit main" switch (default ON = additive)
//   - inline tag autocomplete pulled from that booru's own handler so
//     suggestions are local to the site you're typing for
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
                'Extra tags go to that booru only. Turn off the "Inherit main" '
                "checkbox if the main tag doesn't exist on that booru.",
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
  late final TextEditingController controller;
  late final FocusNode focusNode;
  late final BooruHandler handler;

  Timer? _debounce;
  CancelToken? _cancelToken;
  bool _loading = false;
  bool _failed = false;
  List<TagSuggestion> _suggestions = const [];
  String _lastQueriedWord = '';

  String get _booruKey => widget.booru.name ?? '';

  bool get _inherit => widget.tab.inheritMainTags[_booruKey] ?? true;

  // The slice the autocomplete should be querying — everything after the last
  // space, with any leading negation/restrict prefix stripped so "-naruto"
  // and "1#naruto" still autocomplete "naruto".
  String get _currentWord {
    final String text = controller.text;
    final int cutoff = text.lastIndexOf(' ');
    final String word = cutoff < 0 ? text : text.substring(cutoff + 1);
    return word.replaceAll(RegExp('^[-~]'), '').replaceAll(RegExp(r'^\d+#'), '').trim();
  }

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.tab.tagOverrides[_booruKey] ?? '');
    focusNode = FocusNode();
    // Build a single-booru handler for this row so suggestions come from the
    // right site. Cheap and shared across the row's lifetime.
    handler = BooruHandlerFactory().getBooruHandler([widget.booru], null).booruHandler;
    controller.addListener(_onTextChanged);
    focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    controller.removeListener(_onTextChanged);
    focusNode.removeListener(_onFocusChanged);
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {}); // toggles panel visibility
  }

  void _onTextChanged() {
    // Persist full override text.
    final String value = controller.text;
    final String key = _booruKey;
    if (key.isNotEmpty) {
      if (value.trim().isEmpty) {
        widget.tab.tagOverrides.remove(key);
      } else {
        widget.tab.tagOverrides[key] = value;
      }
    }

    // Debounce an autocomplete query for the in-progress (last) word only.
    _debounce?.cancel();
    final String word = _currentWord;
    if (word.isEmpty) {
      _cancelToken?.cancel();
      _suggestions = const [];
      _loading = false;
      _failed = false;
      if (mounted) setState(() {});
      return;
    }
    if (word == _lastQueriedWord && _suggestions.isNotEmpty) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runQuery(word));
  }

  Future<void> _runQuery(String word) async {
    _cancelToken?.cancel();
    if (!handler.hasTagSuggestions) {
      // No remote suggestions for this booru; clear silently.
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _failed = false;
      });
      return;
    }
    _lastQueriedWord = word;
    _cancelToken = CancelToken();
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final res = await handler.getTagSuggestions(word, cancelToken: _cancelToken);
    if (!mounted) return;
    res.fold(
      (err) {
        final dynamic e = err.error;
        if (e is DioException && CancelToken.isCancel(e)) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
      },
      (data) {
        setState(() {
          _loading = false;
          _failed = false;
          _suggestions = data;
        });
      },
    );
  }

  void _onSuggestionTap(TagSuggestion tag) {
    final String text = controller.text;
    final int cutoff = text.lastIndexOf(' ');
    final String prefix = cutoff < 0 ? '' : text.substring(0, cutoff + 1);
    final String newText = '$prefix${tag.tag} ';
    controller.text = newText;
    controller.selection = TextSelection.collapsed(offset: newText.length);
    // _onTextChanged fires from the assignment above and will clear the panel
    // because the last word is now empty.
  }

  void _onSubmitted(String _) {
    // Same as tapping the main search button: SearchHandler reads the main bar
    // text and rebuilds the tab carrying the latest overrides forward.
    final SearchHandler s = SearchHandler.instance;
    s.searchAction(s.searchTextController.text, null);
  }

  void _onInheritToggle(bool? value) {
    final String key = _booruKey;
    if (key.isEmpty) return;
    if (value ?? true) {
      widget.tab.inheritMainTags.remove(key);
    } else {
      widget.tab.inheritMainTags[key] = false;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool showPanel = focusNode.hasFocus && _currentWord.isNotEmpty;

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
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: _onSubmitted,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _inherit ? '+ extra tags for this booru' : 'tags for this booru only',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Row(
              children: [
                SizedBox(
                  height: 28,
                  width: 28,
                  child: Checkbox(
                    value: _inherit,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _onInheritToggle,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _onInheritToggle(!_inherit),
                  child: Text(
                    'Inherit main tags',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (showPanel)
            _SuggestionsPanel(
              loading: _loading,
              failed: _failed,
              suggestions: _suggestions,
              onTap: _onSuggestionTap,
              onRetry: () => _runQuery(_currentWord),
            ),
        ],
      ),
    );
  }
}

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.loading,
    required this.failed,
    required this.suggestions,
    required this.onTap,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final List<TagSuggestion> suggestions;
  final void Function(TagSuggestion) onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 6, 0, 0),
        child: SizedBox(height: 2, child: LinearProgressIndicator(minHeight: 2)),
      );
    }

    if (failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
        child: InkWell(
          onTap: onRetry,
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

    if (suggestions.isEmpty) return const SizedBox.shrink();

    final TagHandler tagHandler = TagHandler.instance;
    final int visibleCount = suggestions.length > 6 ? 6 : suggestions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
            final tag = suggestions[index];
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
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
