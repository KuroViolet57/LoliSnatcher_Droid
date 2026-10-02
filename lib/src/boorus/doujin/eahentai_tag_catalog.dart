import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_query.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// eahentai's index pages (r70; captured 2026-09-17):
///
///   `/artists?q=<L>&p=<n>`     100 per page, `<a href="/artist/b%20kaiman">
///                              b kaiman <span>7 albums</span></a>`; a page
///                              past the end answers 404
///   `/characters?q=<L>&p=<n>`  the same shape, `/character/<name>`
///   `/parodies?q=<L>&p=<n>`    the same shape, `/parody/<name>`
///   `/tags?q=<L>`              one page a letter, each tag a
///                              `/search?type=gallery&q=<Tag>&p=1` link
///
/// Letters are `#` and A-Z. A shard is ONE page of one letter (27 letters ×
/// [pagesPerLetter] shards a namespace), so the puller's cancel, progress
/// and resume point work per request; once a letter has ended (a 404 or a
/// short page) the rest of its shards answer empty without a request.
class EaHentaiTagCatalog extends TagCatalogSource {
  EaHentaiTagCatalog(this.handler);

  final EaHentaiHandler handler;

  static const List<String> shardKeys = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  static const Map<String, String> paths = {
    'artist': 'artists',
    'character': 'characters',
    'parody': 'parodies',
    'tag': 'tags',
  };

  /// Rows per index page on the site; a shorter page is the last one.
  static const int pageSize = 100;

  /// Shards a letter (its pages); the busiest letters have five today.
  static const int pagesPerLetter = 20;

  static const int shardsPerNamespace = 27 * pagesPerLetter;

  /// The pause before a real request; the puller's own pause between shards
  /// is short, because most shards of an ended letter cost no request.
  static const Duration requestPace = Duration(milliseconds: 400);

  /// Letters whose last page was seen, per namespace.
  final Set<String> _ended = {};

  @override
  Duration get shardDelay => const Duration(milliseconds: 100);

  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType, shards: shardsPerNamespace),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: doujinCharacterType, shards: shardsPerNamespace),
    TagCatalogNamespace(key: 'parody', label: 'Parodies', type: doujinCopyrightType, shards: shardsPerNamespace),
    TagCatalogNamespace(key: 'tag', label: 'Tags', type: doujinNoneType, shards: shardsPerNamespace),
  ];

  /// The letter and page a shard stands for.
  static ({int letter, int page}) shardPosition(int shard) => (letter: shard ~/ pagesPerLetter, page: shard % pagesPerLetter + 1);

  /// A tag is a bare word to the search (it matches by text); the rest go
  /// typed, which the handler turns into the site's typed search.
  @override
  String searchTerm(BooruTagEntry e) => e.namespace == 'tag' ? e.name : '${e.namespace}:${e.name}';

  static String shardUrl(String namespace, int shard, {int page = 1}) =>
      '${EaHentaiQuery.site}/${paths[namespace]}?q=${Uri.encodeComponent(shardKeys[shard])}${page > 1 ? '&p=$page' : ''}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard < 0 || shard >= shardsPerNamespace || !paths.containsKey(namespace)) return null;
    final ({int letter, int page}) at = shardPosition(shard);
    final String letterKey = '$namespace|${at.letter}';
    if (_ended.contains(letterKey)) return const [];
    // Tags are one page a letter.
    if (namespace == 'tag' && at.page > 1) {
      _ended.add(letterKey);
      return const [];
    }
    await Future<void>.delayed(requestPace);
    final ({int status, String body}) r = await handler.fetchForCatalog(shardUrl(namespace, at.letter, page: at.page));
    if (r.status == 404) {
      _ended.add(letterKey);
      return const [];
    }
    if (r.status != 200) throw Exception('eahentai answered ${r.status} for ${paths[namespace]} ${shardKeys[at.letter]} page ${at.page}');
    final List<BooruTagEntry> rows = parseIndex(namespace, r.body);
    if (namespace == 'tag' || rows.length < pageSize) _ended.add(letterKey);
    return rows;
  }

  static final RegExp _albums = RegExp(r'([\d,]+)\s*album');

  /// The entries of one index page.
  @visibleForTesting
  static List<BooruTagEntry> parseIndex(String namespace, String html) {
    final dom.Document doc = parse(html);
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    if (namespace == 'tag') {
      for (final dom.Element a in doc.querySelectorAll('a[href^="/search?"]')) {
        final Uri? uri = Uri.tryParse(a.attributes['href'] ?? '');
        final String raw = uri?.queryParameters['q'] ?? '';
        final String name = normalizeDoujinTagName(raw);
        if (name.isEmpty || !seen.add(name)) continue;
        out.add(BooruTagEntry(name: name, namespace: 'tag', tagType: doujinNoneType));
      }
      return out;
    }
    final String prefix = '/${namespace == 'parody' ? 'parody' : namespace}/';
    for (final dom.Element a in doc.querySelectorAll('a[href^="$prefix"]')) {
      final String href = a.attributes['href'] ?? '';
      final String encoded = href.substring(prefix.length).split('?').first;
      String decoded;
      try {
        decoded = Uri.decodeComponent(encoded);
      } catch (_) {
        decoded = encoded;
      }
      final String name = normalizeDoujinTagName(decoded);
      if (name.isEmpty || !seen.add(name)) continue;
      final RegExpMatch? m = _albums.firstMatch(a.text);
      final int count = m == null ? 0 : (int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0);
      out.add(
        BooruTagEntry(
          name: name,
          namespace: namespace,
          count: count,
          tagType: switch (namespace) {
            'artist' => doujinArtistType,
            'character' => doujinCharacterType,
            'parody' => doujinCopyrightType,
            _ => doujinNoneType,
          },
        ),
      );
    }
    return out;
  }
}
