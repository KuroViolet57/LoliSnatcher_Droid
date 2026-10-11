part of '../tag_index_source.dart';

/// Booru-on-Rails (twibooru and a booru of that type).
///
/// `GET /api/v3/search/tags` is already the suggestion call. Checked on
/// twibooru.org on 2026-10-07 with `LoliSnatcher_Droid/1.0.0`: pages are
/// most-used first, `per_page` is honored, and 500 still returns 250, so a
/// page of 50 cannot look like the end. The documented categories are
/// character, content-fanmade, content-official, error, oc, origin, rating,
/// species, and spoiler. General tags have no category. Artists are not a
/// category: they are origin tags named `artist:…`.
///
/// Names are stored underscored (`twilight_sparkle`). The posts API spells
/// them with spaces, and the handler already stores a post's tags with
/// underscores. The search URL turns those underscores back into `+`.
///
/// The tags endpoint allows 60 requests a minute. A pull waits just over a
/// second between pages.
class BooruOnRailsTagIndex extends TagIndexSource {
  const BooruOnRailsTagIndex();

  /// Under the 250-row cap seen when `per_page=500` was asked.
  @override
  int get pageSize => 50;

  @override
  bool get walksByCategory => true;

  @override
  Duration get catalogDelay => const Duration(milliseconds: 1100);

  /// The query behind each chip (twibooru, 2026-10-07).
  ///
  /// Copyrights are `content-official` (g4, equestria girls). Fan-made
  /// series are a different category and are typed when the general walk
  /// meets them. `oc` is the same: typed as a character, not its own chip.
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
    'character': TagType.character,
    'oc': TagType.character,
    'species': TagType.species,
    'content-official': TagType.copyright,
    'content-fanmade': TagType.copyright,
    'origin': TagType.meta,
    'rating': TagType.meta,
    'spoiler': TagType.meta,
    'error': TagType.meta,
  };

  /// The app's spelling: lower case, underscores for spaces.
  @visibleForTesting
  static String normalizeName(String raw) => raw.trim().toLowerCase().replaceAll(' ', '_');

  /// `artist needed` is an error tag, not an artist. Only the `artist:`
  /// prefix is an artist.
  @visibleForTesting
  static TagType typeOf(String name, String? category) =>
      name.startsWith('artist:') ? TagType.artist : (_categories[category] ?? TagType.none);

  Future<List<BooruTagEntry>> _fetch(Booru booru, String query, {Map<String, String>? headers}) async {
    final response = await DioNetwork.get(
      '${booru.baseURL}/api/v3/search/tags?$query',
      headers: {'User-Agent': Tools.browserUserAgent, ...?headers},
    );
    return parseRows(response.data);
  }

  /// `{"tags":[{name, category, posts, namespace}, …]}`.
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
          count: int.tryParse(e['posts']?.toString() ?? '') ?? 0,
        ),
      );
    }
    return out;
  }

  /// `*` and `+` stay literal. The suggestion URL writes them that way, and
  /// a `%2B` was not the form the site was checked with.
  static String _encodeQ(String q) =>
      Uri.encodeQueryComponent(q).replaceAll('%2A', '*').replaceAll('%2B', '+');

  String _pageQuery(String q, int page) => 'q=${_encodeQ(q)}&per_page=$pageSize&page=${page + 1}';

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

  /// Spaces and underscores both become the site's `+`.
  static String _siteSpelling(String query) => query.trim().toLowerCase().replaceAll('_', '+').replaceAll(' ', '+');

  /// A single token uses the suggestion form (`*rai*` finds rainbow dash).
  /// Stars around a multi-word tag returned nothing on twibooru
  /// (`*twilight+sparkle*`, 2026-10-07), so that query is sent plain.
  @visibleForTesting
  String searchQuery(String query) {
    final String spelled = _siteSpelling(query);
    if (spelled.isEmpty) return '';
    final String q = spelled.contains('+') ? spelled : '*$spelled*';
    return 'q=${_encodeQ(q)}&per_page=$pageSize';
  }

  @override
  Future<List<BooruTagEntry>> search(Booru booru, String query) {
    final String q = searchQuery(query);
    if (q.isEmpty) return Future.value(const []);
    return _fetch(booru, q);
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
