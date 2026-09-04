import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_query.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

enum KemonoArtistsMode { all, recent, favourites }

/// The site's Artists page: every creator as a banner card, two to a row —
/// banner behind, avatar and name in front, service badge, favourites count
/// and the last update. Search by name, filter by service, sort by
/// popularity, update, indexing or name. The rows come from the local
/// creator index ([KemonoCreatorStore]); "Recent" and "Favourites" come from
/// the site live and are joined with the index for their counts.
///
/// Doubles as the tag builder's Artists picker ([pick]): the tapped card's
/// search term is returned instead of opened.
class KemonoArtistsPage extends StatefulWidget {
  const KemonoArtistsPage({
    required this.booru,
    this.mode = KemonoArtistsMode.all,
    this.asPicker = false,
    super.key,
  });

  final Booru booru;
  final KemonoArtistsMode mode;
  final bool asPicker;

  /// The tag builder's Artists chip: opens the page, returns `creator:…`.
  static Future<String?> pick(BuildContext context, Booru booru) => Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => KemonoArtistsPage(booru: booru, asPicker: true)),
  );

  /// The kemono handler of the current tab when it is this booru, else a
  /// throwaway one — the favourite keys live on the handler.
  static KemonoHandler handlerFor(Booru booru) {
    final SearchHandler search = SearchHandler.instance;
    if (search.tabs.isNotEmpty) {
      final current = search.currentBooruHandler;
      if (current is KemonoHandler && current.booru.baseURL == booru.baseURL) return current;
    }
    return BooruHandlerFactory().getBooruHandler([booru], null).booruHandler as KemonoHandler;
  }

  @override
  State<KemonoArtistsPage> createState() => _KemonoArtistsPageState();
}

class _KemonoArtistsPageState extends State<KemonoArtistsPage> {
  static const int _pageSize = 60;
  static const Map<String, String> sortLabels = {
    'favorited': 'Most favourited',
    'updated': 'Recently updated',
    'indexed': 'Recently added',
    'name': 'Name',
  };

  late final KemonoHandler _handler = KemonoArtistsPage.handlerFor(widget.booru);
  final KemonoCreatorStore _store = KemonoCreatorStore.instance;
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late KemonoArtistsMode _mode = widget.mode;
  final Set<String> _services = {};
  String _sort = 'favorited';
  final List<KemonoCreator> _rows = [];
  List<KemonoCreator> _live = const [];
  bool _loading = false;
  bool _lastPage = false;
  int _offset = 0;
  String? _liveError;
  Timer? _debounce;
  int _seenRefresh = -1;

  bool get _signedIn => KemonoSessionHandler.instance.hasSession(widget.booru);

  @override
  void initState() {
    super.initState();
    _store.state.addListener(_onIndexTick);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) unawaited(_loadMore());
    });
    unawaited(_store.ensureFresh());
    if (_signedIn) unawaited(_handler.loadFavouriteCreatorKeys().then((_) => _safeSetState()));
    unawaited(_reset());
  }

  @override
  void dispose() {
    _store.state.removeListener(_onIndexTick);
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _safeSetState() {
    if (mounted) setState(() {});
  }

  void _onIndexTick() {
    final state = _store.state.value;
    if (!state.running && state.refreshedAt != _seenRefresh) {
      _seenRefresh = state.refreshedAt;
      unawaited(_reset());
    } else {
      _safeSetState();
    }
  }

  Future<void> _reset() async {
    _offset = 0;
    _lastPage = false;
    _rows.clear();
    _liveError = null;
    if (_mode != KemonoArtistsMode.all) {
      await _loadLive();
    }
    await _loadMore();
  }

  /// "Recent" and "Favourites" come from the site; the index fills in the
  /// favourites count and the filter/sort are applied on the phone.
  Future<void> _loadLive() async {
    setState(() => _loading = true);
    try {
      final List rows = _mode == KemonoArtistsMode.recent
          ? await KemonoApi.updatedArtists(booru: widget.booru)
          : await KemonoApi.favourites(widget.booru, type: 'artist');
      final List<KemonoCreator> live = [
        for (final r in rows)
          if (r is Map) ?KemonoCreator.fromJson(r),
      ];
      final Map<String, KemonoCreator> indexed = {
        for (final c in await _store.search('', limit: live.length + 1, onlyKeys: {for (final c in live) c.key})) c.key: c,
      };
      _live = [
        for (final c in live)
          KemonoCreator(
            service: c.service,
            id: c.id,
            name: c.name.isNotEmpty ? c.name : (indexed[c.key]?.name ?? ''),
            indexed: c.indexed != 0 ? c.indexed : (indexed[c.key]?.indexed ?? 0),
            updated: c.updated != 0 ? c.updated : (indexed[c.key]?.updated ?? 0),
            favorited: c.favorited != 0 ? c.favorited : (indexed[c.key]?.favorited ?? 0),
          ),
      ];
      if (_mode == KemonoArtistsMode.favourites) {
        _handler.favouriteCreatorKeys
          ..clear()
          ..addAll(_live.map((c) => c.key));
      }
    } catch (e) {
      _live = const [];
      _liveError = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<KemonoCreator> _filteredLive() {
    final String q = _query.text.trim().toLowerCase();
    final List<KemonoCreator> out = [
      for (final c in _live)
        if ((q.isEmpty || c.name.toLowerCase().contains(q)) && (_services.isEmpty || _services.contains(c.service))) c,
    ];
    int cmp(KemonoCreator a, KemonoCreator b) => switch (_sort) {
      'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      'indexed' => b.indexed.compareTo(a.indexed),
      'updated' => b.updated.compareTo(a.updated),
      _ => b.favorited.compareTo(a.favorited),
    };
    out.sort(cmp);
    return out;
  }

  Future<void> _loadMore() async {
    if (_loading || _lastPage) return;
    setState(() => _loading = true);
    List<KemonoCreator> got;
    if (_mode == KemonoArtistsMode.all) {
      got = await _store.search(
        _query.text,
        services: _services,
        sort: _sort,
        limit: _pageSize,
        offset: _offset,
      );
    } else {
      got = _filteredLive();
      _lastPage = true;
    }
    if (!mounted) return;
    setState(() {
      _rows.addAll(got);
      _offset += got.length;
      if (got.length < _pageSize) _lastPage = true;
      _loading = false;
    });
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_reset());
    });
  }

  void _pick(KemonoCreator c) {
    if (widget.asPicker) {
      Navigator.of(context).pop(c.searchQuery);
      return;
    }
    SearchHandler.instance.addTabByString(c.searchQuery, customBooru: widget.booru, switchToNew: true);
    Navigator.of(context).pop();
  }

  Future<void> _toggleFavourite(KemonoCreator c) async {
    if (!_signedIn) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Sign in to favourite artists'),
        content: const Text('Enter your kemono username and password in the booru settings.'),
        sideColor: Colors.orange,
      );
      return;
    }
    final bool now = !_handler.favouriteCreatorKeys.contains(c.key);
    final (bool ok, String message) = await _handler.setCreatorFavourite(c.service, c.id, now);
    if (!mounted) return;
    setState(() {});
    FlashElements.showSnackbar(
      context: context,
      title: Text(ok ? (now ? 'Favourited ${c.name}' : 'Unfavourited ${c.name}') : 'kemono did not accept that'),
      content: Text(message),
      sideColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    );
  }

  String _indexLine(KemonoIndexState s) {
    if (s.running) {
      return s.total == 0
          ? 'Downloading the creator index…'
          : 'Storing ${s.inserted.toShortString()} / ${s.total.toShortString()} creators';
    }
    if (s.error != null) return 'Index refresh failed: ${s.error}';
    if (s.count == 0) return 'No creator index yet';
    final int age = DateTime.now().millisecondsSinceEpoch - s.refreshedAt;
    final String ago = age < 3600000 ? '${age ~/ 60000} min ago' : '${age ~/ 3600000} h ago';
    return '${s.count.toShortString()} creators · refreshed $ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.asPicker
              ? 'Pick an artist'
              : switch (_mode) {
                  KemonoArtistsMode.all => 'Artists',
                  KemonoArtistsMode.recent => 'Recently updated artists',
                  KemonoArtistsMode.favourites => 'Favourite artists',
                },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Symbols.sort_rounded),
            tooltip: 'Sort',
            onSelected: (v) {
              setState(() => _sort = v);
              unawaited(_reset());
            },
            itemBuilder: (_) => [
              for (final e in sortLabels.entries)
                CheckedPopupMenuItem(value: e.key, checked: _sort == e.key, child: Text(e.value)),
            ],
          ),
          ValueListenableBuilder<KemonoIndexState>(
            valueListenable: _store.state,
            builder: (context, s, _) => IconButton(
              tooltip: 'Refresh the creator index',
              icon: s.running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Symbols.refresh_rounded),
              onPressed: s.running ? null : () => unawaited(_store.refresh()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _store.refresh();
          await _reset();
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: ValueListenableBuilder<KemonoIndexState>(
                valueListenable: _store.state,
                builder: (context, s, _) => Column(
                  children: [
                    if (s.running) LinearProgressIndicator(value: s.progress),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                        _indexLine(s),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: s.error != null ? Colors.orange : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _query,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Symbols.search_rounded),
                    hintText: 'Search artists by name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    if (!widget.asPicker) ...[
                      for (final m in KemonoArtistsMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(switch (m) {
                              KemonoArtistsMode.all => 'All',
                              KemonoArtistsMode.recent => 'Recent',
                              KemonoArtistsMode.favourites => 'Favourites',
                            }),
                            selected: _mode == m,
                            onSelected: (m == KemonoArtistsMode.favourites && !_signedIn)
                                ? null
                                : (_) {
                                    setState(() => _mode = m);
                                    unawaited(_reset());
                                  },
                          ),
                        ),
                      const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                    ],
                    for (final s in KemonoQuery.services)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s),
                          selected: _services.contains(s),
                          onSelected: (on) {
                            setState(() => on ? _services.add(s) : _services.remove(s));
                            unawaited(_reset());
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_liveError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_liveError!, style: const TextStyle(color: Colors.orange)),
                ),
              ),
            if (_rows.isEmpty && !_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      _mode == KemonoArtistsMode.all && _store.state.value.count == 0
                          ? 'The creator index is empty. Pull down to download it.'
                          : 'No artists match.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 90),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.45,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final c = _rows[index];
                    return KemonoCreatorCard(
                      creator: c,
                      favourite: _handler.favouriteCreatorKeys.contains(c.key),
                      showHeart: _signedIn,
                      onTap: () => _pick(c),
                      onFavourite: () => unawaited(_toggleFavourite(c)),
                    );
                  },
                  childCount: _rows.length,
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              ),
          ],
        ),
      ),
    );
  }
}

/// One creator: the banner as the card, avatar and name over it.
class KemonoCreatorCard extends StatelessWidget {
  const KemonoCreatorCard({
    required this.creator,
    required this.onTap,
    this.favourite = false,
    this.showHeart = false,
    this.onFavourite,
    super.key,
  });

  final KemonoCreator creator;
  final bool favourite;
  final bool showHeart;
  final VoidCallback onTap;
  final VoidCallback? onFavourite;

  static const Map<String, String> serviceInitials = {
    'patreon': 'Patreon',
    'fanbox': 'Fanbox',
    'gumroad': 'Gumroad',
    'discord': 'Discord',
    'fantia': 'Fantia',
    'boosty': 'Boosty',
    'subscribestar': 'SubscribeStar',
    'dlsite': 'DLsite',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String updated = creator.updated == 0 ? '' : DateFormat.yMMMd().format(creator.updatedAt);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        child: InkWell(
          onTap: onTap,
          onLongPress: onFavourite,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                creator.bannerUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primaryContainer, theme.colorScheme.surfaceContainerHighest],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              // Scrim so the name reads over any banner.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0x33000000), Color(0xCC000000)],
                    stops: [0, 0.5, 1],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xAA000000),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    serviceInitials[creator.service] ?? creator.service,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
              if (showHeart)
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    onPressed: onFavourite,
                    icon: Icon(
                      favourite ? Symbols.favorite_rounded : Symbols.favorite_border_rounded,
                      fill: favourite ? 1 : 0,
                      color: favourite ? const Color(0xFFF0708A) : Colors.white,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      foregroundImage: NetworkImage(creator.iconUrl),
                      onForegroundImageError: (_, _) {},
                      child: Text(
                        creator.name.isNotEmpty ? creator.name.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            creator.name.isEmpty ? '${creator.service}:${creator.id}' : creator.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          Row(
                            children: [
                              const Icon(Symbols.favorite_rounded, size: 11, color: Color(0xFFF0708A), fill: 1),
                              const SizedBox(width: 3),
                              Text(
                                creator.favorited.toShortString(),
                                style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w600),
                              ),
                              if (updated.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    updated,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
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
}

/// A creator's own tags (`/api/v1/{service}/user/{id}/tags`), live, with a
/// filter box; pops `tag:name`. The tag builder's third chip on creator tabs.
class KemonoCreatorTagsSheet extends StatefulWidget {
  const KemonoCreatorTagsSheet({
    required this.booru,
    required this.service,
    required this.id,
    this.scrollController,
    super.key,
  });

  final Booru booru;
  final String service;
  final String id;
  final ScrollController? scrollController;

  /// The picker entry point: the creator of the current tab.
  static Future<String?> pick(BuildContext context, Booru booru) async {
    final handler = SearchHandler.instance.tabs.isNotEmpty ? SearchHandler.instance.currentBooruHandler : null;
    final creator = handler is KemonoHandler ? handler.currentCreator : null;
    if (creator == null) return null;
    final res = await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      bottomSheetExpandableByScroll: true,
      page: (scrollController) => KemonoCreatorTagsSheet(
        booru: booru,
        service: creator.service,
        id: creator.id,
        scrollController: scrollController,
      ),
    ).open();
    return res is String ? res : null;
  }

  @override
  State<KemonoCreatorTagsSheet> createState() => _KemonoCreatorTagsSheetState();
}

class _KemonoCreatorTagsSheetState extends State<KemonoCreatorTagsSheet> {
  final TextEditingController _query = TextEditingController();
  List<({String tag, int count})> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await KemonoApi.creatorTags(widget.service, widget.id, booru: widget.booru);
      _all = [
        for (final r in rows)
          if (r is Map && (r['tag']?.toString().isNotEmpty ?? false))
            (tag: r['tag'].toString(), count: int.tryParse(r['post_count']?.toString() ?? '') ?? 0),
      ];
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String q = _query.text.trim().toLowerCase();
    final rows = [
      for (final t in _all)
        if (q.isEmpty || t.tag.toLowerCase().contains(q)) t,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Symbols.sell_rounded),
          title: const Text("This creator's tags", style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            _loading ? 'Loading…' : (_error ?? '${_all.length} tags'),
            style: TextStyle(fontSize: 11.5, color: _error != null ? Colors.orange : theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Symbols.search_rounded),
              hintText: 'Filter tags',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Flexible(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(_loading ? 'Loading…' : 'Nothing matches')),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final t = rows[index];
                    return ListTile(
                      dense: true,
                      title: Text(t.tag),
                      trailing: Text(t.count.toShortString(), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () => Navigator.of(context).pop('tag:${t.tag.replaceAll(' ', '_')}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
