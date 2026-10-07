import 'package:lolisnatcher/models/booru_type.dart';

/// Extra tags a remote media chip adds, in the app's pipe OR syntax.
///
/// The search translator turns `a|b` into `~a ~b` before Danbooru sees it.
/// Null means this source has no checked query for that chip. An empty
/// string means the chip asks for everything and adds no tags.
///
/// Checked against danbooru.donmai.us on 2026-10-07 with the app user agent:
/// the tilde form of the video clause returned mp4, including beside `1girl`,
/// and the image clause returned jpg and png. `filetype:gif` and
/// `filetype:webm` each returned that extension. Sound has no filetype on
/// the cheatsheet, so that chip is not offered. Flash and ugoira are in
/// neither Images nor Video.
String? remoteMediaClause(BooruType? type, String filter) {
  if (type != BooruType.Danbooru) return null;
  return switch (filter) {
    'all' => '',
    'video' => 'filetype:mp4|filetype:webm',
    'image' => 'filetype:jpg|filetype:png|filetype:gif',
    _ => null,
  };
}

/// True when at least one chip can ask this source instead of hiding rows.
bool remoteMediaAsksSite(BooruType? type) => remoteMediaClause(type, 'video') != null;

/// Chip values for a source that asks the site. Local feeds do not use this.
List<String> remoteMediaChipValues(BooruType? type) {
  if (!remoteMediaAsksSite(type)) return const [];
  return const ['all', 'image', 'video'];
}
