import 'dart:async';

import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_site.dart';
import 'package:lolisnatcher/src/boorus/kemono_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/drawer_refresh.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_file_hosts.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/pages/kemono_artists_page.dart';
import 'package:lolisnatcher/src/pages/kemono_messages_pages.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_type_strip.dart';

/// The site's own sidebar, in the place of the pinned-tags drawer on a
/// kemono-style tab: the site's menu — Artists (search, recent, random),
/// Posts (search, popular, tags, random), Favorites, DMs, Announcements —
/// as coloured pills, plus the creator index's and file hosts' status and,
/// at the bottom, the switch back to the app's normal drawer (whose Quick
/// access has the switch back here). Rows the site has no endpoint for are
/// not shown (see [KemonoSite]).
///
/// An InnerDrawer child has no Material of its own: without the one here the
/// text gets the yellow underline and every ripple throws.
class KemonoSidebar extends StatefulWidget {
  const KemonoSidebar({required this.booru, required this.toggleDrawer, super.key});

  final Booru booru;
  final VoidCallback toggleDrawer;

  @override
  State<KemonoSidebar> createState() => _KemonoSidebarState();
}

class _KemonoSidebarState extends State<KemonoSidebar> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  late final KemonoSite site = KemonoSite.of(widget.booru);
  late final KemonoCreatorStore store = KemonoCreatorStore.forSite(site);
  final KemonoSessionHandler session = KemonoSessionHandler.instance;
  late final KemonoFileHosts hosts = KemonoFileHosts.forSite(site);
  Worker? _tabWorker;

  static const Color artists = Color(0xFFB9A0E8);
  static const Color posts = Color(0xFF8FBFD4);
  static const Color favorites = Color(0xFFF0708A);
  static const Color messages = Color(0xFFE8C46B);

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabWorker = ever(searchHandler.index, (_) => _tick());
    DrawerRefresh.tick.addListener(_tick);
    session.revision.addListener(_tick);
    store.state.addListener(_tick);
    hosts.state.addListener(_tick);
    hosts.running.addListener(_tick);
    unawaited(store.ensureFresh());
  }

  @override
  void dispose() {
    _tabWorker?.dispose();
    DrawerRefresh.tick.removeListener(_tick);
    session.revision.removeListener(_tick);
    store.state.removeListener(_tick);
    hosts.state.removeListener(_tick);
    hosts.running.removeListener(_tick);
    super.dispose();
  }

  KemonoHandler? get _handler {
    if (searchHandler.tabs.isEmpty) return null;
    final h = searchHandler.currentBooruHandler;
    return h is KemonoHandler ? h : null;
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
    FlashElements.showSnackbar(context: context, title: Text(title), content: Text(detail ?? ''));
  }

  Future<void> _randomArtist() async {
    try {
      final ref = await KemonoApi.randomArtist(booru: widget.booru);
      if (ref == null) throw Exception('no artist came back');
      _openTab('creator:${ref.service}:${ref.id}');
    } catch (e) {
      _say('Random artist failed', '$e');
    }
  }

  Future<void> _pickTag() async {
    try {
      final KemonoHandler handler = _handler ?? KemonoArtistsPage.handlerFor(widget.booru);
      final TagCatalogSource catalog = handler.tagCatalog;
      final TagCatalogNamespace? ns = catalog.namespaceFor(KemonoTagCatalog.tagKey);
      if (ns == null) {
        _say('${site.name} has no tag list');
        return;
      }
      final res = await SettingsPageOpen(
        context: context,
        asBottomSheet: true,
        bottomSheetExpandableByScroll: true,
        page: (scrollController) =>
            TagCatalogPickerSheet(booru: widget.booru, catalog: catalog, namespace: ns, scrollController: scrollController),
      ).open();
      if (res is String && res.isNotEmpty) {
        searchHandler.addTagToSearch(res);
        unawaited(searchHandler.searchAction(searchHandler.searchTextController.text, null));
        widget.toggleDrawer();
      }
    } catch (e) {
      _say('Tags failed', '$e');
    }
  }

  void _swapToAppSidebar() {
    settingsHandler.kemonoSidebar.value = false;
    unawaited(settingsHandler.saveSettings(restate: false));
  }

  String _indexLine(KemonoIndexState s) {
    if (s.running) {
      return s.total == 0 ? 'Downloading the creator index…' : '${s.inserted.toShortString()} / ${s.total.toShortString()} stored';
    }
    if (s.error != null) return 'Index failed: ${s.error}';
    if (s.count == 0) return 'No creator index yet';
    final int age = DateTime.now().millisecondsSinceEpoch - s.refreshedAt;
    final String ago = age < 3600000 ? '${age ~/ 60000} min ago' : '${age ~/ 3600000} h ago';
    return '${s.count.toShortString()} creators · $ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool signedIn = session.hasSession(widget.booru);
    final creator = _handler?.currentCreator;
    final KemonoIndexState index = store.state.value;
    final bool hostsDown = hosts.state.value.values.any((s) => !s.ok);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _Section(
                      title: 'Artists',
                      color: artists,
                      children: [
                        _Pill(
                          icon: Symbols.person_search_rounded,
                          label: 'Search',
                          subtitle: 'Every creator, with banners',
                          color: artists,
                          onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru)),
                        ),
                        if (site.hasUpdatedArtists)
                          _Pill(
                            icon: Symbols.update_rounded,
                            label: 'Recent',
                            subtitle: 'Updated latest',
                            color: artists,
                            onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru, mode: KemonoArtistsMode.recent)),
                          ),
                        if (site.hasRandom)
                          _Pill(
                            icon: Symbols.shuffle_rounded,
                            label: 'Random',
                            color: artists,
                            onTap: () => unawaited(_randomArtist()),
                          ),
                      ],
                    ),
                    _Section(
                      title: 'Posts',
                      color: posts,
                      children: [
                        _Pill(
                          icon: Symbols.search_rounded,
                          label: 'Search',
                          subtitle: 'Words, tags, creators',
                          color: posts,
                          onTap: () {
                            widget.toggleDrawer();
                            unawaited(
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MainSearchQueryEditorPage())),
                            );
                          },
                        ),
                        if (site.hasPopular)
                          _Pill(
                            icon: Symbols.trending_up_rounded,
                            label: 'Popular',
                            subtitle: 'Today · popular:week / month for more',
                            color: posts,
                            onTap: () => _openTab('popular:day'),
                          ),
                        if (site.hasTagList)
                          _Pill(
                            icon: Symbols.sell_rounded,
                            label: 'Tags',
                            subtitle: "The site's tag list",
                            color: posts,
                            onTap: () => unawaited(_pickTag()),
                          ),
                        if (site.hasRandom)
                          _Pill(
                            icon: Symbols.shuffle_rounded,
                            label: 'Random',
                            color: posts,
                            onTap: () => _openTab('random'),
                          ),
                      ],
                    ),
                    _Section(
                      title: 'Favorites',
                      color: favorites,
                      children: [
                        if (signedIn) ...[
                          _Pill(
                            icon: Symbols.favorite_rounded,
                            label: 'Posts',
                            color: favorites,
                            onTap: () => _openTab('favorites:posts'),
                          ),
                          _Pill(
                            icon: Symbols.artist_rounded,
                            label: 'Artists',
                            color: favorites,
                            onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru, mode: KemonoArtistsMode.favourites)),
                          ),
                        ] else
                          _Pill(
                            icon: Symbols.login_rounded,
                            label: 'Sign in to use favorites',
                            subtitle: 'Username and password in the booru settings',
                            color: favorites,
                            onTap: () => _openPage(BooruEdit(widget.booru)),
                          ),
                      ],
                    ),
                    _Section(
                      title: 'Messages',
                      color: messages,
                      children: [
                        if (site.hasDms)
                          _Pill(
                            icon: Symbols.mail_rounded,
                            label: 'DMs',
                            color: messages,
                            onTap: () => _openPage(KemonoDmsPage(booru: widget.booru)),
                          ),
                        _Pill(
                          icon: Symbols.campaign_rounded,
                          label: 'Announcements',
                          subtitle: creator == null ? 'Open a creator first' : null,
                          color: messages,
                          enabled: creator != null,
                          onTap: () => _openPage(
                            KemonoAnnouncementsPage(booru: widget.booru, service: creator!.service, id: creator.id),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _statusCard(theme, index, hostsDown),
              const SizedBox(height: 8),
              _Pill(
                icon: Symbols.swap_horiz_rounded,
                label: 'Use the app sidebar',
                subtitle: 'Pinned tags and quick access',
                color: theme.colorScheme.secondary,
                outlined: true,
                onTap: _swapToAppSidebar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: BooruFavicon(widget.booru),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.booru.name ?? site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              Text(
                Uri.parse(site.site).host,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(icon: const Icon(Symbols.close_rounded), onPressed: widget.toggleDrawer),
      ],
    );
  }

  Widget _statusCard(ThemeData theme, KemonoIndexState index, bool hostsDown) {
    final TextStyle small = TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Symbols.group_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _indexLine(index),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: index.error != null ? small.copyWith(color: Colors.orange) : small,
                ),
              ),
              IconButton(
                tooltip: 'Refresh the creator index',
                visualDensity: VisualDensity.compact,
                icon: index.running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Symbols.refresh_rounded, size: 20),
                onPressed: index.running ? null : () => unawaited(store.refresh()),
              ),
            ],
          ),
          if (index.running)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: LinearProgressIndicator(value: index.progress, minHeight: 2),
            ),
          Row(
            children: [
              Icon(
                hostsDown ? Symbols.cloud_off_rounded : Symbols.cloud_done_rounded,
                size: 16,
                color: hostsDown ? Colors.orange : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hosts.summary(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: hostsDown ? small.copyWith(color: Colors.orange) : small,
                ),
              ),
              IconButton(
                tooltip: 'Check whether the file hosts answer from this network',
                visualDensity: VisualDensity.compact,
                icon: hosts.running.value
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Symbols.network_check_rounded, size: 20),
                onPressed: hosts.running.value ? null : () => unawaited(hosts.check(force: true)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A group of pills under a small coloured heading.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.color, required this.children});

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
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: theme.colorScheme.onSurfaceVariant),
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
/// under it, a chevron. [outlined] draws only the border, for the one row
/// that leaves the site's menu.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    this.outlined = false,
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
