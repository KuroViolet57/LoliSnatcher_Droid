import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Result of resolving a query for another booru.
class TagAliasResult {
  const TagAliasResult({
    required this.query,
    required this.changed,
    this.perTerm = const {},
  });

  /// The query to actually search on the target booru.
  final String query;

  /// Whether any term differs from the input.
  final bool changed;

  /// original term -> resolved term, only for terms that changed.
  final Map<String, String> perTerm;
}

/// Cross-booru tag translation. Boorus disagree on how the "same" tag is
/// written (`burnice` on one site vs `burnice_white_(zenless_zone_zero)` on
/// another); this resolves a tag written for one booru into the closest
/// equivalent on a target booru using the target's own tag autocomplete.
///
/// Strategy per term (plain tags only — meta `key:value` terms pass through):
///   1. ask the target's autocomplete for the term itself — an exact hit means
///      the tag exists there as written, keep it;
///   2. otherwise retry with the de-qualified base (parentheticals stripped)
///      and, failing that, its leading words;
///   3. rank candidates: full word coverage of the base name first, then a
///      matching tag type (artist/character, when the source type is known),
///      then the target site's post count.
/// Results (including failures) are cached per booru+term for the session.
class TagAliasResolver {
  TagAliasResolver._();

  // 'booruKey|term' -> resolved term (null = resolution attempted and failed).
  static final Map<String, String?> _cache = {};

  static final Map<String, BooruHandler> _handlerCache = {};

  static String _booruKey(Booru booru) => '${booru.type?.name}|${booru.name}|${booru.baseURL}';

  static BooruHandler _handlerFor(Booru booru) {
    final String key = _booruKey(booru);
    return _handlerCache[key] ??= (BooruHandlerFactory().getBooruHandler([booru], 20).booruHandler
      ..storeTagsGlobally = false);
  }

  static bool _isMetaTerm(String term) {
    final String bare = term.startsWith('-') || term.startsWith('~') ? term.substring(1) : term;
    return bare.contains(':');
  }

  /// Resolves a full (space-separated) query for [target]. Unresolvable plain
  /// terms are kept as-is so the search still runs (and visibly returns what
  /// the target actually has for them, usually nothing).
  static Future<TagAliasResult> resolveQuery(
    String query,
    Booru target,
  ) async {
    final List<String> terms = query.trim().split(' ').where((t) => t.isNotEmpty).toList();
    final List<String> out = [];
    final Map<String, String> perTerm = {};

    for (final term in terms) {
      if (_isMetaTerm(term)) {
        out.add(term);
        continue;
      }
      final String prefix = (term.startsWith('-') || term.startsWith('~')) ? term[0] : '';
      final String bare = prefix.isEmpty ? term : term.substring(1);

      final String? resolved = await _resolveTerm(bare, target);
      if (resolved != null && resolved.toLowerCase() != bare.toLowerCase()) {
        out.add('$prefix$resolved');
        perTerm[bare] = resolved;
      } else {
        out.add(term);
      }
    }

    return TagAliasResult(
      query: out.join(' '),
      changed: perTerm.isNotEmpty,
      perTerm: perTerm,
    );
  }

  static Future<String?> _resolveTerm(String term, Booru target) async {
    final String key = '${_booruKey(target)}|${term.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];

    final BooruHandler handler = _handlerFor(target);
    if (!handler.hasTagSuggestions) {
      // Can't check anything — leave the term untouched (and don't cache, the
      // user may switch to a booru that can).
      return null;
    }

    final String normalized = term.toLowerCase();
    // burnice_white_(zenless_zone_zero) -> burnice_white
    final String base = normalized.replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'_+$'), '');
    final List<String> words = base.split(RegExp('[_ ]+')).where((w) => w.isNotEmpty).toList();

    // Candidate autocomplete queries, most→least specific.
    final List<String> candidates = <String>{
      normalized,
      if (base.isNotEmpty && base != normalized) base,
      if (words.length > 1) words.take(2).join('_'),
      if (words.isNotEmpty && words.first.length >= 3) words.first,
    }.toList();

    final TagType sourceType = TagHandler.instance.getTag(normalized).tagType;

    String? best;
    double bestScore = 0;

    for (final candidate in candidates) {
      List<TagSuggestion> suggestions = [];
      try {
        final res = await handler.getTagSuggestions(candidate);
        res.fold((_) {}, (data) => suggestions = data);
      } catch (e) {
        Logger.Inst().log(
          'alias suggestions failed for "$candidate" on ${target.name}: $e',
          'TagAliasResolver',
          '_resolveTerm',
          LogTypes.booruHandlerInfo,
        );
        continue;
      }

      for (final s in suggestions) {
        final String sTag = s.tag.toLowerCase();
        if (sTag.isEmpty) continue;

        // Exact hit: the tag exists on the target as written — done.
        if (sTag == normalized) {
          _cache[key] = s.tag;
          return s.tag;
        }

        double score = 0;
        // Word coverage of the source base name — the dominant signal.
        if (words.isNotEmpty) {
          final int covered = words.where(sTag.contains).length;
          if (covered == 0) continue;
          score += 10.0 * covered / words.length;
          // The tag's own leading word should match ours (avoids matching
          // `white_hair` for `burnice_white` via the "white" word alone).
          if (!sTag.contains(words.first)) continue;
        }
        // Same tag type (artist stays artist, character stays character).
        if (sourceType != TagType.none && s.type == sourceType) score += 3;
        // Popularity as a mild tiebreak.
        if (s.count > 0) score += (s.count.clamp(0, 100000)) / 100000.0;

        if (score > bestScore) {
          bestScore = score;
          best = s.tag;
        }
      }

      // A full-coverage match from a more specific candidate is good enough —
      // don't dilute it with looser candidates.
      if (best != null && bestScore >= 10) break;
    }

    // Demand full word coverage for multi-word tags, and at least a
    // first-word match for single-word ones.
    final double minScore = words.length > 1 ? 10 : 5;
    final String? result = (bestScore >= minScore) ? best : null;
    _cache[key] = result;
    return result;
  }
}
