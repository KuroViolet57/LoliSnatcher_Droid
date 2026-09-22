import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' show parseFragment;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
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
/// A fourth, for the search editor's tag builder: the site's tag categories
/// as namespaces ([catalogNamespaces]), walked one category at a time where
/// the site can ([categoryPageAt]) or as one count-ordered list otherwise
/// ([catalogPageAt]). Rows always land in the snapshot with no namespace and
/// the category as their type, which is how the chips read them back
/// ([TagCatalogNamespace.byType]).
///
/// Everything here was verified against the live APIs. Notable results:
///   * Gelbooru-0.2 (`page=dapi&s=tag&q=index`) honours `name=` (exact, one
///     row) and `name_pattern=%x%` (SQL LIKE), ignores `names=` entirely, and
///     ignores `json=1` on rule34.xxx — it always answers XML. It also
///     ignores `orderby=count`, so its index comes out in id order, and it
///     cannot filter by type at all.
///   * Danbooru/e621 (`/tags.json`) *do* honour `search[order]=count` and
///     `search[category]`, so their snapshots arrive most-used-first, one
///     category at a time. Moebooru (`/tag.json?order=count&type=`) and
///     sankaku (`/tags?order=count&type=`) do the same (2026-09-06).
///   * Philomena has no artist category: artists are `origin` tags named
///     `artist:…`, and general tags have no category at all.
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

  //
  // The tag builder's view of the family
  //

  /// The namespaces the search editor's tag builder offers for this family:
  /// the site's tag categories, each read by type from the snapshot
  /// ([TagCatalogNamespace.byType]). Empty = no builder for this family.
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) => const [];

  /// True when the site lists ONE category at a time ([categoryPageAt]);
  /// false when the whole index is walked once, most-used first, and every
  /// chip reads its own type out of it ([catalogPageAt]).
  bool get walksByCategory => false;

  /// One page of the whole index, most-used first — the shared walk, and the
  /// tag browser's pull. Defaults to [pageAt].
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      pageAt(booru, page);

  /// One page of ONE category, most-used first; empty past the end.
  Future<List<BooruTagEntry>> categoryPageAt(
    Booru booru,
    TagType type,
    int page, {
    Map<String, String>? headers,
  }) async => const [];

  /// Pages one pull of the builder fetches before it stops and waits for
  /// "Pull more" — a tap should finish well under a minute at [catalogDelay].
  int get catalogPagesPerPull => maxIndexPages;

  /// Pause between the builder's pages. Sites rate-limit sustained walks.
  Duration get catalogDelay => const Duration(milliseconds: 350);

  /// Rows one builder page holds for [booru] — some families take a bigger
  /// page than [pageAt] uses, and some sites render more than others.
  int pageSizeFor(Booru booru) => pageSize;

  /// Whether [rows] was the last page of a walk, so the next one need not be
  /// asked for. A page short of [pageSizeFor] is the end on every API.
  bool lastPage(Booru booru, List<BooruTagEntry> rows) => rows.length < pageSizeFor(booru);

  /// The order chips are offered in.
  static const List<TagType> catalogOrder = [
    TagType.artist,
    TagType.contributor,
    TagType.character,
    TagType.copyright,
    TagType.species,
    TagType.meta,
    TagType.lore,
    TagType.none,
  ];

  /// The builder chip for a type. Key and label follow the doujin catalogs'
  /// convention (`artist`, `character`, …, `tag` for the general ones), so a
  /// typed `artist:x` reaches the same autocomplete.
  static TagCatalogNamespace typeNamespace(TagType type, {int? maxShards}) {
    final (String key, String label) = switch (type) {
      TagType.artist => ('artist', 'Artists'),
      TagType.character => ('character', 'Characters'),
      TagType.copyright => ('copyright', 'Copyrights'),
      TagType.species => ('species', 'Species'),
      TagType.meta => ('meta', 'Meta'),
      TagType.contributor => ('contributor', 'Contributors'),
      TagType.lore => ('lore', 'Lore'),
      TagType.none => ('tag', 'Tags'),
    };
    return TagCatalogNamespace(key: key, label: label, type: type, maxShards: maxShards, byType: true);
  }

  /// The chips for [types], in [catalogOrder].
  static List<TagCatalogNamespace> namespacesFor(Iterable<TagType> types, {int? maxShards}) => [
    for (final type in catalogOrder)
      if (types.contains(type)) typeNamespace(type, maxShards: maxShards),
  ];

  static final Map<String, Map<String, TagType>> _typeMaps = {};

  /// The family's raw-type → [TagType] numbering, read off the booru's own
  /// handler so there is exactly one copy of it — built once per booru, not
  /// once per row (a page carries up to a thousand).
  static Map<String, TagType> typeMapFor(Booru booru) {
    final String key = '${booru.type?.name}|${hostOf(booru)}';
    return _typeMaps.putIfAbsent(key, () {
      try {
        return Map<String, TagType>.unmodifiable(
          BooruHandlerFactory().getBooruHandler([booru], null).booruHandler.tagTypeMap,
        );
      } catch (_) {
        return const {};
      }
    });
  }

  /// Maps a site's raw type value onto the app's [TagType].
  static TagType typeFor(Booru booru, String raw) =>
      raw.isEmpty ? TagType.none : (typeMapFor(booru)[raw] ?? TagType.none);

  /// Host without `www.`: the key of anything remembered per site.
  static String hostOf(Booru booru) =>
      (Uri.tryParse(booru.baseURL ?? '')?.host ?? '').replaceFirst('www.', '').toLowerCase();

  @visibleForTesting
  static void resetForTests() {
    _typeMaps.clear();
    GelbooruTagIndex.resetForTests();
  }

  static TagIndexSource? forBooru(Booru? booru) {
    if (booru?.type == null || (booru!.baseURL?.isEmpty ?? true)) return null;
    return switch (booru.type!) {
      BooruType.Gelbooru || BooruType.GelbooruAlike || BooruType.Realbooru => const GelbooruTagIndex(),
      BooruType.Danbooru => const DanbooruTagIndex(),
      BooruType.e621 => const E621TagIndex(),
      BooruType.Philomena => const PhilomenaTagIndex(),
      BooruType.Moebooru => const MoebooruTagIndex(),
      BooruType.Sankaku => const SankakuTagIndex(),
      _ => null,
    };
  }

  static bool supports(Booru? booru) => forBooru(booru) != null;
}

/// Gelbooru 0.2 family — rule34.xxx, xbooru, gelbooru.com, tbib, realbooru…
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

  /// Rows the list page renders per request, by host. Most forks render 20;
  /// these render 50 (verified 2026-09-06) — and `pid` counts ROWS, so a walk
  /// stepping by 20 there would re-read most of every page. Page 0 teaches
  /// any other host's count.
  static const Map<String, int> _knownRowsPerPage = {'tbib.org': 50, 'realbooru.com': 50, 'gelbooru.com': 50};
  static final Map<String, int> _rowsPerPage = Map.of(_knownRowsPerPage);

  @visibleForTesting
  static void resetForTests() {
    _rowsPerPage
      ..clear()
      ..addAll(_knownRowsPerPage);
  }

  @override
  int pageSizeFor(Booru booru) => _rowsPerPage[TagIndexSource.hostOf(booru)] ?? pageSize;

  /// The scrape drops junk rows, so a short page tells nothing; the walk runs
  /// until a page has no rows at all.
  @override
  bool lastPage(Booru booru, List<BooruTagEntry> rows) => false;

  /// No type filter exists on the list, so the builder walks it once and
  /// every chip reads its own type out of the shared snapshot. 100 pages a
  /// pull: the site answers 429 to ~190 back-to-back pages, and a tap should
  /// not take a minute.
  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) => TagIndexSource.namespacesFor(
    const [TagType.artist, TagType.character, TagType.copyright, TagType.meta, TagType.none],
  );

  @override
  int get catalogPagesPerPull => 100;

  /// The list page ONLY. The dapi fallback in [pageAt] needs credentials on
  /// rule34.xxx, answers nothing anonymously on gelbooru.com and comes out in
  /// id order everywhere — none of which makes a usable list.
  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      scrapeListPage(booru, page, headers: headers);

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
  /// descends properly, `pid` counting rows rather than pages. So the index
  /// pull scrapes what the site shows its own users, and falls back to the
  /// API walk if a fork doesn't render that page.
  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) async {
    try {
      final List<BooruTagEntry> scraped = await scrapeListPage(booru, page);
      if (scraped.isNotEmpty) return scraped;
    } catch (_) {
      // fall through to the API
    }
    return _fetch('${_base(booru)}&limit=100&pid=$page');
  }

  /// One page of `page=tags&s=list`, sorted by count. `pid` counts rows, so
  /// the offset is page × this host's rows per page; page 0 teaches it.
  Future<List<BooruTagEntry>> scrapeListPage(Booru booru, int page, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      listPageUrl(booru, page),
      headers: headers ?? {'User-Agent': Tools.browserUserAgent},
    );
    final String body = response.data?.toString() ?? '';
    if (page == 0) {
      final int rows = rowsOnPage(body);
      if (rows >= pageSize) _rowsPerPage[TagIndexSource.hostOf(booru)] = rows;
    }
    return parseHtmlList(body);
  }

  @visibleForTesting
  String listPageUrl(Booru booru, int page) =>
      '${booru.baseURL}/index.php?page=tags&s=list&sort=desc&order_by=index_count&pid=${page * pageSizeFor(booru)}';

  /// Rendered rows on a list page, junk rows included — what `pid` counts.
  @visibleForTesting
  static int rowsOnPage(String body) => RegExp('class="tag-type-[a-z]+"').allMatches(body).length;

  /// Row shape on most forks (verified on rule34.xxx and xbooru):
  /// `<td>10325626</td><td><span class="tag-type-general"><a href="…tags=female">`
  static final RegExp _htmlRow = RegExp(
    r'<td>(\d+)</td>\s*<td>\s*<span class="tag-type-([a-z]+)">\s*<a href="[^"]*tags=([^"]*)"',
    dotAll: true,
  );

  /// gelbooru.com's own shape (verified 2026-09-06): the count FOLLOWS the
  /// link — `<span class="tag-type-general"><a href="…tags=1girl">1girl</a>
  /// </span> <span class="tag-count">9660397</span>`.
  static final RegExp _htmlRowCountAfter = RegExp(
    r'<span class="tag-type-([a-z]+)">\s*<a href="[^"]*tags=([^"&]*)"[^>]*>[^<]*</a>\s*</span>\s*<span class="tag-count">(\d+)</span>',
    dotAll: true,
  );

  static const Map<String, TagType> _htmlTypes = {
    'artist': TagType.artist,
    'model': TagType.artist, // realbooru's performers
    'copyright': TagType.copyright,
    'character': TagType.character,
    'metadata': TagType.meta,
    'general': TagType.none,
  };

  /// gelbooru.com lists its deprecated aliases (`1firl`, `1_girl`…) with the
  /// post counts of the tags they point at; searching one finds nothing.
  static const Set<String> _skipTypes = {'deprecated'};

  @visibleForTesting
  static List<BooruTagEntry> parseHtmlList(String body) {
    final List<BooruTagEntry> out = [];
    void add(String rawType, String rawName, String rawCount) {
      if (_skipTypes.contains(rawType)) return;
      String name;
      try {
        name = Uri.decodeComponent(rawName);
      } catch (_) {
        name = rawName;
      }
      // Sites carry junk rows (a tag literally named "\tbreasts" exists on
      // xbooru; gelbooru.com's first row has no name at all): anything empty
      // or with whitespace in it can never be searched.
      name = (parseFragment(name).text ?? name).trim().toLowerCase();
      if (name.isEmpty || name.contains(RegExp(r'\s'))) return;
      out.add(
        BooruTagEntry(
          name: name,
          tagType: _htmlTypes[rawType] ?? TagType.none,
          count: int.tryParse(rawCount) ?? 0,
        ),
      );
    }

    int matched = 0;
    for (final m in _htmlRow.allMatches(body)) {
      matched++;
      add(m.group(2) ?? '', m.group(3) ?? '', m.group(1) ?? '');
    }
    if (matched == 0) {
      for (final m in _htmlRowCountAfter.allMatches(body)) {
        add(m.group(1) ?? '', m.group(2) ?? '', m.group(3) ?? '');
      }
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

  /// `tags.json` filters by `search[category]`, so each chip walks its own
  /// category most-used first, a thousand rows a page, five pages a pull.
  static const Map<TagType, String> categoryCodes = {
    TagType.artist: '1',
    TagType.character: '4',
    TagType.copyright: '3',
    TagType.meta: '5',
    TagType.none: '0',
  };

  /// Rows per builder page: the API's maximum.
  static const int catalogPageSize = 1000;

  @override
  bool get walksByCategory => true;

  @override
  int get catalogPagesPerPull => 5;

  @override
  Duration get catalogDelay => const Duration(milliseconds: 500);

  @override
  int pageSizeFor(Booru booru) => catalogPageSize;

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(categoryCodes.keys);

  String _creds(Booru booru) {
    final String key = booru.apiKey ?? '';
    final String user = booru.userID ?? '';
    if (key.isEmpty || user.isEmpty) return '';
    return '&login=$user&api_key=$key';
  }

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/tags.json?$query${_creds(booru)}',
      headers: {'User-Agent': Tools.browserUserAgent, ...?headers},
    );
    return parseRows(booru, response.data);
  }

  /// `[{name, category, post_count}, …]`; the numbering comes from the
  /// handler, resolved once for the page.
  @visibleForTesting
  static List<BooruTagEntry> parseRows(Booru booru, dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! List) return const [];
    final Map<String, TagType> types = TagIndexSource.typeMapFor(booru);
    return [
      for (final e in decoded)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: types[e['category']?.toString() ?? ''] ?? TagType.none,
            count: int.tryParse(e['post_count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  String _pageQuery(int page, int limit, {TagType? type}) =>
      'limit=$limit&page=${page + 1}'
      '${type == null ? '' : '&search[category]=${categoryCodes[type] ?? '0'}'}'
      '&search[order]=count&search[hide_empty]=yes';

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) => _fetch(booru, _pageQuery(page, pageSize));

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      _fetch(booru, _pageQuery(page, catalogPageSize), headers: headers);

  /// The query one category page sends.
  @visibleForTesting
  String categoryQuery(TagType type, int page) => _pageQuery(page, catalogPageSize, type: type);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) =>
      _fetch(booru, categoryQuery(type, page), headers: headers);

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
/// descriptive user agent, wraps the payload when it is empty, and caps a
/// page at 320 rows (verified 2026-09-06: 1000 is refused).
class E621TagIndex extends TagIndexSource {
  const E621TagIndex();

  @override
  int get pageSize => 100;

  @override
  bool get orderedByCount => true;

  static const Map<TagType, String> categoryCodes = {
    TagType.artist: '1',
    TagType.character: '4',
    TagType.copyright: '3',
    TagType.species: '5',
    TagType.meta: '7',
    // r44: the modelers of an animation, and lore tags.
    TagType.contributor: '2',
    TagType.lore: '8',
    TagType.none: '0',
  };

  static const int catalogPageSize = 320;

  @override
  bool get walksByCategory => true;

  @override
  int get catalogPagesPerPull => 10;

  /// The site's API policy: no more than one request a second, sustained.
  @override
  Duration get catalogDelay => const Duration(seconds: 1);

  @override
  int pageSizeFor(Booru booru) => catalogPageSize;

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(categoryCodes.keys);

  Map<String, String> _headers(Booru booru) {
    final String key = booru.apiKey ?? '';
    final String user = booru.userID ?? '';
    return {
      'User-Agent': Tools.appUserAgent,
      if (key.isNotEmpty && user.isNotEmpty)
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$key'))}',
    };
  }

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/tags.json?$query',
      headers: {..._headers(booru), ...?headers},
    );
    return parseRows(booru, response.data);
  }

  /// e621 answers `{"tags":[]}` for an empty result and a bare list otherwise.
  @visibleForTesting
  static List<BooruTagEntry> parseRows(Booru booru, dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    final List raw = decoded is List ? decoded : ((decoded is Map ? decoded['tags'] : null) as List? ?? const []);
    final Map<String, TagType> types = TagIndexSource.typeMapFor(booru);
    return [
      for (final e in raw)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: types[e['category']?.toString() ?? ''] ?? TagType.none,
            count: int.tryParse(e['post_count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  String _pageQuery(int page, int limit, {TagType? type}) =>
      'limit=$limit&page=${page + 1}'
      '${type == null ? '' : '&search[category]=${categoryCodes[type] ?? '0'}'}'
      '&search[order]=count&search[hide_empty]=true';

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) => _fetch(booru, _pageQuery(page, pageSize));

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      _fetch(booru, _pageQuery(page, catalogPageSize), headers: headers);

  /// The query one category page sends.
  @visibleForTesting
  String categoryQuery(TagType type, int page) => _pageQuery(page, catalogPageSize, type: type);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) =>
      _fetch(booru, categoryQuery(type, page), headers: headers);

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
///
/// Names are stored UNDERSCORED (`twilight_sparkle`), the way the app writes
/// every Philomena tag it meets on a post: the site spells them with spaces,
/// the query editor cannot hold a space inside a token, and the handler's
/// `formatTagsWithUnderscoresPhilomena` turns the underscores back into
/// spaces for the site. Rows stored with spaces could never be matched by
/// the store's lookups.
class PhilomenaTagIndex extends TagIndexSource {
  const PhilomenaTagIndex();

  /// The API caps `per_page` at 50 (verified 2026-09-06).
  @override
  int get pageSize => 50;

  @override
  bool get orderedByCount => true;

  @override
  bool get walksByCategory => true;

  @override
  int get catalogPagesPerPull => 40;

  @override
  Duration get catalogDelay => const Duration(milliseconds: 500);

  /// The query behind each chip (verified on derpibooru 2026-09-06).
  /// Artists are not a category: they are `origin` tags named `artist:…`,
  /// and `q=artist:*` lists them most-used first. General tags have no
  /// category at all, so that chip walks everything and keeps the untyped;
  /// the typed rows it meets on the way are stored too.
  static const Map<TagType, String> categoryQueries = {
    TagType.artist: 'artist:*',
    TagType.character: 'category:character',
    TagType.species: 'category:species',
    TagType.copyright: 'category:content-official',
    TagType.none: '*',
  };

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(categoryQueries.keys);

  static const Map<String, TagType> _categories = {
    'artist': TagType.artist,
    'character': TagType.character,
    'oc': TagType.character,
    // screencap, edit, alternate version… — the artists filed here are typed
    // by their name in [typeOf].
    'origin': TagType.meta,
    'species': TagType.species,
    'content-official': TagType.copyright,
    'content-fanmade': TagType.copyright,
    'rating': TagType.meta,
    'spoiler': TagType.meta,
    'error': TagType.meta,
  };

  /// The app's spelling of a site tag: lower case, underscores for spaces.
  @visibleForTesting
  static String normalizeName(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  @visibleForTesting
  static TagType typeOf(String name, String? category) =>
      name.startsWith('artist:') ? TagType.artist : (_categories[category] ?? TagType.none);

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/api/v1/json/search/tags?$query',
      headers: {'User-Agent': Tools.browserUserAgent, ...?headers},
    );
    return parseRows(response.data);
  }

  /// `{"tags":[{name, category, images}, …]}`.
  @visibleForTesting
  static List<BooruTagEntry> parseRows(dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    final List raw = (decoded is Map ? decoded['tags'] : null) as List? ?? const [];
    final List<BooruTagEntry> out = [];
    for (final e in raw) {
      if (e is! Map) continue;
      final String name = normalizeName(e['name']?.toString() ?? '');
      if (name.isEmpty) continue;
      out.add(
        BooruTagEntry(
          name: name,
          tagType: typeOf(name, e['category']?.toString()),
          count: int.tryParse(e['images']?.toString() ?? '') ?? 0,
        ),
      );
    }
    return out;
  }

  /// The wildcard stays a bare `*`, the way the site was verified.
  static String _encodeQ(String q) => Uri.encodeQueryComponent(q).replaceAll('%2A', '*');

  String _pageQuery(String q, int page) => 'q=${_encodeQ(q)}&per_page=$pageSize&page=${page + 1}&sf=images&sd=desc';

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) => _fetch(booru, _pageQuery('*', page));

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      _fetch(booru, _pageQuery('*', page), headers: headers);

  /// The query one category page sends.
  @visibleForTesting
  String categoryQuery(TagType type, int page) => _pageQuery(categoryQueries[type] ?? '*', page);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) =>
      _fetch(booru, categoryQuery(type, page), headers: headers);

  /// The site spells tags with spaces; an underscored query goes back with
  /// them.
  static String _siteSpelling(String query) => query.trim().toLowerCase().replaceAll('_', ' ');

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = _encodeQ('*${_siteSpelling(query)}*');
    return _fetch(booru, 'q=$q&per_page=$pageSize&sf=images&sd=desc');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = normalizeName(name);
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'q=${_encodeQ(_siteSpelling(clean))}&per_page=5');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}

/// Moebooru (yande.re, konachan). `/tag.json` lists by type most-used first
/// (verified 2026-09-06: `order=count&type=N&page=N`; yande.re takes
/// `limit=1000`, konachan answers 1000 with a Cloudflare page and 500 is
/// fine, so 500 it is).
class MoebooruTagIndex extends TagIndexSource {
  const MoebooruTagIndex();

  @override
  int get pageSize => 100;

  @override
  bool get orderedByCount => true;

  /// Types 5 and 6 mean different things per site (yande.re: circles and
  /// faults; konachan: style and series) and are left out.
  static const Map<TagType, String> categoryCodes = {
    TagType.artist: '1',
    TagType.character: '4',
    TagType.copyright: '3',
    TagType.none: '0',
  };

  static const int catalogPageSize = 500;

  @override
  bool get walksByCategory => true;

  @override
  int get catalogPagesPerPull => 4;

  @override
  Duration get catalogDelay => const Duration(milliseconds: 500);

  @override
  int pageSizeFor(Booru booru) => catalogPageSize;

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(categoryCodes.keys);

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/tag.json?$query',
      headers: {'User-Agent': Tools.browserUserAgent, ...?headers},
    );
    return parseRows(booru, response.data);
  }

  /// `[{name, type, count}, …]`.
  @visibleForTesting
  static List<BooruTagEntry> parseRows(Booru booru, dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! List) return const [];
    final Map<String, TagType> types = TagIndexSource.typeMapFor(booru);
    return [
      for (final e in decoded)
        if (e is Map && (e['name']?.toString().isNotEmpty ?? false))
          BooruTagEntry(
            name: e['name'].toString().toLowerCase(),
            tagType: types[e['type']?.toString() ?? ''] ?? TagType.none,
            count: int.tryParse(e['count']?.toString() ?? '') ?? 0,
          ),
    ];
  }

  String _pageQuery(int page, int limit, {TagType? type}) =>
      'limit=$limit&order=count${type == null ? '' : '&type=${categoryCodes[type] ?? '0'}'}&page=${page + 1}';

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) => _fetch(booru, _pageQuery(page, pageSize));

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      _fetch(booru, _pageQuery(page, catalogPageSize), headers: headers);

  /// The query one category page sends.
  @visibleForTesting
  String categoryQuery(TagType type, int page) => _pageQuery(page, catalogPageSize, type: type);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) =>
      _fetch(booru, categoryQuery(type, page), headers: headers);

  /// `name=` is a LIKE pattern with `*` wildcards (the handler's autocomplete
  /// relies on it), so a substring search wraps the query in them.
  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent('*${query.trim().toLowerCase().replaceAll(' ', '_')}*');
    return _fetch(booru, 'limit=$pageSize&order=count&name=$q');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'limit=5&name=${Uri.encodeComponent(clean)}');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}

/// Sankaku chan through `sankakuapi.com`: `/tags` lists by type most-used
/// first (verified 2026-09-06: `order=count&type=N&limit=1000&page=N`, no
/// account needed). Rows carry the canonical `tagName` beside a translated
/// display `name`.
class SankakuTagIndex extends TagIndexSource {
  const SankakuTagIndex();

  @override
  int get pageSize => 100;

  @override
  bool get orderedByCount => true;

  /// 8 is "medium" (comic, portrait, doujinshi…), which the handler already
  /// files as meta; 9 holds the site's own visibility flags and is skipped.
  static const Map<TagType, String> categoryCodes = {
    TagType.artist: '1',
    TagType.character: '4',
    TagType.copyright: '3',
    TagType.meta: '8',
    TagType.none: '0',
  };

  static const int catalogPageSize = 1000;

  @override
  bool get walksByCategory => true;

  @override
  int get catalogPagesPerPull => 3;

  @override
  Duration get catalogDelay => const Duration(milliseconds: 700);

  @override
  int pageSizeFor(Booru booru) => catalogPageSize;

  @override
  List<TagCatalogNamespace> catalogNamespaces(Booru booru) =>
      TagIndexSource.namespacesFor(categoryCodes.keys);

  /// What the handler sends, minus the session token.
  static Map<String, String> defaultHeaders() => {
    'Accept': 'application/json, text/plain, */*',
    'User-Agent': Constants.sankakuAppUserAgent,
    'Referer': 'https://sankaku.app/',
    'Origin': 'https://sankaku.app',
    'api-version': '2',
  };

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${SankakuHandler.apiBaseFor(booru)}/tags?lang=en&$query',
      headers: {...defaultHeaders(), ...?headers},
    );
    return parseRows(booru, response.data);
  }

  static String _nameOf(Map e) => (e['tagName'] ?? e['name'] ?? '').toString().toLowerCase();

  /// `[{tagName, name, type, post_count}, …]` — `tagName` is the tag, `name`
  /// its translation.
  @visibleForTesting
  static List<BooruTagEntry> parseRows(Booru booru, dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! List) return const [];
    final Map<String, TagType> types = TagIndexSource.typeMapFor(booru);
    return [
      for (final e in decoded)
        if (e is Map && _nameOf(e).isNotEmpty)
          BooruTagEntry(
            name: _nameOf(e),
            tagType: types[e['type']?.toString() ?? ''] ?? TagType.none,
            count: int.tryParse((e['post_count'] ?? e['count'])?.toString() ?? '') ?? 0,
          ),
    ];
  }

  String _pageQuery(int page, int limit, {TagType? type}) =>
      'limit=$limit&order=count${type == null ? '' : '&type=${categoryCodes[type] ?? '0'}'}&page=${page + 1}';

  @override
  Future<List<BooruTagEntry>> pageAt(Booru booru, int page) => _fetch(booru, _pageQuery(page, pageSize));

  @override
  Future<List<BooruTagEntry>> catalogPageAt(Booru booru, int page, {Map<String, String>? headers}) =>
      _fetch(booru, _pageQuery(page, catalogPageSize), headers: headers);

  /// The query one category page sends.
  @visibleForTesting
  String categoryQuery(TagType type, int page) => _pageQuery(page, catalogPageSize, type: type);

  @override
  Future<List<BooruTagEntry>> categoryPageAt(Booru booru, TagType type, int page, {Map<String, String>? headers}) =>
      _fetch(booru, categoryQuery(type, page), headers: headers);

  /// `name=` matches by prefix on this API — the handler's autocomplete.
  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = Uri.encodeComponent(query.trim().toLowerCase().replaceAll(' ', '_'));
    return _fetch(booru, 'limit=$pageSize&order=count&name=$q');
  }

  @override
  Future<BooruTagEntry?> exact(Booru booru, String name) async {
    final String clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final got = await _fetch(booru, 'limit=5&name=${Uri.encodeComponent(clean)}');
    for (final e in got) {
      if (e.name == clean) return e;
    }
    return null;
  }
}
