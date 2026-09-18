import 'dart:math';
import 'dart:typed_data';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';

typedef WeightedTag = ({String tag, double weight});

/// How a board's description becomes booru tags (r73).
///
/// Words and word pairs of the description are looked up in the pulled tag
/// lists of the chosen sources (an exact name counts most, a name that
/// starts with the word less), words no list knows are asked of the sites'
/// own suggestions, tags an image match named come first, and the
/// downloaded encoder ranks the candidates by how close each reads to the
/// whole description. Everything here is a seam so the feed can be tested
/// without a database, a site or a model.
class BoardQueryBuilder {
  const BoardQueryBuilder._();

  static const Set<String> stopWords = {
    'a', 'an', 'the', 'and', 'or', 'of', 'with', 'on', 'at', 'in', 'to', 'for', 'from', 'by', 'is', 'are', 'be', 'this',
    'that', 'these', 'those', 'it', 'its', 'as', 'some', 'very', 'more', 'less', 'into', 'onto', 'over', 'under', 'i',
    'me', 'my', 'want', 'show', 'find', 'please', 'posts', 'post', 'images', 'image', 'pictures', 'picture', 'something',
    'anything', 'doing', 'being', 'like', 'while', 'her', 'his', 'she', 'he', 'they', 'them', 'who', 'where', 'has',
    'have', 'but', 'not', 'no', 'yes', 'any', 'all',
  };

  static final RegExp _nonWord = RegExp(r'[^a-z0-9_\u00c0-\uffff]+');

  static Future<List<BooruTagEntry>> Function(Booru booru, String query) storeLookup = _defaultStoreLookup;
  static Future<List<String>> Function(BooruHandler? handler, String word) siteSuggest = _defaultSiteSuggest;
  static Future<Float32List?> Function(String text)? embed = _defaultEmbed;

  /// The candidates in one batch; null when the encoder is off (then
  /// [embed] is tried per candidate, which is how a test fakes it).
  static Future<List<Float32List?>?> Function(List<String> texts)? embedMany = _defaultEmbedMany;

  static void resetForTests() {
    storeLookup = _defaultStoreLookup;
    siteSuggest = _defaultSiteSuggest;
    embed = _defaultEmbed;
    embedMany = _defaultEmbedMany;
  }

  static Future<List<BooruTagEntry>> _defaultStoreLookup(Booru booru, String query) => BooruTagStore.browse(booru, query: query, limit: 12);

  static Future<List<String>> _defaultSiteSuggest(BooruHandler? handler, String word) async {
    if (handler == null || !handler.hasTagSuggestions) return const [];
    final res = await handler.getTagSuggestions(word);
    return res.fold((_) => const <String>[], (list) => [for (final s in list.take(5)) s.tag]);
  }

  static Future<Float32List?> _defaultEmbed(String text) async {
    final EncoderHandler? e = EncoderHandler.maybe;
    if (e == null || !e.enabled) return null;
    return e.embedText(text);
  }

  static Future<List<Float32List?>?> _defaultEmbedMany(List<String> texts) async {
    final EncoderHandler? e = EncoderHandler.maybe;
    if (e == null || !e.enabled) return null;
    return e.embedTexts(texts);
  }

  /// Lowercase words without punctuation or stop words.
  static List<String> tokens(String description) => description
      .toLowerCase()
      .split(_nonWord)
      .where((w) => w.length >= 2 && !stopWords.contains(w))
      .toList();

  /// Consecutive word pairs joined the booru way.
  static List<String> bigrams(List<String> words) => [for (int i = 0; i + 1 < words.length; i++) '${words[i]}_${words[i + 1]}'];

  static double dot(Float32List a, Float32List b) {
    final int n = min(a.length, b.length);
    double s = 0;
    for (int i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  /// The tags to ask the sources for, strongest first.
  static Future<List<WeightedTag>> deriveTags(
    String description, {
    required List<Booru> sources,
    List<BooruHandler> handlers = const [],
    List<String> seedTags = const [],
    Set<String> exclude = const {},
    int limit = 6,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final Map<String, double> score = {};
    final List<String> order = [];
    void add(String tag, double w) {
      final String t = tag.trim().toLowerCase();
      if (t.isEmpty || exclude.contains(t) || stopWords.contains(t)) return;
      if (!score.containsKey(t)) order.add(t);
      score[t] = (score[t] ?? 0) + w;
    }

    for (final String s in seedTags) {
      add(s, 4);
    }
    final List<String> words = tokens(description);
    final List<String> terms = [...bigrams(words), ...words];
    final List<String> unknown = [];
    for (final String term in terms) {
      bool hit = false;
      // The sources' lists in parallel: a page waits for the slowest, not the sum.
      final List<List<BooruTagEntry>> perSource = await Future.wait([
        for (final Booru booru in sources) storeLookup(booru, term).timeout(timeout).catchError((Object _) => const <BooruTagEntry>[]),
      ]);
      for (final List<BooruTagEntry> rows in perSource) {
        for (final BooruTagEntry row in rows.take(12)) {
          final String name = row.name.toLowerCase();
          if (name == term) {
            add(name, 3);
            hit = true;
          } else if (name.startsWith('${term}_')) {
            // "beach" -> beach_umbrella, not girl -> girls_und_panzer.
            add(name, 1.5);
            hit = true;
          } else if (name.contains(term)) {
            add(name, 0.5);
            hit = true;
          }
        }
      }
      if (!hit && !term.contains('_')) unknown.add(term);
    }
    // Words no list knows go to the sites, a few at most (each is a request).
    for (final String word in unknown.take(4)) {
      final List<BooruHandler?> askers = handlers.isEmpty ? <BooruHandler?>[null] : handlers;
      for (final BooruHandler? h in askers) {
        List<String> suggestions;
        try {
          suggestions = await siteSuggest(h, word).timeout(timeout);
        } catch (_) {
          suggestions = const [];
        }
        for (int i = 0; i < suggestions.length; i++) {
          add(suggestions[i], i == 0 ? 2 : 1);
        }
        if (suggestions.isNotEmpty) break;
      }
    }
    if (score.isEmpty) return const [];
    // The encoder: how close each candidate reads to the whole description.
    // The strongest two dozen by the lexical score, embedded in one batch.
    final embedder = embed;
    if (embedder != null && description.trim().isNotEmpty) {
      Float32List? desc;
      try {
        desc = await embedder(description).timeout(timeout);
      } catch (_) {
        desc = null;
      }
      if (desc != null) {
        final List<String> shortlist = [...order]..sort((a, b) => score[b]!.compareTo(score[a]!));
        final List<String> picked = shortlist.take(24).toList();
        List<Float32List?>? vecs;
        final many = embedMany;
        if (many != null) {
          try {
            vecs = await many([for (final String t in picked) t.replaceAll('_', ' ')]).timeout(timeout);
          } catch (_) {
            vecs = null;
          }
        }
        for (int i = 0; i < picked.length; i++) {
          Float32List? v = vecs != null && vecs.length == picked.length ? vecs[i] : null;
          if (vecs == null) {
            try {
              v = await embedder(picked[i].replaceAll('_', ' ')).timeout(timeout);
            } catch (_) {
              v = null;
            }
          }
          if (v != null) score[picked[i]] = score[picked[i]]! + 2 * max(0, dot(desc, v));
        }
      }
    }
    final List<String> sorted = [...order]..sort((a, b) {
      final int c = score[b]!.compareTo(score[a]!);
      return c != 0 ? c : order.indexOf(a).compareTo(order.indexOf(b));
    });
    return [for (final String t in sorted.take(limit)) (tag: t, weight: score[t]!)];
  }

  /// Every must-have tag present (as typed, or in the site's own spelling
  /// from [aliases]) and no excluded tag; case-insensitive.
  static bool accepts(BooruItem item, {required List<String> must, required List<String> exclude, Map<String, String> aliases = const {}}) {
    final Set<String> tags = {for (final t in item.tagsList) t.fullString.toLowerCase()};
    bool has(String tag) {
      final String t = tag.toLowerCase();
      if (tags.contains(t)) return true;
      final String? alias = aliases[t] ?? aliases[tag];
      return alias != null && tags.contains(alias.toLowerCase());
    }

    for (final String m in must) {
      if (!has(m)) return false;
    }
    for (final String x in exclude) {
      if (has(x)) return false;
    }
    return true;
  }
}
