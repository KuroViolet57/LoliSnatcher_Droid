/// Lightweight summary of a saved-post collection (album), as shown on the
/// Collections page. The posts themselves live in the shared BooruItem table
/// and are loaded on demand by `CollectionsHandler`.
class CollectionInfo {
  const CollectionInfo({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.createdAt,
    this.coverThumbnailURL,
  });

  final int id;
  final String name;
  final int itemCount;
  final int createdAt;
  final String? coverThumbnailURL;
}
