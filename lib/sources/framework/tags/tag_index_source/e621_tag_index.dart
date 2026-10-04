part of '../tag_index_source.dart';

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
