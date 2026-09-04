import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ignore: implementation_imports
import 'package:flutter_html/src/builtins/image_builtin.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/kemono_post.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_file_hosts.dart';
import 'package:lolisnatcher/src/handlers/post_files_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/pages/kemono_artists_page.dart';
import 'package:lolisnatcher/src/pages/post_files_page.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/common/parsed_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/comments_dialog.dart';

/// A kemono post the way the site's post page shows it: creator, title,
/// dates, the content (text, links, inline images), every file — pictures and
/// videos through the viewer, other attachments with their real names and a
/// download — the embed, the tags, the comments, and the neighbouring posts.
class KemonoPostPage extends StatefulWidget {
  const KemonoPostPage({required this.booru, required this.item, super.key});

  /// Opens a post by id (prev/next navigation): a minimal item is built from
  /// the detail once it arrives.
  factory KemonoPostPage.byId({required Booru booru, required String service, required String user, required String post}) {
    return KemonoPostPage(
      booru: booru,
      item: BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: KemonoApi.postUrl(service, user, post),
        serverId: '$service:$user:$post',
      ),
    );
  }

  final Booru booru;
  final BooruItem item;

  @override
  State<KemonoPostPage> createState() => _KemonoPostPageState();
}

class _KemonoPostPageState extends State<KemonoPostPage> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final KemonoCreatorStore store = KemonoCreatorStore.instance;
  final KemonoFileHosts hosts = KemonoFileHosts.instance;
  late final KemonoHandler handler = KemonoArtistsPage.handlerFor(widget.booru);

  KemonoPost? post;
  List<CommentItem> comments = const [];
  bool commentsLoaded = false;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    hosts.state.addListener(_tick);
    unawaited(_load());
  }

  @override
  void dispose() {
    hosts.state.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final ref = KemonoProfile.splitId(widget.item.serverId);
    if (ref == null) {
      setState(() {
        loading = false;
        error = 'not a kemono post';
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final detail = await KemonoApi.postDetail(ref.service, ref.user, ref.post, booru: widget.booru);
      final KemonoPost? parsed = detail == null ? null : KemonoPost.fromDetail(detail);
      if (parsed == null) throw Exception('the post is gone');
      unawaited(store.warmNames([(service: parsed.service, id: parsed.user)]).then((_) => _tick()));
      if (!mounted) return;
      setState(() {
        post = parsed;
        loading = false;
      });
      unawaited(hosts.check());
      unawaited(_loadComments(ref));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _loadComments(({String service, String user, String post}) ref) async {
    try {
      final List rows = await KemonoApi.comments(ref.service, ref.user, ref.post, booru: widget.booru);
      final List<CommentItem> parsed = [];
      for (int i = 0; i < rows.length; i++) {
        final CommentItem? c = await handler.parseComment(rows[i], i);
        if (c != null) parsed.add(c);
      }
      if (!mounted) return;
      setState(() {
        comments = parsed;
        commentsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => commentsLoaded = true);
    }
  }

  // ── actions ──────────────────────────────────────────────────────────

  void _openTab(String query) {
    searchHandler.addTabByString(query, customBooru: widget.booru, switchToNew: true);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _openExternal(String url) async {
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      FlashElements.showSnackbar(context: context, title: const Text('Could not open'), content: Text('$e'));
    }
  }

  Future<void> _copy(String text, {String what = 'Link'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    FlashElements.showSnackbar(context: context, title: Text('$what copied'), duration: const Duration(seconds: 2));
  }

  /// The item the snatcher downloads for [file]: the real name wins over the
  /// hashed one on disk.
  BooruItem _itemFor(KemonoPostFile file) {
    return BooruItem(
      fileURL: file.url,
      sampleURL: file.url,
      thumbnailURL: file.thumbUrl ?? widget.item.thumbnailURL,
      tagsList: widget.item.tagsList,
      postURL: post?.postUrl ?? widget.item.postURL,
      serverId: post?.serverId ?? widget.item.serverId,
      fileExt: file.extension.isEmpty ? null : file.extension,
      downloadFileName: file.name,
    );
  }

  void _download(List<KemonoPostFile> files) {
    if (files.isEmpty) return;
    SnatchHandler.instance.queue(files.map(_itemFor).toList(), widget.booru, settingsHandler.snatchCooldown, false);
    FlashElements.showSnackbar(
      context: context,
      title: Text(files.length == 1 ? 'Downloading ${files.first.name}' : 'Downloading ${files.length} files'),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _openMedia(int index) async {
    final KemonoPost p = post!;
    final List<PostFile> media = KemonoProfile.postFilesOf(p);
    if (media.isEmpty) return;
    await openPostFilesOverlay(
      context,
      items: PostFilesHandler.instance.itemsFor(widget.item, media),
      booru: widget.booru,
      initialIndex: index.clamp(0, media.length - 1),
    );
  }

  Future<void> _fileMenu(KemonoPostFile file) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(file.url, maxLines: 2, overflow: TextOverflow.ellipsis)),
            const Divider(height: 1),
            ListTile(leading: const Icon(Symbols.download_rounded), title: const Text('Download'), onTap: () => Navigator.pop(ctx, 'download')),
            ListTile(leading: const Icon(Symbols.link_rounded), title: const Text('Copy link'), onTap: () => Navigator.pop(ctx, 'copy')),
            ListTile(leading: const Icon(Symbols.open_in_browser_rounded), title: const Text('Open in browser'), onTap: () => Navigator.pop(ctx, 'browser')),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'download':
        _download([file]);
      case 'copy':
        await _copy(file.url);
      case 'browser':
        await _openExternal(file.url);
    }
  }

  static String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      return DateFormat.yMMMd().add_Hm().format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final KemonoPost? p = post;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.title.isNotEmpty == true ? p!.title : 'Post', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (p != null)
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Symbols.open_in_browser_rounded),
              onPressed: () => unawaited(_openExternal(p.postUrl)),
            ),
          if (p != null)
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Symbols.link_rounded),
              onPressed: () => unawaited(_copy(p.postUrl)),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null || p == null
          ? _errorBody(theme)
          : _body(theme, p),
    );
  }

  Widget _errorBody(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'Nothing came back', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: () => unawaited(_load()), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, KemonoPost p) {
    final String? outage = p.files.isEmpty ? null : hosts.noticeFor(p.files.first.url);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _creatorRow(theme, p),
        const SizedBox(height: 12),
        if (p.title.isNotEmpty) Text(p.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          [
            if (p.published != null) 'Published ${_date(p.published)}',
            if (p.edited != null && p.edited != p.published) 'edited ${_date(p.edited)}',
            if (p.files.isNotEmpty) '${p.files.length} ${p.files.length == 1 ? 'file' : 'files'}',
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        if (outage != null) ...[
          const SizedBox(height: 12),
          _notice(theme, outage),
        ],
        if (p.hasContent) ...[
          const SizedBox(height: 16),
          _section(theme, 'Content'),
          LoliHtml(
            p.contentForHtml(),
            extensions: [
              ImageBuiltIn(
                networkHeaders: {
                  ...handler.getMediaHeaders(),
                  'User-Agent': Tools.browserUserAgent,
                },
              ),
            ],
          ),
        ],
        if (p.embed != null) ...[
          const SizedBox(height: 16),
          _section(theme, 'Embed'),
          _embedCard(theme, p.embed!),
        ],
        if (p.poll != null) ...[
          const SizedBox(height: 16),
          _section(theme, 'Poll'),
          _poll(theme, p.poll!),
        ],
        if (p.images.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(theme, '${p.images.length} ${p.images.length == 1 ? 'picture' : 'pictures'}', trailing: _downloadAll(p.images)),
          _imagesGrid(theme, p),
        ],
        if (p.videos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(theme, '${p.videos.length} ${p.videos.length == 1 ? 'video' : 'videos'}', trailing: _downloadAll(p.videos)),
          for (final f in p.videos) _fileRow(theme, f, icon: Symbols.movie_rounded, onTap: () => unawaited(_openMedia(p.displayable.indexOf(f)))),
        ],
        if (p.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(theme, '${p.attachments.length} ${p.attachments.length == 1 ? 'attachment' : 'attachments'}', trailing: _downloadAll(p.attachments)),
          for (final f in p.attachments) _fileRow(theme, f, icon: Symbols.attach_file_rounded, onTap: () => _download([f])),
        ],
        if (p.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(theme, 'Tags'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in p.tags)
                ActionChip(
                  label: Text(t),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openTab('tag:${t.replaceAll(RegExp(r'\s+'), '_')}'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _section(
          theme,
          commentsLoaded ? '${comments.length} ${comments.length == 1 ? 'comment' : 'comments'}' : 'Comments',
          trailing: TextButton(
            onPressed: () => SettingsPageOpen(context: context, page: (_) => CommentsDialog(item: widget.item, handler: handler)).open(),
            child: const Text('Open'),
          ),
        ),
        if (!commentsLoaded)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (comments.isEmpty)
          Text('No comments', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
        else
          for (final c in comments) _commentTile(theme, c),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: p.prev == null || p.prev!.isEmpty ? null : () => _goTo(p, p.prev!),
                icon: const Icon(Symbols.chevron_left_rounded),
                label: const Text('Previous post'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: p.next == null || p.next!.isEmpty ? null : () => _goTo(p, p.next!),
                icon: const Icon(Symbols.chevron_right_rounded),
                label: const Text('Next post'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _goTo(KemonoPost p, String postId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => KemonoPostPage.byId(booru: widget.booru, service: p.service, user: p.user, post: postId)),
    );
  }

  Widget _creatorRow(ThemeData theme, KemonoPost p) {
    final String name = store.nameOf(p.service, p.user) ?? '${p.service}:${p.user}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openTab('creator:${p.service}:${p.user}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundImage: NetworkImage(KemonoApi.iconUrl(p.service, p.user)),
              onForegroundImageError: (_, _) {},
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(p.service, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Symbols.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _notice(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.cloud_off_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer))),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _downloadAll(List<KemonoPostFile> files) {
    return TextButton.icon(
      onPressed: () => _download(files),
      icon: const Icon(Symbols.download_rounded, size: 18),
      label: Text(files.length == 1 ? 'Download' : 'Download all'),
    );
  }

  Widget _embedCard(ThemeData theme, KemonoPostEmbed e) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Symbols.link_rounded),
        title: Text(e.subject?.isNotEmpty == true ? e.subject! : (e.url ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: e.description?.isNotEmpty == true ? Text(e.description!, maxLines: 3, overflow: TextOverflow.ellipsis) : (e.url != null && e.subject?.isNotEmpty == true ? Text(e.url!, maxLines: 1, overflow: TextOverflow.ellipsis) : null),
        onTap: e.url == null || e.url!.isEmpty ? null : () => unawaited(_openExternal(e.url!)),
      ),
    );
  }

  Widget _poll(ThemeData theme, Map<String, dynamic> poll) {
    final String title = poll['title']?.toString() ?? poll['question']?.toString() ?? '';
    final choices = poll['choices'];
    final int total = int.tryParse(poll['total_votes']?.toString() ?? '') ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (choices is List)
              for (final c in choices)
                if (c is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(c['text']?.toString() ?? '')),
                        Text(
                          '${c['votes'] ?? ''}',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('$total votes', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _imagesGrid(ThemeData theme, KemonoPost p) {
    final List<KemonoPostFile> images = p.images;
    final List<KemonoPostFile> order = p.displayable;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: images.length,
      itemBuilder: (context, i) {
        final KemonoPostFile f = images[i];
        return InkWell(
          onTap: () => unawaited(_openMedia(order.indexOf(f))),
          onLongPress: () => unawaited(_fileMenu(f)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Image.network(
                f.thumbUrl!,
                fit: BoxFit.cover,
                headers: handler.getMediaHeaders(),
                errorBuilder: (_, _, _) => Center(child: Icon(Symbols.broken_image_rounded, color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fileRow(ThemeData theme, KemonoPostFile f, {required IconData icon, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(f.extension.isEmpty ? f.path : '.${f.extension}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
      trailing: IconButton(
        tooltip: 'Download',
        icon: const Icon(Symbols.download_rounded),
        onPressed: () => _download([f]),
      ),
      onTap: onTap,
      onLongPress: () => unawaited(_fileMenu(f)),
    );
  }

  Widget _commentTile(ThemeData theme, CommentItem c) {
    final String when = c.createDate == null ? '' : _date(c.createDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Text((c.authorName ?? '?').isEmpty ? '?' : (c.authorName ?? '?')[0].toUpperCase(), style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c.authorName ?? c.authorID ?? 'someone', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (when.isNotEmpty) Text(when, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 2),
                ParsedText(text: c.content ?? '', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
