part of '../tag_index_source.dart';

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
