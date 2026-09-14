import 'dart:convert';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';

/// The two taste worlds. They never mix: a doujin event trains the doujin
/// model only, a booru event the booru model only — the same wall the classic
/// profile keeps.
enum RecommenderWorld { booru, doujin }

/// An item as the learner sees it: hashed binary features, with the names
/// kept beside them so "what was learned" can be read back.
class FeatureVector {
  const FeatureVector(this.hashes, this.names);

  static const FeatureVector empty = FeatureVector([], []);

  final List<int> hashes;
  final List<String> names;

  bool get isEmpty => hashes.isEmpty;
}

/// Builds feature vectors. Every feature is a short string
/// (`tag:red_hair`, `type:artist:zun`, `ns:parody:genshin_impact`,
/// `site:nhentai.net`, `media:video`, `score:10-49`, `pages:26-60`,
/// `title:tao`) hashed into one of [buckets] slots — no vocabulary to
/// maintain, unknown tags simply land in their slot.
class ItemFeatures {
  const ItemFeatures._();

  static const int bucketBits = 18;
  static const int buckets = 1 << bucketBits;

  /// FNV-1a over the UTF-8 bytes, masked to [buckets].
  static int hash(String name) {
    int h = 0x811c9dc5;
    for (final int b in utf8.encode(name)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & (buckets - 1);
  }

  static RecommenderWorld worldOf(BooruItem item) =>
      DoujinDataHandler.isDoujinItem(item) ? RecommenderWorld.doujin : RecommenderWorld.booru;

  static RecommenderWorld worldOfBooru(Booru? booru) =>
      DoujinDataHandler.isDoujinBooru(booru) ? RecommenderWorld.doujin : RecommenderWorld.booru;

  /// The doujin namespaces a query term may carry.
  static const Set<String> doujinNamespaces = {
    'artist', 'group', 'circle', 'cosplayer', 'parody', 'series', 'character',
    'female', 'male', 'mixed', 'other', 'tag', 'language', 'category', 'type',
  };

  /// [namespaces] (bare name -> namespace) or [handler] (a doujin handler
  /// remembering its namespaces) name a doujin tag's namespace; without
  /// either, the tag's type stands in.
  static FeatureVector of(
    BooruItem item,
    RecommenderWorld world, {
    Map<String, String>? namespaces,
    BooruHandler? handler,
  }) {
    final _Builder b = _Builder();
    for (final Tag tag in item.tagsList) {
      final String name = normalizeDoujinTagName(tag.fullString);
      if (name.isEmpty) continue;
      b.add('tag:$name');
      final TagType type = _typeOf(tag, item, world);
      if (world == RecommenderWorld.doujin) {
        final String? ns = namespaces?[name] ?? _handlerNamespace(handler, name) ?? _namespaceOfType(type);
        if (ns != null && ns != 'tag') b.add('ns:$ns:$name');
      } else if (type != TagType.none) {
        b.add('type:${type.name}:$name');
      }
    }
    final String host = Uri.tryParse(item.postURL)?.host.toLowerCase() ?? '';
    if (host.isNotEmpty) b.add('site:$host');
    b.add('media:${_mediumOf(item, world)}');
    final int? score = int.tryParse(item.score ?? '');
    if (score != null) b.add('score:${scoreBucket(score)}');
    if (world == RecommenderWorld.doujin) {
      final int? pages = item.fileCountHint.value;
      if (pages != null && pages > 0) b.add('pages:${pagesBucket(pages)}');
      _addTitle(b, item.description ?? '');
    }
    return b.build();
  }

  /// A remembered gallery: namespaced tag strings (`parody:genshin_impact`)
  /// and what a history entry keeps, without the item itself.
  static FeatureVector ofDoujinParts({
    required List<String> namespacedTags,
    String title = '',
    String host = '',
    int? pages,
  }) {
    final _Builder b = _Builder();
    for (final String raw in namespacedTags) {
      final int colon = raw.indexOf(':');
      final String ns = colon > 0 ? raw.substring(0, colon).trim().toLowerCase() : 'tag';
      final String name = normalizeDoujinTagName(colon > 0 ? raw.substring(colon + 1) : raw);
      if (name.isEmpty) continue;
      b.add('tag:$name');
      if (ns != 'tag') b.add('ns:$ns:$name');
    }
    if (host.isNotEmpty) b.add('site:${host.toLowerCase()}');
    b.add('media:book');
    if (pages != null && pages > 0) b.add('pages:${pagesBucket(pages)}');
    _addTitle(b, title);
    return b.build();
  }

  /// A search as a pseudo-item of its terms: exclusions and metatags dropped,
  /// doujin namespaces kept.
  static FeatureVector ofQuery(String query, RecommenderWorld world) {
    final _Builder b = _Builder();
    for (final String term in query.split(RegExp(r'\s+'))) {
      final String t = term.trim().toLowerCase();
      if (t.isEmpty || t.startsWith('-') || t.startsWith('~')) continue;
      final int colon = t.indexOf(':');
      if (colon > 0) {
        final String ns = t.substring(0, colon);
        final String name = normalizeDoujinTagName(t.substring(colon + 1));
        if (world == RecommenderWorld.doujin && doujinNamespaces.contains(ns) && name.isNotEmpty) {
          if (ns != 'tag') b.add('ns:$ns:$name');
          b.add('tag:$name');
        }
        continue;
      }
      final String name = normalizeDoujinTagName(t);
      if (name.isNotEmpty) b.add('tag:$name');
    }
    return b.build();
  }

  static String scoreBucket(int score) {
    if (score <= 0) return '0';
    if (score < 10) return '1-9';
    if (score < 50) return '10-49';
    if (score < 200) return '50-199';
    if (score < 1000) return '200-999';
    return '1000+';
  }

  static String pagesBucket(int pages) {
    if (pages <= 10) return '1-10';
    if (pages <= 25) return '11-25';
    if (pages <= 60) return '26-60';
    if (pages <= 150) return '61-150';
    return '151+';
  }

  /// Whether a learned feature can steer retrieval: a typed or namespaced
  /// name, or a meaningful bare tag — never a site, a bucket, a title word,
  /// a generic tag or a language.
  static bool isSeedable(String name) {
    if (name.startsWith('type:')) return !name.startsWith('type:meta:');
    if (name.startsWith('ns:')) {
      final String ns = name.substring(3, name.indexOf(':', 3).clamp(3, name.length));
      return ns != 'language' && ns != 'category' && ns != 'type';
    }
    if (name.startsWith('tag:')) return InterestsHandler.isMeaningfulTag(name.substring(4));
    return false;
  }

  /// A feature name as a person reads it: `type:artist:zun` → `artist: zun`,
  /// `ns:parody:genshin_impact` → `parody: genshin impact`, `tag:red_hair` →
  /// `red hair`, `pages:26-60` → `26–60 pages`.
  static String describe(String name) {
    String words(String s) => s.replaceAll('_', ' ');
    if (name.startsWith('type:') || name.startsWith('ns:')) {
      final int first = name.indexOf(':');
      final int second = name.indexOf(':', first + 1);
      if (second > first) return '${name.substring(first + 1, second)}: ${words(name.substring(second + 1))}';
    }
    if (name.startsWith('tag:')) return words(name.substring(4));
    if (name.startsWith('title:')) return 'title word "${name.substring(6)}"';
    if (name.startsWith('site:')) return 'site: ${name.substring(5)}';
    if (name.startsWith('media:')) return name.substring(6);
    if (name.startsWith('score:')) return 'score ${name.substring(6)}';
    if (name.startsWith('pages:')) return '${name.substring(6).replaceAll('-', '–')} pages';
    return words(name);
  }

  /// The bare term a seedable feature stands for (`type:artist:zun` → `zun`,
  /// `ns:parody:x` → `parody:x`, `tag:y` → `y`).
  static String seedTerm(String name) {
    if (name.startsWith('type:')) return name.substring(name.indexOf(':', 5) + 1);
    if (name.startsWith('ns:')) return name.substring(3);
    if (name.startsWith('tag:')) return name.substring(4);
    return name;
  }

  static TagType _typeOf(Tag tag, BooruItem item, RecommenderWorld world) {
    if (tag.tagType != TagType.none || world == RecommenderWorld.doujin) return tag.tagType;
    try {
      return SuggestionEngine.typeOf(tag, item: item);
    } catch (_) {
      return tag.tagType;
    }
  }

  static String? _handlerNamespace(BooruHandler? handler, String name) {
    if (handler == null) return null;
    try {
      return handler.tagNamespace(name);
    } catch (_) {
      return null;
    }
  }

  static String? _namespaceOfType(TagType type) => switch (type) {
    TagType.artist => 'artist',
    TagType.copyright => 'parody',
    TagType.character => 'character',
    _ => null,
  };

  static String _mediumOf(BooruItem item, RecommenderWorld world) {
    if (world == RecommenderWorld.doujin) return 'book';
    if (item.mediaType.value.isVideo) return 'video';
    if (item.mediaType.value.isAnimation) return 'animation';
    return 'image';
  }

  static const int _maxTitleFeatures = 16;

  static void _addTitle(_Builder b, String text) {
    if (text.trim().isEmpty) return;
    int added = 0;
    for (final String token in DoujinRecommendationEngine.titleTokens(text)) {
      if (added >= _maxTitleFeatures) break;
      if (b.add('title:$token')) added++;
    }
  }
}

class _Builder {
  final List<int> hashes = [];
  final List<String> names = [];
  final Set<String> _seen = {};

  bool add(String name) {
    if (!_seen.add(name)) return false;
    names.add(name);
    hashes.add(ItemFeatures.hash(name));
    return true;
  }

  FeatureVector build() => FeatureVector(List.unmodifiable(hashes), List.unmodifiable(names));
}
