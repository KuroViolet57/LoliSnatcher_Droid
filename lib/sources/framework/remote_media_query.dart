import 'package:lolisnatcher/models/booru_type.dart';

/// Extra tags a remote media chip adds, in the app's pipe OR syntax.
///
/// The search translator turns `a|b` into `~a ~b` before Danbooru sees it.
/// Null means this source has no checked query for that chip. An empty
/// string means the chip asks for everything and adds no tags.
///
/// Checked on 2026-10-07 with the app user agent.
///
/// A GIF is animated, so it is on Video, not Images. Checked again on
/// 2026-10-07 with the app user agent, as the tilde form the translator
/// emits.
///
/// Danbooru Video `~filetype:mp4 ~filetype:webm ~filetype:gif` returned
/// those three extensions, including beside `1girl`, and no jpg or png.
/// Images `~filetype:jpg ~filetype:png` returned jpg and png and no gif.
/// Sound has no filetype. Flash and ugoira are in neither chip.
///
/// e621 Video `~type:mp4 ~type:webm ~type:gif` returned those three,
/// including beside `1girl`. The same query on e6ai did too. e926 answered
/// curl with the same three; a PowerShell request to e926 was 403.
/// Images `~type:jpg ~type:png ~type:webp` returned jpg, png, and webp,
/// and no gif. Webp stays on Images: the app treats that extension as an
/// image, and the site has no separate animated-webp type. Flash is in
/// neither chip. Sound is not offered.
///
/// Derpibooru, and only a base URL that contains `derpibooru`, checked
/// 2026-10-07 with the app user agent. The handler quotes a metatag so its
/// underscore survives, then keeps the spaces around `||`. That spaced OR
/// returned gif, webm, and animated png, including beside `twilight sparkle`,
/// and no jpg. A GIF the site marks as not animated is still a GIF, so
/// Images also exclude `original_format:gif` and `original_format:webm`.
/// That image query returned jpg, png, and svg, and a gif added to it
/// returned nothing. Ponybooru and Ponerpics answered `original_format:gif`,
/// but `animated:true` or `animated:false` returned nothing, so they get
/// no chips. Sound is not offered. The comma form of `||` returned nothing
/// on all three hosts.
String? remoteMediaClause(BooruType? type, String filter, {String? baseUrl}) {
  return switch (type) {
    BooruType.Danbooru => switch (filter) {
      'all' => '',
      'video' => 'filetype:mp4|filetype:webm|filetype:gif',
      'image' => 'filetype:jpg|filetype:png',
      _ => null,
    },
    BooruType.e621 => switch (filter) {
      'all' => '',
      'video' => 'type:mp4|type:webm|type:gif',
      'image' => 'type:jpg|type:png|type:webp',
      _ => null,
    },
    BooruType.Philomena when baseUrl?.contains('derpibooru') ?? false => switch (filter) {
      'all' => '',
      'video' => '"original_format:gif"|"original_format:webm"|animated:true',
      'image' => 'animated:false -"original_format:gif" -"original_format:webm"',
      _ => null,
    },
    _ => null,
  };
}

/// The search text plus the chip clause, or the search text when this chip
/// adds nothing.
String appendRemoteMediaClause(String base, BooruType? type, String mediaFilter, {String? baseUrl}) {
  final String? clause = remoteMediaClause(type, mediaFilter, baseUrl: baseUrl);
  if (clause == null || clause.isEmpty) return base;
  final String trimmed = base.trim();
  return trimmed.isEmpty ? clause : '$trimmed $clause';
}

/// True when at least one chip can ask this source instead of hiding rows.
bool remoteMediaAsksSite(BooruType? type, {String? baseUrl}) => remoteMediaClause(type, 'video', baseUrl: baseUrl) != null;

/// Chip values for a source that asks the site. Local feeds do not use this.
List<String> remoteMediaChipValues(BooruType? type, {String? baseUrl}) {
  if (!remoteMediaAsksSite(type, baseUrl: baseUrl)) return const [];
  return const ['all', 'image', 'video'];
}
