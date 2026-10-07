import 'package:lolisnatcher/models/booru_type.dart';

/// Extra tags a remote media chip adds, in the app's pipe OR syntax.
///
/// The search translator turns `a|b` into `~a ~b` before Danbooru sees it.
/// Null means this source has no checked query for that chip. An empty
/// string means the chip asks for everything and adds no tags.
///
/// Checked on 2026-10-07 with the app user agent.
///
/// Danbooru `filetype:` tilde form returned mp4 beside `1girl`, and the image
/// clause returned jpg and png. `filetype:gif` and `filetype:webm` each
/// returned that extension. Sound has no filetype. Flash and ugoira are in
/// neither Images nor Video.
///
/// e621, e926, and e6ai `type:` tilde form returned webm and mp4, including
/// beside `1girl` on e621. `type:gif` and `type:webp` each returned that
/// extension. The image clause returned jpg and png. Flash is in neither
/// Images nor Video. Sound is not offered.
String? remoteMediaClause(BooruType? type, String filter) {
  return switch (type) {
    BooruType.Danbooru => switch (filter) {
      'all' => '',
      'video' => 'filetype:mp4|filetype:webm',
      'image' => 'filetype:jpg|filetype:png|filetype:gif',
      _ => null,
    },
    BooruType.e621 => switch (filter) {
      'all' => '',
      'video' => 'type:mp4|type:webm',
      'image' => 'type:jpg|type:png|type:gif|type:webp',
      _ => null,
    },
    _ => null,
  };
}

/// The search text plus the chip clause, or the search text when this chip
/// adds nothing.
String appendRemoteMediaClause(String base, BooruType? type, String mediaFilter) {
  final String? clause = remoteMediaClause(type, mediaFilter);
  if (clause == null || clause.isEmpty) return base;
  final String trimmed = base.trim();
  return trimmed.isEmpty ? clause : '$trimmed $clause';
}

/// True when at least one chip can ask this source instead of hiding rows.
bool remoteMediaAsksSite(BooruType? type) => remoteMediaClause(type, 'video') != null;

/// Chip values for a source that asks the site. Local feeds do not use this.
List<String> remoteMediaChipValues(BooruType? type) {
  if (!remoteMediaAsksSite(type)) return const [];
  return const ['all', 'image', 'video'];
}
