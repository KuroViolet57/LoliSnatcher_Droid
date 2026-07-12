import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Resolves how a tag is spelled on a *different* booru.
///
/// Boorus name the same concept differently — `burnice_white` on one site is
/// `burnice_white_(zenless_zone_zero)` on another — so searching the literal
/// tag cross-booru often returns nothing even though the content exists.
///
/// Downloading and pairing every booru's full tag database on-device isn't
/// realistic (millions of rows, most sites don't even export them), so this
/// resolves lazily instead: when a tag is needed on booru B, B's own
/// tag-autocomplete API is queried with progressively relaxed variants of the
/// tag, the best candidate is picked, and the mapping is cached persistently
/// (TagAliasCache) so each pair is only ever resolved once.
///
/// Matching strategy, in order of preference:
///   1. exact tag exists on the target booru        -> use as-is
///   2. base name (parenthetical qualifier removed) -> exact base match
///   3. candidates that extend the base with a qualifier: base_(something)
///   4. candidates starting with the base name
///   5. candidates containing the base name
/// Within a bucket, the candidate with the highest post count wins.
class TagAliasResolver {
  TagAliasResolver._();

  // In-flight requests, deduped so a burst of calls for the same (tag, booru)
  // does one network lookup.
  static final Map<String, Future<String?>> _inFlight = {};

  static String _booruKey(Booru booru) => '${booru.type?.name}/${booru.name}';

  static String _stripQualifier(String tag) {
    // burnice_white_(zenless_zone_zero) -> burnice_white
    return tag.replaceAll(RegExp(r'_?\([^)]*\)$'), '').trim();
  }

  /// Returns the tag to use on [target] for [sourceTag]:
  /// - the tag itself when it exists there,
  /// - a mapped spelling when one is found,
  /// - null when the concept can't be found on that booru.
  static Future<String?> resolve(String sourceTag, Booru target) async {
    final String tag = sourceTag.trim().toLowerCase();
    if (tag.isEmpty || tag.contains(':') || tag.startsWith('-') || tag.startsWith('~')) {
      // meta tags / operators are handler-specific, not resolvable concepts
      return tag.isEmpty ? null : tag;
    }

    final String key = '$tag@${_booruKey(target)}';
    final String? cached = await SettingsHandler.instance.dbHandler.getTagAlias(tag, _booruKey(target));
    if (cached != null) {
      return cached.isEmpty ? null : cached;
    }

    return _inFlight[key] ??= _resolveRemote(tag, target).whenComplete(() => _inFlight.remove(key));
  }

  static Future<String?> _resolveRemote(String tag, Booru target) async {
    String? result;
    try {
      final handler = BooruHandlerFactory().getBooruHandler([target], 20).booruHandler;
      handler.storeTagsGlobally = false;

      if (!handler.hasTagSuggestions) {
        // Can't verify anything — assume the literal tag and don't cache.
        return tag;
      }

      final String base = _stripQualifier(tag);

      // Query with the base name: its results contain both the exact tag and
      // qualified variants, covering buckets 1-5 in one request when the
      // qualifier was the only difference.
      List<TagSuggestion> candidates = [];
      final res = await handler.getTagSuggestions(base);
      res.fold((_) {}, (list) => candidates = list);

      // If the tag has no qualifier and the base search found nothing,
      // there's nothing more to relax — confirmed miss.
      if (candidates.isEmpty && base == tag) {
        result = null;
      } else {
        if (candidates.isEmpty && base != tag) {
          // Base yielded nothing; try the full spelling as a last resort.
          final resFull = await handler.getTagSuggestions(tag);
          resFull.fold((_) {}, (list) => candidates = list);
        }
        result = _pickBest(tag, base, candidates);
      }
    } catch (e, s) {
      Logger.Inst().log(
        'alias resolve failed for "$tag" on ${target.name}: $e',
        'TagAliasResolver',
        '_resolveRemote',
        LogTypes.exception,
        s: s,
      );
      // Network hiccup: fall back to the literal tag, don't cache the failure.
      return tag;
    }

    try {
      await SettingsHandler.instance.dbHandler.setTagAlias(tag, _booruKey(target), result ?? '');
    } catch (_) {}
    return result;
  }

  static String? _pickBest(String tag, String base, List<TagSuggestion> candidates) {
    if (candidates.isEmpty) return null;

    final List<(int bucket, TagSuggestion s)> ranked = [];
    for (final s in candidates) {
      final String name = s.tag.toLowerCase();
      int bucket;
      if (name == tag) {
        bucket = 0; // exact spelling exists
      } else if (name == base) {
        bucket = 1; // unqualified base exists
      } else if (name.startsWith('${base}_(')) {
        bucket = 2; // base + (qualifier)
      } else if (name.startsWith(base)) {
        bucket = 3;
      } else if (name.contains(base)) {
        bucket = 4;
      } else {
        continue;
      }
      ranked.add((bucket, s));
    }
    if (ranked.isEmpty) return null;

    ranked.sort((a, b) {
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      return b.$2.count.compareTo(a.$2.count);
    });
    return ranked.first.$2.tag.toLowerCase();
  }
}
