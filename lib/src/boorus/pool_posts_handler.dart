import 'dart:async';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_pool.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/pool_source.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Serves one pool's posts as an ordinary post feed.
///
/// A pool tab is a normal grid — viewer, snatcher, favourites and blacklist
/// all behave as usual — because this produces the same [BooruItem]s the
/// site's own handler would, by delegating to it.
///
/// Three strategies, picked from what the site actually supports:
///   * the site has a pool metatag that ALREADY returns pool order
///     (danbooru `ordpool:`, philomena `gallery_id:`) -> just delegate,
///     page for page;
///   * the site has a pool metatag but returns date order (e621 `pool:`) ->
///     resolve the ordered ids, pull the members, reorder to match;
///   * the site has no pool filter at all (gelbooru family) -> scrape the
///     ordered ids and fetch each post by id.
/// In every case pool ORDER is preserved: comics depend on it.
class PoolPostsHandler extends BooruHandler {
  PoolPostsHandler(
    super.booru,
    super.limit, {
    required this.poolId,
    this.poolName,
  });

  final String poolId;
  final String? poolName;

  late final PoolSource? _source = PoolSource.forBooru(booru);

  late final BooruHandler _delegate = (BooruHandlerFactory().getBooruHandler([booru], limit).booruHandler)
    ..storeTagsGlobally = false;

  /// Ordered member ids, resolved once.
  List<String>? _orderedIds;
  bool _resolved = false;

  /// Everything the pool holds, in order, for the reorder strategy.
  List<BooruItem>? _allOrdered;

  // Safety net for the "fetch everything then reorder" path.
  static const int _maxMembersFetched = 1000;

  @override
  bool get hasSizeData => _delegate.hasSizeData;

  @override
  bool get hasTagSuggestions => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String validateTags(String tags) => tags;

  @override
  List<MetaTag> availableMetaTags() => [];

  Future<void> _resolveIds() async {
    if (_resolved) return;
    _resolved = true;
    try {
      _orderedIds = await _source?.fetchPostIds(booru, BooruPool(id: poolId, name: poolName ?? ''));
    } catch (e, s) {
      Logger.Inst().log(
        'failed to resolve post ids for pool $poolId: $e',
        'PoolPostsHandler',
        '_resolveIds',
        LogTypes.exception,
        s: s,
      );
    }
  }

  @override
  Future<dynamic> search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) pageNum = pageNumCustom;

    final PoolSource? source = _source;
    if (source == null) {
      errorString = 'This booru has no pools.';
      locked = true;
      return fetched;
    }

    final int before = fetched.length;
    final String? query = source.postsQuery(poolId);

    try {
      List<BooruItem> pageItems;
      if (query != null && source.queryPreservesOrder) {
        // The site returns pool order itself — page straight through.
        _delegate.pageNum = pageNum;
        _delegate.locked = false;
        pageItems = ((await _delegate.search(query, null)) as List<BooruItem>? ?? const [])
            .skip(fetched.length)
            .toList();
      } else {
        await _resolveIds();
        pageItems = query != null ? await _pageByReorder(query) : await _pageById();
      }

      if (pageItems.isEmpty) {
        locked = true;
        return fetched;
      }

      await afterParseResponse(pageItems);
      if (fetched.length == before) locked = true;
      return fetched;
    } catch (e, s) {
      Logger.Inst().log(
        'pool $poolId page $pageNum failed: $e',
        'PoolPostsHandler',
        'search',
        LogTypes.exception,
        s: s,
      );
      errorString = e.toString();
      locked = true;
      return fetched;
    }
  }

  /// e621: members come back newest-first, so pull them all once and reorder
  /// to the pool's own sequence, then hand out pages from that.
  Future<List<BooruItem>> _pageByReorder(String query) async {
    if (_allOrdered == null) {
      final List<BooruItem> collected = [];
      int page = 0;
      while (collected.length < _maxMembersFetched) {
        _delegate.pageNum = page;
        _delegate.locked = false;
        final List<BooruItem> got =
            ((await _delegate.search(query, null)) as List<BooruItem>? ?? const []).skip(collected.length).toList();
        if (got.isEmpty) break;
        collected.addAll(got);
        if (_delegate.locked) break;
        page++;
      }

      final List<String>? order = _orderedIds;
      if (order != null && order.isNotEmpty) {
        final Map<String, BooruItem> byId = {
          for (final item in collected)
            if (item.serverId != null) item.serverId!: item,
        };
        _allOrdered = [
          for (final id in order)
            if (byId[id] != null) byId[id]!,
        ];
        // Anything the order didn't mention still belongs to the pool.
        for (final item in collected) {
          if (!order.contains(item.serverId)) _allOrdered!.add(item);
        }
      } else {
        _allOrdered = collected;
      }
    }

    final int start = fetched.length;
    if (start >= _allOrdered!.length) return const [];
    return _allOrdered!.skip(start).take(limit).toList();
  }

  /// Gelbooru family: no pool filter exists, so each member is fetched by id.
  /// Bounded concurrency keeps a big pool from opening 50 sockets at once.
  Future<List<BooruItem>> _pageById() async {
    final List<String>? ids = _orderedIds;
    if (ids == null || ids.isEmpty) return const [];

    final int start = fetched.length;
    if (start >= ids.length) return const [];
    final List<String> slice = ids.skip(start).take(limit).toList();

    final List<BooruItem> out = [];
    const int batchSize = 6;
    for (int i = 0; i < slice.length; i += batchSize) {
      final List<String> batch = slice.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((id) async {
          // A fresh handler per request: they accumulate into `fetched`, and
          // sharing one would interleave results from parallel calls.
          final BooruHandler h = BooruHandlerFactory().getBooruHandler([booru], 1).booruHandler
            ..storeTagsGlobally = false
            ..pageNum = 0;
          try {
            final List<BooruItem> got = (await h.search('id:$id', null)) as List<BooruItem>? ?? const [];
            return got.isEmpty ? null : got.first;
          } catch (_) {
            return null;
          }
        }),
      );
      out.addAll(results.whereType<BooruItem>());
    }
    return out;
  }

  @override
  Future<void> searchCount(String input) async {
    totalCount.value = _orderedIds?.length ?? 0;
  }
}
