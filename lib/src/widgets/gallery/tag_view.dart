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
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/widgets/common/loli_dropdown.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/boorus/favourites_handler.dart';
import 'package:lolisnatcher/src/boorus/foryou_handler.dart';
import 'package:lolisnatcher/src/boorus/history_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';
import 'package:lolisnatcher/src/widgets/gallery/doujin_item_sheet.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/floating_preview_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_alias_resolver.dart';
import 'package:lolisnatcher/src/boorus/suggestion_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/tag_hub_page.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/text_parser/rules/url_rule.dart';
import 'package:lolisnatcher/src/widgets/collections/add_to_collection_sheet.dart';
import 'package:lolisnatcher/src/widgets/gallery/post_details_sheet.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/draggable_overflow_text.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/common/parsed_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/desktop/desktop_scroll.dart';
import 'package:lolisnatcher/src/widgets/dialogs/comments_dialog.dart';
import 'package:lolisnatcher/src/widgets/gallery/notes_renderer.dart';
import 'package:lolisnatcher/src/widgets/gallery/find_elsewhere_sheet.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_tag_chip.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';
import 'package:lolisnatcher/src/widgets/tags_manager/tm_list_item_dialog.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

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

class _TagViewState extends State<TagView> {
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
  TagType typeOfTag(Tag tag) {
    final TagType? mine = BooruTagStore.manualType(tag.fullString, tagBooru);
    if (mine != null) return mine;
    if (tagHandler.hasTag(tag.fullString)) {
      final TagType stored = tagHandler.getTag(tag.fullString).tagType;
      if (stored != TagType.none) return stored;
    }
    return tag.tagType;
  }
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

  Timer? sortTimer;

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

    reloadItemData(initial: true).then((_) async {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        parseSortGroupTagsWithoutCache();
        sortTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => parseSortGroupTagsWithoutCache(),
        );
      }
    });
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
          reloadItemData(initial: true).then((_) async {
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
              parseSortGroupTagsWithoutCache();
              sortTimer?.cancel();
              sortTimer = Timer.periodic(
                const Duration(seconds: 5),
                (_) => parseSortGroupTagsWithoutCache(),
              );
            }
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
    sortTimer?.cancel();
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
    tagsData = settingsHandler.parseTagsList(tags, isCapped: false);
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

  Widget commentsButton() {
    final bool hasSupport = handler.hasCommentsSupport;
    final bool hasComments = item.hasComments == true;
    final IconData icon = hasComments ? CupertinoIcons.text_bubble_fill : CupertinoIcons.text_bubble;

    if (!hasSupport || item.fileURL.isEmpty) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.tagView.comments,
      icon: Icon(
        icon,
        color: Theme.of(context).iconTheme.color,
      ),
      action: () {
        SettingsPageOpen(
          context: context,
          page: (_) => CommentsDialog(
            item: item,
            handler: handler,
          ),
        ).open();
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
    final Booru currentBooru = searchHandler.currentBooru;
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
      if (t.tagType.isArtist) return true;
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
      final userMetaTag = searchHandler.currentBooruHandler.availableMetaTags().firstWhereOrNull((t) => t is UserMetaTag);
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
    for (final tag in toMark) {
      settingsHandler.addTagToList('marked', tag);
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
    final int idx = handler.filteredFetched.indexOf(item);
    if (idx < 0) return;
    searchHandler.currentTab.toggleItemFavourite(idx);
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
    final theme = Theme.of(context);

    Widget btn({
      required IconData icon,
      required String label,
      required Color activeColor,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final Color fg = active ? activeColor : theme.colorScheme.onSurface;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // fill is the Material Symbols variable-font axis — without it
                // the "active" state renders the same outline glyph.
                Icon(icon, size: 22, color: fg, fill: active ? 1 : 0),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? activeColor : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Obx(() {
              final bool fav = item.isFavourite.value == true;
              return btn(
                icon: Symbols.favorite_rounded,
                label: 'Favorite',
                activeColor: const Color(0xFFF0708A),
                active: fav,
                onTap: _toggleFavourite,
              );
            }),
            Obx(() {
              final bool snatched = item.isSnatched.value == true;
              return btn(
                icon: snatched ? Symbols.download_done_rounded : Symbols.download_rounded,
                label: snatched ? 'Saved' : 'Save',
                activeColor: const Color(0xFF7FC98B),
                active: snatched,
                onTap: () => _snatchItem(context),
              );
            }),
            btn(
              icon: Symbols.bookmark_add_rounded,
              label: 'Collect',
              activeColor: const Color(0xFFE8C46B),
              onTap: () => showAddToCollectionSheet(context, [item]),
            ),
            btn(
              icon: Symbols.info_rounded,
              label: 'Details',
              activeColor: theme.colorScheme.secondary,
              onTap: () => showPostDetailsSheet(context, item),
            ),
          ],
        ),
      ),
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

    return Material(
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
      child: InkWell(
        customBorder: const StadiumBorder(),
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
                final item = tagHandler.getTagFor(currentTag, booru).copyWith();
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
        onLongPress: tagSelectionMode ? null : () async {
          // Long-press opens the tag as a new background tab, honouring the
          // user's "New tab placement" setting and showing the same toast every
          // other background-tab action does. Adding to the current search
          // still lives behind tap → dialog.
          await ServiceHandler.vibrate(duration: 40, amplitude: 180);
          final Booru previewBooru = possibleBooruHandler?.booru ?? searchHandler.currentBooru;
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
        },
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (tagSelectionMode) {
                    _toggleBatchTag(currentTag);
                    return;
                  }
                  final Booru previewBooru = possibleBooruHandler?.booru ?? searchHandler.currentBooru;
                  FloatingPreviewHandler.instance.open(tag: currentTag, booru: previewBooru);
                },
                child: Padding(
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
              ),
            ],
          ),
        ),
      ),
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
                // tag to find related content on the other boorus.
                ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: Icon(Symbols.travel_explore_rounded, size: 20, color: Theme.of(context).colorScheme.secondary),
                    title: const Text(
                      'Find this post elsewhere',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    onTap: () => showFindElsewhereSheet(
                      context,
                      item,
                      (possibleBooruHandler ?? handler).booru,
                    ),
                  ),
                //
                // Inline "more from artist / uploader" grids — Boorusama-style.
                // Each grid is gated on:
                //   - the global Settings → Interface → inlineRelatedGrids toggle
                //   - the data being available for this item + handler
                if (settingsHandler.inlineRelatedGrids) ..._buildRelatedGrids(),
                //
                // The old "Details" expansion (url/extension/resolution/...)
                // is gone — the Flow Details sheet (action row → Details)
                // covers all of it. Comments have no other home, so they stay
                // as a standalone row.
                commentsButton(),
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
                if (settingsHandler.dbEnabled)
                  Builder(
                    builder: (context) {
                      final List<String> seeds = InterestsHandler.seedTagsFromItem(item, limit: 3);
                      if (seeds.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        leading: Icon(Symbols.auto_awesome_rounded, color: Theme.of(context).iconTheme.color),
                        title: const Text('Recommend more like this'),
                        subtitle: Text(
                          seeds.map((s) => s.replaceAll('_', ' ')).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          final booru = settingsHandler.ensureForYouBooru();
                          final String query = seeds.map((s) => 'seed:$s').join(' ');
                          searchHandler.addTabByString(query, customBooru: booru, switchToNew: true);
                          if (settingsHandler.appMode.value.isMobile) {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          }
                        },
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

enum _BlacklistScope { global, perBooru }

Future<_BlacklistScope?> _pickBlacklistScope(BuildContext context, Booru booru) async {
  final String? booruName = booru.name;
  // If the booru has no usable name (e.g. virtual Favourites/Downloads/Merge),
  // there's no "per-booru" target — just blacklist globally without asking.
  if (booruName == null || booruName.isEmpty) return _BlacklistScope.global;
  return showDialog<_BlacklistScope>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add to blacklist'),
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Symbols.public_rounded),
            title: const Text('Globally'),
            subtitle: const Text('Hides items with this tag on every booru'),
            onTap: () => Navigator.of(ctx).pop(_BlacklistScope.global),
          ),
          ListTile(
            leading: const Icon(Symbols.collections_bookmark_rounded),
            title: const Text('Only on this booru'),
            subtitle: Text(booruName),
            onTap: () => Navigator.of(ctx).pop(_BlacklistScope.perBooru),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Future<void> showTagDialog({
  required BuildContext context,
  required String tag,
  required BooruHandler handler,
  required bool isHidden,
  required bool isMarked,
  required bool isInSearch,
  required HasTabWithTagResult hasTabWithTag,
  required VoidCallback onUpdate,
}) async {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;

  final Tag resolvedTag = tagHandler.getTagFor(tag, handler.booru);
  final Color typeColor = resolvedTag.getColour() ?? const Color(0xFF8A80A0);
  final String typeName = resolvedTag.tagType.locName;
  await showModalBottomSheet<void>(
    context: context,
    routeSettings: RouteSettings(name: 'tagDialog/$tag'),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4260),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Flow header: type-colour bar + tag name (in type colour) + type + close
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag.replaceAll('_', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          typeName,
                          style: const TextStyle(
                            color: Color(0xFF8A80A0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
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
                  //
          // Boorusama-style floating preview window (draggable/resizable,
          // opens over whatever page spawned this dialog).
          ListTile(
            leading: Icon(
              Symbols.picture_in_picture_alt_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: Text(context.loc.tagView.preview),
            onTap: () {
              final Booru previewBooru = handler.booru.type?.isMerge == true
                  ? (handler as MergebooruHandler).booruHandlers.first.booru
                  : handler.booru;
              Navigator.of(context).pop();
              FloatingPreviewHandler.instance.open(
                tag: tag,
                booru: previewBooru,
              );
            },
          ),
          //
          // Tag hub — a dedicated page showing this tag across every
          // configured booru. Artists get follow support and their own label.
          ListTile(
            leading: Icon(
              resolvedTag.tagType.isArtist ? Symbols.artist_rounded : Symbols.hub_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: Text(resolvedTag.tagType.isArtist ? 'Artist hub' : 'Tag hub'),
            subtitle: Text(
              resolvedTag.tagType.isArtist
                  ? 'Follow + their work across your boorus'
                  : 'This tag across your boorus',
            ),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TagHubPage(
                    tag: tag,
                    originBooru: handler.booru,
                  ),
                ),
              );
            },
          ),
          //
          ListTile(
            leading: Icon(
              Symbols.content_copy_rounded,
              color: Theme.of(context).iconTheme.color,
            ),
            title: Text(context.loc.tagView.copy),
            onTap: () {
              Clipboard.setData(ClipboardData(text: tag));
              FlashElements.showSnackbar(
                context: context,
                duration: const Duration(seconds: 2),
                title: Text(
                  context.loc.copiedToClipboard,
                  style: const TextStyle(fontSize: 20),
                ),
                content: Text(
                  tag,
                  style: const TextStyle(fontSize: 16),
                ),
                leadingIcon: Symbols.content_copy_rounded,
                sideColor: Colors.green,
              );
              Navigator.of(context).pop();
            },
          ),
          //
          if (isInSearch)
            ListTile(
              leading: Icon(
                Symbols.delete_rounded,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromSearch),
              onTap: () {
                searchHandler.removeTagFromSearch(tag);
                Navigator.of(context).pop();
              },
            )
          else
            const SizedBox.shrink(),
          //
          // Open the tag as a background tab inside a tab group — existing
          // group or a newly named one.
          ListTile(
            leading: Icon(
              Symbols.create_new_folder_rounded,
              color: Theme.of(context).iconTheme.color,
            ),
            title: const Text('Open in group'),
            subtitle: const Text('Inside a group, outside it, or a new one'),
            onTap: () {
              Navigator.of(context).pop();
              showOpenTagInGroupSheet(
                NavigationHandler.instance.navContext,
                tag,
                handler.booru,
              );
            },
          ),
          //
          if (!isHidden && !isMarked)
            ListTile(
              leading: const Icon(Symbols.star_rounded, color: Colors.yellow),
              title: Text(context.loc.tagView.addToMarked),
              onTap: () {
                settingsHandler.addTagToList('marked', tag);
                searchHandler.filterCurrentFetched();
                handler.filterFetched();
                onUpdate();
                Navigator.of(context).pop(true);
              },
            ),
          if (!isHidden && !isMarked && !settingsHandler.isTagHiddenForBooru(tag, handler.booru.name))
            ListTile(
              leading: const Icon(CupertinoIcons.eye_slash, color: Colors.red),
              title: Text(context.loc.tagView.addToHidden),
              onTap: () async {
                final scope = await _pickBlacklistScope(context, handler.booru);
                if (scope == null) return;
                if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
                  // Doujin sources blacklist via sourceSettings only.
                  SourceSettingsHandler.instance.addBlacklistTag(
                    scope == _BlacklistScope.global ? null : handler.booru,
                    tag,
                  );
                } else if (scope == _BlacklistScope.global) {
                  settingsHandler.addTagToList('hidden', tag);
                } else if (handler.booru.name?.isNotEmpty == true) {
                  settingsHandler.addTagToBooruHiddenList(handler.booru.name!, tag);
                }
                searchHandler.filterCurrentFetched();
                handler.filterFetched();
                onUpdate();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          if (isMarked)
            ListTile(
              leading: Icon(
                Symbols.star_border_rounded,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromMarked),
              onTap: () {
                settingsHandler.removeTagFromList('marked', tag);
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          if (isHidden)
            ListTile(
              leading: Icon(
                CupertinoIcons.eye_slash,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromHidden),
              onTap: () {
                settingsHandler.removeTagFromList('hidden', tag);
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          if (settingsHandler.isTagHiddenForBooru(tag, handler.booru.name))
            ListTile(
              leading: Icon(
                CupertinoIcons.eye_slash,
                color: Theme.of(context).iconTheme.color,
              ),
              title: const Text("Remove from this booru's blacklist"),
              subtitle: Text(handler.booru.name ?? ''),
              onTap: () {
                final n = handler.booru.name;
                if (n != null && n.isNotEmpty) {
                  settingsHandler.removeTagFromBooruHiddenList(n, tag);
                  searchHandler.filterCurrentFetched();
                  handler.filterFetched();
                }
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          //
          FutureBuilder<PinnedTag?>(
            future: DoujinDataHandler.isDoujinBooru(searchHandler.currentBooru)
                ? Future.value(() {
                    for (final p in doujinPinsAsPinnedTags(searchHandler.currentBooru)) {
                      if (p.tagName == tag) return p;
                    }
                    return null;
                  }())
                : settingsHandler.dbHandler.getPinnedTag(
                    tag,
                    booruType: searchHandler.currentBooru.type?.name,
                    booruName: searchHandler.currentBooru.name,
                  ),
            builder: (_, snapshot) {
              final isPinned = snapshot.data != null;
              final pinnedTag = snapshot.data;

              void reopenDialog() {
                Navigator.of(context).pop();
                showTagDialog(
                  context: context,
                  tag: tag,
                  handler: handler,
                  isHidden: isHidden,
                  isMarked: isMarked,
                  isInSearch: isInSearch,
                  hasTabWithTag: hasTabWithTag,
                  onUpdate: onUpdate,
                );
              }

              return ListTile(
                title: Text(isPinned ? context.loc.pinnedTags.unpinTag : context.loc.pinnedTags.pinTag),
                leading: Icon(isPinned ? Symbols.push_pin_rounded : Symbols.push_pin_rounded),
                onTap: () async {
                  if (isPinned && pinnedTag != null) {
                    await showUnpinTagDialog(
                      context,
                      tag,
                      pinnedTag,
                      () {},
                    );
                  } else {
                    await showPinTagDialog(
                      context,
                      tag,
                      searchHandler.currentBooru,
                      () {},
                    );
                  }
                  reopenDialog();
                },
              );
            },
          ),
          //
          if (hasTabWithTag.hasTagInAnyForm)
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    CupertinoIcons.doc_on_doc,
                    color: Theme.of(context).iconTheme.color,
                  ),

                  Positioned(
                    right: -5,
                    top: -5,
                    child: Icon(
                      Symbols.circle_rounded,
                      size: 6,
                      color: hasTabWithTag.color(context),
                    ),
                  ),
                ],
              ),
              title: Text(context.loc.tagView.relatedTabs),
              onTap: () => showRelatedTabsDialog(context, tag),
            ),
          // Edit tag removed from this menu — double-tapping the chip opens
          // the tag editor directly.
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Sentinel returned by [pickTabGroupName] when the "Open outside group"
/// entry (shown only if [pickTabGroupName]'s allowOutside is set and the
/// current tab is grouped) is chosen.
const String kOpenOutsideGroupSentinel = ' outside-group';
const String kOpenFromSentinel = ' open-from';

/// Group picker: bottom sheet listing existing tab groups (with counts) plus
/// a "New group…" entry that prompts for a name. Returns the chosen/created
/// group name, [kOpenOutsideGroupSentinel] for "outside group", or null when
/// dismissed.
Future<String?> pickTabGroupName(
  BuildContext context, {
  String title = 'Pick a group',
  bool allowOutside = false,
  // When set, offers an "Open from" entry: a new group named
  // `from__<tag>` as the seed of a fresh discovery run.
  String? openFromTag,
}) async {
  final searchHandler = SearchHandler.instance;
  final List<String> groups = searchHandler.tabGroupNames;
  const String newGroupSentinel = ' new-group';
  // Only meaningful while browsing inside a group.
  final bool showOutside =
      allowOutside && searchHandler.tabs.isNotEmpty && (searchHandler.currentTab.groupName?.isNotEmpty ?? false);

  final String? chosen = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) {
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
                  Icon(Symbols.create_new_folder_rounded, size: 20, color: theme.colorScheme.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  // Quick actions first: outside-group escape hatch, then the
                  // "start a new discovery run from this tag" shortcut.
                  if (showOutside)
                    ListTile(
                      leading: Icon(Symbols.folder_off_rounded, color: theme.iconTheme.color),
                      title: const Text('Outside group'),
                      subtitle: const Text("Ungrouped tab after this group's block"),
                      onTap: () => Navigator.of(ctx).pop(kOpenOutsideGroupSentinel),
                    ),
                  if (openFromTag != null)
                    ListTile(
                      leading: const Icon(Symbols.conversion_path_rounded, color: Colors.green),
                      title: const Text('Open from'),
                      subtitle: Text('New group "from__${openFromTag.replaceAll(' ', '_')}" — a fresh starting point'),
                      onTap: () => Navigator.of(ctx).pop(kOpenFromSentinel),
                    ),
                  if (showOutside || openFromTag != null) const Divider(height: 1),
                  for (final g in groups)
                    ListTile(
                      leading: Icon(Symbols.folder_open_rounded, color: theme.colorScheme.secondary),
                      title: Text(g),
                      subtitle: Text(
                        '${searchHandler.tabsInGroup(g).length} ${searchHandler.tabsInGroup(g).length == 1 ? 'tab' : 'tabs'}',
                      ),
                      onTap: () => Navigator.of(ctx).pop(g),
                    ),
                  ListTile(
                    leading: const Icon(Symbols.add_rounded, color: Colors.green),
                    title: const Text('New group…'),
                    onTap: () => Navigator.of(ctx).pop(newGroupSentinel),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  if (chosen == null) return null;
  if (chosen == kOpenOutsideGroupSentinel || chosen == kOpenFromSentinel) return chosen;
  if (chosen != newGroupSentinel) return chosen;

  if (!context.mounted) return null;
  final TextEditingController controller = TextEditingController();
  final String? name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New tab group'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Group name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.loc.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (name == null || name.isEmpty) ? null : name;
}

/// Bottom sheet to open [tag] as a background tab inside a tab group:
/// pick an existing group or name a new one on the spot.
Future<void> showOpenTagInGroupSheet(
  BuildContext context,
  String tag,
  Booru booru,
) async {
  final String? choice = await pickTabGroupName(
    context,
    title: 'Open "${tag.replaceAll('_', ' ')}" in group',
    allowOutside: true,
    openFromTag: tag,
  );
  if (choice == null) return;

  final bool outside = choice == kOpenOutsideGroupSentinel;
  final bool openFrom = choice == kOpenFromSentinel;
  // "Open from": seed a fresh discovery run — new group named after the tag.
  final String? groupName = outside
      ? null
      : openFrom
      ? 'from__${tag.replaceAll(' ', '_')}'
      : choice;

  SearchHandler.instance.addTabByString(
    tag,
    customBooru: booru,
    // Outside: ungrouped tab; the insertion snapping places it after the
    // current group's block. New groups honour the placement setting.
    group: groupName,
    switchToNew: false,
  );

  FlashElements.showSnackbar(
    isKeyUnique: true,
    key: 'added_new_tab',
    duration: const Duration(seconds: 2),
    title: Text(
      outside ? 'Opened outside group' : 'Opened in group "$groupName"',
      style: const TextStyle(fontSize: 20),
    ),
    content: Text(tag, style: const TextStyle(fontSize: 16)),
    leadingIcon: Symbols.fiber_new_rounded,
    sideColor: Colors.green,
  );
}

Future<void> showRelatedTabsDialog(
  BuildContext context,
  String tag,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _RelatedTabsDialog(tag),
  );
}

class _RelatedTabsDialog extends StatefulWidget {
  const _RelatedTabsDialog(
    this.tag,
  );

  final String tag;

  @override
  State<_RelatedTabsDialog> createState() => _RelatedTabsDialogState();
}

class _RelatedTabsDialogState extends State<_RelatedTabsDialog> {
  final searchHandler = SearchHandler.instance;

  List<(int, SearchTab)> tabsWithOnlyTag = [], tabsWithOnlyTagDifferentBooru = [], tabsContainingTag = [];

  HasTabWithTagResult selectedType = HasTabWithTagResult.noTag;

  @override
  void initState() {
    super.initState();

    tabsWithOnlyTag = searchHandler.getTabsWithOnlyTag(widget.tag);
    tabsWithOnlyTagDifferentBooru = searchHandler.getTabsWithOnlyTagDifferentBooru(widget.tag);
    tabsContainingTag = searchHandler.getTabsContainingTag(widget.tag);

    selectedType = HasTabWithTagResult.noTag;
    if (tabsWithOnlyTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTag;
    } else if (tabsWithOnlyTagDifferentBooru.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTagDifferentBooru;
    } else if (tabsContainingTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.containsTag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listItems = switch (selectedType) {
      .onlyTag => tabsWithOnlyTag,
      .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru,
      .containsTag => tabsContainingTag,
      _ => <(int, SearchTab)>[],
    };

    return SettingsDialog(
      scrollable: false,
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          LoliDropdown(
            value: selectedType,
            onChanged: (newType) {
              setState(() => selectedType = newType ?? HasTabWithTagResult.noTag);
            },
            items: [
              if (tabsWithOnlyTag.isNotEmpty) HasTabWithTagResult.onlyTag,
              if (tabsWithOnlyTagDifferentBooru.isNotEmpty) HasTabWithTagResult.onlyTagDifferentBooru,
              if (tabsContainingTag.isNotEmpty) HasTabWithTagResult.containsTag,
            ],
            itemBuilder: (v) => ListTile(
              leading: Icon(
                Symbols.circle_rounded,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(
                '${v?.locName(context) ?? ''} (${switch (v) {
                  .onlyTag => tabsWithOnlyTag.length,
                  .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru.length,
                  .containsTag => tabsContainingTag.length,
                  _ => 0,
                }})',
              ),
            ),
            selectedItemBuilder: (v) => ListTile(
              leading: Icon(
                Symbols.circle_rounded,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(v?.locName(context) ?? ''),
            ),
            labelText: context.loc.tagView.relatedTabs,
          ),
          Container(
            width: double.maxFinite,
            height: (listItems.length * 80.0).clamp(0, MediaQuery.sizeOf(context).height * 0.66) + 32,
            decoration: const BoxDecoration(),
            child: ListView.builder(
              itemCount: listItems.length,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemBuilder: (context, index) {
                final (tabIndex, tab) = listItems[index];
                return TabManagerItem(
                  tab: tab,
                  index: index,
                  isFiltered: true,
                  originalIndex: tabIndex,
                  onTap: () async {
                    await ServiceHandler.vibrate();
                    if (SettingsHandler.instance.appMode.value.isMobile) {
                      Navigator.of(context).popUntil((r) => r.isFirst); // exit viewer
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      searchHandler.changeTabIndex(tabIndex);
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      actionButtons: const [CloseDialogButton(withIcon: true)],
    );
  }
}

//

class SourceLinkErrorDialog extends StatelessWidget {
  const SourceLinkErrorDialog({
    required this.link,
    super.key,
  });

  final String link;
  List<String> get detectedUrls => const UrlParseRule()
      .findMatches(link)
      .map((m) => m.segment.metadata['url'] as String? ?? m.segment.text)
      .toList();

  Future<void> copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.copiedToClipboard,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(link, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.content_copy_rounded,
      sideColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.tagView.sourceDialogTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          if (detectedUrls.isNotEmpty) ...[
            Text(
              context.loc.tagView.detectedLinks,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            ...detectedUrls.map(
              (url) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Symbols.link_rounded, size: 20),
                title: Text(url, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                onTap: () async {
                  final ok = await launchUrlString(
                    url,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok) {
                    FlashElements.showSnackbar(
                      title: Text(context.loc.failedToOpenLink),
                      content: Text(url),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          ParsedText(
            text: link,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        ElevatedButton.icon(
          onPressed: () => copy(context),
          label: Text(context.loc.copy),
          icon: const Icon(Symbols.content_copy_rounded),
        ),
        const CloseDialogButton(withIcon: true),
      ],
    );
  }
}

/// A header-only widget that, when tapped, expands inline to show a
/// [TagContentPreview] grid for the given query against the given booru.
///
/// Lazy on purpose: we DON'T mount the underlying TagContentPreview until
/// the user explicitly opts in, so opening the drawer doesn't fire a
/// (potentially slow / metered) request per related section, and scrolling
/// past the related-grids region stays cheap.
class _CollapsibleRelatedPreview extends StatefulWidget {
  const _CollapsibleRelatedPreview({
    required this.title,
    required this.icon,
    required this.booru,
    required this.query,
    required this.parentTab,
    super.key,
  });

  final String title;
  final IconData icon;
  final Booru booru;
  final String query;
  final SearchTab? parentTab;

  @override
  State<_CollapsibleRelatedPreview> createState() => _CollapsibleRelatedPreviewState();
}

class _CollapsibleRelatedPreviewState extends State<_CollapsibleRelatedPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(widget.icon),
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Open in floating window',
                icon: Icon(
                  Symbols.picture_in_picture_alt_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                onPressed: () {
                  FloatingPreviewHandler.instance.open(
                    tag: widget.query,
                    booru: widget.booru,
                  );
                },
              ),
              Icon(_expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
            ],
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TagContentPreview(
              tag: widget.query,
              boorus: [widget.booru],
              parentTab: widget.parentTab,
              compact: true,
              // No compactTitle here: the wrapper above already shows the
              // section header, so let TagContentPreview render its default
              // "Preview" sub-label so we don't get a duplicate title.
            ),
          ),
      ],
    );
  }
}

class TagContentPreview extends StatefulWidget {
  TagContentPreview({
    required this.tag,
    required this.boorus,
    required this.parentTab,
    this.readOnly = false,
    this.compact = false,
    this.compactTitle,
    this.onEffectiveTagChanged,
    this.hideWhenEmpty = false,
    this.header,
    this.suggestFor,
    this.suggestBoorus,
    super.key,
  }) : assert(
         boorus.isNotEmpty,
         'boorus must not be empty',
       );

  final String tag;
  final List<Booru> boorus;
  final SearchTab? parentTab;
  final bool readOnly;

  // Reports the strip's current effective query (base tag + any active
  // "videos / GIFs only" filter) so an enclosing widget's own "open in
  // new tab" button can carry the same filter the strip is showing.
  final ValueChanged<String>? onEffectiveTagChanged;

  // When true, the preview renders with minimal chrome (no booru dropdown,
  // no refresh/close icons, no "open in new tab" cluster) and eagerly
  // loads on init. Used inline inside the post-details drawer.
  final bool compact;
  // Optional override for the "Preview" header — e.g. "More from artist X".
  final String? compactTitle;

  // When true, the whole strip (and [header], if any) collapses to nothing
  // once the search comes back empty — used by the hub pages so boorus that
  // don't know the tag don't waste a "Nothing found" row of screen space.
  final bool hideWhenEmpty;

  // Optional widget rendered above the strip (e.g. the hub's favicon+name
  // row). Lives inside the preview so it collapses together with it when
  // [hideWhenEmpty] kicks in.
  final Widget? header;

  // When set, this strip stops being a single tag search and becomes the
  // blended suggestion feed for that post: several different facet queries
  // (character / franchise-minus-character / artist / act / style) fetched in
  // parallel and interleaved under per-facet quotas and per-artist,
  // per-character caps. See SuggestionHandler / SuggestionEngine.
  final BooruItem? suggestFor;

  // Cross-booru discovery: when set (and longer than one), the facets are
  // spread across these boorus with tag spellings translated per site.
  final List<Booru>? suggestBoorus;

  @override
  State<TagContentPreview> createState() => _TagContentPreviewState();
}

class _TagContentPreviewState extends State<TagContentPreview> with AutomaticKeepAliveClientMixin {
  // Hub strips stay alive off-screen: without this, scrolling a hub unmounts
  // strips and they re-fetch (and re-collapse) when scrolled back — janky.
  @override
  bool get wantKeepAlive => widget.compact;

  final settingsHandler = SettingsHandler.instance;
  final viewerHandler = ViewerHandler.instance;

  // Whether this strip has EVER shown results. A strip that once had posts
  // must not collapse just because a later filter cycle (e.g. gif on a booru
  // with no gifs for the tag) comes back empty.
  bool _hadResults = false;
  // Bounded auto-pagination: some boorus return thin/empty early pages for
  // rare tags — keep fetching a few pages until there's something to show.
  int _autoPagesFetched = 0;

  final AutoScrollController scrollController = AutoScrollController();

  Booru? selectedBooru;

  SearchTab? tab;
  bool loading = false;
  bool isLastPage = false;
  String errorString = '';

  // Cross-booru alias translation: when the strip is switched to a booru
  // other than the one the tag was written for, the tag is resolved to that
  // booru's own spelling via TagAliasResolver (e.g. `burnice` →
  // `burnice_white_(zenless_zone_zero)`). null = no translation active.
  String? resolvedQuery;
  Map<String, String> resolvedTerms = {};

  // Header "videos / GIFs only" filter. -1 means off; otherwise it's an
  // index into the active booru's `animatedPreviewFilters` list, which the
  // button cycles through (off → [0] → [1] → … → off).
  int animatedFilterIndex = -1;

  // The list of filter fragments for the active booru (e.g. a single
  // `animated|video` stop on OR boorus, or `video`/`webm`/`animated` on
  // realbooru). Falls back to a single OR stop before the handler exists.
  List<String> get _animatedFilters =>
      tab?.booruHandler.animatedPreviewFilters ?? const ['animated|video'];

  // The currently applied filter fragment, or null when off / out of range
  // (the latter can happen briefly after switching to a booru with a
  // shorter filter list).
  String? get _activeAnimatedFilter =>
      (animatedFilterIndex >= 0 && animatedFilterIndex < _animatedFilters.length)
      ? _animatedFilters[animatedFilterIndex]
      : null;

  // The actual query sent to the booru handler — `widget.tag` (translated to
  // the selected booru's spelling when a resolution is active) plus any
  // per-strip filter the user toggled in the header.
  String get _effectiveTag {
    final String base = resolvedQuery ?? widget.tag;
    final filter = _activeAnimatedFilter;
    return filter == null ? base : '$base $filter';
  }

  // The booru this strip's tag was originally written for.
  Booru? get _originBooru =>
      widget.parentTab?.selectedBooru.value ?? (widget.boorus.isNotEmpty ? widget.boorus.first : null);

  // Translates the tag for the selected booru when it differs from the origin
  // booru. Failures (or nothing to translate) leave the original query.
  Future<void> _maybeResolveAliases() async {
    resolvedQuery = null;
    resolvedTerms = {};
    final Booru? origin = _originBooru;
    final Booru? target = selectedBooru;
    if (origin == null || target == null) return;
    if (origin.name == target.name && origin.type == target.type) return;
    try {
      final res = await TagAliasResolver.resolveQuery(widget.tag, target);
      if (res.changed) {
        resolvedQuery = res.query;
        resolvedTerms = res.perTerm;
      }
    } catch (_) {}
  }

  // Whether the booru currently powering this strip understands
  // cross-booru OR (so we can collapse the cycle to a single
  // "animated|video" stop instead of stepping through both).
  // Tooltip describing the current filter state and what the next tap does.
  String get _animatedButtonTooltip {
    final filters = _animatedFilters;
    final active = _activeAnimatedFilter;
    if (active == null) {
      // Off → first tap applies filters[0]. Label it for clarity.
      final first = filters.isNotEmpty ? filters.first : 'animated|video';
      return first.contains('|') ? 'Videos / GIFs only' : 'Filter: $first';
    }
    final bool isLast = animatedFilterIndex >= filters.length - 1;
    final String label = active.contains('|') ? 'videos / GIFs' : active;
    return isLast ? 'Filter: $label — tap to clear' : 'Filter: $label — tap for next';
  }

  final ValueNotifier<int> viewedIndex = ValueNotifier(-1);

  bool get isSingleBooru => widget.boorus.length == 1;

  final String previewId = const Uuid().v4();

  @override
  void initState() {
    super.initState();

    viewerHandler.addTagPreview(
      widget.parentTab?.id,
      previewId,
      widget.tag,
    );

    if (isSingleBooru) {
      selectedBooru = widget.boorus.first;
    }

    // Compact mode is used inline (no booru dropdown to wait on), so kick
    // off the first fetch as soon as the widget mounts.
    if (widget.compact && selectedBooru != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadPreview();
      });
    }
  }

  Future<void> loadPreview({
    bool refresh = false,
    bool retry = false,
  }) async {
    if (selectedBooru == null) {
      return;
    }

    if (refresh || tab == null) {
      _autoPagesFetched = 0;
      await _maybeResolveAliases();
      if (!mounted) return;
      tab = SearchTab(
        selectedBooru!,
        null,
        _effectiveTag,
        customHandler: widget.suggestFor == null
            ? null
            : SuggestionHandler(
                selectedBooru!,
                30,
                sourceItem: widget.suggestFor!,
                targetBoorus: widget.suggestBoorus,
              ),
      );
      // Preview strips are throwaway mini-searches. Don't let them write the
      // previewed booru's tag types into the shared store — otherwise
      // previewing a tag on a different booru re-colours the current booru's
      // tags and the resulting rebuild resets this strip's selected booru.
      tab!.booruHandler.storeTagsGlobally = false;
      loading = false;
      isLastPage = false;
      errorString = '';
      setState(() {});
    }

    if (loading) {
      return;
    }

    if (retry) {
      errorString = '';
      tab!.booruHandler.errorString = '';

      isLastPage = false;
      tab!.booruHandler.locked = false;
      tab!.booruHandler.pageNum--;
    }

    if (isLastPage || errorString.isNotEmpty) {
      return;
    }

    if (tab!.booruHandler.locked == false) {
      loading = true;
      tab!.booruHandler.pageNum++;
    }
    setState(() {});

    await tab!.booruHandler.search(_effectiveTag, null);

    if (tab!.booruHandler.locked && !isLastPage) {
      isLastPage = true;
      setState(() {});
    }

    if (tab!.booruHandler.errorString.isNotEmpty) {
      errorString = tab!.booruHandler.errorString;
      if (!mounted) return;
      setState(() {});
    }

    if (tab!.booruHandler.totalCount.value == 0) {
      unawaited(tab!.booruHandler.searchCount(_effectiveTag));
    }

    if (tab!.booruHandler.filteredFetched.isNotEmpty) {
      _hadResults = true;
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      loading = false;
      setState(() {});
    });
    if (!mounted) return;
    setState(() {});

    // Thin/empty early pages (rare tags on some boorus): auto-fetch a few
    // more pages so the strip doesn't claim "nothing found" (or show 3
    // thumbs) when the tag actually has posts further in.
    final BooruHandler handlerRef = tab!.booruHandler;
    if (!isLastPage &&
        errorString.isEmpty &&
        handlerRef.filteredFetched.length < 10 &&
        _autoPagesFetched < 4) {
      _autoPagesFetched++;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && tab?.booruHandler == handlerRef) {
          loadPreview();
        }
      });
    }
  }

  Future<void> onPreviewTap(int index) async {
    viewedIndex.value = index;
    final viewerKey = GlobalKey(debugLabel: 'viewer-${tab!.tags.replaceAll(' ', '_')}');
    ViewerHandler.instance.addViewer(viewerKey);
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => GalleryViewPage(
          key: viewerKey,
          tab: tab!,
          initialIndex: index,
          canSelect: false,
          readOnly: widget.readOnly,
          onPageChanged: (page) async {
            viewedIndex.value = page;
            await scrollController.scrollToIndex(
              page,
              duration: const Duration(milliseconds: 10),
              preferPosition: AutoScrollPosition.begin,
            );
          },
        ),
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        barrierColor: Colors.black26,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return const ZoomPageTransitionsBuilder().buildTransitions(
            MaterialPageRoute(
              builder: (_) => const SizedBox.shrink(),
            ),
            context,
            animation,
            secondaryAnimation,
            child,
          );
        },
      ),
    );
    viewedIndex.value = -1;
  }

  Future<void> onPreviewDoubleTap(int index) async {
    if (widget.readOnly) return;

    await tab?.toggleItemFavourite(index);
  }

  Future<void> onPreviewSecondaryTap(int index) async {
    if (tab == null) {
      return;
    }

    final BooruItem item = tab!.booruHandler.filteredFetched[index];
    await Clipboard.setData(ClipboardData(text: Uri.encodeFull(item.fileURL)));
    FlashElements.showSnackbar(
      duration: const Duration(seconds: 2),
      title: Text(context.loc.tagView.copiedFileURL, style: const TextStyle(fontSize: 20)),
      content: Text(Uri.encodeFull(item.fileURL), style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.content_copy_rounded,
      sideColor: Colors.green,
    );
  }

  Future<void> showTagPreviewsListDialog() async {
    if (widget.parentTab == null) return;

    await showDialog(
      context: context,
      builder: (_) => _TagPreviewsListDialog(widget.parentTab!.id),
    );
  }

  @override
  void dispose() {
    viewerHandler.removeTagPreview(
      widget.parentTab?.id,
      previewId,
    );
    super.dispose();
  }

  // Opens the LoliDropdown booru picker programmatically — used by the
  // chip-arrow button. Mirrors what SettingsBooruDropdown did before.
  Future<void> _openBooruPicker(BuildContext context) async {
    final dropdown = LoliDropdown<Booru?>(
      value: selectedBooru,
      onChanged: (v) {
        setState(() {
          selectedBooru = v;
        });
        loadPreview(refresh: true);
      },
      items: [...settingsHandler.booruList],
      labelText: context.loc.booru,
      itemBuilder: (b) => b == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TabBooruSelectorItem(booru: b),
            ),
      selectedItemBuilder: (b) => b == null
          ? Text(context.loc.tagView.selectBooruToLoad)
          : TabBooruSelectorItem(booru: b),
      searchable: settingsHandler.booruList.length > 5,
      searchCheck: (s, b) =>
          (b?.name?.toLowerCase().contains(s) ?? true) ||
          (b?.type?.name.toLowerCase().contains(s) ?? true),
    );
    await dropdown.showDialog(context);
  }

  // Advances the "videos / GIFs only" filter to the next stop in the
  // active booru's `animatedPreviewFilters` list and reloads the strip.
  // Walks off → [0] → [1] → … → off. A single-entry list (most OR boorus)
  // behaves as a plain on/off toggle; realbooru steps through
  // video → webm → animated.
  void _toggleAnimatedOnly() {
    setState(() {
      final int next = animatedFilterIndex + 1;
      animatedFilterIndex = next < _animatedFilters.length ? next : -1;
    });
    widget.onEffectiveTagChanged?.call(_effectiveTag);
    loadPreview(refresh: true);
  }

  // The "open this tag in a new tab" action — extracted so it can be reused
  // from the chip's icon button.
  void _openInNewTab(BuildContext context) {
    final defaultMode = settingsHandler.defaultTabAddMode == 'next' ? TabAddMode.next : TabAddMode.end;
    SearchHandler.instance.addTabByString(
      _effectiveTag,
      customBooru: selectedBooru,
      addMode: defaultMode,
      group: SearchHandler.inheritGroup,
    );

    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.tagView.addedNewTab,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(_effectiveTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
      primaryActionBuilder: (context, controller) {
        return Row(
          children: [
            IconButton(
              onPressed: () {
                ServiceHandler.vibrate();
                if (settingsHandler.appMode.value.isMobile) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  SearchHandler.instance.changeTabIndex(
                    SearchHandler.instance.tabs.length - 1,
                  );
                });
                controller.dismiss();
              },
              icon: Icon(
                Symbols.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => controller.dismiss(),
              icon: Icon(Symbols.close_rounded, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openInNewTabLongPress(BuildContext context) async {
    await ServiceHandler.vibrate();

    final TabAddMode? chosenMode = await showDialog<TabAddMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Open new tab'),
          contentPadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Symbols.vertical_align_bottom_rounded),
                title: const Text('Open at end of tab list'),
                onTap: () => Navigator.of(dialogContext).pop(TabAddMode.end),
              ),
              ListTile(
                leading: const Icon(Symbols.tab_rounded),
                title: const Text('Open next to current tab'),
                onTap: () => Navigator.of(dialogContext).pop(TabAddMode.next),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (chosenMode == null) return;

    SearchHandler.instance.addTabByString(
      _effectiveTag,
      customBooru: selectedBooru,
      addMode: chosenMode,
      switchToNew: false,
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
      content: Text(_effectiveTag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.fiber_new_rounded,
      sideColor: Colors.green,
    );
  }

  /// Boorusama-style chip that replaces the old preview header + standalone
  /// booru dropdown. Layout: favicon, booru name, video filter, new-tab,
  /// picker arrow. The chip surface is non-tappable — the arrow is the only
  /// way to open the booru picker, so the inline action buttons aren't
  /// swallowed by a wrapping button.
  Widget _buildBooruChip(BuildContext context) {
    final boo = selectedBooru;
    final theme = Theme.of(context);
    final hasTabResult = SearchHandler.instance.hasTabWithTag(
      _effectiveTag,
      customBooru: selectedBooru,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          if (boo != null) ...[
            BooruFavicon(boo),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                boo.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            // Alias translation indicator: this booru spells the tag
            // differently, show what the strip is actually searching.
            if (resolvedTerms.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '→ ${resolvedTerms.values.map((t) => t.replaceAll('_', ' ')).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ] else
            Flexible(
              child: Text(
                context.loc.tagView.selectBooruToLoad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(width: 4),
          // Hidden when the booru has no way to express "animated" — an empty
          // filter list means the site profile checked and there is nothing
          // real to search for, so the button would only append dead tags.
          if (_animatedFilters.isNotEmpty)
          IconButton(
            tooltip: _animatedButtonTooltip,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _activeAnimatedFilter == null ? Symbols.movie_rounded : Symbols.movie_rounded,
              color: _activeAnimatedFilter == null ? null : theme.colorScheme.secondary,
            ),
            onPressed: _toggleAnimatedOnly,
          ),
          IconButton(
            tooltip: 'Open in a new tab',
            visualDensity: VisualDensity.compact,
            icon: Stack(
              children: [
                const Icon(Symbols.fiber_new_rounded),
                if (hasTabResult.hasTagInAnyForm)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Symbols.circle_rounded,
                      size: 6,
                      color: hasTabResult.color(context),
                    ),
                  ),
              ],
            ),
            onPressed: () => _openInNewTab(context),
            onLongPress: () => _openInNewTabLongPress(context),
          ),
          IconButton(
            tooltip: 'Pick booru',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.arrow_drop_down_rounded),
            onPressed: () => _openBooruPicker(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Search finished (not loading, no error) with zero results — the tag
    // simply doesn't exist on this booru. With hideWhenEmpty the whole strip
    // (header included) collapses instead of wasting a "Nothing found" row.
    final bool isKnownEmpty =
        tab != null && !loading && errorString.isEmpty && tab!.booruHandler.filteredFetched.isEmpty;
    if (widget.hideWhenEmpty && isKnownEmpty && !_hadResults) {
      return const AnimatedSize(
        duration: Duration(milliseconds: 200),
        child: SizedBox.shrink(),
      );
    }

    final Widget strip = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: tab == null
            ? (widget.compact
                  // Compact path: auto-loads in initState, so this "no tab"
                  // state is just a brief one-frame placeholder. Keep it
                  // small and label-less so it doesn't conflict with the
                  // section header rendered above.
                  ? const SizedBox(height: 32)
                  : ListTile(
                leading: Icon(
                  Symbols.search_rounded,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(widget.compactTitle ?? context.loc.tagView.preview),
                trailing: widget.parentTab == null
                    ? null
                    : IconButton(
                        icon: const Icon(Symbols.list_rounded),
                        onPressed: showTagPreviewsListDialog,
                      ),
                subtitle: isSingleBooru
                    ? null
                    : Container(
                        width: context.mediaSize.width,
                        height: 52,
                        margin: const EdgeInsets.only(top: 8),
                        child: SettingsBooruDropdown(
                          title: context.loc.booru,
                          placeholder: context.loc.tagView.selectBooruToLoad,
                          value: selectedBooru,
                          items: isSingleBooru ? settingsHandler.booruList : widget.boorus,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            selectedBooru = value;
                            loadPreview(refresh: true);
                          },
                          titleAsLabel: true,
                          drawBottomBorder: false,
                        ),
                      ),
                onTap: isSingleBooru ? loadPreview : null,
              ))
            : ((tab!.booruHandler.filteredFetched.isEmpty && (loading || errorString.isNotEmpty))
                  ? ListTile(
                      leading: Icon(
                        loading ? Symbols.search_rounded : Symbols.restart_alt_rounded,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      trailing: loading
                          ? const CircularProgressIndicator()
                          : (widget.parentTab == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Symbols.list_rounded),
                                    onPressed: showTagPreviewsListDialog,
                                  )),
                      title: loading
                          ? Text(context.loc.tagView.previewIsLoading)
                          : Text(context.loc.tagView.failedToLoadPreview),
                      subtitle: errorString.isNotEmpty ? Text(context.loc.tagView.tapToTryAgain) : null,
                      onTap: errorString.isNotEmpty ? () => loadPreview(refresh: true) : null,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Boorusama-style chip — replaces the old Preview
                        // header + standalone booru dropdown. Shown for BOTH
                        // compact (tag-chevron / "More from artist X") and
                        // non-compact paths, because the original booru
                        // dropdown was present in both too.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                          child: _buildBooruChip(context),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 220 + 10 + 16, // bigger thumbs + listview paddings
                          width: MediaQuery.sizeOf(context).width,
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: (notif) {
                              final bool isNotAtStart = notif.metrics.pixels > 0;
                              final bool isAtOrNearEdge =
                                  notif.metrics.atEdge ||
                                  notif.metrics.pixels >
                                      (notif.metrics.maxScrollExtent - (notif.metrics.extentInside * 2));

                              if (widget.compact) {
                                // In the inline / compact strip: only paginate
                                // when the user actively scrolls near the right
                                // edge of the horizontal list. The original
                                // "screen not filled → load more" branch would
                                // fire infinitely because a horizontal strip
                                // on a phone rarely overflows the viewport.
                                if (!loading && isNotAtStart && isAtOrNearEdge) {
                                  loadPreview();
                                }
                                return true;
                              }

                              final bool isScreenFilled =
                                  notif.metrics.extentBefore != 0 || notif.metrics.extentAfter != 0;

                              if (!loading) {
                                if (!isScreenFilled || (isNotAtStart && isAtOrNearEdge)) {
                                  loadPreview();
                                }
                              }

                              return true;
                            },
                            child: Scrollbar(
                              controller: scrollController,
                              interactive: true,
                              thickness: 6,
                              thumbVisibility: true,
                              child: Listener(
                                onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
                                child: FadingEdgeScrollView.fromScrollView(
                                  child: ListView.builder(
                                    controller: scrollController,
                                    shrinkWrap: true,
                                    scrollDirection: Axis.horizontal,
                                    itemCount: tab!.booruHandler.filteredFetched.isEmpty
                                        ? 1
                                        : tab!.booruHandler.filteredFetched.length +
                                              ((loading || errorString.isNotEmpty) ? 1 : 0),
                                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                                    itemBuilder: (context, index) {
                                      if (tab!.booruHandler.filteredFetched.isEmpty) {
                                        return Center(
                                          child: Column(
                                            // mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Kaomoji(
                                                category: KaomojiCategory.indifference,
                                                style: TextStyle(fontSize: 24),
                                              ),
                                              Text(
                                                context.loc.nothingFound,
                                                style: const TextStyle(fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      if (loading && index == tab!.booruHandler.filteredFetched.length) {
                                        return const Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 32),
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      }

                                      if (errorString.isNotEmpty && index == tab!.booruHandler.filteredFetched.length) {
                                        return Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            margin: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surface,
                                              border: Border.all(color: Theme.of(context).dividerColor),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              spacing: 8,
                                              children: [
                                                const Icon(
                                                  Symbols.error_rounded,
                                                  size: 30,
                                                ),
                                                Text(
                                                  context.loc.tagView.failedToLoadPreviewPage,
                                                  style: const TextStyle(fontSize: 16),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    loadPreview(retry: true);
                                                  },
                                                  child: Text(context.loc.tagView.tryAgain),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      return Material(
                                        color: Colors.transparent,
                                        child: Container(
                                          padding: const EdgeInsets.only(right: 8),
                                          height: 220,
                                          width: 148,
                                          child: ValueListenableBuilder(
                                            valueListenable: viewedIndex,
                                            builder: (context, viewedIndex, _) {
                                              return ThumbnailCardBuild(
                                                index: index,
                                                item: tab!.booruHandler.filteredFetched[index],
                                                handler: tab!.booruHandler,
                                                scrollController: scrollController,
                                                isHighlighted: viewedIndex == index,
                                                selectable: false,
                                                onTap: onPreviewTap,
                                                onDoubleTap: onPreviewDoubleTap,
                                                // Doujin strips get the full item context menu; other
                                                // sources keep the old no-op (select doesn't fit here).
                                                onLongPress: tab!.booruHandler.hasReader
                                                    ? (i) => showDoujinItemSheet(context, tab: tab!, index: i)
                                                    : null,
                                                onSecondaryTap: onPreviewSecondaryTap,
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    )),
      ),
    );

    if (widget.header == null) {
      return strip;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.header!,
        strip,
      ],
    );
  }
}

class _TagPreviewsListDialog extends StatelessWidget {
  const _TagPreviewsListDialog(
    this.tabId,
  );

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final viewerHandler = ViewerHandler.instance;
    final searchHandler = SearchHandler.instance;
    final settingsHandler = SettingsHandler.instance;

    final list = viewerHandler.tagPreviewsHistory[tabId] ?? [];
    final controllers = List.generate(list.length, (_) => ScrollController());
    // scroll to end of each stack history item
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   for (final c in controllers) {
    //     c.jumpTo(c.position.maxScrollExtent);
    //   }
    // });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              //
              Text(
                context.loc.tagView.tagPreviews,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              //
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, entryIndex) {
                    final entry = list[list.length - entryIndex - 1];
                    final bool isActive = entry == list.last;
                    final bool isSecondsToLast = list.length > 1 && entry == list[list.length - 2];

                    if (entry.isEmpty) return const SizedBox.shrink();

                    bool matchesCurrentState = true;
                    final currentState = viewerHandler.currentTagPreviewState(tabId).map((e) => e.value).toList();
                    entry.forEachIndexed((i, e) {
                      if (i >= currentState.length || currentState[i] != e.value) {
                        matchesCurrentState = false;
                        return;
                      }
                    });

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isActive || isSecondsToLast)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              isActive ? context.loc.tagView.currentState : context.loc.tagView.history,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        //
                        Material(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            shape: Border(
                              top: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                            ),
                            trailing: (isActive || matchesCurrentState)
                                ? null
                                : IconButton(
                                    icon: const Icon(Symbols.history_rounded),
                                    onPressed: () async {
                                      Navigator.of(context).pop();

                                      final state = viewerHandler.currentTagPreviewState(tabId);

                                      entry.forEachIndexed((index, e) async {
                                        final tag = e.value;

                                        // skip if tag already in stack
                                        if (state.all((e) => e.value != tag)) {
                                          unawaited(
                                            showTagDialog(
                                              context: context,
                                              tag: tag,
                                              handler: searchHandler.currentBooruHandler,
                                              isHidden: settingsHandler.hiddenTags.contains(tag),
                                              isMarked: settingsHandler.markedTags.contains(tag),
                                              isInSearch:
                                                  searchHandler.searchTextController.text
                                                      .toLowerCase()
                                                      .split(' ')
                                                      .indexWhere(
                                                        (t) =>
                                                            t == tag.toLowerCase() ||
                                                            t == '-${tag.toLowerCase()}' ||
                                                            t == '~${tag.toLowerCase()}' ||
                                                            RegExp(
                                                              r'^(?:-|~)?\d+#(?:-|~)?' + tag.regexpEscape() + r'$',
                                                            ).hasMatch(t),
                                                      ) !=
                                                  -1,
                                              hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                              onUpdate: () {},
                                            ),
                                          );
                                          await Future.delayed(const Duration(milliseconds: 50));
                                        }
                                      });
                                    },
                                  ),
                            title: SizedBox(
                              height: 40,
                              width: double.maxFinite,
                              child: FadingEdgeScrollView.fromScrollView(
                                child: ListView(
                                  controller: controllers[entryIndex],
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  children: [
                                    ...entry.mapWithIndex(
                                      (e, i) {
                                        final tag = e.value;
                                        final bool isLast = i == entry.length - 1;

                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            MainSearchTagChip(
                                              tag: tag,
                                              booru: searchHandler.currentBooru,
                                              isSelected: isActive && isLast,
                                              onTap: () {
                                                if (isActive) {
                                                  // close everything up to this tag
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    Navigator.of(context).popUntil(
                                                      (route) =>
                                                          route.settings.name == 'tagDialog/$tag' || route.isFirst,
                                                    );
                                                  });
                                                } else {
                                                  // open dialog for this tag
                                                  Navigator.of(context).pop();
                                                  unawaited(
                                                    showTagDialog(
                                                      context: context,
                                                      tag: tag,
                                                      handler: searchHandler.currentBooruHandler,
                                                      isHidden: settingsHandler.hiddenTags.contains(tag),
                                                      isMarked: settingsHandler.markedTags.contains(tag),
                                                      isInSearch:
                                                          searchHandler.searchTextController.text
                                                              .toLowerCase()
                                                              .split(' ')
                                                              .indexWhere(
                                                                (t) =>
                                                                    t == tag.toLowerCase() ||
                                                                    t == '-${tag.toLowerCase()}' ||
                                                                    t == '~${tag.toLowerCase()}' ||
                                                                    RegExp(
                                                                      r'^(?:-|~)?\d+#(?:-|~)?' +
                                                                          tag.regexpEscape() +
                                                                          r'$',
                                                                    ).hasMatch(t),
                                                              ) !=
                                                          -1,
                                                      hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                                      onUpdate: () {},
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                            if (!isLast)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 4),
                                                child: Icon(
                                                  Symbols.arrow_forward_rounded,
                                                  size: 14,
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              //
              ListTile(
                leading: Icon(
                  Symbols.cancel_rounded,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(context.loc.close),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              //
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
