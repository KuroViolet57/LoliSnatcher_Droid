import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:dio/dio.dart';
import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:lolisnatcher/features/tags/logic/pinned_tag_visibility.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/settings/modular_ui.dart';
import 'package:lolisnatcher/core/ui/desktop_scroll.dart';
import 'package:lolisnatcher/sources/framework/tags/tag_catalog_source.dart';
import 'package:lolisnatcher/features/tags/ui/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/features/tags/ui/tag_type_strip.dart';
import 'package:rich_text_controller/rich_text_controller.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/sources/local/mergebooru_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/history_item.dart';
import 'package:lolisnatcher/models/meta_tag.dart';
import 'package:lolisnatcher/models/pinned_tag.dart';
import 'package:lolisnatcher/models/tag_suggestion.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/core/storage/booru_tag_store.dart';
import 'package:lolisnatcher/sources/doujin/common/doujin_filters.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/features/tags/logic/followed_artists_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_history_store.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/ui/buttons/cancel_button.dart';
import 'package:lolisnatcher/core/ui/buttons/confirm_button.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/kaomoji/kaomoji.dart';
import 'package:lolisnatcher/core/ui/text/marquee_text.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/features/viewer/ui/info/tag_view.dart';
import 'package:lolisnatcher/features/history/ui/history.dart';
import 'package:lolisnatcher/core/ui/image/booru_favicon.dart';
import 'package:lolisnatcher/features/feed/ui/search/main_search_bar.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';

part 'main_search_query_editor_page/suggestion_text.dart';
part 'main_search_query_editor_page/editor_source.dart';
part 'main_search_query_editor_page/metatags_block.dart';
part 'main_search_query_editor_page/suggestions_content.dart';
part 'main_search_query_editor_page/history_block.dart';
part 'main_search_query_editor_page/tag_builder_block.dart';
part 'main_search_query_editor_page/popular_tags_block.dart';
part 'main_search_query_editor_page/prefix_edit_dialog.dart';
part 'main_search_query_editor_page/pinned_tags_block.dart';
part 'main_search_query_editor_page/pin_dialogs.dart';
part 'main_search_query_editor_page/pinned_tags_manager.dart';
part 'main_search_query_editor_page/doujin_filters_block.dart';

class MainSearchQueryEditorPage extends StatefulWidget {
  const MainSearchQueryEditorPage({
    this.subTag,
    this.tagToEditIndex,
    this.autoFocus = true,
    super.key,
  });

  final String? subTag;
  final int? tagToEditIndex;
  final bool autoFocus;

  @override
  State<MainSearchQueryEditorPage> createState() => _MainSearchQueryEditorPageState();
}

class _MainSearchQueryEditorPageState extends State<MainSearchQueryEditorPage> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  final ScrollController suggestionsScrollController = ScrollController(),
      tagToEditScrollController = ScrollController();
  final AutoScrollController searchBarScrollController = AutoScrollController();

  late final RichTextController suggestionTextController;
  String get suggestionTextControllerCleanedInput => suggestionTextController.text
      .replaceAll(RegExp('^-'), '')
      .replaceAll(RegExp('^~'), '')
      .replaceAll(RegExp(r'^\d+#'), '')
      .trim();

  final FocusNode suggestionTextFocusNode = FocusNode();
  final ValueNotifier<bool> suggestionTextFocusNodeHasFocus = ValueNotifier(false);

  bool loading = true, failed = false;
  String? failedMsg;

  String? tagToEdit;
  int? tagToEditIndex;

  List<TagSuggestion> suggestedTags = [];

  CancelToken? cancelToken;

  Timer? debounce;

  @override
  void initState() {
    super.initState();

    final tags = searchHandler.currentBooruHandler.availableMetaTags();

    suggestionTextController = RichTextController(
      text: '',
      onMatch: (_) {},
      onMatchIndex: (_) {},
      regExpDotAll: true,
      regExpMultiLine: true,
      regExpUnicode: true,
      targetMatches:
          [
                ...tags,
                if (tags.isEmpty) GenericMetaTag(),
              ]
              .map(
                (e) => MatchTargetItem(
                  regex: e.keyDividerMatcher,
                  allowInlineMatching: true,
                  deleteOnBack: false,
                  style: TextStyle(
                    color: Colors.pink,
                    backgroundColor: Colors.pink.withValues(alpha: 0.1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              .toList(),
    );

    searchHandler.searchTextController.addListener(onSearchTextChanged);
    suggestionTextController.addListener(onSuggestionTextChanged);
    suggestionTextFocusNode.addListener(suggestionTextFocusListener);

    if (widget.tagToEditIndex != null) {
      onChipTap(
        searchHandler.searchTextControllerTags[widget.tagToEditIndex!],
        widget.tagToEditIndex!,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        searchBarScrollController.scrollToIndex(
          widget.tagToEditIndex!,
          preferPosition: AutoScrollPosition.end,
        );
      });
    } else {
      if (widget.autoFocus) {
        suggestionTextFocusNode.requestFocus();
      }
      runSearch();
    }
  }

  void onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _lastSuggestionText = '';
  void onSuggestionTextChanged() {
    // focus change can trigger this too, so we run search only when text changed
    if (suggestionTextController.text != _lastSuggestionText) {
      _lastSuggestionText = suggestionTextController.text;
      runSearch(instant: false);
    }
  }

  void suggestionTextFocusListener() {
    if (mounted) {
      suggestionTextFocusNodeHasFocus.value = suggestionTextFocusNode.hasFocus;
    }
  }

  Future<void> runSearch({
    bool instant = true,
  }) async {
    final handler = searchHandler.currentBooruHandler;
    if (suggestionTextControllerCleanedInput.isEmpty) {
      debounce?.cancel();
      cancelToken?.cancel();
      loading = false;
      failed = false;
      failedMsg = null;
      suggestedTags.clear();
      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          suggestionsScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      return;
    }

    debounce?.cancel();
    debounce = Timer(
      instant ? Duration.zero : const Duration(milliseconds: 400),
      () async {
        loading = true;
        failed = false;
        failedMsg = null;
        suggestedTags.clear();
        cancelToken?.cancel();
        setState(() {});

        bool isCancelled = false;

        // The text this lookup answers. Once the page is closed, or the user
        // typed on, its answer is dropped instead of replacing the newer one.
        final String input = suggestionTextControllerCleanedInput;
        bool isStale() => !mounted || suggestionTextControllerCleanedInput != input;

        final metaTags = searchHandler.currentBooruHandler.availableMetaTags();
        final MetaTag? metaTag = metaTags.firstWhereOrNull(
          (p) => p.keyParser(suggestionTextControllerCleanedInput) != null,
        );
        if (metaTag != null) {
          // A typed `artist:asa` lists the source's own catalog first.
          final List<TagSuggestion>? fromCatalog = await TagCatalogSource.suggestFromCatalog(
            handler,
            searchHandler.currentBooru,
            suggestionTextControllerCleanedInput,
          );
          if (isStale()) return;
          if (fromCatalog != null) {
            suggestedTags = fromCatalog;
          } else if (metaTag.hasAutoComplete) {
            final List<TagSuggestion> autoComplete = await metaTag.getAutoComplete(suggestionTextControllerCleanedInput);
            if (isStale()) return;
            suggestedTags = autoComplete;
            suggestedTags.sort((a, b) => a.tag.compareTo(b.tag));
          } else {
            suggestedTags.clear();
          }

          loading = false;
          failed = false;
          failedMsg = null;
          setState(() {});
        } else if (handler.hasTagSuggestions) {
          cancelToken = CancelToken();
          final res = await handler.getTagSuggestions(
            searchHandler.currentBooruHandler is MergebooruHandler
                ? suggestionTextController.text
                : suggestionTextControllerCleanedInput,
            cancelToken: cancelToken,
          );
          res.fold(
            (e) {
              final errorObj = e.error;
              if (errorObj is DioException && CancelToken.isCancel(errorObj)) {
                isCancelled = true;
                failed = false;
                failedMsg = null;
              } else {
                loading = false;
                failed = true;
                failedMsg = e.statusCode?.toString() ?? e.message;
              }

              if (mounted) {
                setState(() {});
              }
            },
            (data) {
              loading = false;
              failed = false;
              failedMsg = null;
              suggestedTags = data;
              if (mounted) {
                setState(() {});
              }

              // Through the HANDLER, so handlers that don't feed the shared
              // booru tag store (doujin sources) don't re-type booru tags.
              for (final tag in suggestedTags.where((t) => !t.type.isNone)) {
                handler.addTagsWithType([tag.tag], tag.type);
              }
            },
          );
        } else {
          final databaseSearch = (await settingsHandler.dbHandler.getTags(suggestionTextControllerCleanedInput, 10))
              .map((
                tag,
              ) {
                return TagSuggestion(
                  tag: tag,
                  type: tagHandler.getTag(tag).tagType,
                  icon: const Icon(Symbols.archive_rounded),
                );
              })
              .toList();

          final historySearch =
              (await SearchHistoryStore.byInput(suggestionTextControllerCleanedInput, 10))
                  .map((tag) {
                    return TagSuggestion(
                      tag: tag,
                      type: tagHandler.getTag(tag).tagType,
                      icon: const Icon(Symbols.history_rounded),
                    );
                  })
                  .where(
                    (htag) =>
                        !databaseSearch.any((dbtag) => dbtag.tag.trim().toLowerCase() == htag.tag.trim().toLowerCase()),
                  )
                  .toList();
          if (isStale()) return;

          loading = false;
          failed = false;
          failedMsg = null;
          suggestedTags = [
            ...databaseSearch,
            ...historySearch,
          ];
          suggestedTags.sort((a, b) => a.tag.toLowerCase().compareTo(b.tag.toLowerCase()));
          setState(() {});
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !isCancelled) {
            suggestionsScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      },
    );
  }

  void onChipTap(String tag, int tagIndex) {
    if (tagToEditIndex == tagIndex) {
      suggestionTextController.clear();
      tagToEditIndex = null;
      tagToEdit = null;
    } else {
      suggestionTextController.value = TextEditingValue(
        text: tag,
        selection: TextSelection(
          baseOffset: tag.length,
          extentOffset: tag.length,
          affinity: TextAffinity.upstream,
        ),
      );
      suggestionTextFocusNode.requestFocus();

      tagToEditIndex = tagIndex;
      tagToEdit = tag;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        searchBarScrollController.scrollToIndex(
          tagIndex,
          preferPosition: AutoScrollPosition.end,
        );
      });
    }
    setState(() {});

    runSearch();
  }

  void onChipLongTap(String tag, int tagIndex) {
    // Same action sheet as long-pressing a suggestion (tag type, preview,
    // copy, pin/unpin) — single tap already covers editing, and pinning is
    // the thing you actually want from a tag that's already in the query.
    // Add/exclude entries are hidden: the tag is in the query already.
    onSuggestionLongTap(
      TagSuggestion(tag: tag.startsWith('-') ? tag.substring(1) : tag),
      showAddActions: false,
    );
  }

  void onChipDeleteTap(String tag, int tagIndex) {
    final List<String> tempTags = searchHandler.searchTextControllerTags..removeAt(tagIndex);
    searchHandler.searchTextController.text = tempTags.join(' ');
    if (tagToEditIndex != null) {
      // TODO update index to closest instead of resetting?
      tagToEditIndex = null;
      tagToEdit = null;
      suggestionTextController.clear();
      setState(() {});
    }
  }

  void onResetTap() {
    searchHandler.searchTextController.text = searchHandler.currentTab.tags.trim();
  }

  void onClearTap() {
    if (tagToEditIndex != null) {
      tagToEditIndex = null;
      tagToEdit = null;
      suggestionTextController.clear();
      setState(() {});
    }
  }

  void onSearchTap() {
    Navigator.of(context).pop();
    searchHandler.searchTextController.clearComposing();
    searchHandler.searchAction(searchHandler.searchTextController.text, null);
  }

  void onSearchLongTap() {
    Navigator.of(context).pop();
    ServiceHandler.vibrate();
    searchHandler.searchTextController.clearComposing();
    searchHandler.addTabByString(searchHandler.searchTextController.text, switchToNew: true);
  }

  void onSuggestionTap(
    TagSuggestion tag, {
    bool raw = false,
  }) {
    String tagText = tag.tag;

    if (!raw) {
      final String extrasFromInput = suggestionTextController.text
          .replaceAll(suggestionTextControllerCleanedInput, '')
          .trim();
      tagText = '$extrasFromInput$tagText';
    }

    final int? itemIndex = tagToEditIndex;
    if (tagToEditIndex != null) {
      final List<String> tempTags = [...searchHandler.searchTextControllerTags];
      tempTags[tagToEditIndex!] = tagText;
      searchHandler.searchTextController.text = tempTags.join(' ');
    } else {
      searchHandler.searchTextController.text = '${searchHandler.searchTextController.text.trim()} $tagText';
    }

    suggestedTags = [];
    suggestionTextController.clear();
    suggestionTextFocusNode.requestFocus();
    tagToEditIndex = null;
    tagToEdit = null;
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (itemIndex != null) {
        searchBarScrollController.scrollToIndex(
          itemIndex,
          duration: const Duration(milliseconds: 300),
          preferPosition: AutoScrollPosition.end,
        );
      } else {
        searchBarScrollController.animateTo(
          searchBarScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    runSearch();
  }

  Future<void> onSuggestionLongTap(
    TagSuggestion tag, {
    bool showAddActions = true,
  }) async {
    // TODO add more actions? hate/fave +-, add as exclude, add with multibooru number?
    await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      page: (_) {
        return SettingsBottomSheet(
          contentItems: [
            const SizedBox(height: 16),
            TagSuggestionText(tag: tag, isExpanded: false),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 24,
                  decoration: BoxDecoration(
                    // Domain-aware: the site's own type wins, and the shared
                    // booru tag map is never consulted on a doujin source.
                    color: tagHandler.colourForDisplay(
                      tag.tag,
                      searchHandler.currentBooru,
                      ownType: tag.type,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  tagHandler
                      .typeForDisplay(tag.tag, searchHandler.currentBooru, ownType: tag.type)
                      .locName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showAddActions) ...[
              ListTile(
                title: Text(context.loc.add),
                leading: const Icon(
                  Symbols.add_rounded,
                  color: Colors.green,
                ),
                onTap: () async {
                  onSuggestionTap(tag);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: Text(context.loc.exclude),
                leading: const Icon(
                  Symbols.remove_rounded,
                  color: Colors.red,
                ),
                onTap: () async {
                  tag = tag.copyWith(tag: '-${tag.tag}');
                  onSuggestionTap(tag);
                  Navigator.of(context).pop();
                },
              ),
            ],
            TagContentPreview(
              tag: tag.tag,
              boorus: searchHandler.currentBooru.type?.isMerge == true
                  ? [
                      ...(searchHandler.currentBooruHandler as MergebooruHandler).booruHandlers.map((e) => e.booru),
                    ]
                  : [searchHandler.currentBooru],
              parentTab: null,
            ),
            ListTile(
              title: Text(context.loc.copy),
              leading: const Icon(Symbols.content_copy_rounded),
              onTap: () async {
                final tagText = tag.tag;

                await Clipboard.setData(ClipboardData(text: tagText));
                FlashElements.showSnackbar(
                  title: Text(context.loc.copied, style: const TextStyle(fontSize: 20)),
                  content: Text(context.loc.searchBar.copiedTagToClipboard(tag: tagText)),
                  sideColor: Colors.green,
                  leadingIcon: Symbols.check_rounded,
                  leadingIconColor: Colors.green,
                  duration: const Duration(seconds: 2),
                );
                Navigator.of(context).pop();
              },
            ),
            FutureBuilder<PinnedTag?>(
              future: DoujinDataHandler.isDoujinBooru(searchHandler.currentBooru)
                  ? Future.value(
                      doujinPinsAsPinnedTags(searchHandler.currentBooru)
                          .where((p) => p.tagName == tag.tag)
                          .firstOrNull,
                    )
                  : settingsHandler.dbHandler.getPinnedTag(
                      tag.tag,
                      booruType: searchHandler.currentBooru.type?.name,
                      booruName: searchHandler.currentBooru.name,
                    ),
              builder: (_, snapshot) {
                final isPinned = snapshot.data != null || tag.isPinned == true;
                final pinnedTag = snapshot.data;

                return ListTile(
                  title: Text(isPinned ? context.loc.pinnedTags.unpinTag : context.loc.pinnedTags.pinTag),
                  leading: Icon(isPinned ? Symbols.push_pin_rounded : Symbols.push_pin_rounded),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (isPinned && pinnedTag != null) {
                      await showUnpinTagDialog(
                        context,
                        tag.tag,
                        pinnedTag,
                        () => onTagUnpinned(tag),
                      );
                    } else {
                      await showPinTagDialog(
                        context,
                        tag.tag,
                        searchHandler.currentBooru,
                        () => onTagPinned(tag),
                      );
                    }
                  },
                );
              },
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        );
      },
    ).open();
  }

  void onSuggestionTextSubmitted(String text) {
    if (text.isNotEmpty) {
      onSuggestionTap(TagSuggestion(tag: text), raw: true);
    } else {
      onSearchTap();
    }
  }

  void onTagPinned(TagSuggestion tag) {
    final index = suggestedTags.indexWhere((t) => t == tag);

    if (index != -1) {
      suggestedTags[index] = suggestedTags[index].copyWith(isPinned: true);
      setState(() {});
    }
  }

  void onTagUnpinned(TagSuggestion tag) {
    final index = suggestedTags.indexWhere((t) => t == tag);

    if (index != -1) {
      suggestedTags[index] = suggestedTags[index].copyWith(isPinned: false);
      setState(() {});
    }
  }

  Future<void> onMetatagSelect(AddMetatagBottomSheetResult result) async {
    final tag = result.tag.tagBuilder(
      null,
      result.compareMode == null ? null : (result.tag as MetaTagWithCompareModes).dividerForMode(result.compareMode),
      result.value,
    );
    if (result.shouldAddDirectly) {
      onSuggestionTap(TagSuggestion(tag: tag));
    } else {
      suggestionTextController.text = tag;
    }
    suggestionTextFocusNode.requestFocus();
  }

  double get keyboardActionsHeight => 44;

  KeyboardActionsConfig buildConfig() {
    return KeyboardActionsConfig(
      keyboardActionsPlatform: KeyboardActionsPlatform.ALL,
      nextFocus: false,
      actions: [
        KeyboardActionsItem(
          focusNode: suggestionTextFocusNode,
          displayActionBar: false,
          displayArrows: false,
          displayDoneButton: false,
          footerBuilder: (_) => PreferredSize(
            preferredSize: Size.fromHeight(keyboardActionsHeight),
            child: KeyboardVisibilityBuilder(
              builder: (context, isKbVisible) {
                final buttonStyle = context.theme.elevatedButtonTheme.style?.copyWith(
                  fixedSize: WidgetStateProperty.all<Size>(
                    Size(keyboardActionsHeight, keyboardActionsHeight),
                  ),
                  padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                    EdgeInsets.fromLTRB(
                      4,
                      isKbVisible ? 4 : 0,
                      4,
                      4,
                    ),
                  ),
                );

                return Container(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  height: keyboardActionsHeight - 4,
                  color: context.theme.colorScheme.surface,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          // Add '_' at current cursor position
                          final String beforeSelection = suggestionTextController.selection.textBefore(
                            suggestionTextController.text,
                          );
                          // final String insideSelection = searchHandler.searchTextController.selection.textInside(searchHandler.searchTextController.text);
                          final String afterSelection = suggestionTextController.selection.textAfter(
                            suggestionTextController.text,
                          );
                          suggestionTextController.text = '${beforeSelection}_$afterSelection';
                          // set cursor to the end when tapped unfocused
                          suggestionTextController.selection = TextSelection(
                            baseOffset: beforeSelection.length + 1,
                            extentOffset: beforeSelection.length + 1,
                            affinity: TextAffinity.upstream,
                          );
                        },
                        style: buttonStyle?.copyWith(
                          padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                            EdgeInsets.fromLTRB(
                              4,
                              isKbVisible ? 4 : 0,
                              4,
                              8,
                            ),
                          ),
                        ),
                        child: Align(
                          alignment: isKbVisible ? Alignment.bottomCenter : Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 4,
                            ),
                            child: SizedBox(
                              width: 30,
                              height: 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.theme.colorScheme.onSecondary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () async {
                          final ClipboardData? cdata = await Clipboard.getData(Clipboard.kTextPlain);
                          final String copied = cdata?.text ?? '';
                          if (copied.isNotEmpty) {
                            suggestionTextController.text =
                                '${suggestionTextController.text}${(suggestionTextController.text.isEmpty || suggestionTextController.text.endsWith(' ')) ? '' : ' '}$copied';
                            suggestionTextController.selection = TextSelection(
                              baseOffset: suggestionTextController.text.length,
                              extentOffset: suggestionTextController.text.length,
                              affinity: TextAffinity.upstream,
                            );
                          }
                        },
                        style: buttonStyle,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isKbVisible ? 0 : 20),
                          child: Icon(
                            Symbols.content_paste_rounded,
                            color: context.theme.colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: suggestionTextFocusNode.unfocus,
                        style: buttonStyle,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isKbVisible ? 0 : 20),
                          child: Icon(
                            Symbols.keyboard_hide_rounded,
                            color: context.theme.colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ValueListenableBuilder(
                        valueListenable: suggestionTextController,
                        builder: (context, _, _) {
                          return ElevatedButton(
                            onPressed: suggestionTextControllerCleanedInput.isEmpty
                                ? onSearchTap
                                : () => onSuggestionTextSubmitted(suggestionTextController.text),
                            onLongPress: suggestionTextControllerCleanedInput.isEmpty
                                ? onSearchLongTap
                                : () => onSuggestionLongTap(TagSuggestion(tag: suggestionTextControllerCleanedInput)),
                            style: buttonStyle,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: isKbVisible ? 0 : 20),
                              child: Icon(
                                suggestionTextControllerCleanedInput.isEmpty ? Symbols.search_rounded : Symbols.add_rounded,
                                color: context.theme.colorScheme.onSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    debounce?.cancel();
    cancelToken?.cancel();
    searchHandler.searchTextController.removeListener(onSearchTextChanged);
    suggestionTextFocusNode.removeListener(suggestionTextFocusListener);
    suggestionTextFocusNode.dispose();
    suggestionTextController.removeListener(onSuggestionTextChanged);
    suggestionTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [
      Expanded(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  controller: suggestionsScrollController,
                  interactive: true,
                  scrollbarOrientation: settingsHandler.handSide.value.isLeft
                      ? ScrollbarOrientation.left
                      : ScrollbarOrientation.right,
                  child: ValueListenableBuilder(
                    valueListenable: suggestionTextController,
                    builder: (context, suggestionText, child) => RefreshIndicator(
                      triggerMode: RefreshIndicatorTriggerMode.anywhere,
                      strokeWidth: 4,
                      color: context.theme.colorScheme.secondary,
                      // edgeOffset: MediaQuery.paddingOf(context).top,
                      onRefresh: runSearch,
                      notificationPredicate: (_) => suggestionText.text.isNotEmpty,
                      child: child!,
                    ),
                    child: FadingEdgeScrollView.fromScrollView(
                      child: ListView.builder(
                        reverse: !settingsHandler.useTopSearchbarInput,
                        controller: suggestionsScrollController,
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top + 16,
                          bottom: 12,
                        ),
                        itemCount: suggestedTags.isEmpty ? 1 : min(100, suggestedTags.length),
                        itemBuilder: (context, index) {
                          if (suggestedTags.isEmpty) {
                            if (loading) {
                              return const SizedBox.shrink();
                            } else if (failed) {
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: runSearch,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Symbols.refresh_rounded),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              context.loc.searchBar.failedToLoadSuggestions(
                                                msg: failedMsg?.isNotEmpty == true ? '\n\n[$failedMsg]' : '',
                                              ),
                                              style: context.theme.textTheme.bodyLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (suggestionTextControllerCleanedInput.isEmpty) {
                              return SuggestionsMainContent(
                                onMetatagSelect: onMetatagSelect,
                                onTagTap: (tag) => onSuggestionTap(TagSuggestion(tag: tag)),
                                onInsertTerm: (term) => onSuggestionTap(TagSuggestion(tag: term), raw: true),
                                hidePopular: searchHandler.currentBooru.type?.isFavouritesOrDownloads == true,
                                queryText: () => searchHandler.searchTextController.text,
                                onQueryReplaced: (String q) {
                                  searchHandler.searchTextController.text = q;
                                  setState(() {});
                                },
                              );
                            }

                            return Center(
                              child: Container(
                                height: constraints.maxHeight - 32,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Kaomoji(
                                      category: KaomojiCategory.indifference,
                                      style: TextStyle(fontSize: 36),
                                    ),
                                    Text(
                                      searchHandler.currentBooruHandler.hasTagSuggestions
                                          ? context.loc.searchBar.noSuggestionsFound
                                          : context.loc.searchBar.tagSuggestionsNotAvailable,
                                      style: context.theme.textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final TagSuggestion tag = suggestedTags[index];
                          final tagColor = tagHandler.colourForDisplay(
                            tag.tag,
                            searchHandler.currentBooru,
                            ownType: tag.type,
                          );

                          return Container(
                            height: kMinInteractiveDimension + (tag.hasDescription ? 8 : 0),
                            alignment: Alignment.centerLeft,
                            color: tagColor?.withValues(alpha: 0.1),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onSuggestionTap(tag),
                                onLongPress: () => onSuggestionLongTap(tag),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Tag-type colour bar for quick scanning
                                      // of artist/character/copyright matches.
                                      Container(
                                        width: 4,
                                        height: 22,
                                        margin: const EdgeInsets.only(right: 10),
                                        decoration: BoxDecoration(
                                          color: tagColor ?? context.theme.dividerColor.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      if (tag.icon != null)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: tag.icon,
                                        ),
                                      //
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            TagSuggestionText(
                                              tag: tag,
                                              searchText: suggestionTextControllerCleanedInput,
                                            ),
                                            if (tag.hasDescription)
                                              Text(
                                                tag.description!,
                                                style: context.theme.textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface.withValues(alpha: 0.66),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      //
                                      FutureBuilder<PinnedTag?>(
                                        // Doujin pins live in the doujin
                                        // store; the booru table also answers
                                        // with GLOBAL booru pins, which would
                                        // mark doujin suggestions as pinned
                                        // while the drawer showed nothing.
                                        future: DoujinDataHandler.isDoujinBooru(searchHandler.currentBooru)
                                            ? Future.value(
                                                doujinPinsAsPinnedTags(searchHandler.currentBooru)
                                                    .where((p) => p.tagName == tag.tag)
                                                    .firstOrNull,
                                              )
                                            : settingsHandler.dbHandler.getPinnedTag(
                                                tag.tag,
                                                booruType: searchHandler.currentBooru.type?.name,
                                                booruName: searchHandler.currentBooru.name,
                                              ),
                                        builder: (context, snapshot) {
                                          final isPinned = snapshot.data != null || tag.isPinned == true;
                                          if (isPinned) return const Icon(Symbols.push_pin_rounded, size: 16);

                                          return const SizedBox.shrink();
                                        },
                                      ),
                                      if (tag.count > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 12),
                                          child: Text(
                                            tag.count.toShortString(),
                                            style: context.theme.textTheme.bodySmall?.copyWith(
                                              color: context.theme.colorScheme.onSurface.withValues(alpha: 0.66),
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            //
            if (loading)
              const Positioned(
                bottom: 16,
                right: 16,
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      // Search bar
      SizedBox(
        height: MainSearchBar.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Hero(
            tag: 'mainSearchBar-${widget.subTag}',
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
              ),
              child: MainSearchBar(
                onChipTap: onChipTap,
                onChipLongTap: onChipLongTap,
                onChipDeleteTap: onChipDeleteTap,
                onResetTap: onResetTap,
                onClearTap: onClearTap,
                onSearchTap: onSearchTap,
                onSearchLongTap: onSearchLongTap,
                scrollController: searchBarScrollController,
                selectedTagIndex: tagToEditIndex,
              ),
            ),
          ),
        ),
      ),
      // Suggestions text input
      KeyboardActions(
        enable: settingsHandler.showSearchbarQuickActions && (Platform.isAndroid || Platform.isIOS),
        config: buildConfig(),
        autoScroll: false,
        overscroll: 0,
        isDialog: false,
        child: ValueListenableBuilder(
          valueListenable: suggestionTextFocusNodeHasFocus,
          builder: (context, suggestionTextFocusNodeHasFocus, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SettingsTextInput(
                  controller: suggestionTextController,
                  focusNode: suggestionTextFocusNode,
                  title: context.loc.searchBar.searchForTags,
                  titleAsLabel: true,
                  hintText: context.loc.searchBar.searchForTags,
                  clearable: true,
                  onSubmitted: onSuggestionTextSubmitted,
                  onSubmittedLongTap: (_) => onSuggestionLongTap(
                    TagSuggestion(tag: suggestionTextControllerCleanedInput),
                  ),
                  onlyInput: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  textInputAction: TextInputAction.search,
                  enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
                  showSubmitButton: (text) => !settingsHandler.showSearchbarQuickActions && text.isNotEmpty,
                  contextMenuBuilder: (_, editableTextState) {
                    final List<ContextMenuButtonItem> buttonItems = editableTextState.contextMenuButtonItems;

                    // allow only on single tag input
                    if (!suggestionTextController.text.trim().contains(' ')) {
                      buttonItems.insert(
                        0,
                        ContextMenuButtonItem(
                          label: context.loc.searchBar.prefix,
                          onPressed: () {
                            ContextMenuController.removeAny();
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              showDragHandle: true,
                              builder: (_) => _PrefixEditDialog(suggestionTextController),
                            );
                          },
                        ),
                      );
                    }

                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                  submitIcon: Symbols.add_rounded,
                  prefixIcon: IconButton(
                    icon: const Icon(Symbols.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              // The tag builder lives in the Metatags card of the suggestions
              // (MetatagsBlock); the old helper-key row is gone.
              if (settingsHandler.useTopSearchbarInput)
                const SizedBox(height: 4)
              else if (settingsHandler.showSearchbarQuickActions && (Platform.isAndroid || Platform.isIOS))
                KeyboardVisibilityBuilder(
                  builder: (context, isKbVisible) {
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: double.maxFinite,
                        height:
                            (isKbVisible || (suggestionTextFocusNodeHasFocus && (Platform.isAndroid || Platform.isIOS)))
                            ? 0 // keyboardActionsHeight
                            : MediaQuery.paddingOf(context).bottom,
                        // child: ColoredBox(color: Colors.yellow.withValues(alpha: 0.2)),
                      ),
                    );
                  },
                )
              else
                SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    ];

    if (settingsHandler.useTopSearchbarInput) {
      widgets = widgets.reversed.toList();
      if (settingsHandler.showSearchbarQuickActions) {
        widgets.add(
          KeyboardVisibilityBuilder(
            builder: (context, isKbVisible) {
              return isKbVisible ? SizedBox(height: keyboardActionsHeight) : const SizedBox.shrink();
            },
          ),
        );
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: SafeArea(
        top: settingsHandler.useTopSearchbarInput,
        bottom: settingsHandler.useTopSearchbarInput,
        child: Column(
          children: widgets,
        ),
      ),
    );
  }
}
