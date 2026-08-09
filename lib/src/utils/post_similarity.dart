import 'dart:math';

import 'package:lolisnatcher/src/data/tag_type.dart';

/// Shared vocabulary for the recommendation code: which tags actually carry
/// meaning, and how to compare tag names across boorus that spell them
/// differently (spaces vs underscores).
///
/// See SuggestionEngine for how these are used to build varied suggestions.

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

/// How much a shared tag says about two posts being alike.
///
/// [count] is the booru-reported number of posts carrying the tag when the
/// handler provides one (rule34.xyz does, and it is by far the best rarity
/// signal available); otherwise rarity falls back to 1 and only the tag type
/// and the generic-tag stoplist shape the weight.
double tagRelevanceWeight(String name, TagType type, int count) {
  final String normalized = normalizeTagName(name);
  if (normalized.isEmpty || normalized == 'tagme') return 0;

  final double typeWeight = switch (type) {
    TagType.artist => 6,
    TagType.character => 5,
    TagType.copyright => 3,
    TagType.species => 2,
    TagType.meta => 0.3,
    _ => 1,
  };

  // Rarity: a tag on 200 posts is a much stronger hint than one on 200k.
  // log-scaled and clamped so a single ultra-rare tag can't swamp everything.
  double rarityWeight;
  if (count > 0) {
    rarityWeight = (log(2000000 / max(count, 1)) / log(10)).clamp(0.2, 4.0);
  } else {
    rarityWeight = 1;
  }

  // Untyped generic/medium tags carry nearly nothing. Typed tags keep their
  // weight even if the name looks generic (an artist literally named "loop"
  // is still an artist).
  if (type == TagType.none && kGenericMediumTags.contains(normalized)) {
    rarityWeight = min(rarityWeight, 0.15);
  }

  return typeWeight * rarityWeight;
}
