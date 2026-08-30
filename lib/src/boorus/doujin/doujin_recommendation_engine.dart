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

  /// Significant lowercase words of a title.
  static List<String> titleTokens(String s) => [
    for (final w in s.toLowerCase().split(RegExp('[^a-z0-9]+')))
      if (w.length > 2 && !_titleStopWords.contains(w)) w,
  ];

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

  /// The Related list: other chapters and language versions of the same work.
  static List<BooruItem> related(BooruItem source, List<BooruItem> candidates, {int? count}) {
    final String base = baseTitle(_titleOf(source));
    if (base.isEmpty) return const [];
    final Set<String> seen = {source.postURL};
    final out = <BooruItem>[];
    for (final c in candidates) {
      if (!seen.add(c.postURL)) continue;
      if (!isSameWork(base, _titleOf(c))) continue;
      out.add(c);
      if (count != null && out.length >= count) break;
    }
    return out;
  }
}
