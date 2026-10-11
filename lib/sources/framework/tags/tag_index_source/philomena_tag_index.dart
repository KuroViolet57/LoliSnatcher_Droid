part of '../tag_index_source.dart';

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
