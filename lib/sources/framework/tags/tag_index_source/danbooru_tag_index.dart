part of '../tag_index_source.dart';

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
