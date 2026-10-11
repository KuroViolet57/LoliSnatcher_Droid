

/// Shared vocabulary for the recommendation code: which tags actually carry
/// meaning, and how to compare tag names across boorus that spell them
/// differently (spaces vs underscores).
///
/// See SuggestionEngine for how these are used to build varied suggestions.
library;

/// Medium / format / catch-all tags. These match a huge share of any booru,
/// so they carry almost no relevance information.
const Set<String> kGenericMediumTags = {
  '3d', '2d', 'blender', 'sfm', 'source_filmmaker', 'koikatsu', 'daz3d',
  'unreal_engine', 'animated', 'animation', 'video', 'webm', 'mp4', 'gif',
  'loop', 'looping_animation', 'sound', 'no_sound', 'audio', 'hd', '4k',
  '60fps', '1080p', '720p', 'nsfw', 'tagme', 'english_text', 'text',
  'uncensored', 'censored', 'longer_than_30_seconds', 'shorter_than_30_seconds',
  'longer_than_one_minute', 'male', 'female', '1boy', '1boys', '1girl',
  '1girls', '2girls', 'solo', 'straight', 'duo', 'human', 'nude', 'naked',
  'penis', 'pussy', 'breasts', 'ass', 'high_resolution', 'highres',
  'light-skinned_female', 'light-skinned_male', 'completely_nude',
};

/// Tags are spelled with spaces on some boorus and underscores on others —
/// compare on a single normalised form.
String normalizeTagName(String tag) => tag.trim().toLowerCase().replaceAll(' ', '_');
