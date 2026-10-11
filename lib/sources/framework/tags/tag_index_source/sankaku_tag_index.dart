part of '../tag_index_source.dart';

/// Sankaku chan through `sankakuapi.com`: `/tags` lists by type most-used
/// first (verified 2026-09-06: `order=count&type=N&limit=1000&page=N`, no
/// account needed). Rows carry the canonical `tagName` beside a translated
/// display `name`.
class SankakuTagIndex extends TagIndexSource {
  const SankakuTagIndex();

  @override
  int get pageSize => 100;

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
