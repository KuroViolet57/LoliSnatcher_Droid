import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/pages/flash_player_page.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// A FurAffinity submission the way its page shows it (r42): the picture,
/// title and artist, stats and file details, the description with its links,
/// the artist's gallery around it (older/newer), the folders it is in, its
/// keywords and the comments. Like the kemono post page.
class FurAffinityPostPage extends StatefulWidget {
  const FurAffinityPostPage({required this.booru, required this.item, this.fetchPage, super.key});

  /// Opens a submission by id (older/newer, the mini gallery).
  factory FurAffinityPostPage.byId({required Booru booru, required String id, Future<String> Function(String url)? fetchPage}) {
    return FurAffinityPostPage(
      booru: booru,
      fetchPage: fetchPage,
      item: BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: '${FurAffinityQuery.site}/view/$id/',
        serverId: id,
      ),
    );
  }

  final Booru booru;
  final BooruItem item;

  /// Reads a page; the handler's (with the account) when not given.
  final Future<String> Function(String url)? fetchPage;

  @override
  State<FurAffinityPostPage> createState() => _FurAffinityPostPageState();
}

class _FurAffinityPostPageState extends State<FurAffinityPostPage> {
  late final FurAffinityHandler handler = FurAffinityHandler(widget.booru, FurAffinityHandler.pageSize);
  final Map<String, String> _mediaHeaders = const {'Referer': '${FurAffinityQuery.site}/'};
  FurAffinitySubmission? post;
  String? error;
  bool loading = true;
  bool? faved;

  String get _url => widget.item.postURL.isNotEmpty ? widget.item.postURL : '${FurAffinityQuery.site}/view/${widget.item.serverId}/';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final String html = await (widget.fetchPage ?? (String url) => handler.fetchPage(url))(_url);
      final FurAffinitySubmission? s = FurAffinityParser.submission(html);
      if (!mounted) return;
      setState(() {
        post = s;
        faved = s?.favLink?.faved;
        error = s == null ? 'This submission could not be read (it may need you to log in, or be removed).' : null;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  void _openTab(String query) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    SearchHandler.instance.addTabByString(query, customBooru: widget.booru, switchToNew: true);
  }

  void _openPost(String id) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FurAffinityPostPage.byId(booru: widget.booru, id: id, fetchPage: widget.fetchPage),
      ),
    );
  }

  Future<void> _toggleFav() async {
    final bool target = !(faved ?? false);
    final (bool ok, String message) = await handler.setSiteFavourite(widget.item, target);
    if (!mounted) return;
    if (ok) setState(() => faved = target);
    FlashElements.showSnackbar(context: context, title: Text(message));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FurAffinitySubmission? p = post;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.title.isNotEmpty == true ? p!.title : 'Submission', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (p != null && FurAffinitySessionHandler.instance.isLoggedIn && faved != null)
            IconButton(
              key: const ValueKey('fa-post-fav'),
              tooltip: faved! ? 'Remove from FurAffinity favorites' : 'Add to FurAffinity favorites',
              icon: Icon(faved! ? Symbols.favorite_rounded : Symbols.favorite_border_rounded, fill: faved! ? 1 : 0),
              onPressed: _toggleFav,
            ),
          IconButton(
            tooltip: 'Open the page',
            icon: const Icon(Symbols.open_in_browser_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InAppWebviewView(initialUrl: _url))),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (p == null
                ? Center(
                    child: Padding(padding: const EdgeInsets.all(24), child: Text(error ?? '')),
                  )
                : _body(theme, p)),
    );
  }

  Widget _body(ThemeData theme, FurAffinitySubmission p) {
    final NumberFormat count = NumberFormat.decimalPattern();
    final String gif = p.fileUrl.toLowerCase().endsWith('.gif') ? p.fileUrl : '';
    final String picture = gif.isNotEmpty
        ? gif
        : (p.previewUrl.isNotEmpty ? p.previewUrl : (FlashPlayerPage.isFlashUrl(p.fileUrl) ? widget.item.thumbnailURL : p.fileUrl));
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black),
                body: InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: Image(
                      image: CustomNetworkImage(p.fileUrl, headers: _mediaHeaders),
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: Image(
            image: CustomNetworkImage(picture, headers: _mediaHeaders),
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => const SizedBox(height: 120, child: Center(child: Icon(Symbols.broken_image_rounded))),
          ),
        ),
        if (FlashPlayerPage.isFlashUrl(p.fileUrl))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('fa-post-flash'),
              icon: const Icon(Symbols.play_circle_rounded),
              label: const Text('Play Flash (Ruffle)'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FlashPlayerPage(swfUrl: p.fileUrl, title: p.title),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(p.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: p.avatarUrl.isEmpty
                  ? const ColoredBox(color: Colors.black26)
                  : Image(
                      image: CustomNetworkImage(p.avatarUrl, headers: _mediaHeaders),
                      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                    ),
            ),
          ),
          title: Text(p.artistName.isNotEmpty ? p.artistName : p.artist),
          subtitle: Text(
            [
              '~${p.artist}',
              if (p.postedAt != null) DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(p.postedAt! * 1000)),
            ].join(' · '),
          ),
          trailing: const Icon(Symbols.chevron_right_rounded),
          onTap: p.artist.isEmpty ? null : () => _openTab('user:${p.artist}'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (IconData icon, String text) in [
                (Symbols.visibility_rounded, count.format(p.views)),
                (Symbols.favorite_rounded, count.format(p.favorites)),
                (Symbols.chat_bubble_rounded, count.format(p.commentCount)),
                if (p.rating.isNotEmpty) (Symbols.shield_rounded, p.rating[0].toUpperCase() + p.rating.substring(1)),
                if (p.category.isNotEmpty) (Symbols.category_rounded, p.category),
                if (p.theme.isNotEmpty) (Symbols.palette_rounded, p.theme),
                if (p.species.isNotEmpty) (Symbols.pets_rounded, p.species),
                if (p.resolution.isNotEmpty) (Symbols.aspect_ratio_rounded, p.resolution),
                if (p.fileSize.isNotEmpty) (Symbols.save_rounded, p.fileSize),
              ])
                Chip(avatar: Icon(icon, size: 16), label: Text(text), visualDensity: VisualDensity.compact),
            ],
          ),
        ),
        if (p.descriptionHtml.isNotEmpty) ...[
          _section(theme, 'Description'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: LoliHtml(p.descriptionHtml)),
        ],
        if (p.gallery.isNotEmpty || p.olderId != null || p.newerId != null) ...[
          _section(theme, 'Gallery'),
          if (p.gallery.isNotEmpty)
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: p.gallery.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final BooruItem g = p.gallery[i];
                  final bool current = g.serverId == widget.item.serverId;
                  return GestureDetector(
                    onTap: current || g.serverId == null ? null : () => _openPost(g.serverId!),
                    child: Container(
                      width: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: current ? theme.colorScheme.secondary : Colors.transparent, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image(
                        image: CustomNetworkImage(g.thumbnailURL, headers: _mediaHeaders),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                if (p.newerId != null)
                  OutlinedButton.icon(
                    key: const ValueKey('fa-post-newer'),
                    icon: const Icon(Symbols.chevron_left_rounded),
                    label: const Text('Newer'),
                    onPressed: () => _openPost(p.newerId!),
                  ),
                const Spacer(),
                if (p.olderId != null)
                  OutlinedButton.icon(
                    key: const ValueKey('fa-post-older'),
                    icon: const Icon(Symbols.chevron_right_rounded),
                    label: const Text('Older'),
                    onPressed: () => _openPost(p.olderId!),
                  ),
              ],
            ),
          ),
        ],
        if (p.folders.isNotEmpty) ...[
          _section(theme, 'Folders'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final FurAffinityFolder f in p.folders)
                  ActionChip(
                    key: ValueKey('fa-folder-${f.id}'),
                    avatar: const Icon(Symbols.folder_rounded, size: 16),
                    label: Text(f.group.isEmpty ? f.name : '${f.group} · ${f.name}'),
                    onPressed: () => _openTab(f.term),
                  ),
              ],
            ),
          ),
        ],
        if (p.keywords.isNotEmpty) ...[
          _section(theme, 'Keywords'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final String k in p.keywords) ActionChip(label: Text(k), visualDensity: VisualDensity.compact, onPressed: () => _openTab(k)),
              ],
            ),
          ),
        ],
        _section(theme, 'Comments (${p.comments.length})'),
        if (p.comments.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No comments'))
        else
          for (final FurAffinityComment c in p.comments)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: c.avatarUrl.isEmpty
                      ? const ColoredBox(color: Colors.black26)
                      : Image(
                          image: CustomNetworkImage(c.avatarUrl, headers: _mediaHeaders),
                          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                        ),
                ),
              ),
              title: Text(
                [
                  if (c.displayName.isNotEmpty) c.displayName else if (c.username.isNotEmpty) c.username else '(hidden)',
                  if (c.postedAt != null) DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(c.postedAt! * 1000)),
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(c.text),
              onTap: c.username.isEmpty ? null : () => _openTab('user:${c.username}'),
            ),
      ],
    );
  }

  Widget _section(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.secondary),
      ),
    );
  }
}
