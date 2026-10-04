/// A pool / gallery / collection of posts on a booru.
///
/// Sites disagree on the name (danbooru & e621 "pools", gelbooru-family
/// "pools", philomena "galleries") and on what they expose, so everything
/// past [id] and [name] is optional.
class BooruPool {
  const BooruPool({
    required this.id,
    required this.name,
    this.description,
    this.creator,
    this.postCount,
    this.postIds,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final String? description;
  final String? creator;
  final int? postCount;

  /// Member post ids IN POOL ORDER, when the source hands them over up front
  /// (e621 does). Comics depend on this order, so it must never be re-sorted.
  final List<String>? postIds;

  /// Only set when the listing gives one for free — never worth a request.
  final String? thumbnailUrl;

  /// Human-readable name (pools are usually stored with underscores).
  String get displayName => name.replaceAll('_', ' ').trim();
}
