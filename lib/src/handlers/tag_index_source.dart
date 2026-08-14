import 'dart:convert';

import 'package:html/parser.dart' show parseFragment;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// How a booru exposes its **tag database** (as opposed to its posts).
///
/// Three things are wanted from a site, and sites differ on all three:
///   * [pageAt]  — walk the whole index, to build a local snapshot;
///   * [search]  — substring lookup, so the browser can find a tag the
///                 snapshot doesn't have yet;
///   * [exact]   — one authoritative row for one tag name, which is how a
///                 tag's type gets *corrected* rather than guessed.
///
/// Everything here was verified against the live APIs. Notable results:
///   * Gelbooru-0.2 (`page=dapi&s=tag&q=index`) honours `name=` (exact, one
///     row) and `name_pattern=%x%` (SQL LIKE), ignores `names=` entirely, and
///     ignores `json=1` on rule34.xxx — it always answers XML. It also
///     ignores `orderby=count`, so its index comes out in id order.
///   * Danbooru/e621 (`/tags.json`) *do* honour `search[order]=count`, so
///     their snapshots arrive most-used-first, which is the useful end.
abstract class TagIndexSource {
  const TagIndexSource();

  /// Rows per [pageAt] request.
  int get pageSize;

  /// How deep a full-index pull is allowed to go. Nobody wants a site's
  /// entire tag database on a phone; the point is the useful end of it.
  int get maxIndexPages => 60;

  /// Whether [pageAt] returns the most-used tags first. When false, walking
  /// the index is a slog through whatever internal order the site uses.
  bool get orderedByCount => false;

  /// One page of the full tag index. [page] is 0-based.
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page);

  /// Substring search against the site's tag database.
  Future<List<BooruTagEntry>> search(Booru booru, String query);

  /// The single authoritative row for [name], or null when the site has no
  /// such tag. Null return from an *unsupported* site is indistinguishable
  /// from a miss on purpose — callers only ever use it to fill in a blank.
  Future<BooruTagEntry?> exact(Booru booru, String name);

  /// Maps a site's raw type value onto the app's [TagType] using the booru's
  /// own handler, so there is exactly one copy of each family's numbering.
  static TagType typeFor(Booru booru, String raw) {
    if (raw.isEmpty) return TagType.none;
    try {
      final map = BooruHandlerFactory().getBooruHandler([booru], null).booruHandler.tagTypeMap;
      return map[raw] ?? TagType.none;
    } catch (_) {
      return TagType.none;
    }
  }

  static TagIndexSource? forBooru(Booru? booru) {
    if (booru?.type == null || (booru!.baseURL?.isEmpty ?? true)) return null;
    return switch (booru.type!) {
      BooruType.Gelbooru || BooruType.GelbooruAlike => const GelbooruTagIndex(),
      BooruType.Danbooru => const DanbooruTagIndex(),
      BooruType.e621 => const E621TagIndex(),
      BooruType.Philomena => const PhilomenaTagIndex(),
      _ => null,
    };
  }

  static bool supports(Booru? booru) => forBooru(booru) != null;
}

/// Gelbooru 0.2 family — rule34.xxx, xbooru, gelbooru.com, bakemono…
class GelbooruTagIndex extends TagIndexSource {
  const GelbooruTagIndex();

  /// The site's own tag list renders 20 rows per page. The API would hand
  /// over 100 at a time, but in an order nobody can use — see [pageAt].
  @override
  int get pageSize => 20;

  /// 20 × 250 ≈ the 5000 most-used tags, which on rule34.xxx reaches down to
  /// roughly ten thousand posts per tag — the whole vocabulary you actually
  /// meet while browsing.
  @override
  int get maxIndexPages => 250;

  @override
  bool get orderedByCount => true;

  String _creds(Booru booru) {
    final String key = booru.apiKey ?? '';
    final String user = booru.userID ?? '';
    if (key.isEmpty || user.isEmpty) return '';
    return '&api_key=$key&user_id=$user';
  }

  String _base(Booru booru) => '${booru.baseURL}/index.php?page=dapi&s=tag&q=index${_creds(booru)}';

  Future<List<BooruTagEntry>> _fetch(String url) async {
    final response = await DioNetwork.get(url, headers: {'User-Agent': Tools.browserUserAgent});
    return _parse(response.data);
  }

  /// The same endpoint answers XML on some sites and JSON on others (and
  /// rule34.xxx ignores `json=1` outright), so both shapes are accepted.
  List<BooruTagEntry> _parseJson(dynamic decoded) {
    final List raw = decoded is List ? decoded : ((decoded is Map ? decoded['tag'] : null) as List? ?? const []);
    return [
      for (final e in raw)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: _typeFromRaw(e['type']?.toString() ?? ''),
            count: int.tryParse(e['count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  List<BooruTagEntry> _parse(dynamic data) {
    if (data is List || data is Map) return _parseJson(data);

    final String body = data?.toString() ?? '';
    final String trimmed = body.trimLeft();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        return _parseJson(jsonDecode(trimmed));
      } catch (_) {
        return const [];
      }
    }

    // Flat XML: <tag type="4" count="39742" name="hatsune_miku" id="…"/>
    final List<BooruTagEntry> out = [];
    for (final m in RegExp(r'<tag\s([^>]*?)/?>').allMatches(body)) {
      final String attrs = m.group(1) ?? '';
      final String name = RegExp('name="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
      if (name.isEmpty) continue;
      out.add(
        BooruTagEntry(
          name: (parseFragment(name).text ?? name).toLowerCase(),
          tagType: _typeFromRaw(RegExp('type="([^"]*)"').firstMatch(attrs)?.group(1) ?? ''),
          count: int.tryParse(RegExp('count="([^"]*)"').firstMatch(attrs)?.group(1) ?? '') ?? 0,
        ),
      );
    }
    return out;
  }

  // Gelbooru numbering, shared by every 0.2 fork: 0 general, 1 artist,
  // 3 copyright, 4 character, 5 metadata. 2 and 6 are legacy/deprecated.
  TagType _typeFromRaw(String raw) => switch (raw) {
    '1' => TagType.artist,
    '3' => TagType.copyright,
    '4' => TagType.character,
    '5' => TagType.meta,
    _ => TagType.none,
  };

  /// Walks the site's tag list **most-used first**.
  ///
  /// The API index is useless for this: `orderby=count` is silently ignored,
  /// and what comes back is dominated by one-off tags — sampling six pages
  /// spread across rule34.xxx's index gave a median post count of 1 at every
  /// depth. Downloading thousands of those would fill the snapshot with
  /// nothing you will ever type.
  ///
  /// The site's own tag list page *does* sort: `page=tags&s=list` with
  /// `sort=desc&order_by=index_count` starts at `female` (10.3M posts) and
  /// descends properly, 20 rows a page, `pid` counting rows rather than
  /// pages. So the index pull scrapes what the site shows its own users, and
  /// falls back to the API walk if a fork doesn't render that page.
  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) async {
    try {
      final response = await DioNetwork.get(
        '${booru.baseURL}/index.php?page=tags&s=list&sort=desc&order_by=index_count&pid=${page * pageSize}',
        headers: {'User-Agent': Tools.browserUserAgent},
      );
      final List<BooruTagEntry> scraped = _parseHtmlList(response.data?.toString() ?? '');
      if (scraped.isNotEmpty) return scraped;
    } catch (_) {
      // fall through to the API
    }
    return _fetch('${_base(booru)}&limit=100&pid=$page');
  }

  /// Row shape (verified on rule34.xxx and xbooru):
  /// `<td>10325626</td><td><span class="tag-type-general"><a href="…tags=female">`
  static final RegExp _htmlRow = RegExp(
    r'<td>(\d+)</td>\s*<td>\s*<span class="tag-type-([a-z]+)">\s*<a href="[^"]*tags=([^"]*)"',
    dotAll: true,
  );

  static const Map<String, TagType> _htmlTypes = {
    'artist': TagType.artist,
    'copyright': TagType.copyright,
    'character': TagType.character,
    'metadata': TagType.meta,
    'general': TagType.none,
  };

  List<BooruTagEntry> _parseHtmlList(String body) {
    final List<BooruTagEntry> out = [];
    for (final m in _htmlRow.allMatches(body)) {
      String name;
      try {
        name = Uri.decodeComponent(m.group(3) ?? '');
      } catch (_) {
        name = m.group(3) ?? '';
      }
      // Sites carry junk rows (a tag literally named "\tbreasts" exists on
      // xbooru); anything with whitespace in it can never be searched.
      name = name.trim().toLowerCase();
      if (name.isEmpty || name.contains(RegExp(r'\s'))) continue;
      out.add(
        BooruTagEntry(
          name: name,
          tagType: _htmlTypes[m.group(2)] ?? TagType.none,
          count: int.tryParse(m.group(1) ?? '') ?? 0,
        ),
      );
    }
    return out;
  }

  /// `name_pattern` is a raw SQL LIKE, so the wildcards have to be sent
  /// percent-encoded or the query string eats them.
  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent(query.trim().toLowerCase().replaceAll(' ', '_'));
    return _fetch('${_base(booru)}&limit=100&name_pattern=%25$q%25');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String q = Uri.encodeComponent(name.trim().toLowerCase());
    if (q.isEmpty) return null;
    final List<BooruTagEntry> got = await _fetch('${_base(booru)}&limit=2&name=$q');
    if (got.isEmpty) return null;
    // `name=` is exact, but be strict anyway — a fork could reinterpret it.
    for (final e in got) {
      if (e.name == name.trim().toLowerCase()) return e;
    }
    return null;
  }
}

/// Danbooru family (danbooru, AiBooru, AllTheFallen).
class DanbooruTagIndex extends TagIndexSource {
  const DanbooruTagIndex();

  @override
  int get pageSize => 100;

  @override
  bool get orderedByCount => true;

  String _creds(Booru booru) {
    final String key = booru.apiKey ?? '';
    final String user = booru.userID ?? '';
    if (key.isEmpty || user.isEmpty) return '';
    return '&login=$user&api_key=$key';
  }

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/tags.json?$query${_creds(booru)}',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final decoded = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: TagIndexSource.typeFor(booru, e['category']?.toString() ?? ''),
            count: int.tryParse(e['post_count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) =>
      _fetch(booru, 'limit=$pageSize&page=${page + 1}&search[order]=count&search[hide_empty]=yes');

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent('*${query.trim().toLowerCase().replaceAll(' ', '_')}*');
    return _fetch(booru, 'limit=$pageSize&search[name_matches]=$q&search[order]=count');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'limit=2&search[name_matches]=${Uri.encodeComponent(clean)}');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}

/// e621 / e6ai — same shape as danbooru, but wants HTTP basic auth and a
/// descriptive user agent, and wraps the payload when it is empty.
class E621TagIndex extends TagIndexSource {
  const E621TagIndex();

  @override
  int get pageSize => 100;

  @override
  bool get orderedByCount => true;

  Map<String, String> _headers(Booru booru) {
    final String key = booru.apiKey ?? '';
    final String user = booru.userID ?? '';
    return {
      'User-Agent': Tools.appUserAgent,
      if (key.isNotEmpty && user.isNotEmpty)
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$key'))}',
    };
  }

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query) async {
    final response = await DioNetwork.get('${booru.baseURL}/tags.json?$query', headers: _headers(booru));
    final decoded = response.data is String ? jsonDecode(response.data as String) : response.data;
    // e621 answers `{"tags":[]}` for an empty result and a bare list otherwise.
    final List raw = decoded is List ? decoded : ((decoded is Map ? decoded['tags'] : null) as List? ?? const []);
    return [
      for (final e in raw)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: TagIndexSource.typeFor(booru, e['category']?.toString() ?? ''),
            count: int.tryParse(e['post_count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) =>
      _fetch(booru, 'limit=$pageSize&page=${page + 1}&search[order]=count&search[hide_empty]=true');

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent('*${query.trim().toLowerCase().replaceAll(' ', '_')}*');
    return _fetch(booru, 'limit=$pageSize&search[name_matches]=$q&search[order]=count');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'limit=2&search[name_matches]=${Uri.encodeComponent(clean)}');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}

/// Philomena (derpibooru and friends).
class PhilomenaTagIndex extends TagIndexSource {
  const PhilomenaTagIndex();

  @override
  int get pageSize => 50;

  @override
  bool get orderedByCount => true;

  static const Map<String, TagType> _categories = {
    'artist': TagType.artist,
    'character': TagType.character,
    'oc': TagType.character,
    'origin': TagType.copyright,
    'species': TagType.species,
    'content-official': TagType.copyright,
    'content-fanmade': TagType.copyright,
    'rating': TagType.meta,
    'spoiler': TagType.meta,
    'error': TagType.meta,
  };

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/api/v1/json/search/tags?$query',
      headers: {'User-Agent': Tools.browserUserAgent},
    );
    final decoded = response.data is String ? jsonDecode(response.data as String) : response.data;
    final List raw = (decoded is Map ? decoded['tags'] : null) as List? ?? const [];
    return [
      for (final e in raw)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: _categories[e['category']?.toString()] ?? TagType.none,
            count: int.tryParse(e['images']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) =>
      _fetch(booru, 'q=*&per_page=$pageSize&page=${page + 1}&sf=images&sd=desc');

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent('*${query.trim().toLowerCase()}*');
    return _fetch(booru, 'q=$q&per_page=$pageSize&sf=images&sd=desc');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'q=${Uri.encodeComponent(clean)}&per_page=2');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}
