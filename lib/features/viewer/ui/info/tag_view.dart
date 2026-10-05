import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fpdart/fpdart.dart' show FpdartOnIterable;
import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/features/tags/logic/tag_type_lookup.dart';
import 'package:lolisnatcher/features/furaffinity/ui/furaffinity_post_page.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_handler.dart';
import 'package:lolisnatcher/sources/booru/danbooru_handler.dart';
import 'package:lolisnatcher/sources/kemono/kemono_handler.dart';
import 'package:lolisnatcher/models/meta_tag.dart';
import 'package:lolisnatcher/models/pinned_tag.dart';
import 'package:lolisnatcher/features/tags/ui/tag_chip_shell.dart';
import 'package:lolisnatcher/core/logging/navigation_trace.dart';
import 'package:lolisnatcher/core/settings/modular_ui.dart';
import 'package:lolisnatcher/features/viewer/ui/info/flow_action_grid.dart';
import 'package:lolisnatcher/core/ui/loli_dropdown.dart';
import 'package:lolisnatcher/features/feed/ui/search/main_search_query_editor_page.dart';
import 'package:lolisnatcher/features/tabs/ui/tab_selector.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/local/downloads_handler.dart';
import 'package:lolisnatcher/sources/local/favourites_handler.dart';
import 'package:lolisnatcher/features/boards/logic/board_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/foryou_handler.dart';
import 'package:lolisnatcher/sources/local/history_handler.dart';
import 'package:lolisnatcher/sources/booru/idol_sankaku_handler.dart';
import 'package:lolisnatcher/sources/local/mergebooru_handler.dart';
import 'package:lolisnatcher/sources/booru/sankaku_handler.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/core/storage/booru_tag_store.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/framework/reader_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/kemono/ui/kemono_post_page.dart';
import 'package:lolisnatcher/features/recommender/logic/recommender_handler.dart';
import 'package:lolisnatcher/features/boards/ui/boards_page.dart';
import 'package:lolisnatcher/features/doujin/ui/detail/doujin_detail_page.dart';
import 'package:lolisnatcher/features/doujin/ui/reader/doujin_reader_page.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_item_menu.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_build.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/features/feed/logic/floating_preview_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/interests_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/tags/logic/query_alias_resolver.dart';
import 'package:lolisnatcher/features/recommender/logic/suggestion_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/suggestion_engine.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/tags/ui/tag_hub_page.dart';
import 'package:lolisnatcher/features/viewer/ui/gallery_view_page.dart';
import 'package:lolisnatcher/core/utils/debouncer.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/utils/text_parser/rules/url_rule.dart';
import 'package:lolisnatcher/features/collections/ui/add_to_collection_sheet.dart';
import 'package:lolisnatcher/features/viewer/ui/info/post_details_sheet.dart';
import 'package:lolisnatcher/core/ui/buttons/close_dialog_button.dart';
import 'package:lolisnatcher/core/ui/text/draggable_overflow_text.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/kaomoji/kaomoji.dart';
import 'package:lolisnatcher/core/ui/text/parsed_text.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/core/ui/desktop_scroll.dart';
import 'package:lolisnatcher/features/viewer/ui/comments_dialog.dart';
import 'package:lolisnatcher/features/viewer/ui/notes_renderer.dart';
import 'package:lolisnatcher/features/viewer/ui/info/find_elsewhere_sheet.dart';
import 'package:lolisnatcher/core/ui/image/booru_favicon.dart';
import 'package:lolisnatcher/features/feed/ui/search/main_search_tag_chip.dart';
import 'package:lolisnatcher/features/tabs/ui/widgets/tab_booru_selector.dart';
import 'package:lolisnatcher/features/tags/ui/manager/tm_list_item_dialog.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_card_build.dart';

part 'tag_view/tag_dialog.dart';
part 'tag_view/tab_group_picker.dart';
part 'tag_view/related_tabs_dialog.dart';
part 'tag_view/source_link_error_dialog.dart';
part 'tag_view/collapsible_related_preview.dart';
part 'tag_view/tag_content_preview.dart';

class _TagInfoIcon {
  _TagInfoIcon(this.icon, this.color);

  final dynamic icon;
  final Color color;
}

class TagView extends StatefulWidget {
  const TagView({
    required this.item,
    required this.handler,
    this.scrollController,
    super.key,
  });

  final BooruItem item;
  final BooruHandler handler;
  // When hosted inside a DraggableScrollableSheet the sheet provides its own
  // ScrollController that must drive the inner scrollable so dragging the
  // sheet and scrolling its content are unified. When null, TagView owns a
  // plain controller (classic side-drawer behaviour).
  final ScrollController? scrollController;

  @override
  State<TagView> createState() => _TagViewState();
}

class _TagViewState extends State<TagView> with TraceLifecycle {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  TagsListData tagsData = const TagsListData();
  late final ScrollController scrollController = widget.scrollController ?? ScrollController();

  late BooruItem item;
  late BooruHandler handler;
  BooruHandler? possibleBooruHandler;

  /// The booru whose tag vocabulary applies to this post. On virtual feeds
  /// (For You, favourites, merge) that is the item's real source booru, not
  /// the feed — a tag's type is a property of the site it came from.
  Booru get tagBooru => (possibleBooruHandler ?? handler).booru;

  /// The type to colour and GROUP a tag by, in priority order:
  /// your per-booru correction, then the app-wide tag store, then whatever
  /// the handler stamped on the item itself.
  ///
  /// The store lookup used to be gated on `tagHandler.hasTag(...)`, which
  /// silently dropped corrections for any tag the global store had never
  /// heard of — so re-typing such a tag recoloured the chip but left it
  /// sitting in the General group until the whole view was rebuilt.
  /// True when this info panel belongs to a DOUJIN item/source. Booru-only
  /// discovery tools (cross-BOORU "find elsewhere", For You seeding) are not
  /// offered there: they would send doujin data to booru APIs and pull booru
  /// results onto a doujin surface. Doujin sources have their own
  /// Related/Recommended sections on the detail page.
  bool get isDoujinContext =>
      (possibleBooruHandler ?? handler).hasReader || DoujinDataHandler.isDoujinItem(item);

  TagType typeOfTag(Tag tag) => TagTypeLookup.resolve(tag, booru: tagBooru, handler: handler);
  bool hasLoadItemSupport = false;
  bool canLoadItemOnStart = false;
  List<Tag> tags = [];
  List<Tag> filteredTags = [];
  final Map<String, HasTabWithTagResult> tabMatchesMap = {};
  bool? sortTags;
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final GlobalKey searchKey = GlobalKey(debugLabel: 'tagsSearchKey');

  CancelToken? cancelToken;
  bool loadingUpdate = false, failedUpdate = false;

  bool? detailsExpanded;
  bool relatedExpanded = false;

  // Batch tag selection: pick several tags from the list and open them as
  // tabs in one go (each its own tab, or combined into one search).
  bool tagSelectionMode = false;
  final Set<String> selectedBatchTags = {};
  // Cached so collapsing / re-expanding the "Related" tile doesn't re-derive
  // (and the preview widget's own state doesn't get torn down on the second

  TagHandler? _types;

  @override
  void initState() {
    super.initState();

    item = widget.item;
    handler = widget.handler;
    hasLoadItemSupport = handler.hasLoadItemSupport;
    canLoadItemOnStart = handler.shouldUpdateIteminTagView;
    checkForPossibleBooruHandler();
    tags = [...Set.from(item.tagsList)];
    filteredTags = [...tags];
    WidgetsBinding.instance.addPostFrameCallback((_) => parseSortGroupTags());
    searchHandler.searchTextController.addListener(parseSortGroupTagsWithoutCache);
    searchFocusNode.addListener(searchFocusListener);
    _types = TagHandler.maybe;
    _types?.typesChanged.addListener(_onTypesChanged);

    reloadItemData(initial: true).then((_) {
      if (mounted) parseSortGroupTagsWithoutCache();
    });
  }

  void _onTypesChanged() {
    if (!mounted) return;
    parseSortGroupTagsWithoutCache();
  }

  void checkForPossibleBooruHandler() {
    Booru? getMergeBooruEntry() {
      if (handler is! MergebooruHandler) return null;

      final fetchedMap = (handler as MergebooruHandler).fetchedMap;
      for (int i = 0; i < fetchedMap.entries.length; i++) {
        final entry = fetchedMap.entries.elementAt(i);
        if (entry.value.items.contains(item)) {
          return entry.value.booru;
        }
      }
      return null;
    }

    final bool isMergeHandler = handler is MergebooruHandler;

    // Virtual feeds (favourites, downloads, merge, For You, History)
    // aggregate posts from real boorus — resolve the item's actual source so
    // tag previews, related strips and the source row point at the right booru.
    final bool isVirtualFeed =
        handler is FavouritesHandler ||
        handler is DownloadsHandler ||
        handler is ForYouHandler ||
        handler is HistoryHandler ||
        // r77: the Suggested strip's tab and boards (Posts like this) mix
        // posts from several sources too.
        handler is SuggestionHandler ||
        handler is BoardHandler ||
        isMergeHandler;
    if (!isVirtualFeed) {
      return;
    }

    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;
    final Booru? possibleBooru = isMergeHandler
        ? getMergeBooruEntry()
        : SettingsHandler.instance.booruList.firstWhereOrNull((e) {
            final booruHost = Uri.tryParse(e.baseURL ?? '')?.host;

            return (itemPostHost?.isNotEmpty == true &&
                    booruHost?.isNotEmpty == true &&
                    (itemPostHost! == booruHost! ||
                        switch (e.type) {
                          BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                          BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                          _ => false,
                        })) ||
                (itemFileHost?.isNotEmpty == true && booruHost?.isNotEmpty == true && itemFileHost! == booruHost!);
          });

    if (possibleBooru != null && (isMergeHandler || possibleBooru.type?.isFavouritesOrDownloads != true)) {
      possibleBooruHandler = BooruHandlerFactory().getBooruHandler([possibleBooru], null).booruHandler;
      hasLoadItemSupport = possibleBooruHandler!.hasLoadItemSupport;
      canLoadItemOnStart = possibleBooruHandler!.shouldUpdateIteminTagView;
    }
  }

  @override
  void didUpdateWidget(covariant TagView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != item) {
      item = widget.item;
      // Different item -> different related query; bust the cache.
      checkForPossibleBooruHandler();
      tags = [...Set.from(item.tagsList)];
      filteredTags = [...tags];

      // debounce to avoid getting rate limited due to going too fast by using buttons on left side of tag view
      Debounce.debounce(
        tag: 'tag_view_reload_item',
        callback: () {
          WidgetsBinding.instance.addPostFrameCallback((_) => parseSortGroupTags());
          cancelToken?.cancel();
          reloadItemData(initial: true).then((_) {
            if (mounted) parseSortGroupTagsWithoutCache();
          });
        },
      );
    }

    if (widget.handler != handler) {
      handler = widget.handler;
      hasLoadItemSupport = handler.hasLoadItemSupport;
      canLoadItemOnStart = handler.shouldUpdateIteminTagView;
      checkForPossibleBooruHandler();
      setState(() {});
    }
  }

  @override
  void dispose() {
    cancelToken?.cancel();
    _types?.typesChanged.removeListener(_onTypesChanged);
    searchHandler.searchTextController.removeListener(parseSortGroupTagsWithoutCache);
    searchController.dispose();
    searchFocusNode.removeListener(searchFocusListener);
    searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> reloadItemData({
    bool initial = false,
    bool force = false,
  }) async {
    if (loadingUpdate) return;

    if (hasLoadItemSupport && (!initial || canLoadItemOnStart) && (!item.isUpdated || force)) {
      loadingUpdate = true;
      failedUpdate = false;
      setState(() {});
      cancelToken = CancelToken();
      try {
        final res = await (possibleBooruHandler ?? handler).loadItem(
          item: item,
          cancelToken: cancelToken,
          withCapcthaCheck: !initial,
        );
        if (res.failed) {
          failedUpdate = true;
        } else if (res.item != null && (res.item?.isSnatched.value == true || res.item?.isFavourite.value == true)) {
          unawaited(
            SettingsHandler.instance.dbHandler.updateBooruItem(
              res.item!,
              BooruUpdateMode.urlUpdate,
            ),
          );
        }

        if (!res.failed) {
          await getUploaderName();
        }
      } catch (e) {
        failedUpdate = true;
      }
      // The post may answer after this panel is gone (swiped on, HANDOVER 4.23).
      if (!mounted) return;
      loadingUpdate = false;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => parseSortGroupTags(),
      );
    }
  }

  Future<void> getUploaderName() async {
    final usedHandler = possibleBooruHandler ?? handler;
    if (usedHandler is DanbooruHandler && item.uploaderId?.isNotEmpty == true) {
      item.uploaderName = await usedHandler.getUploaderName(item);
    }
  }

  void parseTags() {
    // Doujin items get their hidden badges from the doujin blacklist, never
    // the booru-global one (and vice versa).
    final bool itemIsDoujin = DoujinDataHandler.isDoujinItem(item);
    if (itemIsDoujin) DoujinDataHandler.instance.ensureLoaded();
    tagsData = settingsHandler.parseTagsList(
      tags,
      isCapped: false,
      hiddenTokensOverride: itemIsDoujin ? SourceSettingsHandler.instance.tagBlacklistForItem(item) : null,
      markedTokensOverride: itemIsDoujin ? DoujinDataHandler.instance.starredTags : null,
    );
  }

  List<Tag> filterTags(List<Tag> tagsToFilter) {
    final List<Tag> tags = [];
    if (searchController.text.isEmpty) {
      return tagsToFilter;
    }

    for (int i = 0; i < tagsToFilter.length; i++) {
      if (tagsToFilter[i].fullString.toLowerCase().contains(searchController.text.toLowerCase())) {
        tags.add(tagsToFilter[i]);
      }
    }
    return tags;
  }

  void sortAndGroupTagsList() {
    if (sortTags == null) {
      tags = [...Set.from(item.tagsList)];
      groupTagsList();
    } else {
      tags.sort(
        (a, b) => sortTags == true ? a.fullString.compareTo(b.fullString) : b.fullString.compareTo(a.fullString),
      );
      filteredTags = [
        ...filterTags([...tags]),
      ];
    }
  }

  void groupTagsList() {
    final Map<TagType, List<Tag>> tagMap = {};
    final List<Tag> groupedTags = [];
    for (int i = 0; i < TagType.values.length; i++) {
      tagMap[TagType.values[i]] = [];
    }

    for (int i = 0; i < tags.length; i++) {
      tagMap[typeOfTag(tags[i])]?.add(tags[i]);
    }
    // tagMap.forEach((key, value) => {
    //   print("Type: $key Tags: $value")
    // });
    for (final value in tagMap.values) {
      groupedTags.addAll(value);
    }
    tags = groupedTags;
    filteredTags = [
      ...filterTags([...tags]),
    ];
  }

  Future<void> cacheTabMatchData() async {
    final currentBooru = searchHandler.currentBooru;
    final Set<String> onlyTagCurrentBooru = {};
    final Set<String> onlyTagOtherBooru = {};
    final Set<String> containsTag = {};

    for (final tab in searchHandler.tabs) {
      final parts = tab.tags.toLowerCase().trim().split(' ');
      final isCurrentBooru = tab.selectedBooru.value == currentBooru;

      if (parts.length == 1 && parts[0].isNotEmpty) {
        if (isCurrentBooru) {
          onlyTagCurrentBooru.add(parts[0]);
        } else {
          onlyTagOtherBooru.add(parts[0]);
        }
      }
      for (final part in parts) {
        if (part.isNotEmpty) containsTag.add(part);
      }
    }

    for (final tag in filteredTags) {
      final normalized = tag.fullString.toLowerCase().trim();
      if (onlyTagCurrentBooru.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.onlyTag;
      } else if (onlyTagOtherBooru.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.onlyTagDifferentBooru;
      } else if (containsTag.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.containsTag;
      } else {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.noTag;
      }
    }
  }

  void parseSortGroupTagsWithoutCache() {
    parseSortGroupTags(updateCache: false);
  }

  Future<void> parseSortGroupTags({
    bool updateCache = true,
  }) async {
    parseTags();
    sortAndGroupTagsList();
    if (updateCache) {
      await cacheTabMatchData();
    }
    // Scheduled from a post-frame callback: the panel may be gone by now.
    if (!mounted) return;
    setState(() {});
  }

  void searchFocusListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (searchFocusNode.hasFocus) {
        // doesn't scroll to a proper position in some cases
        // probably because scroll extent changes due to elements being lazily rendered
        await Scrollable.ensureVisible(
          searchKey.currentContext!,
          alignment: (72 + context.viewInsets.top) / context.height,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  Widget tagsButton() {
    return SettingsButton(
      name: context.loc.tagView.tags,
      subtitle: Text(searchController.text.isEmpty ? '${tags.length}' : '${filteredTags.length} / ${tags.length}'),
      trailingIcon: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth - 72),
            margin: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLoadItemSupport) ...[
                  if (possibleBooruHandler != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BooruFavicon(
                              possibleBooruHandler?.booru,
                              size: 20,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              possibleBooruHandler?.booru.name ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  //
                  if (loadingUpdate)
                    IconButton(
                      onPressed: () {
                        cancelToken?.cancel();
                      },
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                            ),
                          ),
                          Icon(
                            Symbols.close_rounded,
                            color: Theme.of(context).iconTheme.color,
                            size: 24,
                          ),
                        ],
                      ),
                    )
                  else
                    IconButton(
                      onPressed: () => reloadItemData(force: true),
                      icon: Icon(
                        failedUpdate ? Symbols.error_rounded : Symbols.refresh_rounded,
                        color: failedUpdate ? Colors.red : Theme.of(context).iconTheme.color,
                        size: 28,
                      ),
                    ),
                ],
                //
                Transform(
                  alignment: Alignment.center,
                  transform: sortTags == true ? Matrix4.rotationX(pi) : Matrix4.rotationX(0),
                  child: IconButton(
                    icon: Icon(
                      (sortTags == true || sortTags == false) ? Symbols.sort_rounded : Symbols.sort_by_alpha_rounded,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onPressed: () {
                      if (sortTags == true) {
                        sortTags = false;
                      } else if (sortTags == false) {
                        sortTags = null;
                      } else {
                        sortTags = true;
                      }
                      sortAndGroupTagsList();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      drawBottomBorder: false,
    );
  }

  /// r79: shared by the Comments row and its button in the action block.
  bool get _commentsAvailable => handler.hasCommentsSupport && item.fileURL.isNotEmpty;

  void _openComments() {
    SettingsPageOpen(
      context: context,
      page: (_) => CommentsDialog(
        item: item,
        handler: handler,
      ),
    ).open();
  }

  Widget commentsButton() {
    final bool hasComments = item.hasComments == true;
    final IconData icon = hasComments ? CupertinoIcons.text_bubble_fill : CupertinoIcons.text_bubble;

    if (!_commentsAvailable) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.tagView.comments,
      icon: Icon(
        icon,
        color: Theme.of(context).iconTheme.color,
      ),
      action: _openComments,
      drawBottomBorder: false,
    );
  }

  /// r79: the post actions that sat as full-width rows under the action
  /// block are buttons in it, unless Settings > Modular UI > Viewer switches
  /// that off. Read when the panel builds - one form is ever built.
  bool get _actionsAsButtons => ModularUi.isOn(ModularUi.viewerPostActionsAsButtons);

  void _openFindElsewhere(BuildContext context) => showFindElsewhereSheet(
    context,
    item,
    (possibleBooruHandler ?? handler).booru,
  );

  void _openNewBoard(BuildContext context) => BoardEditPage.openFromItem(context, item, (possibleBooruHandler ?? handler).booru);

  void _openSimilar(BuildContext context) => BoardsPage.openSimilar(context, item, tagBooru);

  bool get _hasPicture => item.sampleURL.isNotEmpty || item.thumbnailURL.isNotEmpty;

  /// For You is the BOORU taste system - never seeded from a doujin item.
  List<String> _recommendSeeds() =>
      settingsHandler.dbEnabled && !isDoujinContext ? InterestsHandler.seedTagsFromItem(item, limit: 3) : const <String>[];

  void _openRecommend(BuildContext context, List<String> seeds) {
    final booru = settingsHandler.ensureForYouBooru();
    // r75: the post's own site first (it knows these tags), the rest after.
    final String fromHost = Uri.tryParse(tagBooru.baseURL ?? '')?.host ?? '';
    final String query = [if (fromHost.isNotEmpty) 'from:$fromHost', ...seeds.map((s) => 'seed:$s')].join(' ');
    // r75: in the background — a tab never drags the user away.
    searchHandler.addTabByString(query, customBooru: booru, switchToNew: false);
    _openedInNewTab(context, seeds.map((s) => s.replaceAll('_', ' ')).join(', '));
  }

  FlowActionTile _extraTile(BuildContext context, FlowExtra e, List<String> seeds) {
    final String label = e == FlowExtra.comments ? context.loc.tagView.comments : FlowExtras.labelOf(e);
    switch (e) {
      case FlowExtra.comments:
        return FlowActionTile(
          key: const ValueKey('flow-comments'),
          icon: Symbols.chat_bubble_rounded,
          label: label,
          active: item.hasComments == true,
          onTap: _openComments,
        );
      case FlowExtra.elsewhere:
        return FlowActionTile(
          key: const ValueKey('flow-elsewhere'),
          icon: Symbols.travel_explore_rounded,
          label: label,
          onTap: () => _openFindElsewhere(context),
        );
      case FlowExtra.board:
        return FlowActionTile(
          key: const ValueKey('flow-board'),
          icon: Symbols.dashboard_rounded,
          label: label,
          onTap: () => _openNewBoard(context),
        );
      case FlowExtra.similar:
        return FlowActionTile(
          key: const ValueKey('flow-similar'),
          icon: Symbols.image_search_rounded,
          label: label,
          onTap: () => _openSimilar(context),
        );
      case FlowExtra.recommend:
        return FlowActionTile(
          key: const ValueKey('flow-recommend'),
          icon: Symbols.auto_awesome_rounded,
          label: label,
          onTap: () => _openRecommend(context, seeds),
        );
    }
  }

  /// FurAffinity (r42): the submission page.
  Widget furAffinityPostButton() {
    final BooruHandler h = possibleBooruHandler ?? handler;
    if (h is! FurAffinityHandler || item.serverId == null) return const SizedBox.shrink();
    return SettingsButton(
      name: 'Post page',
      icon: Icon(Symbols.article_rounded, color: Theme.of(context).iconTheme.color),
      action: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FurAffinityPostPage(booru: h.booru, item: item)));
      },
      drawBottomBorder: false,
    );
  }

  /// kemono: the post page (content, every file with its name, comments).
  Widget kemonoPostButton() {
    final BooruHandler h = possibleBooruHandler ?? handler;
    if (h is! KemonoHandler || item.serverId == null) return const SizedBox.shrink();
    return SettingsButton(
      name: 'Post page',
      icon: Icon(Symbols.article_rounded, color: Theme.of(context).iconTheme.color),
      action: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => KemonoPostPage(booru: h.booru, item: item)));
      },
      drawBottomBorder: false,
    );
  }

  Widget notesButton() {
    final bool hasSupport = handler.hasNotesSupport;
    final bool hasNotes = item.hasNotes == true;

    if (!hasSupport || !hasNotes) {
      return const SizedBox.shrink();
    }

    return Obx(() {
      if (item.notes.isNotEmpty) {
        return SettingsButton(
          name: viewerHandler.showNotes.value
              ? context.loc.tagView.hideNotes(count: item.notes.length)
              : context.loc.tagView.showNotes(count: item.notes.length),
          icon: Icon(
            Symbols.note_add_rounded,
            color: Theme.of(context).iconTheme.color,
          ),
          action: viewerHandler.showNotes.toggle,
          onLongPress: () {
            showDialog(
              context: context,
              builder: (_) => NotesDialog(item),
            );
          },
          drawBottomBorder: false,
        );
      } else {
        return SettingsButton(
          name: context.loc.tagView.loadNotes,
          icon: Icon(
            Symbols.note_add_rounded,
            color: Theme.of(context).iconTheme.color,
          ),
          action: () async {
            if (item.serverId == null) return;
            item.notes.value = await handler.getNotes(item.serverId!);
          },
          drawBottomBorder: false,
        );
      }
    });
  }

  Widget sourcesList(List<String> sources) {
    sources = sources.where((l) => l.trim().isNotEmpty).toList();

    if (sources.isNotEmpty) {
      return Column(
        children: [
          Divider(
            color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
          ),
          infoText(context.loc.gallery.sources(count: sources.length), ' ', canCopy: false),
          Column(
            children: sources
                .map(
                  (link) => ListTile(
                    onLongPress: () async {
                      await ServiceHandler.vibrate();
                      await showDialog(
                        context: context,
                        builder: (_) => SourceLinkErrorDialog(link: link),
                      );
                    },
                    onTap: () async {
                      final detectedUrl = UrlParseRule.detectPureUrl(link);
                      if (detectedUrl != null) {
                        if (await canLaunchUrlString(detectedUrl)) {
                          await launchUrlString(
                            detectedUrl,
                            mode: LaunchMode.externalApplication,
                          );
                          return;
                        }
                        // Pure URL but failed to launch — show dialog with error context
                        if (mounted) {
                          await showDialog(
                            context: context,
                            builder: (_) => SourceLinkErrorDialog(link: link),
                          );
                        }
                        return;
                      }

                      // Mixed content or no URL — show dialog without error header
                      if (mounted) {
                        await showDialog(
                          context: context,
                          builder: (_) => SourceLinkErrorDialog(link: link),
                        );
                      }
                    },
                    title: DraggableOverflowText(link),
                  ),
                )
                .toList(),
          ),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  // Flow key/value row (matches the Details sheet): muted key column, bold
  // value, subtle copy/open glyph. Tap copies (or opens links).
  Widget infoText(
    String title,
    String data, {
    bool canCopy = true,
    bool isLink = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return InkWell(
      onTap:
          onTap ??
          (isLink
              ? () => launchUrlString(data, mode: LaunchMode.externalApplication)
              : (canCopy
                    ? () {
                        Clipboard.setData(ClipboardData(text: data));
                        FlashElements.showSnackbar(
                          context: context,
                          duration: const Duration(seconds: 2),
                          title: Text(
                            context.loc.copiedToClipboard,
                            style: const TextStyle(fontSize: 20),
                          ),
                          content: Text(
                            '$title: $data',
                            style: const TextStyle(fontSize: 16),
                          ),
                          leadingIcon: Symbols.content_copy_rounded,
                          sideColor: Colors.green,
                        );
                      }
                    : null)),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                data,
                maxLines: isLink ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLink ? theme.colorScheme.secondary : theme.colorScheme.onSurface,
                  decoration: isLink ? TextDecoration.underline : null,
                  decorationColor: theme.colorScheme.secondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(
                  isLink ? Symbols.open_in_new_rounded : Symbols.content_copy_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
          ],
        ),
      ),
    );
  }

  /// Builds the "More from artist X" + "More from uploader Y" inline grid
  /// sections that render at the top of the post-details drawer when the
  /// `inlineRelatedGrids` setting is on.
  ///
  /// Returns an empty list when nothing applicable — caller can spread it
  /// into the sliver child list unconditionally.
  List<Widget> _buildRelatedGrids() {
    final List<Widget> sections = [];
    // The post's OWN booru, not the feed's.
    //
    // On a virtual feed (For You, favourites, merge) searchHandler.currentBooru
    // is the feed itself, so these strips searched For You for the artist and
    // came back with another For You page instead of that artist's work on the
    // site the post came from. tagBooru already resolves this — the tag-type
    // lookup a few lines below has always used it; the strips did not.
    final Booru currentBooru = tagBooru;
    if (currentBooru.name == null) {
      return const [];
    }
    final SearchTab parentTab = searchHandler.currentTab;

    // 1) Artist sections — at most 3 to keep the drawer scannable.
    //    Tag-type is usually classified by the handler via addTagsWithType
    //    into TagHandler's enriched store rather than being set on the Tag
    //    object on the item (see groupTagsList above for the same pattern).
    //    Check both so this works regardless of how the handler tagged it.
    final artists = item.tagsList.where((t) {
      if (t.tagType.isArtist || typeOfTag(t).isArtist) return true;
      return tagHandler.getTagFor(t.fullString, tagBooru).tagType.isArtist;
    }).take(3).toList();
    for (final artist in artists) {
      if (artist.fullString.trim().isEmpty) continue;
      final String artistQuery = artist.fullString;
      sections.add(
        _CollapsibleRelatedPreview(
          key: ValueKey('related-artist-${currentBooru.name}-$artistQuery'),
          title: 'More from artist ${artistQuery.replaceAll('_', ' ')}',
          icon: Symbols.brush_rounded,
          booru: currentBooru,
          query: artistQuery,
          parentTab: parentTab,
        ),
      );
    }

    // 2) Uploader section — only when the handler exposes a UserMetaTag
    //    AND we have a real uploader NAME (not just an ID). Many boorus
    //    (Danbooru, rule34.xxx) return only `uploader_id` in the post JSON
    //    and resolve the name asynchronously; building the strip with the
    //    numeric ID produces a query like `user:12345` that user-search
    //    can't satisfy. Skip until the name is in.
    final String? uploader = item.uploaderName?.isNotEmpty == true ? item.uploaderName : null;
    if (uploader != null) {
      // Same reason: on a virtual feed the FEED's handler has no user metatag
      // (or the wrong one), so the uploader strip silently never appeared.
      final userMetaTag = (possibleBooruHandler ?? handler)
          .availableMetaTags()
          .firstWhereOrNull((t) => t is UserMetaTag);
      if (userMetaTag != null) {
        final String userQuery = userMetaTag.tagBuilder(null, null, uploader);
        if (userQuery.trim().isNotEmpty) {
          sections.add(
            _CollapsibleRelatedPreview(
              key: ValueKey('related-uploader-${currentBooru.name}-$userQuery'),
              title: 'More from uploader $uploader',
              icon: Symbols.person_rounded,
              booru: currentBooru,
              query: userQuery,
              parentTab: parentTab,
            ),
          );
        }
      }
    }

    if (sections.isEmpty) return const [];
    return [
      ...sections,
      const Divider(),
    ];
  }

  /// Boorusama-style tag cloud: chips grouped into colored sections by tag
  /// type (Artist / Character / Copyright / Meta / Species / General).
  ///
  /// The alpha-sort modes (sort button) collapse the sections into a single
  /// flat sorted chip cloud. Tapping a chip opens the full tag dialog
  /// (add/exclude/new tab/preview window/blacklist...), long-pressing
  /// quick-adds the tag to the current search.
  List<Widget> tagChipSectionSlivers(BuildContext context) {
    if (filteredTags.isEmpty) return const [];

    final List<(String?, Color?, List<Tag>)> sections = [];
    final BooruHandler nsHandler = possibleBooruHandler ?? handler;
    final List<(String, String)> nsSections = nsHandler.tagNamespaceSections;
    final bool useNativeNamespaces = sortTags == null &&
        nsSections.isNotEmpty &&
        filteredTags.any((t) => nsHandler.tagNamespace(t.fullString) != null);
    if (useNativeNamespaces) {
      // Doujin sources: the site's own namespaces (Parodies / Characters /
      // Artists / Groups / Categories / Languages / Tags) are richer than
      // TagType, so section by those; chip colours still follow TagType.
      final Map<String, List<Tag>> byNs = {for (final s in nsSections) s.$1: <Tag>[]};
      final String fallbackNs = nsSections.last.$1;
      for (final tag in filteredTags) {
        final String ns = nsHandler.tagNamespace(tag.fullString) ?? fallbackNs;
        (byNs[ns] ?? byNs[fallbackNs]!).add(tag);
      }
      for (final s in nsSections) {
        if (byNs[s.$1]!.isNotEmpty) {
          sections.add((s.$2, typeOfTag(byNs[s.$1]!.first).getColour(), byNs[s.$1]!));
        }
      }
    } else if (sortTags == null) {
      final Map<TagType, List<Tag>> byType = {
        for (final type in TagType.values) type: <Tag>[],
      };
      for (final tag in filteredTags) {
        byType[typeOfTag(tag)]!.add(tag);
      }
      for (final type in TagType.values) {
        if (byType[type]!.isNotEmpty) {
          sections.add((type.locName, type.getColour(), byType[type]!));
        }
      }
    } else {
      sections.add((null, null, filteredTags));
    }

    return [
      // Tags header + interaction hint (Flow info-flow).
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Text(
                'Tags',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${filteredTags.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  tagSelectionMode ? 'tap tags to select' : 'tap · hold = tab · ⧉ = preview',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Batch selection toggle: pick several tags, open them as tabs.
              // A labelled pill (not a bare icon) so it reads as a button.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    tagSelectionMode = !tagSelectionMode;
                    if (!tagSelectionMode) selectedBatchTags.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tagSelectionMode
                        ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.22)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: tagSelectionMode
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.checklist_rounded,
                        size: 15,
                        color: tagSelectionMode
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tagSelectionMode ? 'Done' : 'Select',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tagSelectionMode
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Batch-selection action bar: appears while selecting, offers opening
      // the picked tags as separate tabs or one combined search tab.
      if (tagSelectionMode)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selectedBatchTags.length} selected',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: selectedBatchTags.isEmpty ? null : () => _openSelectedTagsAsTabs(combined: true),
                    icon: const Icon(Symbols.join_rounded, size: 18),
                    label: const Text('One tab'),
                  ),
                  TextButton.icon(
                    onPressed: selectedBatchTags.isEmpty ? null : () => _openSelectedTagsAsTabs(combined: false),
                    icon: const Icon(Symbols.tab_rounded, size: 18),
                    label: Text(selectedBatchTags.length > 1 ? '${selectedBatchTags.length} tabs' : 'Open tab'),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'More actions',
                    icon: const Icon(Symbols.more_horiz_rounded, size: 20),
                    onPressed: selectedBatchTags.isEmpty ? null : _showBatchActionsSheet,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel selection',
                    icon: const Icon(Symbols.close_rounded, size: 18),
                    onPressed: _exitTagSelectionMode,
                  ),
                ],
              ),
            ),
          ),
        ),
      for (final section in sections) ...[
        if (section.$1 != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 16,
                    decoration: BoxDecoration(
                      color:
                          section.$2 ??
                          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.$1!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${section.$3.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in section.$3) buildTagChip(context, tag),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  void _toggleBatchTag(String tag) {
    setState(() {
      if (!selectedBatchTags.remove(tag)) {
        selectedBatchTags.add(tag);
      }
    });
  }

  void _exitTagSelectionMode() {
    setState(() {
      tagSelectionMode = false;
      selectedBatchTags.clear();
    });
  }

  // Selected tags in on-screen order (selection set order is insertion order,
  // which may not match the list after sorting/filtering).
  List<String> get _selectedBatchTagsOrdered {
    final List<String> ordered = [
      for (final t in filteredTags)
        if (selectedBatchTags.contains(t.fullString)) t.fullString,
    ];
    for (final t in selectedBatchTags) {
      if (!ordered.contains(t)) ordered.add(t);
    }
    return ordered;
  }

  /// r75: the notice for a tab opened in the background.
  void _openedInNewTab(BuildContext context, String what) {
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: const Text('Opened in a new tab', style: TextStyle(fontSize: 20)),
      content: Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );
  }

  void _openSelectedTagsAsTabs({required bool combined}) {
    final List<String> toOpen = _selectedBatchTagsOrdered;
    if (toOpen.isEmpty) return;

    final Booru batchBooru = possibleBooruHandler?.booru ?? searchHandler.currentBooru;
    final TabAddMode addMode = settingsHandler.defaultTabAddMode == 'next' ? TabAddMode.next : TabAddMode.end;

    if (combined) {
      searchHandler.addTabByString(
        toOpen.join(' '),
        customBooru: batchBooru,
        addMode: addMode,
        switchToNew: false,
        group: SearchHandler.inheritGroup,
      );
    } else {
      // "next" inserts right after the current tab, so add in reverse to end
      // up with the tabs in selection order.
      for (final tag in addMode == TabAddMode.next ? toOpen.reversed : toOpen) {
        searchHandler.addTabByString(
          tag,
          customBooru: batchBooru,
          addMode: addMode,
          switchToNew: false,
          group: SearchHandler.inheritGroup,
        );
      }
    }

    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(
        combined ? 'Opened combined tab' : 'Opened ${toOpen.length} ${toOpen.length == 1 ? 'tab' : 'tabs'}',
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(
        toOpen.join(combined ? ' ' : ', '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );

    _exitTagSelectionMode();
  }

  void _batchSnackbar(String title, List<String> tags) {
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'batch_tags',
      duration: const Duration(seconds: 2),
      title: Text(title, style: const TextStyle(fontSize: 20)),
      content: Text(
        tags.join(', '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Symbols.checklist_rounded,
      sideColor: Colors.green,
    );
  }

  Future<void> _openSelectedTagsInGroup() async {
    final List<String> toOpen = _selectedBatchTagsOrdered;
    if (toOpen.isEmpty) return;
    final String? groupName = await pickTabGroupName(
      context,
      title: 'Open ${toOpen.length} ${toOpen.length == 1 ? 'tag' : 'tags'} in group',
    );
    if (groupName == null) return;

    final Booru batchBooru = possibleBooruHandler?.booru ?? searchHandler.currentBooru;
    for (final tag in toOpen) {
      searchHandler.addTabByString(
        tag,
        customBooru: batchBooru,
        group: groupName,
        switchToNew: false,
      );
    }
    _batchSnackbar('Opened in group "$groupName"', toOpen);
    _exitTagSelectionMode();
  }

  void _batchAddToSearch({bool exclude = false}) {
    final List<String> toAdd = _selectedBatchTagsOrdered;
    if (toAdd.isEmpty) return;
    for (final tag in toAdd) {
      searchHandler.addTagToSearch(exclude ? '-$tag' : tag);
    }
    _batchSnackbar(exclude ? 'Exclusions added to search bar' : 'Added to search bar', toAdd);
    _exitTagSelectionMode();
  }

  Future<void> _batchHide() async {
    final List<String> toHide = _selectedBatchTagsOrdered;
    if (toHide.isEmpty) return;
    final Booru scopeBooru = (possibleBooruHandler ?? handler).booru;
    final scope = await _pickBlacklistScope(context, scopeBooru);
    if (scope == null) return;
    final bool isDoujin = DoujinDataHandler.isDoujinBooru(scopeBooru);
    for (final tag in toHide) {
      if (isDoujin) {
        // Doujin sources blacklist via sourceSettings, never the booru lists.
        SourceSettingsHandler.instance.addBlacklistTag(
          scope == _BlacklistScope.global ? null : scopeBooru,
          tag,
        );
      } else if (scope == _BlacklistScope.global) {
        settingsHandler.addTagToList('hidden', tag);
      } else if (scopeBooru.name?.isNotEmpty == true) {
        settingsHandler.addTagToBooruHiddenList(scopeBooru.name!, tag);
      }
    }
    searchHandler.filterCurrentFetched();
    handler.filterFetched();
    parseSortGroupTagsWithoutCache();
    _batchSnackbar('Added to blacklist', toHide);
    _exitTagSelectionMode();
  }

  void _batchMark() {
    final List<String> toMark = _selectedBatchTagsOrdered;
    if (toMark.isEmpty) return;
    final bool isDoujin = DoujinDataHandler.isDoujinBooru((possibleBooruHandler ?? handler).booru);
    for (final tag in toMark) {
      if (isDoujin) {
        // Doujin sources star tags in the doujin store, never the booru
        // markedTags list.
        DoujinDataHandler.instance.starTag(tag);
      } else {
        settingsHandler.addTagToList('marked', tag);
      }
    }
    searchHandler.filterCurrentFetched();
    handler.filterFetched();
    parseSortGroupTagsWithoutCache();
    _batchSnackbar('Marked', toMark);
    _exitTagSelectionMode();
  }

  Future<void> _batchPin() async {
    final List<String> toPin = _selectedBatchTagsOrdered;
    if (toPin.isEmpty) return;
    final Booru scopeBooru = (possibleBooruHandler ?? handler).booru;
    for (final tag in toPin) {
      try {
        if (DoujinDataHandler.isDoujinBooru(scopeBooru)) {
          // Doujin pins live in the doujin store, scoped to this source.
          DoujinDataHandler.instance.addPin(tag, scopeBooru);
        } else {
          await settingsHandler.dbHandler.addPinnedTag(tag);
        }
      } catch (_) {}
    }
    _batchSnackbar('Pinned', toPin);
    _exitTagSelectionMode();
  }

  Future<void> _batchCopy() async {
    final List<String> toCopy = _selectedBatchTagsOrdered;
    if (toCopy.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: toCopy.join(' ')));
    _batchSnackbar('Copied to clipboard', toCopy);
    _exitTagSelectionMode();
  }

  // Every tag action that makes sense for several tags at once, in one sheet.
  Future<void> _showBatchActionsSheet() async {
    if (selectedBatchTags.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 2),
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A4260),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Icon(Symbols.checklist_rounded, size: 20, color: theme.colorScheme.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${selectedBatchTags.length} ${selectedBatchTags.length == 1 ? 'tag' : 'tags'} selected',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    ListTile(
                      leading: Icon(Symbols.create_new_folder_rounded, color: theme.colorScheme.secondary),
                      title: const Text('Open in group'),
                      subtitle: const Text('Each as a background tab inside a tab group'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _openSelectedTagsInGroup();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Symbols.add_rounded, color: Colors.green),
                      title: const Text('Add all to search'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchAddToSearch();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Symbols.remove_rounded, color: Colors.red),
                      title: const Text('Exclude all from search'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchAddToSearch(exclude: true);
                      },
                    ),
                    ListTile(
                      leading: const Icon(CupertinoIcons.eye_slash, color: Colors.red),
                      title: const Text('Hide all (blacklist)'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchHide();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Symbols.star_rounded, color: Colors.yellow),
                      title: const Text('Mark all'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchMark();
                      },
                    ),
                    ListTile(
                      leading: Icon(Symbols.push_pin_rounded, color: theme.iconTheme.color),
                      title: const Text('Pin all'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchPin();
                      },
                    ),
                    ListTile(
                      leading: Icon(Symbols.content_copy_rounded, color: theme.iconTheme.color),
                      title: const Text('Copy all'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _batchCopy();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Flow post-action row (Favorite / Save / Collect) shown at the top of the
  // info panel. Reuses the existing favourite / snatch / collection plumbing.
  void _toggleFavourite() {
    // Route by the ITEM on ITS OWN feed — this panel can belong to a
    // floating preview whose tab is NOT the current one, so indexing into
    // currentTab could toggle a different item in a different store.
    if (handler.hasReader || DoujinDataHandler.isDoujinItem(item)) {
      DoujinDataHandler.instance.toggleFavouriteSynced(item, possibleBooruHandler ?? handler);
      return;
    }
    final int idx = handler.filteredFetched.indexOf(item);
    if (idx < 0) return;
    // Prefer the real tab that owns this handler; floating previews have
    // stand-alone tabs, so fall back to a direct item toggle + DB write.
    SearchTab? ownerTab;
    for (final t in searchHandler.tabs) {
      if (t.booruHandler == handler) {
        ownerTab = t;
        break;
      }
    }
    if (ownerTab != null) {
      ownerTab.toggleItemFavourite(idx);
      return;
    }
    if (item.isFavourite.value != null) {
      item.isFavourite.value = item.isFavourite.value != true;
      handler.exemptFromLiveFilter(item);
      settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.local);
    }
  }

  void _snatchItem(BuildContext context) {
    SnatchHandler.instance.queue(
      [item],
      handler.booru,
      settingsHandler.snatchCooldown,
      false,
    );
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: const Text('Queued for download', style: TextStyle(fontSize: 18)),
      leadingIcon: Symbols.download_rounded,
      sideColor: const Color(0xFF7FC98B),
    );
  }

  Widget _flowActionRow(BuildContext context) {
    final List<String> seeds = _actionsAsButtons ? _recommendSeeds() : const <String>[];
    final List<FlowExtra> extras = _actionsAsButtons
        ? FlowExtras.of(
            doujin: isDoujinContext,
            comments: _commentsAvailable,
            hasPicture: _hasPicture,
            recommend: seeds.isNotEmpty,
          )
        : const <FlowExtra>[];
    return FlowActionGrid(
      tiles: [
        Obx(() {
          final bool fav = item.isFavourite.value == true;
          return FlowActionTile(
            icon: Symbols.favorite_rounded,
            label: 'Favorite',
            activeColor: const Color(0xFFF0708A),
            active: fav,
            onTap: _toggleFavourite,
          );
        }),
        Obx(() {
          final bool snatched = item.isSnatched.value == true;
          return FlowActionTile(
            icon: snatched ? Symbols.download_done_rounded : Symbols.download_rounded,
            label: snatched ? 'Saved' : 'Save',
            activeColor: const Color(0xFF7FC98B),
            active: snatched,
            onTap: () => _snatchItem(context),
          );
        }),
        FlowActionTile(
          icon: Symbols.bookmark_add_rounded,
          label: 'Collect',
          activeColor: const Color(0xFFE8C46B),
          onTap: () => showAddToCollectionSheet(context, [item]),
        ),
        FlowActionTile(
          icon: Symbols.info_rounded,
          label: 'Details',
          onTap: () => showPostDetailsSheet(context, item),
        ),
        for (final FlowExtra e in extras) _extraTile(context, e, seeds),
      ],
    );
  }

  /// Reference-style "Pages" grid for doujin sources: every page's own
  /// thumbnail; tapping one opens the reader at exactly that page.
  List<Widget> _pagesGridSlivers(BuildContext context) {
    final BooruHandler bookHandler = possibleBooruHandler ?? handler;
    if (!bookHandler.hasReader) return const [];
    final List<BooruItem>? pages =
        ReaderHandler.instance.books[item.postURL.isNotEmpty ? item.postURL : item.fileURL];
    if (pages == null || pages.isEmpty) return const [];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 2),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Text(
                'Pages',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${pages.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: SourceSettingsHandler.instance.pagePreviewColumns(bookHandler.booru),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            // Doujin pages are portrait; the fixed ratio keeps rows tidy and
            // the thumbnail crops the difference.
            childAspectRatio: 0.7,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final BooruItem page = pages[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openDoujinReader(
                  context,
                  item: item,
                  booru: bookHandler.booru,
                  startAt: index,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ThumbnailBuild(
                      item: page,
                      handler: bookHandler,
                      selectable: false,
                      simple: true,
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            childCount: pages.length,
          ),
        ),
      ),
    ];
  }

  /// Book header for doujin sources: language / category / page count /
  /// favourites pulled from the site's own namespaces, and the Read button
  /// as the drawer's primary action — "Continue" with the saved page when
  /// the book was started before.
  Widget _doujinBookHeader(BuildContext context) {
    final BooruHandler bookHandler = possibleBooruHandler ?? handler;
    if (!bookHandler.hasReader) return const SizedBox.shrink();
    return Obx(() {
      final List<BooruItem>? pages =
          ReaderHandler.instance.books[item.postURL.isNotEmpty ? item.postURL : item.fileURL];
      if (pages == null || pages.isEmpty) return const SizedBox.shrink();
      final progress = ReaderHandler.instance.cachedProgress(
        bookHandler.booru,
        item.serverId ?? item.postURL,
      );
      final bool resuming = progress != null && !progress.isFinished && progress.page > 0;

      final List<String> languages = [];
      String? category;
      for (final t in item.tagsList) {
        final String? ns = bookHandler.tagNamespace(t.fullString);
        if (ns == 'language' && t.fullString != 'translated') languages.add(t.fullString);
        if (ns == 'category') category ??= t.fullString;
      }
      final List<String> infoParts = [
        if (languages.isNotEmpty) languages.join(' / '),
        ?category,
        '${pages.length} pages',
        if (item.score?.isNotEmpty ?? false) '♥ ${item.score}',
      ];

      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              infoParts.join('  ·  '),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                icon: Icon(resuming ? Symbols.auto_stories_rounded : Symbols.menu_book_rounded, size: 20),
                label: Text(
                  resuming
                      ? 'Continue reading · page ${progress.page + 1} of ${pages.length}'
                      : 'Read · ${pages.length} pages',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                onPressed: () => openDoujinReader(
                  context,
                  item: item,
                  booru: bookHandler.booru,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget buildTagChip(BuildContext context, Tag rawTag) {
    final String currentTag = rawTag.fullString;
    if (currentTag.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final TagType resolvedType = typeOfTag(rawTag);
    Color? color = resolvedType.getColour();
    color = color == Colors.transparent ? null : color;

    final bool isHidden = tagsData.hiddenTags.contains(currentTag);
    final bool isMarked = tagsData.markedTags.contains(currentTag);
    final bool isSound = tagsData.soundTags.contains(currentTag);
    final bool isAi = tagsData.aiTags.contains(currentTag);
    final bool isInSearch =
        searchHandler.searchTextController.text
            .toLowerCase()
            .split(' ')
            .indexWhere(
              (t) =>
                  t == currentTag.toLowerCase() ||
                  t == '-${currentTag.toLowerCase()}' ||
                  t == '~${currentTag.toLowerCase()}' ||
                  RegExp(r'^(?:-|~)?\d+#(?:-|~)?' + currentTag.regexpEscape() + r'$').hasMatch(t),
            ) !=
        -1;
    final HasTabWithTagResult hasTabWithTag = tabMatchesMap.containsKey(currentTag)
        ? tabMatchesMap[currentTag]!
        : HasTabWithTagResult.noTag;
    final int tagCount = rawTag.count;

    final Color baseColor = color ?? theme.colorScheme.onSurface;
    // Tint the label towards readable contrast instead of using the raw
    // type color (pure red/brown etc. get muddy on dark surfaces).
    final Color textColor = color == null
        ? theme.colorScheme.onSurface
        : Color.lerp(color, context.isLight ? Colors.black : Colors.white, context.isLight ? 0.35 : 0.45)!;

    final List<_TagInfoIcon> tagIconAndColor = [
      if (isAi) _TagInfoIcon(FontAwesomeIcons.robot, textColor),
      if (isSound) _TagInfoIcon(Symbols.volume_up_rounded, textColor),
      if (isHidden) _TagInfoIcon(CupertinoIcons.eye_slash, Colors.red),
      if (isMarked) _TagInfoIcon(Symbols.star_rounded, Colors.yellow),
    ];

    final bool isSelectedForBatch = tagSelectionMode && selectedBatchTags.contains(currentTag);

    // r77: the preview icon is its own button laid over the chip (see
    // TagChipShell): it reacts at once - no double-tap wait - opens the
    // preview for the page it was tapped on, on the post's own site.
    return TagChipShell(
      key: ValueKey('tag-chip-$currentTag'),
      color: isSelectedForBatch
          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.22)
          : baseColor.withValues(alpha: context.isLight ? 0.09 : 0.16),
      shape: StadiumBorder(
        side: isSelectedForBatch
            ? BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.8)
            : BorderSide(
                color: isInSearch ? baseColor.withValues(alpha: 0.9) : baseColor.withValues(alpha: 0.35),
                width: isInSearch ? 1.6 : 1,
              ),
      ),
      previewZoneWidth: TagChipShell.previewZoneWidthFor(),
      previewLabel: '${context.loc.tagView.preview} $currentTag',
      guardRepeats: !tagSelectionMode,
      onPreview: () {
        if (tagSelectionMode) {
          _toggleBatchTag(currentTag);
          return;
        }
        // The icon reacts at once now, so the top page is the page it was
        // tapped on (ModalRoute.of here would make the whole tag list
        // rebuild on every route change).
        FloatingPreviewHandler.instance.open(tag: currentTag, booru: tagBooru);
      },
      onPreviewLongPress: tagSelectionMode ? null : () => _openTagInNewTab(context, currentTag),
      onTap: tagSelectionMode
          ? () => _toggleBatchTag(currentTag)
          : () {
              showTagDialog(
                context: context,
                tag: currentTag,
                // Virtual feeds (For You, favourites, merge) resolve the item's
                // real source booru — the dialog's preview / hub entries should
                // originate there, not on the virtual feed.
                handler: possibleBooruHandler ?? handler,
                isHidden: isHidden,
                isMarked: isMarked,
                isInSearch: isInSearch,
                hasTabWithTag: hasTabWithTag,
                onUpdate: parseSortGroupTagsWithoutCache,
                knownType: resolvedType,
              );
            },
      onDoubleTap: tagSelectionMode
          ? null
          : () async {
              // Shortcut straight to the tag editor (same dialog as tap →
              // "Edit tag") — mainly for quickly recolouring a tag's type.
              final Booru booru = tagBooru;
              // A COPY: mutating the object handed out by TagHandler would
              // edit the app-wide tag map in place.
              // Seeded from the source's own type on a doujin booru: the
              // shared map is a booru store and would preselect a booru's
              // classification for a coinciding name.
              final item = tagHandler
                  .getTagFor(currentTag, booru)
                  .copyWith(tagType: typeOfTag(rawTag));
              await showDialog(
                context: context,
                builder: (context) => TagsManagerListItemDialog(
                  tag: item,
                  onChangedType: (TagType? newValue) async {
                    if (newValue == null || item.tagType == newValue) return;
                    item.tagType = newValue;
                    // Stored as a correction for THIS booru only. The global
                    // tag map holds one type per tag string for the whole
                    // app, so writing there would recolour the same tag on
                    // every other site as a side effect. Doing it this way
                    // also permanently excludes the pair from automatic
                    // re-typing, which is the point of correcting it.
                    await BooruTagStore.setManualType(booru, currentTag, newValue);
                    parseSortGroupTagsWithoutCache();
                  },
                ),
              );
              parseSortGroupTagsWithoutCache();
            },
      onLongPress: tagSelectionMode ? null : () => _openTagInNewTab(context, currentTag),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 2, top: 3, bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in tagIconAndColor)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: switch (t.icon) {
                  FaIconData _ => FaIcon(t.icon, color: t.color, size: 12),
                  IconData _ => Icon(t.icon, color: t.color, size: 14),
                  _ => const SizedBox.shrink(),
                },
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.62),
              child: _chipTagLabel(currentTag, textColor),
            ),
            if (tagCount > 0) ...[
              const SizedBox(width: 5),
              Text(
                tagCount.toFormattedString(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
            if (hasTabWithTag.hasTagInAnyForm) ...[
              const SizedBox(width: 5),
              Icon(
                Symbols.circle_rounded,
                size: 7,
                color: hasTabWithTag.color(context),
              ),
            ],
            // ⧉ preview zone: a divider + picture-in-picture that opens the
            // floating preview window for this tag (its own tap target, so it
            // doesn't trigger the chip's tap = menu). Generously padded —
            // the icon is small but the hit area must be finger-sized.
            const SizedBox(width: 4),
            Container(width: 1, height: 16, color: baseColor.withValues(alpha: 0.3)),
            // Drawn here; its taps go to TagChipShell's zone over it (r77).
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
              child: Icon(
                tagSelectionMode
                    ? (isSelectedForBatch ? Symbols.check_circle_rounded : Symbols.circle_rounded)
                    : Symbols.picture_in_picture_alt_rounded,
                size: 16,
                fill: isSelectedForBatch ? 1 : 0,
                color: isSelectedForBatch ? Theme.of(context).colorScheme.secondary : baseColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens [currentTag] as a new background tab, honouring the user's "New
  /// tab placement" setting, with the same toast as every other
  /// background-tab action. r77: from the tag name's hold and the preview
  /// icon's hold alike.
  Future<void> _openTagInNewTab(BuildContext context, String currentTag) async {
    // Long-press opens the tag as a new background tab, honouring the
    // user's "New tab placement" setting and showing the same toast every
    // other background-tab action does. Adding to the current search
    // still lives behind tap → dialog.
    await ServiceHandler.vibrate(duration: 40, amplitude: 180);
    // r77: the post's own site (was the main feed's when the post came
    // from elsewhere, e.g. a nested viewer on another site).
    final Booru previewBooru = tagBooru;
    final TabAddMode addMode =
        settingsHandler.defaultTabAddMode == 'next' ? TabAddMode.next : TabAddMode.end;
    searchHandler.addTabByString(
      currentTag,
      customBooru: previewBooru,
      addMode: addMode,
      group: SearchHandler.inheritGroup,
    );
    if (!context.mounted) return;
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.tagView.addedNewTab,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(currentTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );
  }

  // Chip label with the in-panel tag-search match highlighted.
  Widget _chipTagLabel(String currentTag, Color textColor) {
    final TextStyle style = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: textColor,
    );

    final String filter = searchController.text.toLowerCase();
    final int matchIndex = filter.isEmpty ? -1 : currentTag.toLowerCase().indexOf(filter);
    if (matchIndex == -1) {
      return Text(currentTag, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: currentTag.substring(0, matchIndex), style: style),
          TextSpan(
            text: currentTag.substring(matchIndex, matchIndex + filter.length),
            style: style.copyWith(
              decoration: TextDecoration.underline,
              backgroundColor: textColor.withValues(alpha: 0.15),
            ),
          ),
          TextSpan(text: currentTag.substring(matchIndex + filter.length), style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // Builds a space-separated tag query for the "Related" preview strip.
  @override
  Widget build(BuildContext context) {
    final bool tagsAvailable = tags.isNotEmpty || hasLoadItemSupport;
    // Post metadata (url/resolution/size/rating/score/md5/uploader/sources)
    // lives in the Flow Details sheet now — opened from the action row.

    return Scrollbar(
      interactive: true,
      controller: scrollController,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              [
                if (widget.scrollController != null)
                  // Boorusama-style grab handle when hosted in the bottom sheet.
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: kMinInteractiveDimension),
                //
                // Doujin sources: reference-style book header — metadata line
                // and a prominent Read/Continue button, shown the moment
                // loadItem registers the pages.
                _doujinBookHeader(context),
                //
                // Flow post actions (Favorite / Save / Collect).
                _flowActionRow(context),
                //
                // Source booru — virtual feeds (For You, favourites, merge)
                // aggregate posts from real boorus; say which one this is.
                if (possibleBooruHandler != null)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: BooruFavicon(possibleBooruHandler!.booru, size: 20),
                    title: Text(
                      'From ${possibleBooruHandler!.booru.name ?? 'unknown booru'}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                //
                // Cross-booru lookup: pivot on the post's artist/character
                // tag to find related content on the other boorus. Booru-only
                // (see isDoujinContext).
                // r79: a button in the action block unless Modular UI says rows.
                if (!isDoujinContext && !_actionsAsButtons)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: Icon(Symbols.travel_explore_rounded, size: 20, color: Theme.of(context).colorScheme.secondary),
                    title: const Text(
                      'Find this post elsewhere',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _openFindElsewhere(context),
                  ),
                //
                // Boards (r73): a saved search seeded by this post - its tags
                // as words, its image as the reference. Booru-only.
                if (!isDoujinContext && !_actionsAsButtons)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: Icon(Symbols.dashboard_rounded, size: 20, color: Theme.of(context).colorScheme.secondary),
                    title: const Text(
                      'Find posts like this (new board)',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _openNewBoard(context),
                  ),
                //
                // Inline "more from artist / uploader" grids — Boorusama-style.
                // Each grid is gated on:
                //   - the global Settings → Interface → inlineRelatedGrids toggle
                //   - the data being available for this item + handler
                // Booru-only: the strips are built for the current booru and
                // decide artist-ness from the shared booru tag map, so on a
                // doujin item they render booru posts inside a doujin panel.
                // Doujin sources have their own Related / Recommended.
                if (settingsHandler.inlineRelatedGrids && !isDoujinContext) ..._buildRelatedGrids(),
                //
                // The old "Details" expansion (url/extension/resolution/...)
                // is gone — the Flow Details sheet (action row → Details)
                // covers all of it. Comments have no other home, so they stay
                // as a standalone row.
                if (!_actionsAsButtons) commentsButton(),
                kemonoPostButton(),
                furAffinityPostButton(),
                // Doujin "Related": other CHAPTERS and language versions of
                // this very work, found by a quoted phrase search on the base
                // title (the reference apps' Related semantics). Collapsed by
                // default — most one-shots only find themselves.
                Builder(
                  builder: (context) {
                    final BooruHandler versionsHandlerRef = possibleBooruHandler ?? handler;
                    final String? versionsQuery = versionsHandlerRef.relatedVersionsQuery(item);
                    if (versionsQuery == null) return const SizedBox.shrink();
                    return ExpansionTile(
                      title: const Text(
                        'Related — chapters & versions',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      initiallyExpanded: false,
                      iconColor: Colors.white.withValues(alpha: 0.66),
                      collapsedIconColor: Colors.white.withValues(alpha: 0.66),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TagContentPreview(
                            key: ValueKey('versions-${item.serverId}'),
                            tag: versionsQuery,
                            boorus: [versionsHandlerRef.booru],
                            parentTab: searchHandler.currentTab,
                            compact: true,
                            compactTitle: 'Other chapters and languages of this work',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Doujin "Recommended": the site's own related list, served
                // through the normal strip machinery via a `related:<id>`
                // query. Open by default, like the reference app.
                Builder(
                  builder: (context) {
                    final BooruHandler relatedHandlerRef = possibleBooruHandler ?? handler;
                    final String? galleryId = item.serverId;
                    if (!relatedHandlerRef.hasReader || galleryId == null || galleryId.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ExpansionTile(
                      title: const Text(
                        'Recommended',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      initiallyExpanded: true,
                      iconColor: Colors.white.withValues(alpha: 0.66),
                      collapsedIconColor: Colors.white.withValues(alpha: 0.66),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TagContentPreview(
                            key: ValueKey('native-related-$galleryId'),
                            tag: 'recommend:$galleryId',
                            boorus: [relatedHandlerRef.booru],
                            parentTab: searchHandler.currentTab,
                            compact: true,
                            compactTitle: "The site's related list, extended by this gallery's tags and artist",
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // "Related" — preview strip seeded from the item's strongest
                // tags (character/artist/copyright, falling back to general).
                // Only shows when we can build a meaningful seed query.
                Builder(
                  builder: (context) {
                    // Blended suggestions: several different facet queries
                    // (character / franchise minus that character / artist /
                    // act / style) mixed under quotas, rather than one tag
                    // search — a single tag just reproduces Tag Hub.
                    if (SuggestionEngine.facetsForItem(item).isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final Booru previewBooru =
                        possibleBooruHandler?.booru ?? searchHandler.currentBooru;
                    return ExpansionTile(
                      title: const Text(
                        'Suggested',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      initiallyExpanded: relatedExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() => relatedExpanded = expanded);
                      },
                      iconColor: Colors.white.withValues(alpha: 0.66),
                      collapsedIconColor: Colors.white.withValues(alpha: 0.66),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TagContentPreview(
                            key: ValueKey('suggested-${previewBooru.name}-${item.serverId ?? item.fileURL}'),
                            tag: 'suggestions',
                            boorus: [previewBooru],
                            parentTab: searchHandler.currentTab,
                            compact: true,
                            compactTitle: 'Mixed suggestions',
                            suggestFor: item,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                notesButton(),
                // r75: why the learner put this post here (recommendation feeds).
                if (!isDoujinContext && searchHandler.currentTab.booruHandler.booru.type?.isRecommendationFeed == true)
                  FutureBuilder<Explanation?>(
                    future: RecommenderHandler.maybe?.explain(item, handler: possibleBooruHandler ?? handler),
                    builder: (context, snap) {
                      final Explanation? e = snap.data;
                      if (e == null || e.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        leading: Icon(Symbols.lightbulb_rounded, color: Theme.of(context).iconTheme.color),
                        title: const Text('Picked because'),
                        subtitle: Text(e.sentence, maxLines: 3, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
                // r75: posts that look like this one, in a background tab.
                if (!isDoujinContext && _hasPicture && !_actionsAsButtons)
                  ListTile(
                    leading: Icon(Symbols.image_search_rounded, color: Theme.of(context).iconTheme.color),
                    title: const Text('Posts like this'),
                    subtitle: const Text('A tab in the background with posts that look like this one, from your sources', maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _openSimilar(context),
                  ),
                // For You is the BOORU taste system — never seeded from a
                // doujin item.
                if (settingsHandler.dbEnabled && !isDoujinContext && !_actionsAsButtons)
                  Builder(
                    builder: (context) {
                      final List<String> seeds = _recommendSeeds();
                      if (seeds.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        leading: Icon(Symbols.auto_awesome_rounded, color: Theme.of(context).iconTheme.color),
                        title: const Text('Recommend more like this'),
                        subtitle: Text(
                          seeds.map((s) => s.replaceAll('_', ' ')).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openRecommend(context, seeds),
                      );
                    },
                  ),
                if (tagsAvailable) ...[
                  Divider(
                    color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
                  ),
                  tagsButton(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                          filled: false,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: context.theme.dividerTheme.color!.withValues(alpha: 0.66),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: context.theme.dividerTheme.color!.withValues(alpha: 0.66),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      child: SettingsTextInput(
                        key: searchKey,
                        controller: searchController,
                        focusNode: searchFocusNode,
                        title: context.loc.search,
                        titleAsLabel: true,
                        onlyInput: true,
                        clearable: true,
                        pasteable: true,
                        onChanged: (_) {
                          parseSortGroupTagsWithoutCache();
                        },
                        enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: (filteredTags.isEmpty && tags.isNotEmpty)
                ? Column(
                    children: [
                      const Kaomoji(
                        category: KaomojiCategory.indifference,
                        style: TextStyle(fontSize: 36),
                      ),
                      Text(
                        context.loc.tagView.noTagsFound,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 60),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          ...tagChipSectionSlivers(context),
          ..._pagesGridSlivers(context),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom + kMinInteractiveDimension,
            ),
          ),
        ],
      ),
    );
  }
}
