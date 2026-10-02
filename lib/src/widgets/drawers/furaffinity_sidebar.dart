import 'dart:async';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/furaffinity_login_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// FurAffinity's own sidebar (r42), in the place of the pinned-tags drawer on
/// a FurAffinity tab, styled like the kemono one: Browse (newest, search,
/// real animations), You (the submissions inbox, watched artists, your
/// favorites and gallery), the artist of the current tab (gallery, scraps,
/// favorites, folders, watch), the account (log in, blocklist, content
/// filter, log out) and, at the bottom, the switch back to the app's drawer
/// (whose Quick access switches here again).
class FurAffinitySidebar extends StatefulWidget {
  const FurAffinitySidebar({required this.booru, required this.toggleDrawer, super.key});

  final Booru booru;
  final VoidCallback toggleDrawer;

  static const Color browse = Color(0xFF8FBFD4);
  static const Color you = Color(0xFFF0A36B);
  static const Color artist = Color(0xFFB9A0E8);
  static const Color account = Color(0xFF93C49B);

  @override
  State<FurAffinitySidebar> createState() => _FurAffinitySidebarState();
}

class _FurAffinitySidebarState extends State<FurAffinitySidebar> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final FurAffinitySessionHandler session = FurAffinitySessionHandler.instance;
  Worker? _tabWorker;
  bool? _watching;
  String _watchFor = '';

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabWorker = ever(searchHandler.index, (_) => _tick());
    session.revision.addListener(_tick);
  }

  @override
  void dispose() {
    _tabWorker?.dispose();
    session.revision.removeListener(_tick);
    super.dispose();
  }

  FurAffinityHandler get _handler {
    if (searchHandler.tabs.isNotEmpty) {
      final h = searchHandler.currentBooruHandler;
      if (h is FurAffinityHandler) return h;
    }
    return FurAffinityHandler(widget.booru, FurAffinityHandler.pageSize);
  }

  /// The artist of the current tab, if it is a FurAffinity artist tab.
  String get _tabArtist {
    if (searchHandler.tabs.isEmpty || searchHandler.currentBooruHandler is! FurAffinityHandler) return '';
    return FurAffinityQuery.parse(searchHandler.currentTab.tags).user;
  }

  void _openTab(String query) {
    widget.toggleDrawer();
    searchHandler.addTabByString(query, customBooru: widget.booru, switchToNew: true);
  }

  Future<void> _openPage(Widget page) async {
    widget.toggleDrawer();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  void _say(String title, [String? detail]) {
    if (!mounted) return;
    FlashElements.showSnackbar(context: context, title: Text(title), content: Text(detail ?? ""));
  }

  Future<void> _checkWatch(String artist) async {
    _watchFor = artist;
    _watching = null;
    final link = await _handler.fetchWatchLink(artist);
    if (!mounted || _watchFor != artist) return;
    setState(() => _watching = link?.watching);
  }

  Future<void> _toggleWatch(String artist) async {
    final result = await _handler.toggleWatch(artist);
    if (!mounted) return;
    setState(() => _watching = result.watching);
    _say(result.message);
  }

  Future<void> _importBlocklist() async {
    final FurAffinityBlocklist? list = session.siteBlocklist;
    final String? name = widget.booru.name;
    if (list == null || name == null) {
      _say('No blocklist read yet', 'Open any FurAffinity page while logged in, then try again.');
      return;
    }
    final List<String> tags = [
      ...list.tags,
      for (final String u in list.users) u.startsWith('u_') ? 'artist:${u.substring(2)}' : u,
    ];
    for (final String t in tags) {
      settingsHandler.addTagToBooruHiddenList(name, t);
    }
    unawaited(settingsHandler.saveSettings(restate: false).catchError((_) => false));
    _say('Copied ${tags.length} blocked tags', "They are now this source's hidden tags in the app too.");
  }

  void _swapToAppSidebar() {
    settingsHandler.furAffinitySidebar.value = false;
    unawaited(settingsHandler.saveSettings(restate: false).catchError((_) => false));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool signedIn = session.isLoggedIn;
    final String? me = session.username;
    final String artist = _tabArtist;
    if (signedIn && artist.isNotEmpty && artist != _watchFor) unawaited(_checkWatch(artist));
    final FurAffinityBlocklist? blocklist = session.siteBlocklist;
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme, signedIn, me),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    FaSection(
                      title: 'Browse',
                      color: FurAffinitySidebar.browse,
                      children: [
                        FaPill(
                          icon: Symbols.new_releases_rounded,
                          label: 'Browse',
                          subtitle: 'The newest submissions',
                          color: FurAffinitySidebar.browse,
                          onTap: () => _openTab(''),
                        ),
                        FaPill(
                          icon: Symbols.search_rounded,
                          label: 'Search',
                          subtitle: 'Words, filters, categories and species',
                          color: FurAffinitySidebar.browse,
                          onTap: () => _openPage(const MainSearchQueryEditorPage()),
                        ),
                        FaPill(
                          icon: Symbols.animated_images_rounded,
                          label: 'Animated only',
                          subtitle: 'Real GIF animations, newest first',
                          color: FurAffinitySidebar.browse,
                          onTap: () => _openTab('animated:gif sort:date'),
                        ),
                      ],
                    ),
                    if (signedIn)
                      FaSection(
                        title: 'You',
                        color: FurAffinitySidebar.you,
                        children: [
                          FaPill(
                            icon: Symbols.inbox_rounded,
                            label: 'Submissions inbox',
                            subtitle: 'New work from the artists you watch',
                            color: FurAffinitySidebar.you,
                            onTap: () => _openTab('inbox:'),
                          ),
                          FaPill(
                            icon: Symbols.visibility_rounded,
                            label: 'Watched artists',
                            subtitle: me == null ? 'Open a page first so the app knows your name' : 'Everyone you watch',
                            color: FurAffinitySidebar.you,
                            enabled: me != null,
                            onTap: () => _openPage(FurAffinityWatchlistPage(booru: widget.booru, username: me!)),
                          ),
                          FaPill(
                            icon: Symbols.favorite_rounded,
                            label: 'My favorites',
                            color: FurAffinitySidebar.you,
                            enabled: me != null,
                            onTap: () => _openTab('favorites:$me'),
                          ),
                          FaPill(
                            icon: Symbols.photo_library_rounded,
                            label: 'My gallery',
                            color: FurAffinitySidebar.you,
                            enabled: me != null,
                            onTap: () => _openTab('user:$me'),
                          ),
                        ],
                      ),
                    if (artist.isNotEmpty)
                      FaSection(
                        title: 'Artist · $artist',
                        color: FurAffinitySidebar.artist,
                        children: [
                          FaPill(
                            icon: Symbols.photo_library_rounded,
                            label: 'Gallery',
                            color: FurAffinitySidebar.artist,
                            onTap: () => _openTab('user:$artist'),
                          ),
                          FaPill(
                            icon: Symbols.draft_rounded,
                            label: 'Scraps',
                            color: FurAffinitySidebar.artist,
                            onTap: () => _openTab('scraps:$artist'),
                          ),
                          FaPill(
                            icon: Symbols.favorite_rounded,
                            label: 'Favorites',
                            color: FurAffinitySidebar.artist,
                            onTap: () => _openTab('favorites:$artist'),
                          ),
                          FaPill(
                            icon: Symbols.folder_rounded,
                            label: 'Folders',
                            subtitle: 'The folders the artist files their gallery in',
                            color: FurAffinitySidebar.artist,
                            onTap: () => FurAffinityFolderList.show(
                              context,
                              handler: _handler,
                              username: artist,
                              onOpen: (String term) => _openTab(term),
                            ),
                          ),
                          if (signedIn)
                            FaPill(
                              icon: _watching == true ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                              label: _watching == null ? 'Watch…' : (_watching! ? 'Unwatch' : 'Watch'),
                              subtitle: _watching == null ? 'Checking' : (_watching! ? 'You watch this artist' : 'Get their new work in your inbox'),
                              color: FurAffinitySidebar.artist,
                              enabled: _watching != null,
                              onTap: () => _toggleWatch(artist),
                            ),
                        ],
                      ),
                    FaSection(
                      title: 'Account',
                      color: FurAffinitySidebar.account,
                      children: [
                        if (!signedIn)
                          FaPill(
                            icon: Symbols.login_rounded,
                            label: 'Log in',
                            subtitle: 'For mature content, the inbox and watching',
                            color: FurAffinitySidebar.account,
                            onTap: () => _openPage(const FurAffinityLoginPage()),
                          )
                        else ...[
                          FaPill(
                            icon: Symbols.block_rounded,
                            label: 'Blocklist',
                            subtitle: blocklist == null
                                ? 'Read from the next page you open'
                                : '${blocklist.tags.length} tags, ${blocklist.users.length} artists never shown · tap to copy into the app',
                            color: FurAffinitySidebar.account,
                            onTap: _importBlocklist,
                          ),
                          FaPill(
                            icon: Symbols.tune_rounded,
                            label: 'Content filter',
                            subtitle: 'Mature and adult viewing, on the site',
                            color: FurAffinitySidebar.account,
                            onTap: () => _openPage(
                              const InAppWebviewView(initialUrl: 'https://www.furaffinity.net/controls/settings/', title: 'FurAffinity settings'),
                            ),
                          ),
                          FaPill(
                            icon: Symbols.logout_rounded,
                            label: 'Log out',
                            color: FurAffinitySidebar.account,
                            onTap: session.logout,
                          ),
                        ],
                      ],
                    ),
                    KeyedSubtree(
                      key: const ValueKey('fa-sidebar-app'),
                      child: FaPill(
                        icon: Symbols.swap_horiz_rounded,
                        label: 'Use the app sidebar',
                        subtitle: 'Pinned tags, downloads and quick access',
                        color: theme.colorScheme.outline,
                        outlined: true,
                        onTap: _swapToAppSidebar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, bool signedIn, String? me) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: BooruFavicon(widget.booru),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.booru.name ?? 'FurAffinity',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              Text(
                !signedIn ? 'Not logged in' : (me == null ? 'Logged in' : '~$me'),
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(icon: const Icon(Symbols.close_rounded), onPressed: widget.toggleDrawer),
      ],
    );
  }
}

/// The artists someone watches, a page of 200 at a time (r42).
class FurAffinityWatchlistPage extends StatefulWidget {
  const FurAffinityWatchlistPage({required this.booru, required this.username, super.key});

  final Booru booru;
  final String username;

  @override
  State<FurAffinityWatchlistPage> createState() => _FurAffinityWatchlistPageState();
}

class _FurAffinityWatchlistPageState extends State<FurAffinityWatchlistPage> {
  late final FurAffinityHandler handler = FurAffinityHandler(widget.booru, FurAffinityHandler.pageSize);
  final List<FurAffinityWatchEntry> users = [];
  int page = 0;
  bool hasNext = true;
  bool loading = false;
  String? error;
  String filter = '';

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  Future<void> _more() async {
    if (loading || !hasNext) return;
    setState(() => loading = true);
    try {
      final result = await handler.fetchWatchlist(widget.username, page + 1);
      page++;
      users.addAll(result.users);
      hasNext = result.hasNext && result.users.isNotEmpty;
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<FurAffinityWatchEntry> shown = filter.isEmpty
        ? users
        : users.where((u) => u.username.contains(filter) || u.displayName.toLowerCase().contains(filter)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Watched by ~${widget.username}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Symbols.search_rounded), hintText: 'Filter', isDense: true),
              onChanged: (v) => setState(() => filter = v.trim().toLowerCase()),
            ),
          ),
          if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) unawaited(_more());
                return false;
              },
              child: ListView.builder(
                itemCount: shown.length + (loading ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= shown.length)
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  final FurAffinityWatchEntry u = shown[i];
                  return ListTile(
                    leading: const Icon(Symbols.person_rounded),
                    title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                    subtitle: Text('~${u.username}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      SearchHandler.instance.addTabByString('user:${u.username}', customBooru: widget.booru, switchToNew: true);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An artist's gallery folders in a sheet, grouped as the artist groups
/// them; a tap opens one as a feed (r42).
class FurAffinityFolderList extends StatelessWidget {
  const FurAffinityFolderList({required this.folders, required this.onOpen, super.key});

  final List<FurAffinityFolder> folders;
  final ValueChanged<String> onOpen;

  static Future<void> show(
    BuildContext context, {
    required FurAffinityHandler handler,
    required String username,
    required ValueChanged<String> onOpen,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: FutureBuilder<List<FurAffinityFolder>>(
            future: handler.fetchFolders(username),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.isEmpty) return const Center(child: Text('No folders'));
              return FurAffinityFolderList(
                folders: snap.data!,
                onOpen: (term) {
                  Navigator.of(ctx).pop();
                  onOpen(term);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> rows = [];
    String group = ' ';
    for (final FurAffinityFolder f in folders) {
      if (f.group != group) {
        group = f.group;
        if (group.isNotEmpty) {
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                group.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: theme.colorScheme.secondary),
              ),
            ),
          );
        }
      }
      rows.add(
        ListTile(
          key: ValueKey('fa-folder-row-${f.id}'),
          dense: true,
          leading: const Icon(Symbols.folder_rounded),
          title: Text(f.name),
          trailing: f.count > 0 ? Text('${f.count}') : null,
          onTap: () => onOpen(f.term),
        ),
      );
    }
    return ListView(children: rows);
  }
}

/// A sidebar group: a coloured dot and a title over its pills.
class FaSection extends StatelessWidget {
  const FaSection({required this.title, required this.color, required this.children, super.key});

  final String title;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// One coloured pill: a filled icon badge, a bold label, an optional line
/// under it, a chevron (the kemono sidebar's look).
class FaPill extends StatelessWidget {
  const FaPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    this.outlined = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final bool enabled;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color tint = enabled ? color : theme.colorScheme.outline;
    final Color fill = outlined ? Colors.transparent : tint.withValues(alpha: enabled ? 0.14 : 0.06);
    final Color border = tint.withValues(alpha: enabled ? 0.38 : 0.2);
    final Color ink = enabled ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    final Color badgeInk = ThemeData.estimateBrightnessForColor(tint) == Brightness.dark ? Colors.white : const Color(0xFF1B1B22);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: fill,
        shape: StadiumBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          splashColor: tint.withValues(alpha: 0.25),
          highlightColor: tint.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: enabled ? tint : tint.withValues(alpha: 0.4), shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: badgeInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Icon(Symbols.chevron_right_rounded, size: 18, color: enabled ? tint : theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
