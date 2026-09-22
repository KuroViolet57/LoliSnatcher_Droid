/// One parsed e-hentai search: what goes on the URL.
class EHentaiSearch {
  const EHentaiSearch({
    required this.source,
    this.terms = const [],
    this.excludedCategories = 0,
    this.minRating,
    this.minPages,
    this.maxPages,
    this.showExpunged = false,
    this.requireTorrent = false,
    this.error,
  });

  final String source;

  /// Site terms in the site's own syntax (`female:"big breasts"$`, `yuri`).
  final List<String> terms;

  /// `f_cats`: the categories the site must NOT show. 0 = everything.
  final int excludedCategories;

  final int? minRating;
  final int? minPages;
  final int? maxPages;

  /// The site's advanced options (r70): `f_sh` shows expunged galleries,
  /// `f_sto` keeps only galleries with a torrent.
  final bool showExpunged;
  final bool requireTorrent;

  /// Refusal text; non-null means the handler locks with this message.
  final String? error;

  String get fSearch => terms.join(' ');

  bool get advanced => minRating != null || minPages != null || maxPages != null || showExpunged || requireTorrent;
}

/// e-hentai's search grammar, from the app's side (probed 2026-09-09).
///
/// The app spells tags `namespace:name_with_underscores`; the site wants
/// `namespace:"name with underscores"$` for an exact tag match (the `$`
/// anchors the name, the quotes carry the spaces). `-` keeps its meaning.
/// Bare words are keyword (title) search. `category:` chips become the
/// `f_cats` mask, which lists the categories to EXCLUDE (verified: 1013
/// leaves doujinshi and artist cg). `rating:N`, `pages:a-b` need
/// `advsearch=1`. The site has no sort: newest first, a `next=<gid>`
/// cursor for the following page.
class EHentaiQuery {
  EHentaiQuery._();

  static const int allCategories = 1023;

  static const Map<String, int> categoryBits = {
    'misc': 1,
    'doujinshi': 2,
    'manga': 4,
    'artistcg': 8,
    'gamecg': 16,
    'imageset': 32,
    'cosplay': 64,
    'asianporn': 128,
    'non-h': 256,
    'western': 512,
  };

  /// Spellings a chip or a tag tap may hand over.
  static const Map<String, String> _categoryAliases = {
    'artist_cg': 'artistcg',
    'artist-cg': 'artistcg',
    'game_cg': 'gamecg',
    'game-cg': 'gamecg',
    'image_set': 'imageset',
    'image-set': 'imageset',
    'asian_porn': 'asianporn',
    'asian-porn': 'asianporn',
    'non_h': 'non-h',
    'nonh': 'non-h',
  };

  static String? categoryKey(String raw) {
    final String v = raw.trim().toLowerCase();
    if (categoryBits.containsKey(v)) return v;
    return _categoryAliases[v];
  }

  /// One app token in the site's syntax.
  static String siteTerm(String token) {
    final bool negated = token.startsWith('-');
    final String body = negated ? token.substring(1) : token;
    final String sign = negated ? '-' : '';
    final int colon = body.indexOf(':');
    if (colon > 0 && colon < body.length - 1) {
      final String ns = body.substring(0, colon).toLowerCase();
      final String name = body.substring(colon + 1);
      if (ns == 'uploader') return '${sign}uploader:$name';
      // A name the person already quoted stays as it is; the app's own
      // underscored form becomes the site's quoted, anchored one.
      if (name.startsWith('"') && name.endsWith('"')) return '$sign$ns:$name\$';
      return '$sign$ns:"${name.replaceAll('_', ' ')}"\$';
    }
    // A bare word is a keyword search; underscores came from the app's tag
    // conventions and would match nothing in a title.
    if (body.startsWith('"') && body.endsWith('"')) return token;
    if (body.contains('_')) return '$sign"${body.replaceAll('_', ' ')}"';
    return token;
  }

  static final RegExp _pagesRange = RegExp(r'^(\d+)(?:-(\d+))?$');

  /// Splits on whitespace but keeps a quoted phrase in one piece, so
  /// `female:"big breasts"` survives as one term.
  static List<String> tokenize(String input) => [
    for (final m in RegExp(r'\S*"[^"]*"\S*|\S+').allMatches(input.trim())) m.group(0)!,
  ];

  /// The keys that are not site terms but instructions to the app.
  static const Set<String> reservedKeys = {'category', 'cat', 'rating', 'pages', 'expunged', 'torrent'};

  static EHentaiSearch parse(String input) {
    final String source = input.trim();
    final List<String> terms = [];
    int selected = 0;
    int? minRating;
    int? minPages;
    int? maxPages;
    bool showExpunged = false;
    bool requireTorrent = false;
    String? error;
    for (final String token in tokenize(source)) {
      if (token.isEmpty) continue;
      // A leading `-` is the site's exclusion, which its own namespaces take
      // but the app's own keys cannot: `-category:x` would be sent as a term
      // in a namespace the site does not have, and match nothing at all.
      final bool negated = token.startsWith('-');
      final String body = negated ? token.substring(1) : token;
      final int colon = body.indexOf(':');
      final String key = colon > 0 ? body.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? body.substring(colon + 1) : '';
      if (negated && reservedKeys.contains(key)) {
        error ??= 'e-hentai: $key: cannot be excluded — it is a filter, not a tag. Drop the minus, or leave it out.';
        continue;
      }
      switch (key) {
        case 'category' || 'cat':
          final String? cat = categoryKey(value);
          if (cat == null) {
            error ??= 'e-hentai has no category "$value": use ${categoryBits.keys.join(' / ')}.';
          } else {
            selected |= categoryBits[cat]!;
          }
        case 'rating':
          final int? n = int.tryParse(value);
          if (n == null || n < 2 || n > 5) {
            error ??= 'rating: takes the minimum stars, 2 to 5.';
          } else {
            minRating = n;
          }
        case 'expunged':
          showExpunged = value.toLowerCase() != 'off';
        case 'torrent':
          requireTorrent = value.toLowerCase() != 'off';
        case 'pages':
          final RegExpMatch? m = _pagesRange.firstMatch(value);
          if (m == null) {
            error ??= 'pages: takes a count or a range, like pages:10-50.';
          } else {
            minPages = int.parse(m.group(1)!);
            if (m.group(2) != null) maxPages = int.parse(m.group(2)!);
          }
        default:
          terms.add(siteTerm(token));
      }
    }
    return EHentaiSearch(
      source: source,
      terms: terms,
      excludedCategories: selected == 0 ? 0 : allCategories - selected,
      minRating: minRating,
      minPages: minPages,
      maxPages: maxPages,
      showExpunged: showExpunged,
      requireTorrent: requireTorrent,
      error: error,
    );
  }

  /// The listing URL. The extended view (`inline_set=dm_e`) is asked for on
  /// every request so the rows carry their tags whatever the site's sticky
  /// display cookie says; [cursor] is the `next=<gid>` of the previous page.
  ///
  /// r70: [path] is the page searched - `/` (the front page), `/watched`
  /// (the account's tag-watch feed) or `/favorites.php` (the account's
  /// favourites, [favcat] 0-9 for one of its categories); all three take the
  /// same search parameters and the same cursor.
  static String listingUrl(String site, EHentaiSearch s, {String? cursor, String path = '/', String? favcat}) {
    final List<String> params = [];
    if (favcat != null && favcat.isNotEmpty) params.add('favcat=$favcat');
    if (s.fSearch.isNotEmpty) params.add('f_search=${Uri.encodeQueryComponent(s.fSearch)}');
    if (s.excludedCategories > 0) params.add('f_cats=${s.excludedCategories}');
    if (s.advanced) {
      params.add('advsearch=1');
      if (s.showExpunged) params.add('f_sh=on');
      if (s.requireTorrent) params.add('f_sto=on');
      if (s.minRating != null) params.add('f_srdd=${s.minRating}');
      if (s.minPages != null) params.add('f_spf=${s.minPages}');
      if (s.maxPages != null) params.add('f_spt=${s.maxPages}');
    }
    params.add('inline_set=dm_e');
    if (cursor != null && cursor.isNotEmpty) params.add('next=$cursor');
    return '$site$path?${params.join('&')}';
  }

  /// The site's toplists: galleries of all time, the past year, the past
  /// month, yesterday. Numbered pages, `p` from 0 and absent on the first.
  static const Map<String, int> toplistCodes = {
    'toplist_alltime': 11,
    'toplist_year': 12,
    'toplist_month': 13,
    'toplist_yesterday': 15,
  };

  static String toplistUrl(String site, String sort, {required int page}) =>
      '$site/toplist.php?tl=${toplistCodes[sort]}${page > 1 ? '&p=${page - 1}' : ''}';
}
