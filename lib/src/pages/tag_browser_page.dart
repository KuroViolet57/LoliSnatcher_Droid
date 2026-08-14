import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// Browse a booru's tag database, and fix what it gets wrong.
///
/// One page, two jobs, on purpose: the rows already have to show whether a
/// type is this site's own answer or a guess borrowed from elsewhere, and
/// that is exactly the moment you want to correct one — a separate management
/// screen would be the same list with fewer affordances. The "Yours" filter
/// turns the same list into the corrections manager.
///
/// Where the rows come from:
///   * the local snapshot (per-booru table), filled by browsing, by tag
///     lookups the app already makes, by a manual index pull, or by importing
///     a snapshot file;
///   * plus a live search against the site when you type something the
///     snapshot has never seen.
class TagBrowserPage extends StatefulWidget {
  const TagBrowserPage({super.key});

  @override
  State<TagBrowserPage> createState() => _TagBrowserPageState();
}

class _TagBrowserPageState extends State<TagBrowserPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  /// Defaults to the booru you are looking at — unless that is a virtual feed
  /// (Favourites, For You, History), which has no tag database of its own and
  /// is filtered out of [_boorus], so the dropdown would have no matching
  /// entry for it.
  ///
  /// Only read once [_boorus] is known to be non-empty — both entry points
  /// ([initState] and [build]) bail out before touching it otherwise.
  late Booru _booru = _pickInitialBooru();

  Booru _pickInitialBooru() {
    final List<Booru> boorus = _boorus;
    if (searchHandler.tabs.isNotEmpty && boorus.contains(searchHandler.currentBooru)) {
      return searchHandler.currentBooru;
    }
    return boorus.first;
  }

  TagType? _typeFilter;
  bool _onlyMine = false;
  String _query = '';

  final List<BooruTagEntry> _rows = [];
  int _offset = 0;
  bool _loading = false;
  bool _isLastPage = false;
  String _error = '';

  int _snapshotSize = 0;

  // Index pull state.
  bool _pulling = false;
  bool _cancelPull = false;
  int _pulled = 0;

  /// Deepest index page reached per booru, so a pull that got cut short can
  /// pick up instead of re-walking what it already has.
  static final Map<String, int> _resumePage = {};

  static const int _pageSize = 60;

  List<Booru> get _boorus => settingsHandler.booruList
      .where((b) => b.type != null && !b.type!.isLocalDb && !b.type!.isForYou && !b.type!.isMerge)
      .toList();

  TagIndexSource? get _source => TagIndexSource.forBooru(_booru);

  @override
  void initState() {
    super.initState();
    if (_boorus.isEmpty) return;
    _scrollController.addListener(() {
      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _reset();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _rows.clear();
      _offset = 0;
      _isLastPage = false;
      _error = '';
    });
    _refreshSnapshotSize();
    _loadMore();
  }

  Future<void> _refreshSnapshotSize() async {
    final int size = await BooruTagStore.snapshotSize(_booru);
    if (mounted) setState(() => _snapshotSize = size);
  }

  /// Rows for the "Yours" filter come straight from the in-memory correction
  /// map — a corrected tag does not need to exist in the snapshot at all.
  List<BooruTagEntry> _mineRows() {
    final Map<String, TagType> mine = BooruTagStore.manualFor(_booru);
    final String q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final entries = [
      for (final e in mine.entries)
        if (q.isEmpty || e.key.contains(q))
          if (_typeFilter == null || e.value == _typeFilter)
            BooruTagEntry(name: e.key, tagType: e.value, origin: TagTypeOrigin.manual),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  Future<void> _loadMore() async {
    if (_loading || _isLastPage) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      if (_onlyMine) {
        final all = _mineRows();
        if (!mounted) return;
        setState(() {
          _rows
            ..clear()
            ..addAll(all);
          _isLastPage = true;
          _loading = false;
        });
        return;
      }

      List<BooruTagEntry> got = await BooruTagStore.browse(
        _booru,
        query: _query,
        type: _typeFilter,
        limit: _pageSize,
        offset: _offset,
      );

      // Nothing locally for a typed query? Ask the site itself, store what it
      // says, and show that instead of an empty page.
      if (got.isEmpty && _offset == 0 && _query.trim().isNotEmpty) {
        final TagIndexSource? source = _source;
        if (source != null) {
          final remote = await source.search(_booru, _query);
          if (remote.isNotEmpty) {
            await BooruTagStore.record(_booru, remote);
            unawaited(_refreshSnapshotSize());
            got = await BooruTagStore.browse(
              _booru,
              query: _query,
              type: _typeFilter,
              limit: _pageSize,
              offset: 0,
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rows.addAll(got);
        _offset += got.length;
        if (got.length < _pageSize) _isLastPage = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _query = value;
      _reset();
    });
  }

  // ───────────────────────────── actions ─────────────────────────────

  Future<void> _pullIndex() async {
    final TagIndexSource? source = _source;
    if (source == null || _pulling) return;
    setState(() {
      _pulling = true;
      _cancelPull = false;
      _pulled = 0;
    });

    // Resume where the last attempt stopped: a rate-limited pull is expected
    // to be run more than once, and starting over from `female` every time
    // would never get any deeper.
    int page = _resumePage[BooruTagStore.keyFor(_booru)] ?? 0;
    try {
      // Bounded: a full booru tag database is millions of rows and nobody
      // wants that on a phone. Each source sets its own depth from how big
      // its pages are and how well ordered they arrive.
      final int maxPages = source.maxIndexPages;
      while (page < maxPages && !_cancelPull) {
        final List<BooruTagEntry> got = await source.pageAt(_booru, page);
        if (got.isEmpty) break;
        final int written = await BooruTagStore.record(_booru, got);
        if (!mounted) return;
        setState(() => _pulled += written);
        if (got.length < source.pageSize) break;
        page++;
        _resumePage[BooruTagStore.keyFor(_booru)] = page;
        // Sites rate-limit sustained walks: scraping rule34.xxx's tag list
        // back to back started returning 429 at around page 190. Pacing it
        // costs a couple of minutes and keeps the pull from being cut off.
        await Future.delayed(const Duration(milliseconds: 350));
      }
    } catch (e) {
      // Whatever was stored before the failure is already saved and useful,
      // so this is a "stopped early", not a "failed".
      if (mounted) {
        FlashElements.showSnackbar(
          context: context,
          title: Text(_pulled > 0 ? 'Stopped after $_pulled tags' : 'Tag index pull failed'),
          content: Text(
            _pulled > 0
                ? 'The site stopped answering (usually rate limiting). What was fetched is saved — '
                      'run it again later to go deeper.\n$e'
                : e.toString(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          leadingIcon: Symbols.error_rounded,
          sideColor: _pulled > 0 ? Colors.orange : Colors.red,
        );
      }
    }

    if (!mounted) return;
    setState(() => _pulling = false);
    await _refreshSnapshotSize();
    _reset();
  }

  Future<void> _setType(BooruTagEntry row) async {
    final (TagType current, _) = BooruTagStore.resolve(row.name, _booru, snapshotRow: row);
    final bool hasCorrection = BooruTagStore.isManual(row.name, _booru);

    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Setting a type here applies to ${_booru.name ?? BooruTagStore.keyFor(_booru)} only, '
                'and stops this tag being re-typed automatically on that booru.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final type in TagType.values)
              InkWell(
                onTap: () => Navigator.of(context).pop(type),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Icon(
                        type == current
                            ? Symbols.radio_button_checked_rounded
                            : Symbols.radio_button_unchecked_rounded,
                        size: 18,
                        color: type == current
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: type.getColour() ?? Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(type.locName),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          if (hasCorrection)
            TextButton(
              onPressed: () => Navigator.of(context).pop('clear'),
              child: const Text('Remove correction'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result == 'clear') {
      await BooruTagStore.clearManualType(_booru, row.name);
    } else if (result is TagType) {
      await BooruTagStore.setManualType(_booru, row.name, result);
    }
    if (mounted) _reset();
  }

  void _openTag(BooruTagEntry row, {required bool background}) {
    searchHandler.addTabByString(
      row.name,
      customBooru: _booru,
      switchToNew: !background,
      group: background ? SearchHandler.inheritGroup : null,
    );
    if (background) {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: Text('Opened "${row.displayName}" in a new tab'),
        leadingIcon: Symbols.tab_new_right_rounded,
        sideColor: Colors.green,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  String get _snapshotFileName => 'tagsnapshot-${BooruTagStore.keyFor(_booru)}.json';

  Future<void> _exportSnapshot() async {
    final String path = settingsHandler.backupPath;
    if (path.isEmpty) {
      _toast('Set a backup folder first (Settings → Backup & Restore).', error: true);
      return;
    }
    // Export the whole stored snapshot, not just what is on screen.
    final List<BooruTagEntry> all = [];
    int offset = 0;
    while (true) {
      final page = await BooruTagStore.browse(_booru, limit: 500, offset: offset);
      if (page.isEmpty) break;
      all.addAll(page);
      offset += page.length;
      if (page.length < 500) break;
    }
    if (all.isEmpty) {
      _toast('Nothing stored for this booru yet.', error: true);
      return;
    }
    try {
      await ServiceHandler.writeImage(
        utf8.encode(BooruTagStore.exportJson(_booru, all)),
        _snapshotFileName.replaceAll('.json', ''),
        'text',
        'json',
        path,
      );
      _toast('Exported ${all.length} tags to $_snapshotFileName');
    } catch (e) {
      _toast('Export failed: $e', error: true);
    }
  }

  Future<void> _importSnapshotFile() async {
    final String path = settingsHandler.backupPath;
    if (path.isEmpty) {
      _toast('Set a backup folder first (Settings → Backup & Restore).', error: true);
      return;
    }
    try {
      final bytes = await ServiceHandler.getFileFromSAFDirectory(path, _snapshotFileName);
      if (bytes == null) {
        _toast('No $_snapshotFileName in the backup folder.', error: true);
        return;
      }
      final (int count, String? warning) = await BooruTagStore.importJson(_booru, utf8.decode(bytes));
      _toast(count == 0 ? (warning ?? 'Nothing imported.') : 'Imported $count tags. ${warning ?? ''}'.trim());
      await _refreshSnapshotSize();
      if (mounted) _reset();
    } catch (e) {
      _toast('Import failed: $e', error: true);
    }
  }

  Future<void> _importSnapshotUrl() async {
    final controller = TextEditingController();
    final String? url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import snapshot from URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Any URL serving a snapshot file exported from this screen. '
              'Rows land under ${BooruTagStore.keyFor(_booru)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'https://…', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    _toast('Downloading…');
    final (int count, String? warning) = await BooruTagStore.importFromUrl(_booru, url);
    _toast(count == 0 ? (warning ?? 'Nothing imported.') : 'Imported $count tags. ${warning ?? ''}'.trim());
    await _refreshSnapshotSize();
    if (mounted) _reset();
  }

  Future<void> _confirmAndRun(String title, String body, Future<void> Function() action) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    await action();
    await _refreshSnapshotSize();
    if (mounted) _reset();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 3),
      title: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      leadingIcon: error ? Symbols.error_rounded : Symbols.check_circle_rounded,
      sideColor: error ? Colors.red : Colors.green,
    );
  }

  // ───────────────────────────── layout ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boorus = _boorus;

    if (boorus.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tag browser')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('Add a booru first — tags belong to a site.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag browser'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Symbols.more_vert_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'pull':
                  await _pullIndex();
                case 'export':
                  await _exportSnapshot();
                case 'import':
                  await _importSnapshotFile();
                case 'url':
                  await _importSnapshotUrl();
                case 'clearSnapshot':
                  await _confirmAndRun(
                    'Clear stored tags?',
                    "Removes the local copy of this booru's tag list. Your own corrections are kept.",
                    () => BooruTagStore.clearSnapshot(_booru),
                  );
                case 'clearMine':
                  await _confirmAndRun(
                    'Remove your corrections?',
                    'Deletes every type you set by hand on ${_booru.name ?? ''}. '
                        'Those tags become eligible for automatic typing again.',
                    () => BooruTagStore.clearAllManual(_booru),
                  );
              }
            },
            itemBuilder: (context) => [
              if (_source != null)
                const PopupMenuItem(
                  value: 'pull',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Symbols.cloud_download_rounded),
                    title: Text('Pull tag index'),
                  ),
                ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Symbols.folder_open_rounded),
                  title: Text('Import snapshot (backup folder)'),
                ),
              ),
              const PopupMenuItem(
                value: 'url',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Symbols.link_rounded),
                  title: Text('Import snapshot from URL'),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Symbols.save_rounded),
                  title: Text('Export snapshot'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clearSnapshot',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Symbols.delete_sweep_rounded),
                  title: Text('Clear stored tags'),
                ),
              ),
              const PopupMenuItem(
                value: 'clearMine',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Symbols.restart_alt_rounded),
                  title: Text('Remove my corrections'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (boorus.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                height: 52,
                child: SettingsBooruDropdown(
                  value: _booru,
                  items: boorus,
                  onChanged: (Booru? value) {
                    if (value == null) return;
                    setState(() => _booru = value);
                    _reset();
                  },
                  title: 'Booru',
                  contentPadding: EdgeInsets.zero,
                  titleAsLabel: true,
                  drawBottomBorder: false,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search tags on ${_booru.name ?? ''}',
                prefixIcon: const Icon(Symbols.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Symbols.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _query = '';
                          _reset();
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          _buildFilters(theme),
          _buildStatusLine(theme),
          Expanded(child: _buildList(theme)),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // The corrections manager, as a filter rather than a second screen.
          FilterChip(
            label: const Text('Yours'),
            avatar: Icon(
              Symbols.edit_rounded,
              size: 16,
              color: _onlyMine ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurfaceVariant,
            ),
            selected: _onlyMine,
            onSelected: (v) {
              setState(() => _onlyMine = v);
              _reset();
            },
          ),
          const SizedBox(width: 10),
          Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 10), color: theme.dividerColor),
          const SizedBox(width: 10),
          _typeChip(theme, null, 'All'),
          for (final type in TagType.values) ...[
            const SizedBox(width: 6),
            _typeChip(theme, type, type.locName),
          ],
        ],
      ),
    );
  }

  Widget _typeChip(ThemeData theme, TagType? type, String label) {
    final bool selected = _typeFilter == type;
    final Color? color = type?.getColour();
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      avatar: color == null
          ? null
          : Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      onSelected: (_) {
        setState(() => _typeFilter = selected ? null : type);
        _reset();
      },
    );
  }

  Widget _buildStatusLine(ThemeData theme) {
    final TagIndexSource? source = _source;
    final String stored = _snapshotSize == 1 ? '1 tag stored' : '$_snapshotSize tags stored';
    final int mine = BooruTagStore.manualFor(_booru).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 6),
      child: Row(
        children: [
          BooruFavicon(_booru, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pulling
                  ? 'Pulling tag index… $_pulled stored'
                  : '$stored${mine > 0 ? ' · $mine corrected' : ''}'
                        '${source == null ? ' · no tag index on this site' : ''}',
              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_pulling)
            TextButton(
              onPressed: () => setState(() => _cancelPull = true),
              child: const Text('Stop'),
            )
          else if (source != null && _snapshotSize == 0)
            TextButton.icon(
              onPressed: _pullIndex,
              icon: const Icon(Symbols.cloud_download_rounded, size: 16),
              label: const Text('Pull index'),
            ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty && _error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.error_rounded, size: 42),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Symbols.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _onlyMine
                ? 'You have not corrected any tag types on this booru yet.\n\n'
                      'Long-press a tag here — or double-tap one in a post — to set its type.'
                : _query.trim().isEmpty
                ? 'No tags stored for this booru yet.\n\n'
                      "Browse a few posts to collect them as you go, pull the site's tag index, "
                      'or import a snapshot from the menu.'
                : 'Nothing matches "$_query" here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _rows.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _TagRowTile(
          key: ValueKey('${BooruTagStore.keyFor(_booru)}/${_rows[index].name}'),
          entry: _rows[index],
          booru: _booru,
          onTap: () => _openTag(_rows[index], background: false),
          onLongPress: () => _setType(_rows[index]),
          onOpenBackground: () => _openTag(_rows[index], background: true),
        );
      },
    );
  }
}

/// One tag row.
///
/// The border carries the point of the whole screen: solid means this booru
/// said so itself, dashed means the type was borrowed from somewhere else and
/// might be wrong here, and a thick accent border means you set it and it is
/// never going to be overwritten.
class _TagRowTile extends StatelessWidget {
  const _TagRowTile({
    required this.entry,
    required this.booru,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenBackground,
    super.key,
  });

  final BooruTagEntry entry;
  final Booru booru;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (TagType type, TagTypeOrigin origin) = BooruTagStore.resolve(
      entry.name,
      booru,
      snapshotRow: entry,
    );
    final Color accent = type.getColour() ?? theme.colorScheme.onSurfaceVariant;

    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: type.isNone ? Colors.transparent : accent,
              border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      type.isNone ? 'general' : type.locName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${origin.label}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (entry.count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${_formatCount(entry.count)}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (origin.isManual)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Symbols.lock_rounded, size: 15, color: theme.colorScheme.secondary),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Open in background tab',
            icon: const Icon(Symbols.tab_new_right_rounded, size: 20),
            onPressed: onOpenBackground,
          ),
        ],
      ),
    );

    final BorderRadius radius = BorderRadius.circular(12);
    final Widget body = Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: origin.isInferred
          ? CustomPaint(
              painter: _DashedBorderPainter(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                radius: 12,
              ),
              child: body,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: origin.isManual
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.outlineVariant,
                  width: origin.isManual ? 1.8 : 1,
                ),
              ),
              child: body,
            ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

/// Dashed rounded outline — the "this is a guess" marker.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const double dash = 5;
    const double gap = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
