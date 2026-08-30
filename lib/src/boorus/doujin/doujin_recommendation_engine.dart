import 'dart:math' as math;

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// Generated Related / Recommended for doujin sources.
///
/// Most doujin sites publish no "related" or "recommended" endpoint at all,
/// and the ones that do publish something thin. Rather than leave those
/// sections empty on five of six sources, the app derives both itself from
/// data every source already has: the gallery's title and its tags.
///
/// Deliberately operates on [BooruItem] rather than any site's JSON, so one
/// implementation serves every doujin source.
class DoujinRecommendationEngine {
  const DoujinRecommendationEngine._();

  /// Words too short or too generic to say anything about a title.
  static const Set<String> _titleStopWords = {
    'the', 'and', 'for', 'with', 'you', 'your', 'his', 'her', 'chapter', 'part',
    'vol', 'volume', 'ch', 'no', 'ver', 'version', 'digital', 'decensored',
    'english', 'japanese', 'chinese', 'translated', 'colorized', 'uncensored',
  };

  static final RegExp _latinRun = RegExp('[a-z0-9]+');

  /// Kana, and the CJK ideograph blocks that show up in these titles.
  static final RegExp _cjkRun = RegExp(
    '[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+',
  );

  /// Significant lowercase words of a title.
  ///
  /// Splitting on non-letters alone threw away every Japanese and Chinese
  /// title outright - they carry no spaces, so the split produced no tokens
  /// and every CJK-titled work looked unrelated to every other, which is most
  /// of the catalogue on these sites. CJK runs are therefore cut into
  /// character bigrams, the usual stand-in for a real segmenter.
  static List<String> titleTokens(String s) {
    final String lower = s.toLowerCase();
    final List<String> out = [];

    for (final match in _latinRun.allMatches(lower)) {
      final String word = match.group(0)!;
      if (word.length > 2 && !_titleStopWords.contains(word)) out.add(word);
    }

    for (final match in _cjkRun.allMatches(lower)) {
      final String run = match.group(0)!;
      if (run.length < 2) continue;
      for (int i = 0; i + 1 < run.length; i++) {
        out.add(run.substring(i, i + 2));
      }
    }

    return out;
  }

  /// Overlap of significant title words, 0..1, measured against the smaller
  /// of the two sets so a long title can't dilute a real match.
  static double titleSimilarity(List<String> sourceTokens, String title) {
    if (sourceTokens.isEmpty) return 0;
    final Set<String> other = titleTokens(title).toSet();
    if (other.isEmpty) return 0;
    final int common = sourceTokens.where(other.contains).length;
    return common / math.min(sourceTokens.length, other.length);
  }

  /// The part of a title that identifies the WORK rather than the instalment:
  /// bracketed circle/artist prefixes and a trailing chapter/part number are
  /// dropped. Used to find other chapters and language versions of the same
  /// work — the "Related" section.
  static String baseTitle(String title) {
    String out = title;
    // Strip leading [circle (artist)] / (event) groups.
    out = out.replaceAll(RegExp(r'^\s*(\[[^\]]*\]|\([^)]*\))\s*'), '');
    // ...and any trailing bracketed qualifiers (language, digital, etc).
    out = out.replaceAll(RegExp(r'\s*(\[[^\]]*\]|\([^)]*\))\s*$'), '');
    // ...then a trailing instalment marker.
    out = out.replaceAll(
      RegExp(r'\s*(?:ch\.?|chapter|episode|ep\.?|part|pt\.?|vol\.?|volume)?\s*\d+\s*$', caseSensitive: false),
      '',
    );
    return out.trim();
  }

  /// Whether [candidateTitle] looks like another instalment or version of the
  /// work named by [sourceBaseTitle].
  static bool isSameWork(String sourceBaseTitle, String candidateTitle) {
    final String base = sourceBaseTitle.trim().toLowerCase();
    if (base.length < 4) return false;
    return baseTitle(candidateTitle).toLowerCase() == base ||
        candidateTitle.toLowerCase().contains(base);
  }

  /// Normalized tag names of an item, namespace stripped.
  static Set<String> tagsOf(BooruItem item) => {
    for (final t in item.tagsList) SourceSettingsHandler.normalizeTagName(t.fullString),
  };

  /// How relevant [candidate] is to [source]: tag overlap normalised by the
  /// geometric mean of both tag counts (so a heavily-tagged gallery doesn't
  /// dominate), plus a small title-similarity term. There is deliberately NO
  /// artist bonus — same-artist results are capped instead, because the
  /// artist's whole catalogue is one tag-tap away.
  static double score(BooruItem source, BooruItem candidate) {
    final Set<String> sourceTags = tagsOf(source);
    final Set<String> candidateTags = tagsOf(candidate);
    final int overlap = candidateTags.where(sourceTags.contains).length;
    final double denominator = (sourceTags.isEmpty || candidateTags.isEmpty)
        ? 1
        : math.sqrt(sourceTags.length * candidateTags.length);
    final double titleSim = titleSimilarity(
      titleTokens(_titleOf(source)),
      _titleOf(candidate),
    );
    return overlap / denominator + 0.25 * titleSim;
  }

  static String _titleOf(BooruItem item) =>
      (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');

  /// How many same-artist results one page may carry: a small minority.
  static int artistCap(int count) => math.max(2, (count * 0.15).round());

  /// Ranks [candidates] for [source], dropping the source itself, duplicates
  /// and other versions of the same work (those belong in Related, not
  /// Recommended), and keeping same-artist entries a minority.
  static List<BooruItem> rank(
    BooruItem source,
    List<BooruItem> candidates, {
    required int count,
    String? sourceArtist,
  }) {
    if (count <= 0) return const [];
    final String base = baseTitle(_titleOf(source));
    final Set<String> seen = {source.postURL};

    final scored = <({double score, bool sameArtist, BooruItem item})>[];
    for (final c in candidates) {
      if (!seen.add(c.postURL)) continue;
      if (base.isNotEmpty && isSameWork(base, _titleOf(c))) continue;
      final bool sameArtist =
          sourceArtist != null && sourceArtist.isNotEmpty && tagsOf(c).contains(sourceArtist);
      scored.add((score: score(source, c), sameArtist: sameArtist, item: c));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final int cap = artistCap(count);
    int artistTaken = 0;
    final out = <BooruItem>[];
    for (final e in scored) {
      if (out.length >= count) break;
      if (e.sameArtist) {
        if (artistTaken >= cap) continue;
        artistTaken++;
      }
      out.add(e.item);
    }
    return out;
  }

  /// An item's tags with their namespace intact, lowercased and underscored.
  ///
  /// [tagsOf] deliberately drops namespaces because that is what the blacklist
  /// and the tag stars compare on; anything that needs to know whether a tag
  /// is an artist or a series has to use this instead.
  static Set<String> namespacedTagsOf(BooruItem item) => {
    for (final t in item.tagsList) t.fullString.trim().toLowerCase().replaceAll(' ', '_'),
  };

  /// How close two galleries are as *reading*, rather than as taste: shared
  /// title words first, then a shared series, then a shared author. Used to
  /// fill Related out when a work has no other version of itself on the site.
  ///
  /// Author counts here even though [rank] deliberately caps it: another book
  /// by the same circle is a reasonable "read this next", whereas Recommended
  /// is meant to widen taste rather than narrow it to one artist.
  static double relatedness(BooruItem source, BooruItem candidate) {
    final double title = titleSimilarity(titleTokens(_titleOf(source)), _titleOf(candidate));
    // NB: namespaced, not [tagsOf] - that normalises `parody:blue_archive` down
    // to `blue_archive`, which would make every namespace test below fail
    // silently and leave Related empty.
    final Set<String> theirs = namespacedTagsOf(candidate);
    int series = 0;
    int author = 0;
    for (final tag in namespacedTagsOf(source)) {
      final bool isSeries = tag.startsWith('parody:') || tag.startsWith('series:');
      final bool isAuthor =
          tag.startsWith('artist:') || tag.startsWith('circle:') || tag.startsWith('group:');
      if (!isSeries && !isAuthor) continue;
      if (!theirs.contains(tag)) continue;
      if (isSeries) {
        series++;
      } else {
        author++;
      }
    }
    return title +
        (series == 0 ? 0 : 0.5 + 0.1 * (series - 1)) +
        (author == 0 ? 0 : 0.4 + 0.1 * (author - 1));
  }

  /// How many entries Related shows when the caller does not say.
  static const int defaultRelatedCount = 12;

  /// The Related list: other chapters and language versions of the same work
  /// first, then - so that Related is never empty on a source that simply has
  /// no second version of a work - the closest galleries by title words and
  /// shared series.
  static List<BooruItem> related(BooruItem source, List<BooruItem> candidates, {int? count}) {
    final String base = baseTitle(_titleOf(source));
    final int limit = count ?? defaultRelatedCount;
    final Set<String> seen = {source.postURL};
    final out = <BooruItem>[];
    final fill = <({double score, BooruItem item})>[];

    for (final c in candidates) {
      if (!seen.add(c.postURL)) continue;
      if (base.isNotEmpty && isSameWork(base, _titleOf(c))) {
        out.add(c);
        continue;
      }
      fill.add((score: relatedness(source, c), item: c));
    }

    // Same-work entries are never dropped, even past the limit - they are the
    // whole point of the section.
    if (out.length >= limit) return out;

    fill.sort((a, b) => b.score.compareTo(a.score));
    for (final entry in fill) {
      if (out.length >= limit) break;
      // A candidate sharing nothing at all is not "related", it is filler.
      if (entry.score <= 0) break;
      out.add(entry.item);
    }
    return out;
  }
}
