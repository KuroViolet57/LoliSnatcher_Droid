part of '../main_search_query_editor_page.dart';

/// The Tag builder card: one chip per namespace the current source can list
/// in full (`BooruHandler.tagCatalog`) — every artist, character, … the site
/// knows, most-used first, picked from a sheet instead of typed. Sits under
/// the Metatags card; absent when the source has no catalog. The lists live
/// in the database, so with it off the card says so instead of offering
/// pulls that would store nothing.
class TagBuilderBlock extends StatefulWidget {
  const TagBuilderBlock({
    required this.onInsertTerm,
    this.booru,
    super.key,
  });

  /// Where a picked term goes.
  final void Function(String term) onInsertTerm;

  /// The source to build for; null follows the current tab.
  final Booru? booru;

  @override
  State<TagBuilderBlock> createState() => _TagBuilderBlockState();
}

class _TagBuilderBlockState extends State<TagBuilderBlock> with _EditorSourceMixin {
  final scrollController = ScrollController();

  /// Rows stored per namespace for the source, the badge on each chip.
  Map<String, int> _counts = const {};
  String _countsFor = '';

  @override
  Booru? get ownBooru => widget.booru;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCounts());
  }

  @override
  void didUpdateWidget(covariant TagBuilderBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booru != widget.booru) unawaited(_refreshCounts());
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    final TagCatalogSource? catalog = sourceHandler.tagCatalog;
    final Booru booru = sourceBooru;
    final String key = BooruTagStore.keyFor(booru);
    final Map<String, int> counts = catalog == null ? const {} : await BooruTagStore.catalogCounts(booru, catalog);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _countsFor = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TagCatalogSource? catalog = sourceHandler.tagCatalog;
    if (catalog == null || catalog.namespaces.isEmpty) return const SizedBox.shrink();

    final Booru booru = sourceBooru;
    if (_countsFor != BooruTagStore.keyFor(booru)) {
      // The tab changed under an open editor: recount for the new source.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCounts());
    }
    final List<TagCatalogNamespace> namespaces = catalog.namespaces;

    return SearchSectionCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Symbols.category_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Tag builder', style: context.theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!SettingsHandler.instance.dbEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Turn on the database (Settings → Database) to use the tag builder: the lists it pulls are kept there.',
                style: context.theme.textTheme.bodySmall,
              ),
            )
          else
            SizedBox(
              height: 50,
              child: Listener(
                onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
                child: FadingEdgeScrollView.fromScrollView(
                  child: ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: namespaces.length,
                    itemBuilder: (BuildContext context, int index) {
                      final TagCatalogNamespace ns = namespaces[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TagCatalogChip(
                          booru: booru,
                          catalog: catalog,
                          namespace: ns,
                          count: _counts[ns.key] ?? 0,
                          onInsert: widget.onInsertTerm,
                          onStoredChanged: _refreshCounts,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
