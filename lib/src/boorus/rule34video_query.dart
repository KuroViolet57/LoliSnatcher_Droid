/// Where a rule34video query is served from. The site (KVS) has one list
/// per route and no way to combine them, so a query is exactly one of these.
enum Rule34VideoRoute { latest, search, tag, artist, category, uploader }

/// One parsed rule34video query — pure data, so the grammar is testable
/// without a handler and `makeURL` stays synchronous.
class Rule34VideoQuery {
  const Rule34VideoQuery({
    required this.source,
    required this.route,
    this.text = '',
    this.name,
    this.key,
    this.sort,
    this.groups = const [],
    this.error,
  });

  /// The validated input this was parsed from; `makeURL` re-parses when the
  /// handler is asked about a different query than it last resolved.
  final String source;
  final Rule34VideoRoute route;

  /// Search words, spaces between them (underscores converted).
  final String text;

  /// The facet's name, normalized (`makima_(chainsaw_man)`, `paranoiddroid`).
  final String? name;

  /// What the site keys the route by: a tag id, a member id, or a KVS slug.
  /// Null on tag/uploader routes until the id is resolved.
  final String? key;

  /// KVS `sort_by` value, or null for the site's own order.
  final String? sort;

  /// Content group ids, in the order typed; a union. Empty = everything.
  final List<String> groups;

  /// Refusal text; non-null means the handler locks with this message.
  final String? error;

  bool get needsResolution =>
      key == null && (route == Rule34VideoRoute.tag || route == Rule34VideoRoute.uploader);

  /// The text-search block ignores the site's content filter, so with groups
  /// selected the phone has to drop cards itself.
  bool get filtersOnPhone => route == Rule34VideoRoute.search && groups.isNotEmpty;

  Rule34VideoQuery copyWith({
    Rule34VideoRoute? route,
    String? text,
    String? name,
    String? key,
    String? sort,
    List<String>? groups,
    String? error,
  }) => Rule34VideoQuery(
    source: source,
    route: route ?? this.route,
    text: text ?? this.text,
    name: name ?? this.name,
    key: key ?? this.key,
    sort: sort ?? this.sort,
    groups: groups ?? this.groups,
    error: error ?? this.error,
  );

  /// The site's content groups, read off its header toggles (2026-09-06).
  static const Map<String, String> groupIds = {
    'straight': '2109',
    'gay': '192',
    'futa': '15',
    'music': '4747',
    'iwara': '1821',
  };

  /// App word -> KVS `sort_by`. `relevant` is the site's own order (relevance
  /// on text search, newest elsewhere), sent as no parameter.
  static const Map<String, String?> sorts = {
    'relevant': null,
    'newest': 'post_date',
    'viewed': 'video_viewed',
    'rated': 'rating',
    'longest': 'duration',
    'random': 'pseudo_rand',
    'favourited': 'most_favourited',
  };

  static const String refusal =
      'rule34video opens one tag, artist:, category: or uploader: page at a time, '
      'or searches words — it cannot combine them. Try one of them alone.';

  /// The app's spelling of a site name: lowercase, underscores for spaces.
  static String normalizeName(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  /// The slug KVS puts in `/models/{slug}/` and `/categories/{slug}/`:
  /// `NSFW_Sonia_VA (VA)` -> `nsfw-sonia-va-va`, `101 dalmatians` ->
  /// `101-dalmatians`, `2D` -> `2d`. Non-ASCII names need the snapshot's
  /// stored slug instead.
  static String kvsSlug(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp('[^a-z0-9-]'), '-')
      .replaceAll(RegExp('-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static String? groupIdOf(String value) {
    final String v = value.trim().toLowerCase();
    if (groupIds.containsKey(v)) return groupIds[v];
    return groupIds.containsValue(v) ? v : null;
  }

  /// Parses a query. Tokens split on whitespace; `key:value` on the first
  /// colon. [defaultGroups] is the per-source content-type default, used
  /// only when the query carries no `type:` of its own; [defaultSort] (an
  /// app word or KVS key) likewise stands in for a missing `sort:`; the
  /// known-id maps let a bare word or `tag:` route straight to `/tags/{id}/`.
  static Rule34VideoQuery parse(
    String input, {
    List<String> defaultGroups = const [],
    String? defaultSort,
    Map<String, String> knownTagIds = const {},
    Map<String, String> knownUploaderIds = const {},
  }) {
    final String source = input.trim();
    String? sort;
    bool sortGiven = false;
    final List<String> groups = [];
    bool typeGiven = false;
    final List<String> words = [];
    final List<(Rule34VideoRoute route, String value)> facets = [];
    String? error;

    for (final String token in source.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final int colon = token.indexOf(':');
      final String key = colon > 0 ? token.substring(0, colon).toLowerCase() : '';
      final String value = colon > 0 ? token.substring(colon + 1) : '';
      switch (key) {
        case 'sort' || 'order':
          sortGiven = true;
          final String v = value.toLowerCase();
          if (sorts.containsKey(v)) {
            sort = sorts[v];
          } else if (sorts.containsValue(v)) {
            sort = v;
          } else {
            error ??= 'rule34video has no sort "$value": use ${sorts.keys.join(' / ')}.';
          }
        case 'type':
          typeGiven = true;
          final String? id = groupIdOf(value);
          if (id == null) {
            error ??= 'rule34video has no content type "$value": use ${groupIds.keys.join(' / ')}.';
          } else if (!groups.contains(id)) {
            groups.add(id);
          }
        case 'tag':
          if (value.isNotEmpty) facets.add((Rule34VideoRoute.tag, value));
        case 'artist' || 'model':
          if (value.isNotEmpty) facets.add((Rule34VideoRoute.artist, value));
        case 'category':
          if (value.isNotEmpty) facets.add((Rule34VideoRoute.category, value));
        case 'uploader' || 'user':
          if (value.isNotEmpty) facets.add((Rule34VideoRoute.uploader, value));
        default:
          words.add(token);
      }
    }
    if (!sortGiven) {
      final String d = (defaultSort ?? '').trim().toLowerCase();
      sort = sorts.containsKey(d) ? sorts[d] : (sorts.containsValue(d) ? d : null);
    }

    final List<String> effectiveGroups = typeGiven ? groups : List<String>.from(defaultGroups);

    if (error != null) {
      return Rule34VideoQuery(source: source, route: Rule34VideoRoute.latest, error: error);
    }
    if (facets.length > 1 || (facets.isNotEmpty && words.isNotEmpty)) {
      return Rule34VideoQuery(source: source, route: Rule34VideoRoute.latest, error: refusal);
    }

    if (facets.isNotEmpty) {
      final (Rule34VideoRoute route, String raw) = facets.single;
      final String name = normalizeName(raw);
      return switch (route) {
        Rule34VideoRoute.tag => Rule34VideoQuery(
          source: source,
          route: route,
          name: name,
          key: knownTagIds[name],
          sort: sort,
          groups: effectiveGroups,
        ),
        Rule34VideoRoute.uploader => Rule34VideoQuery(
          source: source,
          route: route,
          name: name,
          key: RegExp(r'^\d+$').hasMatch(name) ? name : knownUploaderIds[name],
          sort: sort,
          groups: effectiveGroups,
        ),
        _ => Rule34VideoQuery(
          source: source,
          route: route,
          name: name,
          key: kvsSlug(raw),
          sort: sort,
          groups: effectiveGroups,
        ),
      };
    }

    if (words.isEmpty) {
      return Rule34VideoQuery(source: source, route: Rule34VideoRoute.latest, sort: sort, groups: effectiveGroups);
    }

    // One bare word the session already knows as a tag is better served by
    // the tag page: exhaustive, and the content filter works there.
    if (words.length == 1) {
      final String name = normalizeName(words.single);
      final String? id = knownTagIds[name];
      if (id != null) {
        return Rule34VideoQuery(
          source: source,
          route: Rule34VideoRoute.tag,
          name: name,
          key: id,
          sort: sort,
          groups: effectiveGroups,
        );
      }
    }

    // The site's search is natural language: every cross-booru feature hands
    // over underscored tags, so underscores become spaces here.
    final String text = words.map((w) => w.replaceAll('_', ' ')).join(' ').trim();
    return Rule34VideoQuery(source: source, route: Rule34VideoRoute.search, text: text, sort: sort, groups: effectiveGroups);
  }
}
