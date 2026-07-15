/// A creator/channel surfaced alongside search results (for the discovery
/// strip that appears above the grid).
///
/// Handlers that can identify the creators behind their results populate a list
/// of these on the base handler; the strip renders them and, when one is
/// tapped, runs a search for [searchQuery].
class CreatorInfo {
  const CreatorInfo({
    required this.searchQuery,
    required this.displayName,
    this.avatarUrl,
    this.coverUrl,
    this.subtitle,
  });

  /// The search text to run when this creator is tapped (e.g. a bare username
  /// for xxxfollow, or `creator:name` for redgifs).
  final String searchQuery;

  final String displayName;
  final String? avatarUrl;
  final String? coverUrl;

  /// Optional secondary line (e.g. gif/post count).
  final String? subtitle;
}
