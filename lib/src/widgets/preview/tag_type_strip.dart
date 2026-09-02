import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_puller.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/desktop/desktop_scroll.dart';

/// The tag builder: one chip per namespace the current source can list in
/// full (see `BooruHandler.tagCatalog`). Sits above the search input, always.
/// Tapping a chip opens [TagCatalogPickerSheet]; the term it returns goes to
/// [onInsert]. Nothing for sources with no catalog.
class TagTypeStrip extends StatefulWidget {
  const TagTypeStrip({required this.onInsert, this.booru, super.key});

  /// The source to build for; null follows the current tab.
  final Booru? booru;
  final void Function(String term) onInsert;

  @override
  State<TagTypeStrip> createState() => _TagTypeStripState();
}

class _TagTypeStripState extends State<TagTypeStrip> {
  final ScrollController _scroll = ScrollController();
  Map<String, int> _counts = const {};

  Booru get _booru => widget.booru ?? SearchHandler.instance.currentBooru;

  BooruHandler get _handler => widget.booru == null
      ? SearchHandler.instance.currentBooruHandler
      : BooruHandlerFactory().getBooruHandler([widget.booru!], null).booruHandler;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCounts());
  }

  @override
  void didUpdateWidget(covariant TagTypeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booru != widget.booru) unawaited(_refreshCounts());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    if (_handler.tagCatalog == null) return;
    final counts = await BooruTagStore.namespaceCounts(_booru);
    if (mounted) setState(() => _counts = counts);
  }

  Future<void> _open(TagCatalogSource catalog, TagCatalogNamespace ns) async {
    final Booru booru = _booru;
    final res = await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      bottomSheetExpandableByScroll: true,
      page: (scrollController) =>
          TagCatalogPickerSheet(booru: booru, catalog: catalog, namespace: ns, scrollController: scrollController),
    ).open();
    unawaited(_refreshCounts());
    if (res is String && res.isNotEmpty) widget.onInsert(res);
  }

  @override
  Widget build(BuildContext context) {
    final TagCatalogSource? catalog = _handler.tagCatalog;
    if (catalog == null || catalog.namespaces.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final Booru booru = _booru;

    return SizedBox(
      height: 46,
      child: Listener(
        onPointerSignal: (event) => desktopPointerScroll(_scroll, event),
        child: FadingEdgeScrollView.fromScrollView(
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: catalog.namespaces.length,
            itemBuilder: (context, index) {
              final ns = catalog.namespaces[index];
              final int count = _counts[ns.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ValueListenableBuilder<TagCatalogPullState>(
                  valueListenable: TagCatalogPuller.instance.stateFor(booru, catalog, ns.key),
                  builder: (context, state, _) {
                    if (!state.running && state.stored > 0 && count == 0) {
                      // A pull finished while this strip was on screen.
                      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCounts());
                    }
                    return ActionChip(
                      key: ValueKey('tag-type-${ns.key}'),
                      visualDensity: VisualDensity.compact,
                      avatar: state.running
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ns.type.getColour() ?? theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(ns.label),
                          const SizedBox(width: 5),
                          if (count > 0)
                            Text(
                              count.toShortString(),
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            )
                          else
                            Icon(Symbols.download_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                      onPressed: () => _open(catalog, ns),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Every tag of one namespace on one source, from the local snapshot,
/// filter-as-you-type. Opens a paced pull by itself when the snapshot holds
/// nothing for the namespace yet; rows appear as shards land, and closing
/// the sheet does not stop the pull. Pops the search term of the tapped
/// row (long-press: negated).
class TagCatalogPickerSheet extends StatefulWidget {
  const TagCatalogPickerSheet({
    required this.booru,
    required this.catalog,
    required this.namespace,
    this.scrollController,
    super.key,
  });

  final Booru booru;
  final TagCatalogSource catalog;
  final TagCatalogNamespace namespace;

  /// The sheet's own controller when opened expandable-by-scroll.
  final ScrollController? scrollController;

  @override
  State<TagCatalogPickerSheet> createState() => _TagCatalogPickerSheetState();
}

class _TagCatalogPickerSheetState extends State<TagCatalogPickerSheet> {
  static const int _pageSize = 60;

  final TextEditingController _query = TextEditingController();
  late final ScrollController _scroll = widget.scrollController ?? ScrollController();
  final List<BooruTagEntry> _rows = [];
  Timer? _debounce;
  bool _loading = false;
  bool _lastPage = false;
  int _offset = 0;
  int _total = 0;
  int _seenStored = -1;

  ValueNotifier<TagCatalogPullState> get _pull =>
      TagCatalogPuller.instance.stateFor(widget.booru, widget.catalog, widget.namespace.key);

  @override
  void initState() {
    super.initState();
    _pull.addListener(_onPullTick);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) unawaited(_loadMore());
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _pull.removeListener(_onPullTick);
    _debounce?.cancel();
    _query.dispose();
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _total = await BooruTagStore.snapshotSize(widget.booru, namespace: widget.namespace.key);
    if (!mounted) return;
    if (_total == 0 && !_pull.value.running) {
      unawaited(TagCatalogPuller.instance.pull(widget.booru, widget.catalog, widget.namespace.key));
    }
    await _reset();
  }

  /// A shard landed: reload the visible page so new rows show up.
  void _onPullTick() {
    final state = _pull.value;
    if (!mounted) return;
    if (state.stored != _seenStored) {
      _seenStored = state.stored;
      unawaited(_reset());
    } else {
      setState(() {});
    }
  }

  Future<void> _reset() async {
    _offset = 0;
    _lastPage = false;
    _rows.clear();
    _total = await BooruTagStore.snapshotSize(widget.booru, namespace: widget.namespace.key);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _lastPage) return;
    setState(() => _loading = true);
    final got = await BooruTagStore.browse(
      widget.booru,
      namespace: widget.namespace.key,
      query: _query.text,
      limit: _pageSize,
      offset: _offset,
    );
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

  Future<void> _repull() async {
    TagCatalogPuller.instance.resetResume(widget.booru, widget.catalog, widget.namespace.key);
    await BooruTagStore.clearSnapshot(widget.booru, namespace: widget.namespace.key);
    unawaited(TagCatalogPuller.instance.pull(widget.booru, widget.catalog, widget.namespace.key));
    await _reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _pull.value;
    final String host = BooruTagStore.keyFor(widget.booru);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.namespace.type.getColour() ?? theme.colorScheme.onSurfaceVariant),
          ),
          title: Text('${widget.namespace.label} on $host', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            state.running
                ? 'Pulling… ${state.shards == null ? '${state.shard} done' : '${state.shard} / ${state.shards}'} · ${state.stored.toShortString()} stored'
                : state.error != null
                    ? 'Stopped after ${state.stored.toShortString()} — ${state.error}'
                    : '${_total.toShortString()} in the local list${state.done ? '' : (_total > 0 ? ' (partial — pull again to go deeper)' : '')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: state.error != null ? Colors.orange : theme.colorScheme.onSurfaceVariant),
          ),
          trailing: state.running
              ? TextButton(
                  onPressed: () => TagCatalogPuller.instance.cancel(widget.booru, widget.catalog, widget.namespace.key),
                  child: const Text('Stop'),
                )
              : PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'resume') unawaited(TagCatalogPuller.instance.pull(widget.booru, widget.catalog, widget.namespace.key));
                    if (v == 'repull') unawaited(_repull());
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'resume', child: Text('Pull more / retry')),
                    PopupMenuItem(value: 'repull', child: Text('Clear and pull again')),
                  ],
                ),
        ),
        if (state.running) LinearProgressIndicator(value: state.progress),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Symbols.search_rounded),
              hintText: 'Filter ${widget.namespace.label.toLowerCase()}',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Flexible(
          child: _rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      state.running
                          ? 'Waiting for the first shard…'
                          : _query.text.isNotEmpty
                              ? 'Nothing matches'
                              : state.error != null
                                  ? 'Nothing stored yet — use the menu to retry'
                                  : 'Nothing listed',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: _rows.length + (_loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _rows.length) {
                      return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                    }
                    final e = _rows[index];
                    final String term = widget.catalog.searchTerm(e);
                    return ListTile(
                      dense: true,
                      title: Text(e.displayName),
                      trailing: e.count > 0
                          ? Text(e.count.toShortString(), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant))
                          : null,
                      onTap: () => Navigator.of(context).pop(term),
                      onLongPress: () => Navigator.of(context).pop('-$term'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
