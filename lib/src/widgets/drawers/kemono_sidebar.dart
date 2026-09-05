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
import 'package:lolisnatcher/src/widgets/drawers/drawer_row.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_type_strip.dart';

/// kemono.cr's own sidebar, in the place of the pinned-tags drawer on a
/// Kemono tab: the site's menu — Artists (search, recent, random), Posts
/// (search, popular, tags, random), Favorites, DMs, Announcements — plus the
/// creator index's status and, at the bottom, the switch back to the app's
/// normal drawer (whose Quick access has the switch back here).
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

  Future<void> _randomArtist() async {
    try {
      final ref = await KemonoApi.randomArtist(booru: widget.booru);
      if (ref == null) throw Exception('no artist came back');
      _openTab('creator:${ref.service}:${ref.id}');
    } catch (e) {
      if (!mounted) return;
      FlashElements.showSnackbar(context: context, title: const Text('Random artist failed'), content: Text('$e'));
    }
  }

  Future<void> _pickTag() async {
    final KemonoHandler handler = _handler ?? KemonoArtistsPage.handlerFor(widget.booru);
    final TagCatalogSource catalog = handler.tagCatalog;
    final TagCatalogNamespace? ns = catalog.namespaceFor(KemonoTagCatalog.tagKey);
    if (ns == null) return;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                SizedBox(width: 20, height: 20, child: BooruFavicon(widget.booru)),
                const SizedBox(width: 8),
                Text(
                  widget.booru.name ?? 'Kemono',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                ),
                const Spacer(),
                IconButton(icon: const Icon(Symbols.close_rounded), onPressed: widget.toggleDrawer),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const DrawerSectionLabel('ARTISTS'),
                DrawerRow(
                  icon: Symbols.person_search_rounded,
                  iconColor: const Color(0xFFB9A0E8),
                  label: 'Search',
                  onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru)),
                ),
                if (site.hasUpdatedArtists)
                  DrawerRow(
                    icon: Symbols.update_rounded,
                    iconColor: const Color(0xFFB9A0E8),
                    label: 'Recent',
                    onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru, mode: KemonoArtistsMode.recent)),
                  ),
                if (site.hasRandom)
                  DrawerRow(
                    icon: Symbols.shuffle_rounded,
                    iconColor: const Color(0xFFB9A0E8),
                    label: 'Random',
                    onTap: () => unawaited(_randomArtist()),
                  ),
                const SizedBox(height: 8),
                const DrawerSectionLabel('POSTS'),
                DrawerRow(
                  icon: Symbols.search_rounded,
                  iconColor: const Color(0xFF8FBFD4),
                  label: 'Search',
                  onTap: () {
                    widget.toggleDrawer();
                    unawaited(
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MainSearchQueryEditorPage())),
                    );
                  },
                ),
                if (site.hasPopular)
                  DrawerRow(
                    icon: Symbols.trending_up_rounded,
                    iconColor: const Color(0xFF8FBFD4),
                    label: 'Popular',
                    subtitle: 'today · popular:week / month for more',
                    onTap: () => _openTab('popular:day'),
                  ),
                if (site.hasTagList)
                  DrawerRow(
                    icon: Symbols.sell_rounded,
                    iconColor: const Color(0xFF8FBFD4),
                    label: 'Tags',
                    onTap: () => unawaited(_pickTag()),
                  ),
                if (site.hasRandom)
                  DrawerRow(
                    icon: Symbols.shuffle_rounded,
                    iconColor: const Color(0xFF8FBFD4),
                    label: 'Random',
                    onTap: () => _openTab('random'),
                  ),
                const SizedBox(height: 8),
                const DrawerSectionLabel('FAVORITES'),
                if (signedIn) ...[
                  DrawerRow(
                    icon: Symbols.favorite_rounded,
                    iconColor: const Color(0xFFF0708A),
                    label: 'Posts',
                    onTap: () => _openTab('favorites:posts'),
                  ),
                  DrawerRow(
                    icon: Symbols.artist_rounded,
                    iconColor: const Color(0xFFF0708A),
                    label: 'Artists',
                    onTap: () => _openPage(KemonoArtistsPage(booru: widget.booru, mode: KemonoArtistsMode.favourites)),
                  ),
                ] else
                  DrawerRow(
                    icon: Symbols.login_rounded,
                    iconColor: const Color(0xFFF0708A),
                    label: 'Sign in to use favorites',
                    subtitle: 'Username and password in the booru settings',
                    onTap: () => _openPage(BooruEdit(widget.booru)),
                  ),
                const SizedBox(height: 8),
                const DrawerSectionLabel('MESSAGES'),
                if (site.hasDms)
                  DrawerRow(
                    icon: Symbols.mail_rounded,
                    iconColor: const Color(0xFFE8C46B),
                    label: 'DMs',
                    onTap: () => _openPage(KemonoDmsPage(booru: widget.booru)),
                  ),
                DrawerRow(
                  icon: Symbols.campaign_rounded,
                  iconColor: const Color(0xFFE8C46B),
                  label: 'Announcements',
                  subtitle: creator == null ? 'Open a creator first' : null,
                  enabled: creator != null,
                  onTap: () => _openPage(
                    KemonoAnnouncementsPage(booru: widget.booru, service: creator!.service, id: creator.id),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _indexLine(index),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: index.error != null ? Colors.orange : theme.colorScheme.onSurfaceVariant),
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
          if (index.running) LinearProgressIndicator(value: index.progress, minHeight: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  hosts.summary(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: hosts.state.value.values.any((s) => !s.ok) ? Colors.orange : theme.colorScheme.onSurfaceVariant,
                  ),
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
          const SizedBox(height: 4),
          DrawerRow(
            icon: Symbols.swap_horiz_rounded,
            iconColor: theme.colorScheme.secondary,
            label: 'Use the app sidebar',
            subtitle: 'Pinned tags and quick access',
            onTap: _swapToAppSidebar,
          ),
        ],
      ),
    );
  }
}
