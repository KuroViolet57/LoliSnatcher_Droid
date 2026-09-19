import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_pool.dart';
import 'package:lolisnatcher/src/handlers/pool_source.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// Browses the pools of the current booru.
///
/// Tap a pool to open it (switching to it); long-press to open it in the
/// background, the same gesture language the tag chips and previews use.
class PoolsPage extends StatefulWidget {
  const PoolsPage({super.key});

  @override
  State<PoolsPage> createState() => _PoolsPageState();
}

class _PoolsPageState extends State<PoolsPage> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final ScrollController _scrollController = ScrollController();

  late final Booru _booru = searchHandler.currentBooru;
  late final PoolSource? _source = PoolSource.forBooru(_booru);

  final List<BooruPool> _pools = [];
  int _page = 0;
  bool _loading = false;
  bool _isLastPage = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    final PoolSource? source = _source;
    if (_loading || _isLastPage || source == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final List<BooruPool> got = await source.fetchPools(_booru, _page);
      if (!mounted) return;
      setState(() {
        _pools.addAll(got);
        // The sources paginate in fixed steps; a short page is the last one.
        if (got.isEmpty || got.length < source.pageSize) _isLastPage = true;
        _page++;
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

  void _openPool(BooruPool pool, {required bool background}) {
    searchHandler.addTabByString(
      // Shown in the tab row; the actual fetching is driven by poolId.
      'pool: ${pool.displayName}',
      customBooru: _booru,
      switchToNew: !background,
      group: background ? SearchHandler.inheritGroup : null,
      poolId: pool.id,
      poolName: pool.displayName,
    );
    if (background) {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: Text('Opened "${pool.displayName}" in a new tab'),
        leadingIcon: Symbols.collections_bookmark_rounded,
        sideColor: Colors.green,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            BooruFavicon(_booru, size: 20),
            const SizedBox(width: 10),
            const Text('Pools'),
          ],
        ),
      ),
      body: Builder(
        builder: (context) {
          if (_source == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This booru has no pools.', textAlign: TextAlign.center),
              ),
            );
          }
          if (_pools.isEmpty && _loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_pools.isEmpty && _error.isNotEmpty) {
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
                      onPressed: _loadMore,
                      icon: const Icon(Symbols.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (_pools.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pools found on this booru.', textAlign: TextAlign.center),
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            itemCount: _pools.length + ((_loading || _error.isNotEmpty) ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _pools.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: _error.isNotEmpty
                        ? TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Symbols.refresh_rounded),
                            label: const Text('Retry'),
                          )
                        : const CircularProgressIndicator(),
                  ),
                );
              }

              final BooruPool pool = _pools[index];
              final List<String> subtitleParts = [
                if (pool.postCount != null) '${pool.postCount} posts',
                if (pool.creator?.isNotEmpty ?? false) 'by ${pool.creator}',
              ];
              return ListTile(
                leading: Icon(Symbols.collections_bookmark_rounded, color: theme.colorScheme.secondary),
                title: Text(
                  pool.displayName.isEmpty ? 'Pool ${pool.id}' : pool.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
                trailing: IconButton(
                  tooltip: 'Open in background tab',
                  icon: const Icon(Symbols.tab_new_right_rounded),
                  onPressed: () => _openPool(pool, background: true),
                ),
                onTap: () => _openPool(pool, background: false),
                onLongPress: () => _openPool(pool, background: true),
              );
            },
          );
        },
      ),
    );
  }
}
