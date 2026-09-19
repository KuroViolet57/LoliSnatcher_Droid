import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// The Tag builder for e-hentai / exhentai.
///
/// The site itself publishes no tag index (checked 2026-09-09: `/tags` is a
/// 404, and `tools.php?act=tagsearch` answers "You must be logged in"). So
/// the lists come from the EhTagTranslation database — the community tag
/// database JHenTai and EhViewer read for the same purpose — which publishes
/// ONE markdown file per namespace:
///
///   `https://raw.githubusercontent.com/EhTagTranslation/Database/master/database/<ns>.md`
///
/// reclass 2 KB · cosplayer 6 KB · other 7 KB · language 17 KB · male 43 KB ·
/// female 74 KB · group 259 KB · parody 269 KB · artist 372 KB ·
/// character 718 KB (sizes verified the same day).
///
/// That shape is exactly one chip = one namespace = one request, so every
/// namespace is a single shard and a tap pulls only what it lists.
///
/// Two consequences worth knowing:
/// - the database carries no per-tag counts, so rows sort alphabetically
///   rather than most-used first, unlike the sites that publish counts;
/// - it is a third-party file on GitHub, so it can lag the site by a few days
///   and a network that blocks GitHub gets an error naming it, not an empty
///   list.
/// [EHentaiTagCatalog.parseNamespaceFile], shaped for `compute`.
List<BooruTagEntry> _parseOffThread(List<String> args) =>
    EHentaiTagCatalog.parseNamespaceFile(args[0], args[1]);

class EHentaiTagCatalog extends TagCatalogSource {
  EHentaiTagCatalog(this.handler);

  final EHentaiHandler handler;

  static const String databaseBase = 'https://raw.githubusercontent.com/EhTagTranslation/Database/master/database';

  /// Test seam: answers the file request in place of the network.
  @visibleForTesting
  Future<({int status, String body})> Function(String url)? fetcher;

  static String fileUrl(String namespace) => '$databaseBase/$namespace.md';

  /// The site's namespaces, in the order a person is most likely to want
  /// them. Three are deliberately absent: `category`, `rating` and `pages`
  /// are the app's own filter keys (`EHentaiQuery.reservedKeys`) and a chip
  /// inserting one would be read as a filter rather than a tag; and
  /// `reclass` — whose rows are the gallery categories — is a namespace for
  /// reclassification VOTES, so searching `reclass:manga` answers almost
  /// nothing. The Metatags card already offers those categories as the
  /// `category:` chip, which becomes the site's own category mask.
  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: doujinArtistType, shards: 1),
    TagCatalogNamespace(key: 'character', label: 'Characters', type: doujinCharacterType, shards: 1),
    TagCatalogNamespace(key: 'parody', label: 'Parodies', type: doujinCopyrightType, shards: 1),
    TagCatalogNamespace(key: 'group', label: 'Groups', type: doujinArtistType, shards: 1),
    TagCatalogNamespace(key: 'female', label: 'Female', type: doujinNoneType, shards: 1),
    TagCatalogNamespace(key: 'male', label: 'Male', type: doujinNoneType, shards: 1),
    TagCatalogNamespace(key: 'mixed', label: 'Mixed', type: doujinNoneType, shards: 1),
    TagCatalogNamespace(key: 'cosplayer', label: 'Cosplayers', type: doujinArtistType, shards: 1),
    TagCatalogNamespace(key: 'language', label: 'Language', type: doujinMetaType, shards: 1),
    TagCatalogNamespace(key: 'other', label: 'Other', type: doujinNoneType, shards: 1),
  ];

  /// Where the lists come from, said in the picker rather than only here.
  @override
  String? get pullNote => 'lists from the community tag database on GitHub';

  /// One file per chip, so nothing is gained by pausing between them.
  @override
  Duration get shardDelay => const Duration(milliseconds: 100);

  /// ALWAYS qualified. On this site a bare term is a title keyword search
  /// (`EHentaiQuery.siteTerm`), and the handler can only put a namespace back
  /// on a tag it has already seen in a listing — which a freshly pulled row
  /// has not been.
  @override
  String searchTerm(BooruTagEntry e) => '${e.namespace}:${e.name}';

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    if (shard != 0 || namespaceFor(namespace) == null) return null;
    final String url = fileUrl(namespace);
    final ({int status, String body}) response = await (fetcher?.call(url) ?? _get(url));
    if (response.status != 200) {
      throw Exception(
        'the tag database on GitHub answered ${response.status} for $namespace '
        '(raw.githubusercontent.com — a network that blocks it cannot fill these lists)',
      );
    }
    // character.md is 718 KB and ~15k rows: parsing it on the UI isolate
    // freezes the sheet at the end of an already silent wait.
    return compute(_parseOffThread, [response.body, namespace]);
  }

  /// A plain request: no session cookie, no site headers. This is GitHub,
  /// not the source's own host.
  Future<({int status, String body})> _get(String url) async {
    final Response response = await DioNetwork.get(
      url,
      headers: {'User-Agent': Tools.browserUserAgent, 'Accept': 'text/plain'},
      options: Options(validateStatus: (_) => true),
    );
    return (status: response.statusCode ?? 0, body: response.data?.toString() ?? '');
  }

  /// The rows of one namespace file.
  ///
  /// The file is YAML front matter followed by a markdown table whose first
  /// cell is the site's own tag name. Two kinds of line are not tags: the
  /// header and its `---` separator, and the section dividers the database
  /// uses inside a table (`|  | == Age == | … |`), which have an empty first
  /// cell.
  @visibleForTesting
  static List<BooruTagEntry> parseNamespaceFile(String body, String namespace) {
    final List<BooruTagEntry> out = [];
    final Set<String> seen = {};
    final TagType type = doujinTagTypeFor(namespace);
    for (final String line in body.split('\n')) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith('|')) continue;
      final List<String> cells = trimmed.split('|');
      if (cells.length < 3) continue;
      final String raw = cells[1].trim();
      if (raw.isEmpty || raw.startsWith('-') || raw.startsWith('=') || raw == '原始标签') continue;
      final String name = normalizeDoujinTagName(raw);
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(BooruTagEntry(name: name, tagType: type, namespace: namespace));
    }
    return out;
  }
}
