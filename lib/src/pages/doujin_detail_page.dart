import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/bookmark_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_reader_page.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

/// The doujin DETAIL page — what tapping a doujin card opens instead of the
/// image viewer. Modeled on the reference reader apps:
///
///   cover + titles
///   language · category · pages · favourites · date
///   [ Read ]  [save] [bookmark] [favourite]
///   tag filter + tags grouped by the site's own namespaces
///   Related (chapters & versions) — Recommended — Pages grid
///
/// The reader is reached from the Read button, a page thumbnail, or resumes
/// where you left off. The classic viewer flow stays untouched for
/// non-doujin sources.
class DoujinDetailPage extends StatefulWidget {
  const DoujinDetailPage({
    required this.tab,
    required this.index,
    super.key,
  });

  final SearchTab tab;
  final int index;

  @override
  State<DoujinDetailPage> createState() => _DoujinDetailPageState();
}

class _DoujinDetailPageState extends State<DoujinDetailPage> {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;

  late final BooruHandler handler = widget.tab.booruHandler;
  late final Booru booru = handler.booru;
  late final BooruItem item = handler.filteredFetched[widget.index];

  bool _loading = true;
  String? _loadError;
  final TextEditingController _tagFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tagFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (ReaderHandler.instance.hasBook(item) && item.tagsList.isNotEmpty) {
      setState(() => _loading = false);
      return;
    }
    final res = await handler.loadItem(item: item, withCapcthaCheck: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = res.failed ? (res.error ?? 'failed to load') : null;
    });
  }

  // ─────────────────────── header data helpers ───────────────────────

  List<String> get _titleLines =>
      (item.description ?? '').split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('Scanlator:')).toList();

  String? _firstOfNamespace(String namespace) {
    for (final t in item.tagsList) {
      if (handler.tagNamespace(t.fullString) == namespace && t.fullString != 'translated') {
        return t.fullString;
      }
    }
    return null;
  }

  String get _metaLine {
    final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
    String? date;
    if (item.postDate != null && item.postDateFormat == 'unix') {
      final int? seconds = int.tryParse(item.postDate!);
      if (seconds != null) {
        date = DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
      }
    }
    final List<String> parts = [
      if (_firstOfNamespace('language') != null) _firstOfNamespace('language')!,
      if (_firstOfNamespace('category') != null) _firstOfNamespace('category')!,
      if (pages != null) '${pages.length} pages',
      if (item.score?.isNotEmpty ?? false) '♥ ${item.score}',
      if (date != null) date,
    ];
    return parts.join('  ·  ');
  }

  // ─────────────────────────── actions ───────────────────────────

  void _read({int? startAt}) {
    openDoujinReader(context, item: item, booru: booru, startAt: startAt);
  }

  void _saveAll() {
    final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
    if (pages == null || pages.isEmpty) return;
    SnatchHandler.instance.queue(pages, booru, settingsHandler.snatchCooldown, false);
    FlashElements.showSnackbar(
      context: context,
      title: Text('Saving all ${pages.length} pages...'),
      duration: const Duration(seconds: 2),
      sideColor: Colors.green,
    );
  }

  /// null = idle, otherwise the current sync-state line under the buttons.
  String? _favSyncStatus;

  Future<void> _toggleFavourite() async {
    final bool? before = item.isFavourite.value;
    await widget.tab.toggleItemFavourite(widget.index);
    final bool nowFavourite = item.isFavourite.value == true;
    if (item.isFavourite.value == before) {
      // Local toggle didn't happen (load failure etc.) — no site push.
      setState(() {});
      return;
    }

    // Favourite = the ACCOUNT action when the source can sync (bookmark is
    // the purely-local sibling). Degrades to local-only with a visible note.
    if (!handler.hasSiteFavourites) {
      setState(
        () => _favSyncStatus = nowFavourite
            ? 'Saved locally — add your nhentai API key in the booru settings to sync with your account'
            : null,
      );
      return;
    }
    setState(() => _favSyncStatus = 'Syncing to your nhentai account…');
    final (bool ok, String message) = await handler.setSiteFavourite(item, nowFavourite);
    if (!mounted) return;
    setState(() => _favSyncStatus = message);
    if (ok) {
      // Let the confirmation breathe, then clear it.
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _favSyncStatus == message) setState(() => _favSyncStatus = null);
      });
    }
  }

  void _toggleBookmark() {
    final bool nowBookmarked = BookmarkHandler.instance.toggle(item, booru);
    setState(() {});
    FlashElements.showSnackbar(
      context: context,
      title: Text(nowBookmarked ? 'Bookmarked' : 'Bookmark removed'),
      duration: const Duration(seconds: 1),
      sideColor: Colors.blue,
    );
  }

  // ─────────────────────────── sections ───────────────────────────

  Widget _header(BuildContext context) {
    final List<String> titles = _titleLines;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            height: 185,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Thumbnail(item: item, booru: booru, isStandalone: true, useHero: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles.isNotEmpty ? titles.first : 'Untitled',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (titles.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    titles[1],
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _metaLine,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
    final progress = ReaderHandler.instance.cachedProgress(booru, item.serverId ?? item.postURL);
    final bool resuming = progress != null && !progress.isFinished && progress.page > 0;
    final bool isBookmarked = BookmarkHandler.instance.isBookmarked(item);
    final bool? isFav = item.isFavourite.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: FilledButton.icon(
                icon: Icon(resuming ? Symbols.auto_stories_rounded : Symbols.menu_book_rounded, size: 20),
                label: Text(
                  pages == null
                      ? 'Read'
                      : resuming
                      ? 'Continue · p.${progress.page + 1}'
                      : 'Read · ${pages.length} pages',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                onPressed: pages == null ? null : _read,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Save all pages',
            icon: const Icon(Symbols.download_rounded),
            onPressed: pages == null ? null : _saveAll,
          ),
          IconButton.filledTonal(
            tooltip: isBookmarked ? 'Remove bookmark (local)' : 'Bookmark (local only)',
            icon: Icon(
              isBookmarked ? Symbols.bookmark_rounded : Symbols.bookmark_add_rounded,
              fill: isBookmarked ? 1 : 0,
              color: isBookmarked ? Colors.lightBlueAccent : null,
            ),
            onPressed: _toggleBookmark,
          ),
          IconButton.filledTonal(
            tooltip: isFav == true ? 'Unfavourite' : 'Favourite',
            icon: Icon(
              Symbols.favorite_rounded,
              fill: isFav == true ? 1 : 0,
              color: isFav == true ? const Color(0xFFF0708A) : null,
            ),
            onPressed: isFav == null ? null : _toggleFavourite,
          ),
        ],
      ),
    );
  }

  Widget _favSyncLine(BuildContext context) {
    if (_favSyncStatus == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Text(
        _favSyncStatus!,
        style: TextStyle(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }

  Widget _tagSections(BuildContext context) {
    final String filter = _tagFilter.text.trim().toLowerCase();
    final List<Tag> tags = [
      for (final t in item.tagsList)
        if (filter.isEmpty || t.fullString.toLowerCase().contains(filter)) t,
    ];
    if (item.tagsList.isEmpty) return const SizedBox.shrink();

    final sections = handler.tagNamespaceSections;
    final Map<String, List<Tag>> byNs = {for (final s in sections) s.$1: <Tag>[]};
    final String fallback = sections.isNotEmpty ? sections.last.$1 : 'tag';
    for (final tag in tags) {
      final String ns = handler.tagNamespace(tag.fullString) ?? fallback;
      (byNs[ns] ?? byNs[fallback])?.add(tag);
    }

    final tagsData = settingsHandler.parseTagsList(item.tagsList, isCapped: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: TextField(
            controller: _tagFilter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Symbols.search_rounded, size: 20),
              hintText: 'Search ${item.tagsList.length} tags',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        for (final section in sections)
          if (byNs[section.$1]?.isNotEmpty ?? false) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                section.$2.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in byNs[section.$1]!)
                    _tagChip(
                      context,
                      tag,
                      isMarked: tagsData.markedTags.contains(tag.fullString),
                      isHidden: tagsData.hiddenTags.contains(tag.fullString),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _tagChip(BuildContext context, Tag tag, {required bool isMarked, required bool isHidden}) {
    final Color? typeColor = tag.tagType.getColour();
    final Color base = (typeColor == null || typeColor == Colors.transparent)
        ? Theme.of(context).colorScheme.onSurface
        : typeColor;
    return Material(
      color: isMarked ? const Color(0xFFB8860B).withValues(alpha: 0.3) : base.withValues(alpha: 0.13),
      shape: StadiumBorder(
        side: BorderSide(color: isMarked ? const Color(0xFFDAA520) : base.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        // Tap AND long-press both open the full tag context menu (preview /
        // search / open in tab / copy / favourite / hide), same as the
        // viewer's tag list.
        onTap: () => _openTagMenu(tag, isMarked: isMarked, isHidden: isHidden),
        onLongPress: () => _openTagMenu(tag, isMarked: isMarked, isHidden: isHidden),
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

  void _openTagMenu(Tag tag, {required bool isMarked, required bool isHidden}) {
    showTagDialog(
      context: context,
      tag: tag.fullString,
      handler: handler,
      isHidden: isHidden,
      isMarked: isMarked,
      isInSearch: false,
      hasTabWithTag: HasTabWithTagResult.noTag,
      onUpdate: () => setState(() {}),
    );
  }

  Widget _strip(BuildContext context, {required String title, required String query, required bool expanded, required String compactTitle}) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      initiallyExpanded: expanded,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TagContentPreview(
            key: ValueKey('detail-$title-${item.serverId}'),
            tag: query,
            boorus: [booru],
            parentTab: widget.tab,
            compact: true,
            compactTitle: compactTitle,
          ),
        ),
      ],
    );
  }

  Widget _pagesGrid(BuildContext context) {
    final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
    if (pages == null || pages.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
          child: Text('Pages · ${pages.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: SourceSettingsHandler.instance.pagePreviewColumns(booru),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.7,
            ),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final BooruItem page = pages[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _read(startAt: index),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ThumbnailBuild(item: page, handler: handler, selectable: false, simple: true),
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
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? versionsQuery = handler.relatedVersionsQuery(item);
    final String? galleryId = item.serverId;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          _titleLines.isNotEmpty ? _titleLines.first : 'Doujin',
          style: const TextStyle(fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _header(context),
          _actionRow(context),
          _favSyncLine(context),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Failed to load details: $_loadError',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _loadError = null;
                      });
                      _load();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          _tagSections(context),
          if (versionsQuery != null)
            _strip(
              context,
              title: 'Related — chapters & versions',
              query: versionsQuery,
              expanded: false,
              compactTitle: 'Other chapters and languages of this work',
            ),
          if (galleryId != null && galleryId.isNotEmpty)
            _strip(
              context,
              title: 'Recommended',
              query: 'recommend:$galleryId',
              expanded: true,
              compactTitle: "The site's related list, extended by this gallery's tags and artist",
            ),
          _pagesGrid(context),
        ],
      ),
    );
  }
}
