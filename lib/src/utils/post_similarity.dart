import 'dart:math';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';

/// Post-to-post relevance, modelled on how rule34.xyz orders the suggestions
/// on a post page: candidates from a narrow pool (same creator / same seed
/// query) ranked by how much they overlap the viewed post — where overlap on
/// a *distinctive* tag counts for far more than overlap on a medium or
/// format tag.
///
/// Sharing `3d`, `animated` and `1girls` means nothing: half the site does.
/// Sharing an artist, a character, or a rare kink tag is the actual signal.

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

TagType _resolveType(Tag tag) {
  if (tag.tagType != TagType.none) return tag.tagType;
  // Boorus in the shimmie family send every tag untyped; the app-wide store
  // usually knows the type anyway (learned from other boorus).
  return TagHandler.instance.getTag(tag.fullString).tagType;
}

/// Weighted overlap between [candidate] and [source]. Higher = more alike.
double postSimilarityScore(BooruItem candidate, BooruItem source) {
  if (source.tagsList.isEmpty || candidate.tagsList.isEmpty) return 0;

  // Source tags carry the rarity counts we score with (the candidate's own
  // copy of a tag has the same count anyway).
  final Map<String, Tag> sourceTags = {};
  for (final t in source.tagsList) {
    final String key = normalizeTagName(t.fullString);
    if (key.isEmpty) continue;
    sourceTags[key] = t;
  }
  if (sourceTags.isEmpty) return 0;

  double score = 0;
  final Set<String> counted = {};
  for (final t in candidate.tagsList) {
    final String key = normalizeTagName(t.fullString);
    if (key.isEmpty || counted.contains(key)) continue;
    final Tag? sourceTag = sourceTags[key];
    if (sourceTag == null) continue;
    counted.add(key);
    // Prefer whichever copy of the tag actually carries a count.
    final int count = sourceTag.count > 0 ? sourceTag.count : t.count;
    score += tagRelevanceWeight(key, _resolveType(sourceTag), count);
  }
  return score;
}

bool _isSamePost(BooruItem a, BooruItem b) {
  if (a.postURL.isNotEmpty && a.postURL == b.postURL) return true;
  if (a.fileURL.isNotEmpty && a.fileURL == b.fileURL) return true;
  return false;
}

/// Re-orders [items] in place, most-similar-to-[source] first, and drops the
/// source post itself when the booru returned it.
///
/// [from] pins everything before that index: pages already on screen keep
/// their order while each newly fetched batch is ranked into place, so the
/// strip never reshuffles under a scrolling thumb.
void rankBySimilarity(List<BooruItem> items, BooruItem source, {int from = 0}) {
  if (items.length <= from + 1 && from < items.length) {
    // Single new item — nothing to sort, but still drop a self-match.
    if (_isSamePost(items[from], source)) items.removeAt(from);
    return;
  }
  if (from >= items.length) return;

  final List<BooruItem> head = items.sublist(0, from);
  final List<BooruItem> tail = items.sublist(from)..removeWhere((i) => _isSamePost(i, source));

  // Decorate-sort-undecorate with an index tiebreak: Dart's sort isn't
  // stable, and equal-score items should keep the booru's own ordering.
  final List<({BooruItem item, double score, int index})> decorated = [
    for (int i = 0; i < tail.length; i++)
      (item: tail[i], score: postSimilarityScore(tail[i], source), index: i),
  ]..sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });

  items
    ..clear()
    ..addAll(head)
    ..addAll(decorated.map((d) => d.item));
}
