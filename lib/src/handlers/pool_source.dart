import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_pool.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// How a given booru exposes its pools.
///
/// Pool support is a PER-SITE capability, not a per-handler one: two sites on
/// the same handler can differ (gelbooru.com has pools, tbib.org has none),
/// and the route differs too — some serve clean JSON, some only render HTML.
/// [forBooru] resolves the right source, or null when the site has no pools,
/// which is what the drawer entry keys off so it simply doesn't exist there.
///
/// Everything here was verified against the live sites before being written.
abstract class PoolSource {
  const PoolSource();

  /// Pools per page as the SOURCE paginates them.
  int get pageSize;

  /// Fetches one page of the pool list. [page] is 0-based.
  Future<List<BooruPool>> fetchPools(Booru booru, int page);

  /// Ordered member post ids for a pool, when they must be resolved before
  /// posts can be fetched. Null means "this source can query the pool
  /// directly" (see [postsQuery]).
  Future<List<String>?> fetchPostIds(Booru booru, BooruPool pool) async => null;

  /// A tag query that returns the pool's posts, for sites where the pool is a
  /// real search filter. Null means posts must be fetched by id instead.
  String? postsQuery(String poolId) => null;

  /// True when [postsQuery] already returns posts in pool order server-side,
  /// so the result must not be re-sorted or re-ordered locally.
  bool get queryPreservesOrder => false;

  /// Hosts pool browsing is enabled on.
  ///
  /// An ALLOWLIST, not a denylist: several sites run software that has pools
  /// and still have none worth browsing (or refuse them over the API), so
  /// membership here means "verified working end to end on this site".
  static const Set<String> _poolHosts = {
    'rule34.xxx',
    'realbooru.com',
    'xbooru.com',
    'booru.allthefallen.moe',
  };

  /// The pool source for [booru], or null when the site has no pools.
  static PoolSource? forBooru(Booru? booru) {
    if (booru?.type == null) return null;
    final String host = Uri.tryParse(booru!.baseURL ?? '')?.host.replaceFirst('www.', '') ?? '';
    if (host.isEmpty || !_poolHosts.contains(host)) return null;

    return switch (booru.type!) {
      BooruType.e621 => const E621PoolSource(),
      BooruType.Danbooru => const DanbooruPoolSource(),
      BooruType.Philomena => const PhilomenaGallerySource(),
      // Gelbooru 0.2 family: pools exist only as HTML pages — the dapi pool
      // endpoint stays empty even WITH an api key + user id (verified on both
      // rule34.xxx and gelbooru.com).
      BooruType.Gelbooru || BooruType.GelbooruAlike => const GelbooruHtmlPoolSource(),
      _ => null,
    };
  }

  static bool supports(Booru? booru) => forBooru(booru) != null;
}

/// e621 / e6ai — `/pools.json`, the richest source: it hands back ordered
/// `post_ids` directly.
class E621PoolSource extends PoolSource {
  const E621PoolSource();

  @override
  int get pageSize => 30;

  Map<String, String> _auth(Booru booru) {
    if ((booru.userID?.isNotEmpty ?? false) && (booru.apiKey?.isNotEmpty ?? false)) {
      final String basic = base64Encode(utf8.encode('${booru.userID}:${booru.apiKey}'));
      return {'Authorization': 'Basic $basic'};
    }
    return {};
  }

  @override
  Future<List<BooruPool>> fetchPools(Booru booru, int page) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/pools.json?limit=$pageSize&page=${page + 1}',
      headers: {'User-Agent': Tools.appUserAgent, ..._auth(booru)},
    );
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! List) return [];
    return [
      for (final p in data)
        if (p is Map)
          BooruPool(
            id: p['id'].toString(),
            name: p['name']?.toString() ?? '',
            description: p['description']?.toString(),
            creator: p['creator_name']?.toString(),
            postCount: int.tryParse(p['post_count']?.toString() ?? ''),
            postIds: (p['post_ids'] as List?)?.map((e) => e.toString()).toList(),
          ),
    ];
  }

  /// `pool:<id>` DOES work as a tag here, but returns posts newest-first, NOT
  /// in pool order (verified) — so the ids are resolved up front and the
  /// fetched posts are reordered to match.
  @override
  Future<List<String>?> fetchPostIds(Booru booru, BooruPool pool) async {
    if (pool.postIds?.isNotEmpty ?? false) return pool.postIds;
    final response = await DioNetwork.get(
      '${booru.baseURL}/pools.json?search[id]=${pool.id}',
      headers: {'User-Agent': Tools.appUserAgent, ..._auth(booru)},
    );
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! List || data.isEmpty) return null;
    return (data.first['post_ids'] as List?)?.map((e) => e.toString()).toList();
  }

  /// Used to pull the members in bulk; the caller reorders by post ids.
  @override
  String? postsQuery(String poolId) => 'pool:$poolId';
}

/// Danbooru family (danbooru, AiBooru, AllTheFallen) — `/pools.json`, and
/// `ordpool:` returns members in pool order server-side.
class DanbooruPoolSource extends PoolSource {
  const DanbooruPoolSource();

  @override
  int get pageSize => 30;

  String _creds(Booru booru) {
    if ((booru.userID?.isNotEmpty ?? false) && (booru.apiKey?.isNotEmpty ?? false)) {
      return '&login=${booru.userID}&api_key=${booru.apiKey}';
    }
    return '';
  }

  @override
  Future<List<BooruPool>> fetchPools(Booru booru, int page) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/pools.json?limit=$pageSize&page=${page + 1}${_creds(booru)}',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! List) return [];
    return [
      for (final p in data)
        if (p is Map)
          BooruPool(
            id: p['id'].toString(),
            name: p['name']?.toString() ?? '',
            description: p['description']?.toString(),
            postCount: int.tryParse(p['post_count']?.toString() ?? ''),
            postIds: (p['post_ids'] as List?)?.map((e) => e.toString()).toList(),
          ),
    ];
  }

  /// `ordpool:` is exactly "pool members, in pool order".
  @override
  String? postsQuery(String poolId) => 'ordpool:$poolId';

  @override
  bool get queryPreservesOrder => true;
}

/// Philomena (derpibooru) — pools are called galleries.
class PhilomenaGallerySource extends PoolSource {
  const PhilomenaGallerySource();

  @override
  int get pageSize => 25;

  @override
  Future<List<BooruPool>> fetchPools(Booru booru, int page) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/api/v1/json/search/galleries?q=*&per_page=$pageSize&page=${page + 1}',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    final List<dynamic> galleries = (data is Map ? data['galleries'] : null) as List<dynamic>? ?? [];
    return [
      for (final g in galleries)
        if (g is Map)
          BooruPool(
            id: g['id'].toString(),
            name: g['title']?.toString() ?? '',
            description: g['description']?.toString(),
            creator: g['user']?.toString(),
            postCount: int.tryParse(g['image_count']?.toString() ?? ''),
          ),
    ];
  }

  @override
  String? postsQuery(String poolId) => 'gallery_id:$poolId';

  @override
  bool get queryPreservesOrder => true;
}

/// Gelbooru 0.2 family (rule34.xxx, gelbooru.com, realbooru, xbooru).
///
/// The documented API refuses pools — `page=dapi&s=pool&q=index` answers with
/// an empty body even with a valid api_key + user_id (verified on rule34.xxx
/// and gelbooru.com with the user's own credentials). The site's own HTML
/// works fine, so the list and the member ids are scraped, and each member's
/// details then come from the normal post API via `tags=id:<n>` (verified
/// supported; OR-ing several ids is not).
class GelbooruHtmlPoolSource extends PoolSource {
  const GelbooruHtmlPoolSource();

  /// The HTML list paginates in steps of 25 and ignores `&search=` / `&q=`.
  @override
  int get pageSize => 25;

  @override
  Future<List<BooruPool>> fetchPools(Booru booru, int page) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/index.php?page=pool&s=list&pid=${page * pageSize}',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final doc = html_parser.parse(response.data?.toString() ?? '');

    final List<BooruPool> pools = [];
    for (final row in doc.querySelectorAll('tr')) {
      final link = row.querySelector('a[href*="s=show"]');
      final String? href = link?.attributes['href'];
      if (link == null || href == null) continue;
      final match = RegExp(r'id=(\d+)').firstMatch(href);
      if (match == null) continue;

      // Row layout: Name | Creator | Post count | Public
      final cells = row.querySelectorAll('td');
      String? creator;
      int? count;
      if (cells.length >= 3) {
        creator = cells[1].text.trim();
        count = int.tryParse(RegExp(r'\d+').firstMatch(cells[2].text)?.group(0) ?? '');
      }
      pools.add(
        BooruPool(
          id: match.group(1)!,
          name: link.text.trim(),
          creator: (creator?.isEmpty ?? true) ? null : creator,
          postCount: count,
        ),
      );
    }
    return pools;
  }

  /// The pool page renders its posts in the same `<span class="thumb"
  /// id="pNNN">` markup as a normal grid, in POOL ORDER.
  @override
  Future<List<String>?> fetchPostIds(Booru booru, BooruPool pool) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/index.php?page=pool&s=show&id=${pool.id}',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final String body = response.data?.toString() ?? '';
    final ids = RegExp(r'<span class="thumb" id="p(\d+)"').allMatches(body).map((m) => m.group(1)!).toList();
    return ids.isEmpty ? null : ids;
  }

  /// No pool metatag exists here at all — posts are fetched one id at a time.
  @override
  String? postsQuery(String poolId) => null;
}
