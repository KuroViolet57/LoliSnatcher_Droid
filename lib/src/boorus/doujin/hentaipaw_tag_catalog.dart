import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// hentaipaw's per-type indexes: `/tags?page=N` (captured 2026-09-02: 138
/// pages of 100, each entry `<a href="/tags/14390" class="group"
/// title="name">…</a>` inside `div.tag-container`, no counts anywhere) and,
/// from the same navigation bar, `/artists`, `/groups`, `/parodies` and
/// `/characters` — those four are parsed the same way but were NOT in the
/// capture; a page that turns out to differ stores nothing and shows the
/// download icon until it is captured.
///
/// The site's tag pages are keyed by numeric id, so the id travels with the
/// row ([BooruTagEntry.sourceId]) and the handler routes a picked term to
/// `/tags/{id}` through it.
class HentaiPawTagCatalog extends TagCatalogSource {
  HentaiPawTagCatalog(this.handler);

  final HentaiPawHandler handler;

  static const Map<String, String> paths = {
    'artist': 'artists',
    'group': 'groups',
    'parody': 'parodies',
    'character': 'characters',
    'tag': 'tags',
  };

  /// Pages one pull walks before stopping; the next pull resumes. Tags run
  /// to 138 pages, so two pulls.
  static const int pagesPerPull = 70;

  /// The last page each index reported, read from the first page's
  /// pagination so the walk stops without a request past the end.
  final Map<String, int> _lastPage = {};

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

  /// Always qualified: the handler resolves `ns:name` to the site's id page;
  /// a bare name would fall through to the text search, which does not
  /// match on tags.
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    final String? path = paths[namespace];
    if (path == null || shard < 0) return null;
    final int page = shard + 1;
    final int? last = _lastPage[namespace];
    if (last != null && page > last) return null;
    final ({int status, String body}) response = await handler.page('${HentaiPawHandler.siteBase}/$path?page=$page');
    if (response.status == 404) return null;
    if (response.status != 200) throw Exception('hentaipaw answered ${response.status} for $path page $page');
    final int? reported = lastPageFrom(response.body);
    if (reported != null) _lastPage[namespace] = reported;
    final List<BooruTagEntry> got = parseIndex(response.body, plural: path);
    return got.isEmpty ? null : got;
  }

  static final RegExp _href = RegExp(r'^/([a-z]+)/([0-9]+)/?$');

  /// Entries of one index page. [plural] limits the anchors to that path
  /// (`tags`); null takes every known path on the page.
  @visibleForTesting
  static List<BooruTagEntry> parseIndex(String body, {String? plural}) {
    final dom.Document doc = parse(body);
    final dom.Element? container = doc.querySelector('.tag-container');
    if (container == null) return const [];
    final Map<String, String> namespaceOf = {for (final e in paths.entries) e.value: e.key};
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    for (final a in container.querySelectorAll('a[href]')) {
      final match = _href.firstMatch(a.attributes['href'] ?? '');
      if (match == null) continue;
      final String path = match.group(1)!;
      if (plural != null && path != plural) continue;
      final String? ns = namespaceOf[path];
      if (ns == null) continue;
      final String id = match.group(2)!;
      final String raw = (a.attributes['title'] ?? '').trim().isNotEmpty ? a.attributes['title']!.trim() : a.text.trim();
      final String name = normalizeDoujinTagName(raw);
      if (name.isEmpty || !seen.add('$ns:$name')) continue;
      out.add(
        BooruTagEntry(
          name: name,
          namespace: ns,
          tagType: doujinTagTypeFor(ns),
          sourceId: id,
        ),
      );
    }
    return out;
  }

  /// The page count out of the pagination bar: the "last page" arrow, else
  /// the largest numbered link. Null when the page has no pagination.
  @visibleForTesting
  static int? lastPageFrom(String body) {
    final dom.Document doc = parse(body);
    final dom.Element? nav = doc.querySelector('nav[aria-label="pagination"]');
    if (nav == null) return null;
    int? pageOf(dom.Element a) {
      final m = RegExp('[?&]page=([0-9]+)').firstMatch(a.attributes['href'] ?? '');
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    final dom.Element? last = nav.querySelector('a[aria-label="last page"]');
    if (last != null) {
      final int? n = pageOf(last);
      if (n != null) return n;
    }
    int best = 0;
    for (final a in nav.querySelectorAll('a[href]')) {
      final int? n = pageOf(a);
      if (n != null && n > best) best = n;
    }
    return best == 0 ? null : best;
  }
}
