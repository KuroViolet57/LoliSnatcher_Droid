import 'dart:async';
import 'dart:math';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/text_parser/rules/url_rule.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/draggable_overflow_text.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/common/parsed_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/desktop/desktop_scroll.dart';
import 'package:lolisnatcher/src/widgets/dialogs/comments_dialog.dart';
import 'package:lolisnatcher/src/widgets/gallery/notes_renderer.dart';
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
  bool hasLoadItemSupport = false;
  bool canLoadItemOnStart = false;
  List<Tag> tags = [];
  List<Tag> filteredTags = [];
  final Map<String, HasTabWithTagResult> tabMatchesMap = {};
  // Tags whose inline preview strip is currently expanded in the tag list.
  final Set<String> expandedTagPreviews = {};
  bool? sortTags;
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final GlobalKey searchKey = GlobalKey(debugLabel: 'tagsSearchKey');

  CancelToken? cancelToken;
  bool loadingUpdate = false, failedUpdate = false;

  bool? detailsExpanded;
  bool relatedExpanded = false;
  // Cached so collapsing / re-expanding the "Related" tile doesn't re-derive
  // (and the preview widget's own state doesn't get torn down on the second
  // expand). Filled lazily on the first expand.
  String? _relatedQueryCache;

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

    final bool isFavsOrDlsOrMerge = handler is FavouritesHandler || handler is DownloadsHandler || isMergeHandler;
    if (!isFavsOrDlsOrMerge) {
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
      _relatedQueryCache = null;
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
      if (tagHandler.hasTag(tags[i].fullString)) {
        tagMap[tagHandler.getTag(tags[i].fullString).tagType]?.add(tags[i]);
      } else {
        tagMap[TagType.none]?.add(tags[i]);
      }
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
                            Icons.close,
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
                        failedUpdate ? Icons.error_outline : Icons.refresh,
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
                      (sortTags == true || sortTags == false) ? Icons.sort : Icons.sort_by_alpha,
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
            Icons.note_add,
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
            Icons.note_add,
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

  Widget infoText(
    String title,
    String data, {
    bool canCopy = true,
    bool isLink = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    if (data.isNotEmpty) {
      return ListTile(
        onTap:
            onTap ??
            (canCopy
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
                      leadingIcon: Icons.copy,
                      sideColor: Colors.green,
                    );
                  }
                : null),
        onLongPress: onLongPress,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$title: ',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (!isLink)
              Expanded(
                child: AutoSizeText(
                  data,
                  maxLines: 1,
                  minFontSize: 13,
                  maxFontSize: 14,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1,
                  ),
                  overflowReplacement: DraggableOverflowText(
                    data,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: isLink
            ? DraggableOverflowText(
                data,
                style: const TextStyle(fontSize: 14),
              )
            : null,
        trailing:
            trailing ??
            (isLink
                ? IconButton(
                    icon: const Icon(Icons.exit_to_app),
                    onPressed: () => launchUrlString(
                      data,
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : null),
      );
    }

    return const SizedBox.shrink();
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
      return tagHandler.getTag(t.fullString).tagType.isArtist;
    }).take(3).toList();
    for (final artist in artists) {
      if (artist.fullString.trim().isEmpty) continue;
      final String artistQuery = artist.fullString;
      sections.add(
        _CollapsibleRelatedPreview(
          key: ValueKey('related-artist-${currentBooru.name}-$artistQuery'),
          title: 'More from artist ${artistQuery.replaceAll('_', ' ')}',
          icon: Icons.brush,
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
              icon: Icons.person,
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

  Widget tagsItemBuilder(BuildContext context, Tag tag) {
    final String currentTag = tag.fullString;
    final int tagCount = tag.count;

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

    final List<_TagInfoIcon> tagIconAndColor = [];
    if (isAi) {
      tagIconAndColor.add(_TagInfoIcon(FontAwesomeIcons.robot, Theme.of(context).colorScheme.onSurface));
    }
    if (isSound) {
      tagIconAndColor.add(_TagInfoIcon(Icons.volume_up_rounded, Theme.of(context).colorScheme.onSurface));
    }
    if (isHidden) {
      tagIconAndColor.add(_TagInfoIcon(CupertinoIcons.eye_slash, Colors.red));
    }
    if (isMarked) {
      tagIconAndColor.add(_TagInfoIcon(Icons.star, Colors.yellow));
    }

    if (currentTag != '') {
      final tag = tagHandler.getTag(currentTag);

      return ColoredBox(
        key: ValueKey('tag-$currentTag'),
        color: tag.getColour() == null
            ? Colors.transparent
            : Color.lerp(
                context.isLight ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                tag.getColour()?.withValues(alpha: 0.1),
                0.4,
              )!,
        child: Column(
          children: [
            InkWell(
              onTap: () {
                showTagDialog(
                  context: context,
                  tag: currentTag,
                  handler: handler,
                  isHidden: isHidden,
                  isMarked: isMarked,
                  isInSearch: isInSearch,
                  hasTabWithTag: hasTabWithTag,
                  onUpdate: parseSortGroupTagsWithoutCache,
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TagText(
                            key: ValueKey(currentTag),
                            tag: tag,
                            filterText: searchController.text,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.centerLeft,
                            child: tagCount <= 0
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      tagCount.toFormattedString(),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (tagIconAndColor.isNotEmpty) ...[
                    ...tagIconAndColor.map(
                      (t) => switch (t.icon) {
                        FaIconData _ => Padding(
                          // add a bit of padding to compensate for some icons being too close to each other
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FaIcon(
                            t.icon,
                            color: t.color,
                            size: 18,
                          ),
                        ),
                        IconData _ => Icon(
                          t.icon,
                          color: t.color,
                          size: 20,
                        ),
                        _ => const SizedBox.shrink(),
                      },
                    ),
                    const SizedBox(width: 5),
                  ],
                  IconButton(
                    icon: Stack(
                      children: [
                        Icon(Icons.add, color: Theme.of(context).colorScheme.secondary),
                        if (isInSearch)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.search,
                              size: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      if (isInSearch) {
                        FlashElements.showSnackbar(
                          context: context,
                          duration: const Duration(seconds: 2),
                          title: Text(
                            context.loc.tagView.thisTagAlreadyInSearch,
                            style: const TextStyle(fontSize: 18),
                          ),
                          content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                          leadingIcon: Icons.warning_amber,
                          leadingIconColor: Colors.yellow,
                          sideColor: Colors.yellow,
                        );
                        return;
                      }

                      searchHandler.addTagToSearch(currentTag);
                      FlashElements.showSnackbar(
                        context: context,
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tagView.addedToCurrentSearch, style: const TextStyle(fontSize: 20)),
                        content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                        leadingIcon: Icons.add,
                        sideColor: Colors.green,
                      );
                    },
                  ),
                  IconButton(
                    icon: Stack(
                      children: [
                        Icon(Icons.fiber_new, color: Theme.of(context).colorScheme.secondary),
                        if (hasTabWithTag.hasTagInAnyForm)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: hasTabWithTag.color(context),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      final TabAddMode addMode = settingsHandler.defaultTabAddMode == 'next'
                          ? TabAddMode.next
                          : TabAddMode.end;
                      // Capture the current index before inserting so the
                      // snackbar's jump arrow targets the right tab even in
                      // "next to current" mode (where it won't be at the end).
                      final int indexBefore = searchHandler.currentIndex;
                      searchHandler.addTabByString(currentTag, addMode: addMode);
                      final int newTabIndex = addMode == TabAddMode.next
                          ? indexBefore + 1
                          : searchHandler.tabs.length - 1;

                      parseSortGroupTags();

                      FlashElements.showSnackbar(
                        context: context,
                        isKeyUnique: true,
                        key: 'added_new_tab',
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tagView.addedNewTab, style: const TextStyle(fontSize: 20)),
                        content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                        leadingIcon: Icons.fiber_new,
                        sideColor: Colors.green,
                        primaryActionBuilder: (context, controller) {
                          return Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  ServiceHandler.vibrate();
                                  if (settingsHandler.appMode.value.isMobile) {
                                    Navigator.of(context).popUntil((route) => route.isFirst); // exit viewer
                                  }
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    searchHandler.changeTabIndex(newTabIndex);
                                  });
                                  controller.dismiss();
                                },
                                icon: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => controller.dismiss(),
                                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    onLongPress: () async {
                      await ServiceHandler.vibrate();
                      final TabAddMode addMode = settingsHandler.defaultTabAddMode == 'next'
                          ? TabAddMode.next
                          : TabAddMode.end;
                      if (settingsHandler.appMode.value.isMobile) {
                        Navigator.of(context).popUntil((route) => route.isFirst); // exit viewer
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        searchHandler.addTabByString(currentTag, switchToNew: true, addMode: addMode);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      expandedTagPreviews.contains(currentTag) ? Icons.expand_less : Icons.expand_more,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    tooltip: 'Preview posts with this tag',
                    onPressed: () {
                      setState(() {
                        if (!expandedTagPreviews.remove(currentTag)) {
                          expandedTagPreviews.add(currentTag);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            if (expandedTagPreviews.contains(currentTag))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Builder(
                  builder: (context) {
                    // In merge mode (and Favourites/Downloads), the post being viewed often comes
                    // from a different booru than the tab's primary. Route the preview strip to
                    // that source booru so the tag lookup hits the right site instead of always
                    // querying the primary.
                    final Booru previewBooru = possibleBooruHandler?.booru ?? searchHandler.currentBooru;
                    return TagContentPreview(
                      key: ValueKey('tag-preview-${previewBooru.name}-$currentTag'),
                      tag: currentTag,
                      boorus: [previewBooru],
                      parentTab: searchHandler.currentTab,
                      compact: true,
                    );
                  },
                ),
              ),
            Divider(
              color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
            ),
          ],
        ),
      );
    } else {
      // Render nothing if currentTag is an empty string
      return const SizedBox.shrink();
    }
  }

  // Builds a space-separated tag query for the "Related" preview strip.
  // Prefers character + artist + copyright tags (the narrowest, most-likely-
  // to-match-vibe categories); falls back to a few general tags if none of
  // those are present. Always excludes the current post id so the strip
  // doesn't show this same item back to the user.
  String? _buildRelatedQuery() {
    if (_relatedQueryCache != null) return _relatedQueryCache;

    final List<String> picked = [];

    void pickFrom(TagType type, int limit) {
      int taken = 0;
      for (final t in item.tagsList) {
        if (taken >= limit) break;
        if (t.tagType == type && t.fullString.trim().isNotEmpty && !picked.contains(t.fullString)) {
          picked.add(t.fullString);
          taken++;
        }
      }
    }

    // Up to 2 characters + 1 artist + 1 copyright; if all empty, take 2 general.
    pickFrom(TagType.character, 2);
    pickFrom(TagType.artist, 1);
    pickFrom(TagType.copyright, 1);
    if (picked.isEmpty) {
      pickFrom(TagType.none, 2);
    }

    if (picked.isEmpty) return null;

    final String? id = item.serverId;
    final String exclusion = (id != null && id.isNotEmpty) ? ' -id:$id' : '';
    return _relatedQueryCache = picked.join(' ') + exclusion;
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = Tools.getFileName(item.fileURL);
    final String fileExt = Tools.getFileExt(item.fileURL);
    final String fileUrl = item.fileURL;
    final String fileRes = (item.fileWidth != null && item.fileHeight != null)
        ? '${item.fileWidth?.toInt() ?? ''}x${item.fileHeight?.toInt() ?? ''}'
        : '';
    final String fileSize = item.fileSize != null ? Tools.formatBytes(item.fileSize!, 2) : '';
    final String rating = item.rating ?? '';
    final String score = item.score ?? '';
    final String md5 = item.md5String ?? '';
    final List<String> sources = item.sources ?? [];
    final bool tagsAvailable = tags.isNotEmpty || hasLoadItemSupport;
    // Note: post ID + post URL + formatted post date are intentionally not
    // surfaced at the top of the drawer anymore (per user request); the
    // remaining metadata still renders via the Details expansion further below.

    // Uploader row — moved into the Details expansion (per user request) so it
    // doesn't eat space at the top of the sheet when collapsed.
    final Widget uploaderTile =
        (item.uploaderId?.isNotEmpty == true || item.uploaderName?.isNotEmpty == true)
        ? Builder(
            builder: (context) {
              final bool hasUploaderName = item.uploaderName?.isNotEmpty == true;
              final String text = item.uploaderName ?? item.uploaderId ?? '';

              return infoText(
                context.loc.tagView.uploader,
                text,
                trailing: hasUploaderName
                    ? IgnorePointer(
                        child: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {},
                        ),
                      )
                    : null,
                onTap: hasUploaderName
                    ? () {
                        final userMetaTag = searchHandler.currentBooruHandler
                            .availableMetaTags()
                            .firstWhereOrNull(
                              (t) => t is UserMetaTag,
                            );
                        if (userMetaTag == null) return;

                        final String tag = userMetaTag.tagBuilder(null, null, item.uploaderName);

                        searchHandler.addTagToSearch(tag);
                        FlashElements.showSnackbar(
                          context: context,
                          duration: const Duration(seconds: 2),
                          title: Text(
                            context.loc.tagView.addedToCurrentSearch,
                            style: const TextStyle(fontSize: 20),
                          ),
                          content: Text(tag, style: const TextStyle(fontSize: 16)),
                          leadingIcon: Icons.add,
                          sideColor: Colors.green,
                        );
                      }
                    : null,
                onLongPress: hasUploaderName
                    ? () {
                        Clipboard.setData(ClipboardData(text: text));
                        FlashElements.showSnackbar(
                          context: context,
                          duration: const Duration(seconds: 2),
                          title: Text(context.loc.copiedToClipboard, style: const TextStyle(fontSize: 20)),
                          content: Text(text, style: const TextStyle(fontSize: 16)),
                          leadingIcon: Icons.copy,
                          sideColor: Colors.green,
                        );
                      }
                    : null,
              );
            },
          )
        : const SizedBox.shrink();

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
                // Inline "more from artist / uploader" grids — Boorusama-style.
                // Each grid is gated on:
                //   - the global Settings → Interface → inlineRelatedGrids toggle
                //   - the data being available for this item + handler
                if (settingsHandler.inlineRelatedGrids) ..._buildRelatedGrids(),
                //
                // Uploader, comments and sources are tucked inside the Details
                // expansion (per user request) so the collapsed sheet stays
                // compact.
                ExpansionTile(
                  title: Text(
                    context.loc.tagView.details,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  initiallyExpanded: detailsExpanded ?? settingsHandler.expandDetails,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      detailsExpanded = expanded;
                    });
                  },
                  iconColor: Colors.white.withValues(alpha: 0.66),
                  collapsedIconColor: Colors.white.withValues(alpha: 0.66),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    uploaderTile,
                    if (settingsHandler.isDebug.value) infoText(context.loc.tagView.filename, fileName),
                    infoText(context.loc.tagView.url, fileUrl, isLink: true),
                    infoText(context.loc.tagView.extension, fileExt),
                    infoText(context.loc.tagView.resolution, fileRes),
                    infoText(context.loc.tagView.size, fileSize),
                    infoText(context.loc.tagView.md5, md5),
                    infoText(context.loc.tagView.rating, rating),
                    infoText(context.loc.tagView.score, score),
                    commentsButton(),
                    sourcesList(sources),
                  ],
                ),
                // "Related" — preview strip seeded from the item's strongest
                // tags (character/artist/copyright, falling back to general).
                // Only shows when we can build a meaningful seed query.
                Builder(
                  builder: (context) {
                    final String? query = _buildRelatedQuery();
                    if (query == null) return const SizedBox.shrink();
                    final Booru previewBooru =
                        possibleBooruHandler?.booru ?? searchHandler.currentBooru;
                    return ExpansionTile(
                      title: const Text(
                        'Related',
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
                            key: ValueKey('related-${previewBooru.name}-${item.serverId ?? item.fileURL}'),
                            tag: query,
                            boorus: [previewBooru],
                            parentTab: searchHandler.currentTab,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                notesButton(),
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
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (c, i) => tagsItemBuilder(c, filteredTags[i]),
              childCount: filteredTags.length,
            ),
          ),
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

class _TagText extends StatelessWidget {
  const _TagText({
    required this.tag,
    this.filterText,
    super.key,
  });

  final Tag tag;
  final String? filterText;

  @override
  Widget build(BuildContext context) {
    Color? color = tag.getColour();
    color = color == Colors.transparent ? null : color;
    final basicStyle = TextStyle(
      fontSize: 14,
      fontWeight: filterText?.isNotEmpty == true ? FontWeight.w400 : FontWeight.w600,
    );
    final fullStyle = basicStyle.copyWith(
      color: color,
    );

    if (filterText?.isNotEmpty == true) {
      final List<TextSpan> spans = [];
      final List<String> split = tag.fullString.split(filterText!);

      for (int i = 0; i < split.length; i++) {
        spans.add(
          TextSpan(
            text: split[i],
            style: basicStyle,
          ),
        );
        if (i < split.length - 1) {
          spans.add(
            TextSpan(
              text: filterText,
              style: fullStyle.copyWith(
                backgroundColor: color?.withValues(alpha: 0.1),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      }

      return MarqueeText.rich(
        textSpan: TextSpan(
          children: spans,
          style: basicStyle,
        ),
        isExpanded: false,
        style: basicStyle,
      );
    } else {
      return MarqueeText(
        text: tag.fullString,
        isExpanded: false,
        style: fullStyle,
      );
    }
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
            leading: const Icon(Icons.public),
            title: const Text('Globally'),
            subtitle: const Text('Hides items with this tag on every booru'),
            onTap: () => Navigator.of(ctx).pop(_BlacklistScope.global),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark),
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

  await showDialog(
    context: context,
    routeSettings: RouteSettings(name: 'tagDialog/$tag'),
    builder: (BuildContext context) {
      return SettingsDialog(
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        contentItems: [
          SizedBox(
            height: 60,
            width: MediaQuery.sizeOf(context).width,
            child: ListTile(
              title: MarqueeText(
                key: ValueKey(tag),
                text: tag,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                isExpanded: false,
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 6,
                height: 24,
                decoration: BoxDecoration(
                  color: tagHandler.getTag(tag).getColour(),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tagHandler.getTag(tag).tagType.locName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          //
          TagContentPreview(
            tag: tag,
            boorus: handler.booru.type?.isMerge == true
                ? [
                    ...(handler as MergebooruHandler).booruHandlers.map((e) => e.booru),
                  ]
                : [handler.booru],
            parentTab: searchHandler.currentTab,
          ),
          //
          ListTile(
            leading: Icon(
              Icons.copy,
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
                leadingIcon: Icons.copy,
                sideColor: Colors.green,
              );
              Navigator.of(context).pop();
            },
          ),
          //
          if (isInSearch)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromSearch),
              onTap: () {
                searchHandler.removeTagFromSearch(tag);
                Navigator.of(context).pop();
              },
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.add, color: Colors.green),
              title: Text(context.loc.tagView.addToSearch),
              onTap: () {
                searchHandler.addTagToSearch(tag);

                FlashElements.showSnackbar(
                  context: context,
                  duration: const Duration(seconds: 2),
                  title: Text(
                    context.loc.tagView.addedToSearchBar,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    tag,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Icons.add,
                  sideColor: Colors.green,
                );

                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_rounded, color: Colors.red),
              title: Text(context.loc.tagView.excludeFromSearch),
              onTap: () {
                searchHandler.addTagToSearch('-$tag');

                FlashElements.showSnackbar(
                  context: context,
                  duration: const Duration(seconds: 2),
                  title: Text(
                    context.loc.tagView.exclusionAddedToSearchBar,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    tag,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Icons.add,
                  sideColor: Colors.green,
                );

                Navigator.of(context).pop();
              },
            ),
          ],
          //
          if (!isHidden && !isMarked)
            ListTile(
              leading: const Icon(Icons.star, color: Colors.yellow),
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
                if (scope == _BlacklistScope.global) {
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
                Icons.star_border,
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
            future: settingsHandler.dbHandler.getPinnedTag(
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
                leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
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
                      Icons.circle,
                      size: 6,
                      color: hasTabWithTag.color(context),
                    ),
                  ),
                ],
              ),
              title: Text(context.loc.tagView.relatedTabs),
              onTap: () => showRelatedTabsDialog(context, tag),
            ),
          ListTile(
            leading: Icon(
              Icons.edit,
              color: Theme.of(context).iconTheme.color,
            ),
            title: Text(context.loc.tagView.editTag),
            onTap: () async {
              Navigator.of(context).pop();
              final item = tagHandler.getTag(tag);
              await showDialog(
                context: context,
                builder: (context) => TagsManagerListItemDialog(
                  tag: item,
                  onChangedType: (TagType? newValue) {
                    if (newValue != null && item.tagType != newValue) {
                      item.tagType = newValue;
                      tagHandler.putTag(item, dbEnabled: settingsHandler.dbEnabled);
                      onUpdate();
                    }
                  },
                ),
              );
              onUpdate();
            },
          ),
          //
          ListTile(
            leading: Icon(
              Icons.cancel_outlined,
              color: Theme.of(context).iconTheme.color,
            ),
            title: Text(context.loc.close),
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
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
                Icons.circle,
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
                Icons.circle,
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
      leadingIcon: Icons.copy,
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
                leading: const Icon(Icons.link, size: 20),
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
          icon: const Icon(Icons.copy),
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
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
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
    super.key,
  }) : assert(
         boorus.isNotEmpty,
         'boorus must not be empty',
       );

  final String tag;
  final List<Booru> boorus;
  final SearchTab? parentTab;
  final bool readOnly;

  // When true, the preview renders with minimal chrome (no booru dropdown,
  // no refresh/close icons, no "open in new tab" cluster) and eagerly
  // loads on init. Used inline inside the post-details drawer.
  final bool compact;
  // Optional override for the "Preview" header — e.g. "More from artist X".
  final String? compactTitle;

  @override
  State<TagContentPreview> createState() => _TagContentPreviewState();
}

class _TagContentPreviewState extends State<TagContentPreview> {
  final settingsHandler = SettingsHandler.instance;
  final viewerHandler = ViewerHandler.instance;

  final AutoScrollController scrollController = AutoScrollController();

  Booru? selectedBooru;

  SearchTab? tab;
  bool loading = false;
  bool isLastPage = false;
  String errorString = '';

  // When true the preview filters to animated content by appending the
  // "animated" tag. Works on almost every booru.
  bool onlyAnimated = false;

  // The actual query sent to the booru handler — `widget.tag` plus
  // any per-strip filters the user toggled in the header.
  String get _effectiveTag => onlyAnimated ? '${widget.tag} animated' : widget.tag;

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
      tab = SearchTab(
        selectedBooru!,
        null,
        _effectiveTag,
      );
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

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      loading = false;
      setState(() {});
    });
    if (!mounted) return;
    setState(() {});
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
      leadingIcon: Icons.copy,
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

  // Toggles the "videos / GIFs only" filter and reloads the strip.
  void _toggleAnimatedOnly() {
    setState(() {
      onlyAnimated = !onlyAnimated;
    });
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
      leadingIcon: Icons.fiber_new,
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
                Icons.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => controller.dismiss(),
              icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
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
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('Open at end of tab list'),
                onTap: () => Navigator.of(dialogContext).pop(TabAddMode.end),
              ),
              ListTile(
                leading: const Icon(Icons.tab),
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
      leadingIcon: Icons.fiber_new,
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
          ] else
            Flexible(
              child: Text(
                context.loc.tagView.selectBooruToLoad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: onlyAnimated ? 'Show all' : 'Videos / GIFs only',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              onlyAnimated ? Icons.movie : Icons.movie_outlined,
              color: onlyAnimated ? theme.colorScheme.secondary : null,
            ),
            onPressed: _toggleAnimatedOnly,
          ),
          IconButton(
            tooltip: 'Open in a new tab',
            visualDensity: VisualDensity.compact,
            icon: Stack(
              children: [
                const Icon(Icons.fiber_new),
                if (hasTabResult.hasTagInAnyForm)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Icons.circle,
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
            icon: const Icon(Icons.arrow_drop_down),
            onPressed: () => _openBooruPicker(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
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
                  Icons.search,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(widget.compactTitle ?? context.loc.tagView.preview),
                trailing: widget.parentTab == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.list),
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
                        loading ? Icons.search : Icons.restart_alt,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      trailing: loading
                          ? const CircularProgressIndicator()
                          : (widget.parentTab == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.list),
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
                                                  Icons.error_outline,
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
                                                // onLongPress: onPreviewLongPress, // TODO use select here somehow?
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
                                    icon: const Icon(Icons.history),
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
                                                  Icons.arrow_forward,
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
                  Icons.cancel_outlined,
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
