/// What the app types, as FurAffinity pages (r40). The site has no content
/// API; every route is one of its own HTML pages:
///
///   ''                                   the browse page (newest)
///   words and the site's operators       /search/ (| OR, -/! NOT, ( ), "phrase", <<, ~N, /N)
///   user:name / gallery:name / artist:name   the artist's gallery
///   scraps:name, favorites:name          their scraps and favorites
///   id:N                                 one submission
///   category:N theme:N species:N         search filters by the site's ids
///   sort: order: type: rating: range:    the search form's own options
enum FurAffinityRoute { browse, search, gallery, scraps, favorites, view }

class FurAffinityQuery {
  const FurAffinityQuery({
    required this.kind,
    this.user = '',
    this.id = '',
    this.text = '',
    this.sort = 'relevancy',
    this.order = 'desc',
    this.types = defaultTypes,
    this.ratings = defaultRatings,
    this.range = 'all',
    this.category,
    this.theme,
    this.species,
  });

  static const String host = 'www.furaffinity.net';
  static const String site = 'https://$host';

  static const List<String> sorts = ['relevancy', 'date', 'popularity'];
  static const List<String> orders = ['desc', 'asc'];
  static const List<String> ranges = ['1day', '3days', '7days', '30days', '90days', '1year', '3years', '5years', 'all'];
  static const List<String> allTypes = ['art', 'photo', 'music', 'story', 'poetry', 'flash'];
  static const List<String> defaultTypes = ['art', 'photo'];
  static const List<String> allRatings = ['general', 'mature', 'adult'];
  static const List<String> defaultRatings = allRatings;

  final FurAffinityRoute kind;
  final String user;
  final String id;
  final String text;
  final String sort;
  final String order;
  final List<String> types;
  final List<String> ratings;
  final String range;
  final String? category;
  final String? theme;
  final String? species;

  static final RegExp _token = RegExp(r'"[^"]*"(?:~\d+|/\d+)?|\S+');

  static FurAffinityQuery parse(String tags) {
    FurAffinityRoute? route;
    String user = '';
    String id = '';
    String sort = 'relevancy';
    String order = 'desc';
    String range = 'all';
    final List<String> types = [];
    final List<String> ratings = [];
    String? category;
    String? theme;
    String? species;
    final List<String> words = [];

    for (final RegExpMatch m in _token.allMatches(tags.trim())) {
      final String token = m.group(0)!;
      final int colon = token.indexOf(':');
      final String key = colon > 0 && !token.startsWith('"') ? token.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? token.substring(colon + 1).trim() : '';
      switch (key) {
        case 'user' || 'gallery' || 'artist' when value.isNotEmpty:
          route = FurAffinityRoute.gallery;
          user = value.toLowerCase();
        case 'scraps' when value.isNotEmpty:
          route = FurAffinityRoute.scraps;
          user = value.toLowerCase();
        case 'favorites' || 'favourites' when value.isNotEmpty:
          route = FurAffinityRoute.favorites;
          user = value.toLowerCase();
        case 'id' when value.isNotEmpty:
          route = FurAffinityRoute.view;
          id = value;
        case 'sort' when sorts.contains(value.toLowerCase()):
          sort = value.toLowerCase();
        case 'order' when orders.contains(value.toLowerCase()):
          order = value.toLowerCase();
        case 'range' when ranges.contains(value.toLowerCase()):
          range = value.toLowerCase();
        case 'type' when allTypes.contains(value.toLowerCase()):
          if (!types.contains(value.toLowerCase())) types.add(value.toLowerCase());
        case 'rating' when allRatings.contains(value.toLowerCase()):
          if (!ratings.contains(value.toLowerCase())) ratings.add(value.toLowerCase());
        case 'category' when value.isNotEmpty:
          category = value;
        case 'theme' when value.isNotEmpty:
          theme = value;
        case 'species' when value.isNotEmpty:
          species = value;
        default:
          words.add(token);
      }
    }

    final String text = words.join(' ');
    route ??= (text.isNotEmpty || category != null || theme != null || species != null) ? FurAffinityRoute.search : FurAffinityRoute.browse;
    return FurAffinityQuery(
      kind: route,
      user: user,
      id: id,
      text: text,
      sort: sort,
      order: order,
      types: types.isEmpty ? defaultTypes : types,
      ratings: ratings.isEmpty ? defaultRatings : ratings,
      range: range,
      category: category,
      theme: theme,
      species: species,
    );
  }

  /// The page for [page] (1-based); favorites page by the [cursor] the
  /// previous page handed over. '' when there is no such page.
  String url({required int page, String? cursor}) {
    final int p = page < 1 ? 1 : page;
    switch (kind) {
      case FurAffinityRoute.browse:
        return p == 1 ? '$site/browse/' : '$site/browse/$p/';
      case FurAffinityRoute.gallery:
        return p == 1 ? '$site/gallery/$user/' : '$site/gallery/$user/$p/';
      case FurAffinityRoute.scraps:
        return p == 1 ? '$site/scraps/$user/' : '$site/scraps/$user/$p/';
      case FurAffinityRoute.favorites:
        if (p == 1) return '$site/favorites/$user/';
        return (cursor == null || cursor.isEmpty) ? '' : '$site/favorites/$user/$cursor/next';
      case FurAffinityRoute.view:
        return '$site/view/$id/';
      case FurAffinityRoute.search:
        final Map<String, String> params = {
          'q': text,
          'page': '$p',
          'mode': 'extended',
          'order-by': sort,
          'order-direction': order,
          'range': range,
          for (final String r in ratings) 'rating-$r': '1',
          for (final String t in types) 'type-$t': '1',
          'category': ?category,
          'arttype': ?theme,
          'species': ?species,
        };
        return Uri.https(host, '/search/', params).toString();
    }
  }
}
