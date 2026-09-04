/// The search language of the kemono source, parsed once per fetch.
///
/// kemono's API has no query language of its own beyond `q`, `tag` and the
/// creator path, so the app's search text is mapped onto the handful of
/// feeds the site has:
///
///   plain words                     → `q=` (the site wants 3+ characters)
///   `tag:x` (repeatable)            → `tag=x` filters
///   `creator:{service}:{id}`        → that creator's posts
///   `{service}:{id}`                → same (the form the artist tag carries)
///   `creator:{name}`                → resolved through the creator index
///   `service:x`                     → filtered on the phone (no API filter)
///   `popular:day|week|month|recent[:YYYY-MM-DD]`
///   `random`                        → one random post
///   `favorites:posts`               → the account's favourite posts
///   `id:{service}:{creator}:{post}` → one post
///
/// Pure Dart: no Flutter import, so the grammar is testable without bindings.
enum KemonoQueryKind { posts, creatorPosts, popular, randomPost, favouritePosts, post }

class KemonoQuery {
  const KemonoQuery({
    required this.kind,
    this.q = '',
    this.tags = const [],
    this.service,
    this.creatorId,
    this.creatorName,
    this.postId,
    this.period = 'day',
    this.date,
    this.error,
  });

  static const List<String> services = [
    'patreon',
    'fanbox',
    'gumroad',
    'discord',
    'fantia',
    'boosty',
    'subscribestar',
    'dlsite',
  ];

  static const List<String> periods = ['recent', 'day', 'week', 'month'];

  static const String tooShortMessage = 'kemono needs at least 3 characters to search';

  final KemonoQueryKind kind;

  /// Free text for `q=`; empty when none.
  final String q;

  /// `tag=` filters, as the site spells them (spaces, not underscores).
  final List<String> tags;

  /// A creator's service, or the client-side service filter for plain feeds.
  final String? service;
  final String? creatorId;

  /// A creator named rather than identified; the handler resolves it.
  final String? creatorName;
  final String? postId;
  final String period;
  final String? date;

  /// A reason the query cannot run at all (shown instead of an empty grid).
  final String? error;

  bool get needsCreatorLookup => kind == KemonoQueryKind.creatorPosts && creatorId == null && creatorName != null;

  /// The tab-level creator, when the query is one creator's posts.
  ({String service, String id})? get creator =>
      kind == KemonoQueryKind.creatorPosts && service != null && creatorId != null
      ? (service: service!, id: creatorId!)
      : null;

  KemonoQuery copyWith({String? service, String? creatorId, String? creatorName, String? error}) => KemonoQuery(
    kind: kind,
    q: q,
    tags: tags,
    service: service ?? this.service,
    creatorId: creatorId ?? this.creatorId,
    creatorName: creatorName ?? this.creatorName,
    postId: postId,
    period: period,
    date: date,
    error: error ?? this.error,
  );

  static final RegExp _serviceId = RegExp(r'^([a-z]+):([A-Za-z0-9_.-]+)$');
  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static KemonoQuery parse(String input) {
    final List<String> words = [];
    final List<String> tags = [];
    String? service;
    String? creatorId;
    String? creatorName;
    String? creatorService;
    String? postId;
    String? postCreator;
    String? postService;
    String period = 'day';
    String? date;
    bool popular = false;
    bool random = false;
    bool favourites = false;
    bool single = false;
    String? error;

    for (final String raw in input.trim().split(RegExp(r'\s+'))) {
      final String term = raw.trim();
      if (term.isEmpty) continue;
      // The site cannot exclude anything; a negated term is dropped.
      if (term.startsWith('-')) continue;
      final String lower = term.toLowerCase();
      final int colon = term.indexOf(':');
      final String key = colon > 0 ? lower.substring(0, colon) : lower;
      final String value = colon > 0 ? term.substring(colon + 1) : '';

      if (colon > 0 && key == 'tag' && value.isNotEmpty) {
        tags.add(value.replaceAll('_', ' '));
        continue;
      }
      if (colon > 0 && key == 'creator' && value.isNotEmpty) {
        final match = _serviceId.firstMatch(value.toLowerCase());
        if (match != null && services.contains(match.group(1))) {
          creatorService = match.group(1);
          creatorId = value.substring(value.indexOf(':') + 1);
        } else {
          creatorName = value.replaceAll('_', ' ');
        }
        continue;
      }
      if (colon > 0 && services.contains(key) && value.isNotEmpty && !value.contains(':')) {
        creatorService = key;
        creatorId = value;
        continue;
      }
      if (colon > 0 && key == 'service') {
        final String s = value.toLowerCase();
        if (services.contains(s)) service = s;
        continue;
      }
      if (colon > 0 && key == 'popular') {
        popular = true;
        final List<String> parts = value.toLowerCase().split(':');
        if (parts.isNotEmpty && periods.contains(parts[0])) period = parts[0];
        if (parts.length > 1) {
          if (_isoDate.hasMatch(parts[1]) && DateTime.tryParse(parts[1]) != null) {
            date = parts[1];
          } else {
            error = 'popular wants a date as YYYY-MM-DD';
          }
        }
        continue;
      }
      if (lower == 'popular') {
        popular = true;
        continue;
      }
      if (lower == 'random') {
        random = true;
        continue;
      }
      if ((key == 'favorites' || key == 'favourites') && (value.isEmpty || value.toLowerCase() == 'posts')) {
        favourites = true;
        continue;
      }
      if (colon > 0 && key == 'id') {
        final List<String> parts = value.split(':');
        if (parts.length == 3 && services.contains(parts[0].toLowerCase())) {
          single = true;
          postService = parts[0].toLowerCase();
          postCreator = parts[1];
          postId = parts[2];
        } else {
          error = 'id wants service:creator:post';
        }
        continue;
      }
      words.add(term);
    }

    final String q = words.join(' ');
    KemonoQueryKind kind = KemonoQueryKind.posts;
    if (single) {
      kind = KemonoQueryKind.post;
    } else if (random) {
      kind = KemonoQueryKind.randomPost;
    } else if (favourites) {
      kind = KemonoQueryKind.favouritePosts;
    } else if (popular) {
      kind = KemonoQueryKind.popular;
    } else if (creatorId != null || creatorName != null) {
      kind = KemonoQueryKind.creatorPosts;
    }
    if ((kind == KemonoQueryKind.posts || kind == KemonoQueryKind.creatorPosts) && q.isNotEmpty && q.length < 3) {
      error ??= tooShortMessage;
    }
    return KemonoQuery(
      kind: kind,
      q: q,
      tags: tags,
      service: kind == KemonoQueryKind.post
          ? postService
          : (kind == KemonoQueryKind.creatorPosts ? creatorService : service),
      creatorId: kind == KemonoQueryKind.post ? postCreator : creatorId,
      creatorName: creatorName,
      postId: postId,
      period: period,
      date: date,
      error: error,
    );
  }
}
