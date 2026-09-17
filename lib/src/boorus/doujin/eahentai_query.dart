/// What one eahentai request is (r69): which endpoint, its URL, or why it
/// cannot be made.
enum EaHentaiRequestKind { latest, search, popular, random, album }

class EaHentaiRequest {
  const EaHentaiRequest({required this.kind, required this.url, this.error, this.atEnd = false});

  final EaHentaiRequestKind kind;

  /// The full URL; empty when there is nothing to ask ([error] or [atEnd]).
  final String url;

  /// Refusal text; non-null means the handler locks with this message.
  final String? error;

  /// A feed with a single page (random) asked for a further page.
  final bool atEnd;
}

/// eahentai's search grammar, from the app's side (its JSON API, found in the
/// site's own scripts and fetched on 2026-09-17).
///
///   /api/image/latest/?page=P&take=N                     the newest, P from 0
///   /api/image/search/v2/?type=T&q=Q&take=N&page=P&orderby=O
///       T: gallery (everything) | artist | character | parody | tag
///       O: date_desc | views_daily | views_weekly | views_monthly | views_alltime
///   /api/image/popular/?page=P&take=N&orderby=O          the Popular section
///   /api/image/random/?take=N                            one page
///   /api/image/album/<id>                                a gallery with its pages
///
/// The app spells `sort:weekly`, `type:artist`, `filter:full_color`,
/// `artist:name`, `parody:name`, `character:name`, `tag:name`, `random:`;
/// underscores are the site's spaces. The site's quick-filter buttons append
/// their own words to the query (`q=santa Full Color`), and so does this.
class EaHentaiQuery {
  EaHentaiQuery._();

  static const String site = 'https://eahentai.com';
  static const String api = '$site/api/image';

  /// The site's own page size on its search page.
  static const int pageSize = 42;

  static const Map<String, String> sortOrders = {
    'latest': 'date_desc',
    'today': 'views_daily',
    'weekly': 'views_weekly',
    'monthly': 'views_monthly',
    'alltime': 'views_alltime',
  };

  /// The quick filters, in the site's own words.
  static const Map<String, String> filterWords = {
    'original': 'Original',
    'full_color': 'Full Color',
    'doujins': 'Doujins',
    'manga': 'Manga',
    'uncensored': 'Uncensored',
    'lolicon': 'Lolicon',
    'yuri': 'Yuri',
    'yaoi': 'Yaoi',
  };

  static const Set<String> types = {'all', 'gallery', 'artist', 'character', 'parody', 'tag'};

  /// A namespace the app writes -> the search type the site knows.
  static const Map<String, String> namespaceTypes = {
    'artist': 'artist',
    'parody': 'parody',
    'series': 'parody',
    'character': 'character',
    'tag': 'tag',
  };

  /// Splits on whitespace but keeps a quoted phrase in one piece.
  static List<String> tokenize(String input) => [
    for (final m in RegExp(r'\S*"[^"]*"\S*|\S+').allMatches(input.trim())) m.group(0)!,
  ];

  /// The site's spelling of an app term: no quotes, underscores as spaces.
  static String words(String term) => term.replaceAll('"', '').replaceAll('_', ' ').trim();

  static EaHentaiRequest parse(String tags, {required int page, int take = pageSize}) {
    String sort = 'latest';
    String? type;
    final List<String> filters = [];
    final List<(String type, String name)> named = [];
    final List<String> bare = [];
    bool random = false;
    String? error;

    for (final String token in tokenize(tags)) {
      final int colon = token.indexOf(':');
      final String key = colon > 0 ? token.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? token.substring(colon + 1) : '';
      switch (key) {
        case 'sort':
          final String v = value.toLowerCase();
          if (sortOrders.containsKey(v)) {
            sort = v;
          } else {
            error ??= 'sort: takes ${sortOrders.keys.join(' / ')}, not "$value".';
          }
        case 'type':
          final String v = value.toLowerCase();
          if (types.contains(v)) {
            type = v;
          } else {
            error ??= 'type: takes ${types.join(' / ')}, not "$value".';
          }
        case 'filter':
          final String v = value.toLowerCase();
          if (filterWords.containsKey(v)) {
            if (!filters.contains(v)) filters.add(v);
          } else {
            error ??= 'filter: takes ${filterWords.keys.join(' / ')}, not "$value".';
          }
        case 'random':
          random = true;
        case 'language':
          // The site is English-only: a language chip is not a search.
          break;
        case 'category':
          // The site's kinds are its Doujins / Manga quick filters.
          final String v = value.toLowerCase();
          if (v == 'doujinshi' || v == 'doujins') {
            if (!filters.contains('doujins')) filters.add('doujins');
          } else if (v == 'manga') {
            if (!filters.contains('manga')) filters.add('manga');
          } else {
            final String w = words(value);
            if (w.isNotEmpty) bare.add(w);
          }
        case 'artist' || 'parody' || 'series' || 'character' || 'tag':
          final String name = words(value);
          if (name.isNotEmpty) named.add((namespaceTypes[key]!, name));
        default:
          // A namespace the site has no search for (language:, category:) is
          // searched by its name alone; a bare word as it is.
          final String w = words(colon > 0 ? value : token);
          if (w.isNotEmpty) bare.add(w);
      }
    }
    if (error != null) return EaHentaiRequest(kind: EaHentaiRequestKind.search, url: '', error: error);

    final int p = page < 1 ? 0 : page - 1;
    final int n = take.clamp(1, 100);
    if (random) {
      if (page > 1) return const EaHentaiRequest(kind: EaHentaiRequestKind.random, url: '', atEnd: true);
      return EaHentaiRequest(kind: EaHentaiRequestKind.random, url: '$api/random/?take=$n');
    }

    final String q = [
      for (final (_, String name) in named) name,
      ...bare,
      for (final String f in filters) filterWords[f]!,
    ].join(' ').trim();

    if (q.isEmpty) {
      if (type != null && type != 'all' && type != 'gallery') {
        return EaHentaiRequest(
          kind: EaHentaiRequestKind.search,
          url: '',
          error: 'type: needs something to search for - a word, or artist: / parody: / character: / tag:.',
        );
      }
      if (sort == 'latest') return EaHentaiRequest(kind: EaHentaiRequestKind.latest, url: '$api/latest/?page=$p&take=$n');
      return EaHentaiRequest(kind: EaHentaiRequestKind.popular, url: '$api/popular/?page=$p&take=$n&orderby=${sortOrders[sort]}');
    }

    String t = type ?? 'gallery';
    if (type == null && named.length == 1 && bare.isEmpty) t = named.first.$1;
    if (t == 'all') t = 'gallery';
    return EaHentaiRequest(
      kind: EaHentaiRequestKind.search,
      url: '$api/search/v2/?type=$t&q=${Uri.encodeComponent(q)}&take=$n&page=$p&orderby=${sortOrders[sort]}',
    );
  }
}
