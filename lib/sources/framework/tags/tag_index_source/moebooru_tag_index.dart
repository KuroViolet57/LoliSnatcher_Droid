part of '../tag_index_source.dart';

/// Moebooru (yande.re, konachan). `/tag.json` lists by type most-used first
/// (verified 2026-09-06: `order=count&type=N&page=N`; yande.re takes
/// `limit=1000`, konachan answers 1000 with a Cloudflare page and 500 is
/// fine, so 500 it is).
class MoebooruTagIndex extends TagIndexSource {
  const MoebooruTagIndex();

  @override
  int get pageSize => 100;

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
