import 'dart:math';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/post_similarity.dart';

/// Facet-blend suggestion engine.
///
/// Modelled on how rule34.xyz builds the suggestion list on a post page.
/// Measured over 12 modern posts (30 suggestions each), a set contains ~17
/// distinct artists and ~26 distinct characters, and splits roughly:
///   34% share the artist, 44% share a character (different artist),
///    6% share only the franchise, 16% share none of those — matched on
///   body/act/style tags alone.
///
/// So a good suggestion list is NOT one query ranked cleverly; it is several
/// DIFFERENT queries — the character, the franchise minus that character, the
/// artist (only a few), the distinctive act tags, the medium/style — blended
/// round-robin with hard caps so nothing dominates.
enum SuggestionFacetKind {
  character,
  franchise,
  artist,
  act,
  style,
}

extension SuggestionFacetKindExt on SuggestionFacetKind {
  String get label => switch (this) {
        SuggestionFacetKind.character => 'character',
        SuggestionFacetKind.franchise => 'franchise',
        SuggestionFacetKind.artist => 'artist',
        SuggestionFacetKind.act => 'theme',
        SuggestionFacetKind.style => 'style',
      };
}

class SuggestionFacet {
  SuggestionFacet({
    required this.kind,
    required this.query,
    required this.quota,
    this.excludeCharacters = false,
  });

  final SuggestionFacetKind kind;

  /// Plain tag query for the source booru. Kept to 1–2 terms: deep AND
  /// queries collapse to nothing on smaller boorus, and some (gelbooru
  /// anonymous, shimmie) cap the number of searchable tags.
  final String query;

  /// Max items this facet may contribute to one blended page.
  final int quota;

  /// Franchise facet: drop results that carry one of the source post's own
  /// characters, so it yields a DIFFERENT character from the same franchise
  /// instead of more of the same one. Filtered client-side rather than with
  /// `-tag` exclusions, which not every booru supports.
  final bool excludeCharacters;

  @override
  String toString() => '${kind.name}:$query';
}

class SuggestionEngine {
  SuggestionEngine._();

  /// Per-blend caps. These are what keep a strip varied — without them the
  /// character facet alone happily fills the entire page.
  static const int maxPerArtist = 4;
  static const int maxPerCharacter = 6;

  /// [item], when given, decides whether the shared booru tag store may be
  /// consulted: doujin tags already carry the site's own type, and borrowing
  /// a booru's classification of a coinciding name changed which facet
  /// queries the doujin "Suggested" strip actually ran.
  static TagType typeOf(Tag t, {BooruItem? item}) {
    if (t.tagType != TagType.none) return t.tagType;
    if (item != null && DoujinDataHandler.isDoujinItem(item)) return TagType.none;
    // Shimmie-family boorus type nothing; the app-wide store usually knows.
    return TagHandler.instance.getTag(t.fullString).tagType;
  }

  static List<String> tagsOfType(BooruItem item, TagType type) {
    final List<String> out = [];
    for (final t in item.tagsList) {
      final String v = t.fullString.trim();
      if (v.isEmpty || v.toLowerCase() == 'tagme') continue;
      if (typeOf(t, item: item) == type && !out.contains(v)) out.add(v);
    }
    return out;
  }

  /// Distinctive general tags — the "acts" and traits that make a post feel
  /// like this post (`mating_press`, `used_condom`, `thick_thighs`), with
  /// medium/format noise (`3d`, `animated`, `1girls`) removed. Rarest first,
  /// using the booru's own tag counts when it reports them.
  static List<Tag> actTags(BooruItem item) {
    final List<Tag> candidates = item.tagsList.where((t) {
      final String v = normalizeTagName(t.fullString);
      if (v.isEmpty || v == 'tagme') return false;
      final TagType type = typeOf(t, item: item);
      if (type != TagType.none && type != TagType.species) return false;
      return !kGenericMediumTags.contains(v);
    }).toList()
      ..sort((a, b) {
        final int ca = a.count > 0 ? a.count : 1 << 30;
        final int cb = b.count > 0 ? b.count : 1 << 30;
        if (ca != cb) return ca.compareTo(cb);
        // No counts available: prefer multi-word/qualified names, which are
        // reliably more specific than single generic words.
        int spec(Tag t) => (t.fullString.contains('(') ? 2 : 0) + (t.fullString.contains('_') ? 1 : 0);
        final int bySpec = spec(b).compareTo(spec(a));
        if (bySpec != 0) return bySpec;
        return b.fullString.length.compareTo(a.fullString.length);
      });
    return candidates;
  }

  /// The medium/style tag of a post (`3d`, `blender`, `koikatsu`, ...) — used
  /// to find work in the same style by other artists.
  static String? styleTag(BooruItem item) {
    const List<String> styleOrder = [
      'koikatsu',
      'blender',
      'source_filmmaker',
      'sfm',
      'daz3d',
      'unreal_engine',
      '3d',
      '2d',
    ];
    final Set<String> present = {
      for (final t in item.tagsList) normalizeTagName(t.fullString),
    };
    for (final s in styleOrder) {
      if (present.contains(s)) return s;
    }
    return null;
  }

  /// Builds the facet set for [item].
  ///
  /// [seed] varies which characters/acts are used across pages so scrolling
  /// (and reopening the post) doesn't replay the same handful of queries.
  static List<SuggestionFacet> facetsForItem(BooruItem item, {int seed = 0}) {
    final List<SuggestionFacet> facets = [];

    final List<String> characters = tagsOfType(item, TagType.character);
    final List<String> franchises = tagsOfType(item, TagType.copyright);
    final List<String> artists = tagsOfType(item, TagType.artist);
    final List<Tag> acts = actTags(item);
    final String? style = styleTag(item);

    String rotate(List<String> list, int offset) => list[(seed + offset) % list.length];

    // Same character, anyone's take on it — the single biggest slice in the
    // xyz data (44%), so it gets two facets when the post has two characters.
    if (characters.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.character, query: rotate(characters, 0), quota: 6));
      if (characters.length > 1) {
        facets.add(SuggestionFacet(kind: SuggestionFacetKind.character, query: rotate(characters, 1), quota: 4));
      }
    }

    // Same franchise, DIFFERENT character.
    if (franchises.isNotEmpty) {
      facets.add(
        SuggestionFacet(
          kind: SuggestionFacetKind.franchise,
          query: rotate(franchises, 0),
          quota: 5,
          excludeCharacters: characters.isNotEmpty,
        ),
      );
    }

    // Same artist — deliberately small. The measured median is ~7 of 30 and
    // the user's own read is "3 or 4 at most"; anything more turns the strip
    // into the artist's catalogue, which the dedicated artist section (and
    // Tag Hub) already covers.
    if (artists.isNotEmpty) {
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.artist, query: rotate(artists, 0), quota: 4));
    }

    // Act/trait tags — this is what produces the "unrelated but same vibe"
    // results (16% of xyz's set matches on nothing else).
    for (int i = 0; i < min(2, acts.length); i++) {
      final Tag act = acts[(seed + i) % acts.length];
      facets.add(SuggestionFacet(kind: SuggestionFacetKind.act, query: act.fullString, quota: 4));
    }

    // Same medium/style, paired with an act tag so it stays on-theme rather
    // than returning "all 3D everything".
    if (style != null && acts.isNotEmpty) {
      final Tag act = acts[(seed + 2) % acts.length];
      facets.add(
        SuggestionFacet(
          kind: SuggestionFacetKind.style,
          query: '$style ${act.fullString}',
          quota: 4,
        ),
      );
    }

    // Nothing typed and nothing distinctive (very sparse post): fall back to
    // the rarest tags on their own so the strip still shows something.
    if (facets.isEmpty && acts.isNotEmpty) {
      for (int i = 0; i < min(3, acts.length); i++) {
        facets.add(SuggestionFacet(kind: SuggestionFacetKind.act, query: acts[i].fullString, quota: 6));
      }
    }

    return facets;
  }

  /// Round-robin blend of per-facet result lists.
  ///
  /// Takes one item from each facet in turn so the top of the strip is
  /// immediately varied, enforcing per-facet quotas plus global per-artist and
  /// per-character caps. [exclude] holds items already shown on earlier pages
  /// (and the source post itself).
  static List<BooruItem> blend(
    Map<SuggestionFacet, List<BooruItem>> byFacet, {
    required BooruItem? source,
    Set<String>? exclude,
    int limit = 30,
  }) {
    final List<BooruItem> out = [];
    final Set<String> seen = {...?exclude};
    final Map<String, int> artistCounts = {};
    final Map<String, int> characterCounts = {};
    final Map<SuggestionFacet, int> taken = {};

    final Set<String> sourceCharacters = source == null
        ? const {}
        : tagsOfType(source, TagType.character).map(normalizeTagName).toSet();

    String keyOf(BooruItem i) => i.postURL.isNotEmpty ? i.postURL : i.fileURL;

    bool accept(BooruItem item, SuggestionFacet facet) {
      final String key = keyOf(item);
      if (key.isEmpty || seen.contains(key)) return false;
      if (source != null &&
          ((source.postURL.isNotEmpty && source.postURL == item.postURL) ||
              (source.fileURL.isNotEmpty && source.fileURL == item.fileURL))) {
        return false;
      }

      final List<String> itemCharacters = tagsOfType(item, TagType.character);
      if (facet.excludeCharacters &&
          itemCharacters.any((c) => sourceCharacters.contains(normalizeTagName(c)))) {
        return false;
      }

      // Caps: no single artist or character may take over the blend.
      final List<String> itemArtists = tagsOfType(item, TagType.artist);
      for (final a in itemArtists) {
        if ((artistCounts[normalizeTagName(a)] ?? 0) >= maxPerArtist) return false;
      }
      for (final c in itemCharacters) {
        if ((characterCounts[normalizeTagName(c)] ?? 0) >= maxPerCharacter) return false;
      }

      seen.add(key);
      for (final a in itemArtists) {
        final String k = normalizeTagName(a);
        artistCounts[k] = (artistCounts[k] ?? 0) + 1;
      }
      for (final c in itemCharacters) {
        final String k = normalizeTagName(c);
        characterCounts[k] = (characterCounts[k] ?? 0) + 1;
      }
      taken[facet] = (taken[facet] ?? 0) + 1;
      return true;
    }

    final List<SuggestionFacet> facets = byFacet.keys.toList();
    final Map<SuggestionFacet, int> cursors = {for (final f in facets) f: 0};

    bool progressed = true;
    while (out.length < limit && progressed) {
      progressed = false;
      for (final facet in facets) {
        if (out.length >= limit) break;
        if ((taken[facet] ?? 0) >= facet.quota) continue;
        final List<BooruItem> pool = byFacet[facet] ?? const [];
        int cursor = cursors[facet]!;
        while (cursor < pool.length) {
          final BooruItem candidate = pool[cursor];
          cursor++;
          if (accept(candidate, facet)) {
            out.add(candidate);
            progressed = true;
            break;
          }
        }
        cursors[facet] = cursor;
      }
    }

    return out;
  }
}
