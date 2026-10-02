import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// asmhentai's per-type indexes: `/tags/`, `/artists/`, `/characters/`,
/// `/parodies/`, `/groups/` with `?page=N`, 120 entries a page (35–258
/// pages), each `<a class="badge tag" href="/tag/big-breasts/">big breasts
/// <span class="galleries_count">(228961)</span></a>`. Verified 2026-09-02.
/// No language or category index exists on the site.
class AsmHentaiTagCatalog extends TagCatalogSource {
  AsmHentaiTagCatalog(this.handler);

  final AsmHentaiHandler handler;

  static const Map<String, String> paths = {
    'tag': 'tags',
    'artist': 'artists',
    'character': 'characters',
    'parody': 'parodies',
    'group': 'groups',
  };

  /// Pages a single pull walks before stopping; the next pull resumes.
  static const int pagesPerPull = 80;

  @override
  Duration get shardDelay => const Duration(milliseconds: 400);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'group', label: 'Groups', type: doujinArtistType, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'parody', label: 'Parodies', type: doujinCopyrightType, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: doujinCharacterType, maxShards: pagesPerPull),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType, maxShards: pagesPerPull),
  ];

  /// Everything is qualified: `makeURL` routes one `ns:name` to the site's
  /// taxonomy page, which is what the term identifies.
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    final String? path = paths[namespace];
    if (path == null || shard < 0) return null;
    final Response response = await DioNetwork.get(
      '${AsmHentaiHandler.siteBase}/$path/?page=${shard + 1}',
      headers: handler.getHeaders(),
      options: Options(validateStatus: (_) => true),
    );
    if (response.statusCode != 200) throw Exception('asmhentai answered ${response.statusCode} for $path page ${shard + 1}');
    final List<BooruTagEntry> got = parseIndex(response.data.toString());
    // A page past the end renders the frame with no entries: the last page.
    return got.isEmpty ? null : got;
  }

  static final RegExp _href = RegExp(r'^/([a-z]+)/([^/]+)/?$');

  @visibleForTesting
  static List<BooruTagEntry> parseIndex(String body) {
    final dom.Document doc = parse(body);
    final List<BooruTagEntry> out = [];
    for (final a in doc.querySelectorAll('a.badge')) {
      final match = _href.firstMatch(a.attributes['href'] ?? '');
      if (match == null || !paths.containsKey(match.group(1))) continue;
      final String ns = match.group(1)!;
      final String name = normalizeDoujinTagName(match.group(2)!.replaceAll('-', ' '));
      if (name.isEmpty) continue;
      final String countText = a.querySelector('.galleries_count, .gallery_count')?.text ?? '';
      final String digits = RegExp(r'[\d,]+').firstMatch(countText)?.group(0)?.replaceAll(',', '') ?? '';
      out.add(
        BooruTagEntry(
          name: name,
          namespace: ns,
          tagType: doujinTagTypeFor(ns),
          count: int.tryParse(digits) ?? 0,
        ),
      );
    }
    return out;
  }
}
