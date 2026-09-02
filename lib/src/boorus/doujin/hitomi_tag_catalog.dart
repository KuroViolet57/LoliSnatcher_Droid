import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// hitomi's index pages: `https://hitomi.la/all{tags,artists,series,
/// characters,groups}-{123,a..z}.html`, 27 letter shards per family,
/// entries `<li><a href="/tag/a3-all.html">a3</a> (25)</li>`. Gendered tags
/// sit in the tags family as `/tag/female%3Aabortion-all.html`. Verified
/// 2026-09-02; the old ltn `*.json` indexes are gone (404).
///
/// Languages come from `ltn…/language_support.js` (no counts) and the type
/// list is the site's fixed six.
class HitomiTagCatalog extends TagCatalogSource {
  HitomiTagCatalog(this.handler);

  final HitomiHandler handler;

  static const List<String> shardKeys = [
    '123', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ];

  /// Namespace → index family on the site.
  static const Map<String, String> families = {
    'tag': 'tags',
    'female': 'tags',
    'male': 'tags',
    'artist': 'artists',
    'parody': 'series',
    'character': 'characters',
    'circle': 'groups',
  };

  static const List<String> types = ['doujinshi', 'manga', 'artistcg', 'gamecg', 'imageset', 'anime'];

  @override
  Duration get shardDelay => const Duration(milliseconds: 400);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType, shards: 27),
    TagCatalogNamespace(key: 'circle', label: 'Circles', type: doujinArtistType, shards: 27),
    TagCatalogNamespace(key: 'parody', label: 'Series', type: doujinCopyrightType, shards: 27),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: doujinCharacterType, shards: 27),
    TagCatalogNamespace(key: 'female', label: 'Female', type: doujinNoneType, shards: 27),
    TagCatalogNamespace(key: 'male', label: 'Male', type: doujinNoneType, shards: 27),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType, shards: 27),
    TagCatalogNamespace(key: 'language', label: 'Languages', type: doujinMetaType, shards: 1),
    TagCatalogNamespace(key: 'type', label: 'Types', type: doujinMetaType, shards: 1),
  ];

  /// hitomi's search treats a bare word as free text; every catalog row is
  /// sent qualified so it lands in its own index (`tag:x`, `female:x`, …).
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (namespace == 'type') {
      if (shard != 0) return null;
      return [for (final t in types) BooruTagEntry(name: t, namespace: 'type', tagType: doujinMetaType)];
    }
    if (namespace == 'language') {
      if (shard != 0) return null;
      final Response response = await DioNetwork.get('${HitomiHandler.ltnBase}/language_support.js', headers: handler.getHeaders());
      return parseLanguages(response.data.toString());
    }
    final String? family = families[namespace];
    if (family == null || shard < 0 || shard >= shardKeys.length) return null;
    final Response response = await DioNetwork.get(
      '${HitomiHandler.siteBase}/all$family-${shardKeys[shard]}.html',
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true),
    );
    if (response.statusCode != 200) throw Exception('hitomi answered ${response.statusCode} for all$family-${shardKeys[shard]}');
    // The tags family carries tag, female and male rows together; all three
    // are stored from one fetch.
    return parseIndex(response.data.toString());
  }

  static final RegExp _entry = RegExp(
    r'<li>\s*<a href="/(tag|artist|series|character|group)/([^"]+)-all\.html">[^<]*</a>\s*\(([\d,]+)\)',
  );

  static const Map<String, String> _areaNamespaces = {
    'tag': 'tag',
    'artist': 'artist',
    'series': 'parody',
    'character': 'character',
    'group': 'circle',
  };

  @visibleForTesting
  static List<BooruTagEntry> parseIndex(String body) {
    final List<BooruTagEntry> out = [];
    for (final m in _entry.allMatches(body)) {
      String ns = _areaNamespaces[m.group(1)!]!;
      String slug = Uri.decodeComponent(m.group(2)!);
      if (ns == 'tag') {
        for (final gender in const ['female', 'male']) {
          if (slug.startsWith('$gender:')) {
            ns = gender;
            slug = slug.substring(gender.length + 1);
            break;
          }
        }
      }
      final String name = normalizeDoujinTagName(slug);
      if (name.isEmpty) continue;
      out.add(
        BooruTagEntry(
          name: name,
          namespace: ns,
          tagType: doujinTagTypeFor(ns),
          count: int.tryParse(m.group(3)!.replaceAll(',', '')) ?? 0,
        ),
      );
    }
    return out;
  }

  /// `var bitnumber_language = {"42":"korean","8":"english",…}` → one row per name.
  @visibleForTesting
  static List<BooruTagEntry> parseLanguages(String js) {
    final Set<String> names = {};
    for (final m in RegExp(r'"\d+"\s*:\s*"([^"]+)"').allMatches(js)) {
      names.add(normalizeDoujinTagName(m.group(1)!));
    }
    final List<String> sorted = names.toList()..sort();
    return [for (final n in sorted) BooruTagEntry(name: n, namespace: 'language', tagType: doujinMetaType)];
  }
}
