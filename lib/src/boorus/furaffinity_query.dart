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
///   gender: mode: perpage: from: to:     the rest of it (r41)
///
/// r41: filter terms without words are a search with no words, so the main
/// feed follows the Filters card (the browse page cannot sort or filter by
/// type). A filter term with a value the site does not have is dropped.
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
    this.genders = const [],
    this.mode = 'extended',
    this.perpage,
    this.rangeFrom,
    this.rangeTo,
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
  static const List<String> allGenders = ['male', 'female', 'trans_male', 'trans_female', 'intersex', 'non_binary'];
  static const List<String> modes = ['extended', 'all', 'any'];
  static const List<String> perpages = ['24', '48', '72'];

  /// The terms that set the search form rather than route or search words.
  static const Set<String> filterKeys = {'sort', 'order', 'range', 'type', 'rating', 'gender', 'mode', 'perpage', 'from', 'to'};

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
  final List<String> genders;
  final String mode;
  final String? perpage;
  final String? rangeFrom;
  final String? rangeTo;

  static final RegExp _token = RegExp(r'"[^"]*"(?:~\d+|/\d+)?|\S+');
  static final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static FurAffinityQuery parse(String tags) {
    FurAffinityRoute? route;
    String user = '';
    String id = '';
    String sort = 'relevancy';
    String order = 'desc';
    String range = 'all';
    String mode = 'extended';
    String? perpage;
    String? rangeFrom;
    String? rangeTo;
    final List<String> types = [];
    final List<String> ratings = [];
    final List<String> genders = [];
    String? category;
    String? theme;
    String? species;
    bool filtered = false;
    final List<String> words = [];

    void addTo(List<String> list, String value) {
      if (!list.contains(value)) list.add(value);
    }

    for (final RegExpMatch m in _token.allMatches(tags.trim())) {
      final String token = m.group(0)!;
      final int colon = token.indexOf(':');
      final String key = colon > 0 && !token.startsWith('"') ? token.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? token.substring(colon + 1).trim() : '';
      final String v = value.toLowerCase();
      if (filterKeys.contains(key)) {
        final bool ok = switch (key) {
          'sort' => sorts.contains(v),
          'order' => orders.contains(v),
          'range' => ranges.contains(v),
          'type' => allTypes.contains(v),
          'rating' => allRatings.contains(v),
          'gender' => allGenders.contains(v),
          'mode' => modes.contains(v),
          'perpage' => perpages.contains(v),
          _ => _date.hasMatch(v),
        };
        if (!ok) continue;
        filtered = true;
        switch (key) {
          case 'sort':
            sort = v;
          case 'order':
            order = v;
          case 'range':
            range = v;
          case 'type':
            addTo(types, v);
          case 'rating':
            addTo(ratings, v);
          case 'gender':
            addTo(genders, v);
          case 'mode':
            mode = v;
          case 'perpage':
            perpage = v;
          case 'from':
            rangeFrom = v;
          case 'to':
            rangeTo = v;
        }
        continue;
      }
      switch (key) {
        case 'user' || 'gallery' || 'artist' when value.isNotEmpty:
          route = FurAffinityRoute.gallery;
          user = v;
        case 'scraps' when value.isNotEmpty:
          route = FurAffinityRoute.scraps;
          user = v;
        case 'favorites' || 'favourites' when value.isNotEmpty:
          route = FurAffinityRoute.favorites;
          user = v;
        case 'id' when value.isNotEmpty:
          route = FurAffinityRoute.view;
          id = value;
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
    route ??= (text.isNotEmpty || category != null || theme != null || species != null || filtered) ? FurAffinityRoute.search : FurAffinityRoute.browse;
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
      genders: genders,
      mode: mode,
      perpage: perpage,
      rangeFrom: rangeFrom,
      rangeTo: rangeTo,
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
        final bool manual = rangeFrom != null || rangeTo != null;
        final Map<String, String> params = {
          'q': text,
          'page': '$p',
          'mode': mode,
          'order-by': sort,
          'order-direction': order,
          'range': manual ? 'manual' : range,
          'range_from': ?rangeFrom,
          'range_to': ?rangeTo,
          'perpage': ?perpage,
          for (final String r in ratings) 'rating-$r': '1',
          for (final String t in types) 'type-$t': '1',
          // The logged-in form's gender boxes; named like its rating and
          // type boxes (not visible logged out, so not captured).
          for (final String g in genders) 'gender-$g': '1',
          'category': ?category,
          'arttype': ?theme,
          'species': ?species,
        };
        return Uri.https(host, '/search/', params).toString();
    }
  }
}
