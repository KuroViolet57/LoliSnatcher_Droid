import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

/// Raised whenever hitomi's own data formats stop looking like what this
/// handler knows how to read.
///
/// hitomi derives its image hosts from a rotating script (`gg.js`) and does
/// its searching against packed binary indexes. Both are unversioned and both
/// have changed shape before. Every parser in this file therefore validates
/// what it got and throws this rather than quietly producing a URL that 404s
/// or an id list that is really misaligned garbage - a visible "hitomi changed"
/// message is recoverable by updating the app, silently broken images are not.
class HitomiFormatException implements Exception {
  const HitomiFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The parsed contents of `https://ltn.gold-usergeneratedcontent.net/gg.js`.
///
/// The live script is ~22KB of generated JavaScript in a fixed shape:
///
/// ```js
/// gg = { m: function(g) {
///   var o = 1;
///   switch (g) { case 3344: case 3993: ... o = 0; break; }
///   return o;
/// },
/// s: function(h) { var m = /(..)(.)$/.exec(h); return parseInt(m[2]+m[1], 16).toString(10); },
/// b: '1788094801/' };
/// ```
///
/// It is a lookup table wearing a switch statement, so it is read with a
/// tokeniser rather than by running JavaScript. `b` rotates roughly daily and
/// the case list is reshuffled with it, so the script is re-fetched rather
/// than baked in.
@immutable
class HitomiGg {
  const HitomiGg({required this.b, required this.defaultM, required this.overrides});

  /// The rotating path prefix, e.g. `1788094801/`. Always carries its slash.
  final String b;

  /// `var o = <n>` - the value returned for any key not in the switch.
  final int defaultM;

  /// The `case <key>: ... o = <n>` table.
  final Map<int, int> overrides;

  /// `gg.m(g)` - picks which mirror serves a given key.
  int m(int g) => overrides[g] ?? defaultM;

  /// `gg.s(h)` - the JS is `/(..)(.)$/.exec(h)` then `parseInt(m[2]+m[1], 16)`,
  /// i.e. the last character of the hash is read as the HIGH nibble-pair and
  /// the two before it as the low ones. Getting this order backwards yields a
  /// plausible-looking number and a dead URL, so it is spelled out here.
  static int subdomainKey(String hash) {
    if (hash.length < 3 || !_hexOnly.hasMatch(hash)) {
      throw HitomiFormatException(
        'hitomi.la gave a page hash this app cannot read ("$hash"). '
        'Image URLs cannot be derived until the app is updated.',
      );
    }
    final String reordered = hash[hash.length - 1] + hash.substring(hash.length - 3, hash.length - 1);
    final int? value = int.tryParse(reordered, radix: 16);
    if (value == null) {
      throw HitomiFormatException('hitomi.la page hash "$hash" is not hexadecimal.');
    }
    return value;
  }

  static final RegExp _hexOnly = RegExp(r'^[0-9a-f]+$');

  /// `gg.b + gg.s(hash) + '/' + hash`
  String pathFor(String hash) => '$b${subdomainKey(hash)}/$hash';

  static final RegExp _bPattern = RegExp(r'''b:\s*['"]([^'"]*)['"]''');
  static final RegExp _defaultPattern = RegExp(r'var\s+o\s*=\s*(\d+)\s*;');
  static final RegExp _tokenPattern = RegExp(r'case\s+(\d+)\s*:|o\s*=\s*(\d+)\s*;\s*break\s*;');

  /// Reads a gg.js body. Throws [HitomiFormatException] the moment anything
  /// required is missing, rather than falling back to a guess.
  static HitomiGg parse(String source) {
    const String prefix = 'hitomi.la changed how it derives image URLs';

    final String? rawB = _bPattern.firstMatch(source)?.group(1);
    if (rawB == null || rawB.trim().isEmpty) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer declares a "b" path prefix). '
        'Images cannot be loaded until the app is updated.',
      );
    }
    final String b = rawB.endsWith('/') ? rawB : '$rawB/';

    final String? rawDefault = _defaultPattern.firstMatch(source)?.group(1);
    if (rawDefault == null) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer declares a default mirror). '
        'Images cannot be loaded until the app is updated.',
      );
    }
    final int defaultM = int.parse(rawDefault);

    // The switch is flat - runs of `case N:` share the assignment that follows
    // them - so accumulate keys and flush them when an assignment appears.
    final Map<int, int> overrides = {};
    final List<int> pending = [];
    for (final match in _tokenPattern.allMatches(source)) {
      final String? caseKey = match.group(1);
      if (caseKey != null) {
        pending.add(int.parse(caseKey));
        continue;
      }
      final int value = int.parse(match.group(2)!);
      for (final key in pending) {
        overrides[key] = value;
      }
      pending.clear();
    }

    if (overrides.isEmpty) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer contains a mirror table). '
        'Images cannot be loaded until the app is updated.',
      );
    }

    return HitomiGg(b: b, defaultM: defaultM, overrides: overrides);
  }
}

/// One node of hitomi's on-disk B-tree, used for free-text search.
@immutable
class HitomiIndexNode {
  const HitomiIndexNode({required this.keys, required this.datas, required this.subnodes});

  final List<Uint8List> keys;

  /// `(offset, length)` into the matching `.data` file.
  final List<({int offset, int length})> datas;
  final List<int> subnodes;

  bool get isLeaf => subnodes.every((a) => a == 0);
}

/// hitomi.la.
///
/// hitomi has no API. Everything below is built on the three static endpoints
/// its own front-end uses, all served from `ltn.gold-usergeneratedcontent.net`
/// (`ltn.hitomi.la` no longer resolves at all):
///
///   * `gg.js`                      - how to build image URLs, see [HitomiGg]
///   * `galleries/{id}.js`          - one gallery, as `var galleryinfo = {...}`
///   * `n/**.nozomi`                - packed big-endian int32 id lists, one per
///                                    tag/artist/series/type, newest first
///   * `galleriesindex/galleries.{version}.{index,data}`
///                                  - a B-tree for free-text search
///
/// The nozomi files are the nice part: because they are a flat array of ids in
/// display order, a page of results is a single HTTP range request for exactly
/// the bytes that page needs, rather than a download of the whole index.
///
/// Related comes from hitomi itself (galleryinfo carries a `related` id list);
/// Recommended is generated by [DoujinRecommendationEngine].
class HitomiHandler extends BooruHandler with DoujinNamespacedTags {
  HitomiHandler(super.booru, super.limit);

  // hitomi has no accounts and no API key; the fields would do nothing.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


  static const String _site = 'https://hitomi.la';
  static const String _ltn = 'https://ltn.gold-usergeneratedcontent.net';
  static const String _cdn = 'gold-usergeneratedcontent.net';

  /// hitomi's B-tree branching factor, and the fixed window its own client
  /// reads a node with. Both are constants in hitomi's search.js.
  static const int _btreeBranching = 16;
  static const int _maxNodeSize = 464;

  /// hitomi refuses to return more than this from one text-search bucket, and
  /// so do we - a larger count means the index shape changed under us.
  static const int _maxTextResults = 10000;

  /// How much of a nozomi list is pulled down when a query needs more than one
  /// term intersected. A single-term query never hits this: it is served by a
  /// range request for just the page being shown. 20000 ids is 80KB.
  static const int _intersectionWindow = 20000;

  @override
  bool get hasReader => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  bool get hasSizeData => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  Map<String, String> getHeaders() => {
    ...super.getHeaders(),
    'Referer': '$_site/',
    'Origin': _site,
  };

  /// hitomi's image hosts hotlink-protect hard: the exact same URL returns 404
  /// with no referer and 200 with one. Verified live against a failing
  /// thumbnail from a device log.
  @override
  Map<String, String> getMediaHeaders() => const {
    'Referer': '$_site/',
    'Origin': _site,
  };

  @override
  String validateTags(String tags) => tags.trim();

  @override
  String makePostURL(String id) => '$_site/galleries/$id.html';

  // ── gg.js ─────────────────────────────────────────────────────────────

  HitomiGg? _gg;
  DateTime? _ggFetchedAt;

  /// `b` rotates on the order of once a day; refetching hourly keeps URLs live
  /// without hammering the endpoint.
  static const Duration _ggMaxAge = Duration(hours: 1);

  /// Lets tests drive URL derivation without a network round trip.
  @visibleForTesting
  HitomiGg? get ggForTests => _gg;

  @visibleForTesting
  set ggForTests(HitomiGg? gg) {
    _gg = gg;
    _ggFetchedAt = gg == null ? null : DateTime.now();
  }

  Future<HitomiGg> _requireGg() async {
    final HitomiGg? cached = _gg;
    final DateTime? at = _ggFetchedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < _ggMaxAge) {
      return cached;
    }

    final Response response = await DioNetwork.get('$_ltn/gg.js', headers: getHeaders());
    if (response.statusCode != 200 || response.data is! String) {
      throw HitomiFormatException(
        'hitomi.la would not serve its image-URL script (gg.js '
        '${response.statusCode ?? 'no response'}). Images cannot be loaded right now.',
      );
    }
    final HitomiGg parsed = HitomiGg.parse(response.data as String);
    _gg = parsed;
    _ggFetchedAt = DateTime.now();
    return parsed;
  }

  /// Full-size page image. Mirrors hitomi's `url_from_url_from_hash(..., 'webp')`:
  /// the path is `gg.b + gg.s(hash) + '/' + hash + '.webp'` and the host is
  /// `w<1 + gg.m(key)>`.
  @visibleForTesting
  static String imageUrlFor(HitomiGg gg, String hash) {
    final int key = HitomiGg.subdomainKey(hash);
    return 'https://w${1 + gg.m(key)}.$_cdn/${gg.b}$key/$hash.webp';
  }

  /// Cover / filmstrip thumbnail. Mirrors the `'tn'` base branch, which uses a
  /// completely different path shape - `<last char>/<two before>/<hash>` under
  /// `webpbigtn`, on host `<letter>tn`.
  @visibleForTesting
  static String thumbnailUrlFor(HitomiGg gg, String hash) {
    final int key = HitomiGg.subdomainKey(hash);
    if (hash.length != 64) {
      throw HitomiFormatException(
        'hitomi.la page hash "$hash" is ${hash.length} characters, expected 64. '
        'Thumbnail URLs cannot be derived until the app is updated.',
      );
    }
    final String letter = String.fromCharCode(97 + gg.m(key));
    return 'https://${letter}tn.$_cdn/webpbigtn/'
        '${hash[63]}/${hash.substring(61, 63)}/$hash.webp';
  }

  // ── nozomi id lists ───────────────────────────────────────────────────

  /// Packed big-endian int32 gallery ids.
  @visibleForTesting
  static List<int> decodeNozomi(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    if (bytes.length % 4 != 0) {
      throw HitomiFormatException(
        'hitomi.la search index format changed: an id list was ${bytes.length} '
        'bytes, which is not a whole number of entries. Search results would be '
        'garbage, so none are shown.',
      );
    }
    final ByteData view = ByteData.sublistView(Uint8List.fromList(bytes));
    return [for (int i = 0; i < bytes.length; i += 4) view.getInt32(i, Endian.big)];
  }

  /// Where a single query term lives in the nozomi tree, or null when the term
  /// is free text and has to go through the B-tree instead.
  ///
  /// Follows hitomi's own namespace routing: `female:`/`male:` are stored under
  /// `tag/`, `language:` is the whole-site index for that language, and the
  /// app's `parody:`/`circle:` spellings are mapped onto hitomi's
  /// `series/`/`group/`.
  @visibleForTesting
  static ({String? area, String tag, String language})? nozomiTargetFor(String term) {
    final String normalised = term.trim().toLowerCase().replaceAll('_', ' ');
    if (normalised.isEmpty) return null;

    final int colon = normalised.indexOf(':');
    if (colon <= 0) return null;

    final String namespace = normalised.substring(0, colon).trim();
    final String value = normalised.substring(colon + 1).trim();
    if (value.isEmpty) return null;

    switch (namespace) {
      case 'female':
      case 'male':
        return (area: 'tag', tag: '$namespace:$value', language: 'all');
      case 'language':
        return (area: null, tag: 'index', language: value);
      case 'popular':
        return (area: 'popular', tag: value, language: 'all');
      case 'parody':
      case 'series':
        return (area: 'series', tag: value, language: 'all');
      case 'circle':
      case 'group':
        return (area: 'group', tag: value, language: 'all');
      case 'artist':
      case 'character':
      case 'type':
      case 'tag':
        return (area: namespace, tag: value, language: 'all');
      default:
        // An unknown namespace is not silently flattened into a text search -
        // hitomi would answer with an unrelated bucket.
        return null;
    }
  }

  @visibleForTesting
  static String nozomiUrlFor(({String? area, String tag, String language}) target) {
    // `:` is legal in these paths and hitomi serves them unescaped, but spaces
    // are not.
    final String tag = Uri.encodeComponent(target.tag).replaceAll('%3A', ':');
    final String suffix = '$tag-${target.language}.nozomi';
    return target.area == null ? '$_ltn/n/$suffix' : '$_ltn/n/${target.area}/$suffix';
  }

  /// The whole-site newest-first index, used when nothing was searched for.
  static const ({String? area, String tag, String language}) _allTarget =
      (area: null, tag: 'index', language: 'all');

  Future<List<int>> _nozomi(
    ({String? area, String tag, String language}) target, {
    required int start,
    required int count,
  }) async {
    final String url = nozomiUrlFor(target);
    final Uint8List? bytes = await _rangeGet(url, start * 4, count * 4);
    if (bytes == null) return const [];
    return decodeNozomi(bytes);
  }

  /// A byte range out of one of the static index files.
  ///
  /// `Accept-Encoding: identity` is not optional. hitomi's nginx answers a
  /// partial request with `Content-Encoding: gzip` set even though the slice it
  /// sends is the raw bytes, so an HTTP client that honours the header
  /// gunzips 40 bytes of binary into nothing and the search quietly returns no
  /// results. Asking for identity stops nginx setting the header at all.
  Future<Uint8List?> _rangeGet(String url, int start, int length) async {
    final Response response = await DioNetwork.get(
      url,
      headers: {
        ...getHeaders(),
        'Range': 'bytes=$start-${start + length - 1}',
        'Accept-Encoding': 'identity',
      },
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) =>
            status == 200 || status == 206 || status == 404 || status == 416,
      ),
    );
    // 404: no such tag. 416: asked past the end of the list, i.e. no more pages.
    if (response.statusCode == 404 || response.statusCode == 416) return null;

    final data = response.data;
    final Uint8List bytes = data is List<int> ? Uint8List.fromList(data) : Uint8List(0);
    if (bytes.isEmpty && _rangeSliceLength(response) > 0) {
      // The server said it was sending bytes and none arrived - which is what
      // the gzip trap above looks like. Say so instead of showing "no results".
      throw const HitomiFormatException(
        'hitomi.la returned an unreadable search index (the server sent a '
        'range this app could not decode). Search results are not shown rather '
        'than being shown wrong.',
      );
    }
    return bytes.isEmpty ? null : bytes;
  }

  /// How many bytes the `Content-Range: bytes a-b/total` header promised.
  static int _rangeSliceLength(Response response) {
    final String? header = response.headers.value('content-range');
    if (header == null) return 0;
    final match = RegExp(r'bytes\s+(\d+)-(\d+)/').firstMatch(header);
    if (match == null) return 0;
    return int.parse(match.group(2)!) - int.parse(match.group(1)!) + 1;
  }

  // ── free-text search over the B-tree ──────────────────────────────────

  @visibleForTesting
  static Uint8List hashTerm(String term) =>
      Uint8List.fromList(sha256.convert(utf8.encode(term)).bytes.sublist(0, 4));

  /// `int32 nkeys, (int32 len, bytes)*, int32 ndatas, (int64 offset, int32 len)*,
  /// int64 subnode[B+1]`, all big-endian.
  @visibleForTesting
  static HitomiIndexNode decodeNode(List<int> bytes) {
    const String changed = 'hitomi.la search index format changed';
    final ByteData view = ByteData.sublistView(Uint8List.fromList(bytes));
    int pos = 0;

    int readInt32() {
      if (pos + 4 > bytes.length) throw const HitomiFormatException('$changed (index node truncated).');
      final int value = view.getInt32(pos, Endian.big);
      pos += 4;
      return value;
    }

    int readInt64() {
      if (pos + 8 > bytes.length) throw const HitomiFormatException('$changed (index node truncated).');
      final int value = view.getInt64(pos, Endian.big);
      pos += 8;
      return value;
    }

    final int keyCount = readInt32();
    if (keyCount < 0 || keyCount > _btreeBranching) {
      throw HitomiFormatException('$changed (index node claims $keyCount keys).');
    }
    final List<Uint8List> keys = [];
    for (int i = 0; i < keyCount; i++) {
      final int keyLength = readInt32();
      if (keyLength <= 0 || pos + keyLength > bytes.length) {
        throw HitomiFormatException('$changed (index key length $keyLength).');
      }
      keys.add(Uint8List.fromList(bytes.sublist(pos, pos + keyLength)));
      pos += keyLength;
    }

    final int dataCount = readInt32();
    if (dataCount < 0 || dataCount > _btreeBranching) {
      throw HitomiFormatException('$changed (index node claims $dataCount data entries).');
    }
    final List<({int offset, int length})> datas = [];
    for (int i = 0; i < dataCount; i++) {
      final int offset = readInt64();
      final int length = readInt32();
      datas.add((offset: offset, length: length));
    }

    final List<int> subnodes = [];
    for (int i = 0; i < _btreeBranching + 1; i++) {
      subnodes.add(readInt64());
    }

    return HitomiIndexNode(keys: keys, datas: datas, subnodes: subnodes);
  }

  /// Byte-wise compare, as hitomi's `compare_arraybuffers`.
  @visibleForTesting
  static int compareKeys(Uint8List a, Uint8List b) {
    final int top = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < top; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return 0;
  }

  @visibleForTesting
  static ({bool found, int index}) locateKey(Uint8List key, HitomiIndexNode node) {
    int comparison = -1;
    int i = 0;
    for (; i < node.keys.length; i++) {
      comparison = compareKeys(key, node.keys[i]);
      if (comparison <= 0) break;
    }
    return (found: comparison == 0, index: i);
  }

  String? _indexVersion;

  Future<String?> _searchIndexVersion() async {
    final String? cached = _indexVersion;
    if (cached != null) return cached;
    try {
      final Response response = await DioNetwork.get(
        '$_ltn/galleriesindex/version?_=${DateTime.now().millisecondsSinceEpoch}',
        headers: getHeaders(),
      );
      final String version = response.data?.toString().trim() ?? '';
      if (version.isEmpty || !RegExp(r'^\d+$').hasMatch(version)) return null;
      _indexVersion = version;
      return version;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _textSearch(String term) async {
    final String? version = await _searchIndexVersion();
    if (version == null) return const [];
    final String indexUrl = '$_ltn/galleriesindex/galleries.$version.index';
    final String dataUrl = '$_ltn/galleriesindex/galleries.$version.data';
    final Uint8List key = hashTerm(term.trim().toLowerCase().replaceAll('_', ' '));

    ({int offset, int length})? hit;
    int address = 0;
    // The tree is shallow; the bound is only there so a corrupt index cannot
    // spin forever.
    for (int depth = 0; depth < 32; depth++) {
      final Uint8List? raw = await _rangeGet(indexUrl, address, _maxNodeSize);
      if (raw == null || raw.isEmpty) return const [];
      final HitomiIndexNode node = decodeNode(raw);
      if (node.keys.isEmpty) return const [];
      final located = locateKey(key, node);
      if (located.found) {
        if (located.index >= node.datas.length) {
          throw const HitomiFormatException(
            'hitomi.la search index format changed (key with no data slot).',
          );
        }
        hit = node.datas[located.index];
        break;
      }
      if (node.isLeaf) return const [];
      address = node.subnodes[located.index];
      if (address == 0) return const [];
    }
    if (hit == null) return const [];

    final Uint8List? blob = await _rangeGet(dataUrl, hit.offset, hit.length);
    if (blob == null || blob.length < 4) return const [];
    final ByteData view = ByteData.sublistView(blob);
    final int count = view.getInt32(0, Endian.big);
    if (count < 0 || count > _maxTextResults) {
      throw HitomiFormatException(
        'hitomi.la search index format changed (a result bucket claimed $count entries).',
      );
    }
    if (blob.length < count * 4 + 4) {
      throw const HitomiFormatException(
        'hitomi.la search index format changed (result bucket shorter than its own count).',
      );
    }
    return [for (int i = 0; i < count; i++) view.getInt32(i * 4 + 4, Endian.big)];
  }

  // ── query planning ────────────────────────────────────────────────────

  @visibleForTesting
  static ({List<String> positive, List<String> negative}) parseQuery(String tags) {
    final List<String> positive = [];
    final List<String> negative = [];
    for (final match in RegExp(r'"[^"]*"|\S+').allMatches(tags.trim())) {
      String token = match.group(0)!.replaceAll('"', '').trim();
      if (token.isEmpty) continue;
      if (token.startsWith('-')) {
        token = token.substring(1).trim();
        if (token.isNotEmpty) negative.add(token);
      } else {
        positive.add(token);
      }
    }
    return (positive: positive, negative: negative);
  }

  Future<List<int>> _idsForTerm(String term, {required int start, required int count}) async {
    // Chips display bare (`ahegao`) but hitomi files that tag under
    // `female:ahegao` and resolves the two spellings to different indexes, so
    // the namespace has to go back on before the lookup.
    final target = nozomiTargetFor(qualifyTag(term));
    if (target != null) return _nozomi(target, start: start, count: count);
    // A text bucket is not stored in display order, so it is ordered by id -
    // hitomi ids increase over time, which reproduces its newest-first feed.
    // (The list is copied first: an empty result is a const literal.)
    final List<int> ids = [...await _textSearch(term)]..sort((a, b) => b.compareTo(a));
    if (start >= ids.length) return const [];
    return ids.sublist(start, (start + count).clamp(0, ids.length));
  }

  /// Resolved id lists, so paging a query does not re-run the whole plan.
  final Map<String, List<int>> _resolvedIds = {};

  Future<List<int>> _idsForQuery(String tags, int page) async {
    final parsed = parseQuery(tags);
    final int start = (page - 1) * limit;

    // The common case: nothing to intersect, so a page is exactly one range
    // request for the bytes that page needs.
    if (parsed.negative.isEmpty && parsed.positive.length <= 1) {
      if (parsed.positive.isEmpty) {
        return _nozomi(_allTarget, start: start, count: limit);
      }
      return _idsForTerm(parsed.positive.first, start: start, count: limit);
    }

    final String cacheKey = tags.trim().toLowerCase();
    List<int>? resolved = _resolvedIds[cacheKey];
    if (resolved == null) {
      final List<String> positive = parsed.positive.isEmpty ? const [] : parsed.positive;
      List<int>? working;
      if (positive.isEmpty) {
        working = await _nozomi(_allTarget, start: 0, count: _intersectionWindow);
      } else {
        for (final term in positive) {
          final List<int> ids = await _idsForTerm(term, start: 0, count: _intersectionWindow);
          if (working == null) {
            // The first term sets the ordering; every nozomi list is already
            // newest-first, so the intersection stays in hitomi's own order.
            working = ids;
          } else {
            final Set<int> keep = ids.toSet();
            working = working.where(keep.contains).toList();
          }
          if (working.isEmpty) break;
        }
      }
      for (final term in parsed.negative) {
        if (working == null || working.isEmpty) break;
        final Set<int> drop = (await _idsForTerm(term, start: 0, count: _intersectionWindow)).toSet();
        working = working.where((id) => !drop.contains(id)).toList();
      }
      resolved = working ?? const [];
      _resolvedIds[cacheKey] = resolved;
    }

    if (start >= resolved.length) return const [];
    return resolved.sublist(start, (start + limit).clamp(0, resolved.length));
  }

  // ── galleryinfo ───────────────────────────────────────────────────────

  /// `var galleryinfo = {...}` - a JS assignment wrapping plain JSON.
  @visibleForTesting
  static Map<String, dynamic> parseGalleryInfo(String body) {
    final int brace = body.indexOf('{');
    if (brace == -1) {
      throw const HitomiFormatException(
        'hitomi.la returned a gallery in a format this app cannot read.',
      );
    }
    final decoded = jsonDecode(body.substring(brace));
    if (decoded is! Map) {
      throw const HitomiFormatException(
        'hitomi.la returned a gallery in a format this app cannot read.',
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> _gallery(String id) async {
    try {
      final Response response = await DioNetwork.get(
        '$_ltn/galleries/$id.js',
        headers: getHeaders(),
      );
      if (response.statusCode != 200 || response.data == null) return null;
      return parseGalleryInfo(response.data.toString());
    } on HitomiFormatException {
      rethrow;
    } catch (_) {
      return null;
    }
  }


  /// hitomi splits its tags across half a dozen top-level keys and marks
  /// gendered tags with `female`/`male` flags rather than a namespace, so they
  /// are flattened into the app's `namespace:tag` spelling here.
  /// hitomi splits its tags across half a dozen top-level keys and marks
  /// gendered tags with `female`/`male` flags rather than a namespace. They are
  /// flattened here into bare names with the namespace kept on the side, so a
  /// chip reads `ahegao` while the detail page can still file it under Female
  /// Tags and search can still ask for `female:ahegao` — which matters, because
  /// hitomi resolves those two spellings to different indexes.
  @visibleForTesting
  List<Tag> tagsFromGallery(Map<String, dynamic> gallery) {
    final List<Tag> tags = [];
    final Set<String> seen = {};

    void add(String rawName, String? namespace) {
      if (rawName.trim().isEmpty) return;
      final Tag tag = namespacedTag(rawName, namespace);
      if (tag.fullString.isEmpty || !seen.add(tag.fullString)) return;
      tags.add(tag);
    }

    void addAll(String key, String field, String namespace) {
      for (final entry in gallery[key] as List? ?? const []) {
        if (entry is! Map) continue;
        add(entry[field]?.toString() ?? '', namespace);
      }
    }

    addAll('artists', 'artist', 'artist');
    addAll('groups', 'group', 'circle');
    addAll('parodys', 'parody', 'parody');
    addAll('characters', 'character', 'character');

    for (final entry in gallery['tags'] as List? ?? const []) {
      if (entry is! Map) continue;
      final bool female = entry['female']?.toString().isNotEmpty ?? false;
      final bool male = entry['male']?.toString().isNotEmpty ?? false;
      add(entry['tag']?.toString() ?? '', female ? 'female' : (male ? 'male' : null));
    }

    add(gallery['type']?.toString() ?? '', 'type');
    add(gallery['language']?.toString() ?? '', 'language');

    return tags;
  }

  BooruItem? _itemFromGallery(Map<String, dynamic> gallery, HitomiGg gg) {
    final String id = gallery['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final List files = gallery['files'] as List? ?? const [];
    final String coverHash = files.isEmpty ? '' : (files.first as Map?)?['hash']?.toString() ?? '';
    if (coverHash.isEmpty) return null;

    final String thumbnail = thumbnailUrlFor(gg, coverHash);
    final item = BooruItem(
      fileURL: thumbnail,
      sampleURL: thumbnail,
      thumbnailURL: thumbnail,
      tagsList: tagsFromGallery(gallery),
      postURL: makePostURL(id),
      serverId: id,
      postDate: gallery['date']?.toString(),
      postDateFormat: 'yyyy-MM-dd HH:mm:ssZ',
    );

    final String title = gallery['title']?.toString() ?? '';
    final String japanese = gallery['japanese_title']?.toString() ?? '';
    item.description = japanese.isNotEmpty && japanese != title && title.isNotEmpty
        ? '$title\n$japanese'
        : (title.isNotEmpty ? title : japanese);
    if (files.isNotEmpty) item.fileCountHint.value = files.length;
    return item;
  }

  // ── the doujin query protocol ─────────────────────────────────────────

  static final RegExp _protocol = RegExp(r'^(id|related|recommend):(\d+)$', caseSensitive: false);

  static ({String kind, String id})? _parseProtocol(String tags) {
    final match = _protocol.firstMatch(tags.trim());
    if (match == null) return null;
    return (kind: match.group(1)!.toLowerCase(), id: match.group(2)!);
  }

  @override
  String makeURL(String tags) {
    final int page = pageNum < 1 ? 1 : pageNum;
    final String query = tags.trim();
    // Every fetch is multi-step (index -> ids -> galleries), so the real work
    // happens in [fetchSearch]; this URL only has to identify the request in
    // logs and be parseable.
    return '$_site/search.html?q=${Uri.encodeQueryComponent(query)}&page=$page';
  }

  /// hitomi has no endpoint that returns a page of galleries, so a search is
  /// assembled here: resolve ids from the indexes, then pull each gallery in
  /// parallel. The result is handed to [parseListFromResponse] as a plain list
  /// of galleryinfo maps.
  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    final RequestOptions options = RequestOptions(path: uri.toString());
    final protocol = _parseProtocol(input);
    final int page = pageNum < 1 ? 1 : pageNum;

    List<int> ids;
    if (protocol == null) {
      ids = await _idsForQuery(input, page);
    } else if (protocol.kind == 'id') {
      ids = [int.parse(protocol.id)];
    } else {
      // Related and Recommended both need the source gallery first; they are
      // resolved in [parseListFromResponse] where the engine lives.
      ids = const [];
    }

    final List<Map<String, dynamic>> galleries = await _galleries(ids);
    return Response<dynamic>(requestOptions: options, statusCode: 200, data: galleries);
  }

  /// How many gallery files are pulled at once. Firing a whole candidate pool
  /// at the CDN in one `Future.wait` made Recommended take minutes; a small
  /// window is both faster and politer.
  static const int _galleryConcurrency = 6;

  Future<List<Map<String, dynamic>>> _galleries(List<int> ids) async {
    if (ids.isEmpty) return const [];

    final List<Map<String, dynamic>?> results = List.filled(ids.length, null);
    int next = 0;

    Future<void> worker() async {
      while (true) {
        final int index = next++;
        if (index >= ids.length) return;
        results[index] = await _gallery(ids[index].toString());
      }
    }

    await Future.wait([
      for (int i = 0; i < _galleryConcurrency && i < ids.length; i++) worker(),
    ]);

    // Order is preserved, which matters: hitomi's own `related` list is
    // already ranked and the nozomi indexes are date-sorted.
    return [
      for (final gallery in results) ?gallery,
    ];
  }

  @override
  FutureOr<List> parseListFromResponse(dynamic response) async {
    final HitomiGg gg = await _requireGg();
    final protocol = _parseProtocol(currentTags);
    if (protocol != null && protocol.kind != 'id') {
      return protocol.kind == 'related'
          ? await _fetchRelated(protocol.id, gg)
          : await _fetchRecommended(protocol.id, gg);
    }

    final data = response.data;
    if (data is! List) return [];
    return [
      for (final gallery in data)
        if (gallery is Map<String, dynamic>)
          if (_itemFromGallery(gallery, gg) case final BooruItem item) item,
    ];
  }

  /// [parseListFromResponse] already builds finished items, so the base class's
  /// per-entry hook is a passthrough. Without this override it would replace
  /// every one of them with the default blank [BooruItem] and the grid would
  /// fill with empty cards.
  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) =>
      responseItem is BooruItem ? responseItem : null;


  // ── detail + reader ───────────────────────────────────────────────────

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    dynamic cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    final String id = item.serverId ?? '';
    if (id.isEmpty) return (item: null, failed: true, error: 'no gallery id');

    final HitomiGg gg;
    try {
      gg = await _requireGg();
    } on HitomiFormatException catch (e) {
      return (item: null, failed: true, error: e.message);
    }

    final Map<String, dynamic>? gallery;
    try {
      gallery = await _gallery(id);
    } on HitomiFormatException catch (e) {
      return (item: null, failed: true, error: e.message);
    }
    if (gallery == null) return (item: null, failed: true, error: 'failed to load gallery');

    item.tagsList = tagsFromGallery(gallery);
    final String title = gallery['title']?.toString() ?? '';
    final String japanese = gallery['japanese_title']?.toString() ?? '';
    if (title.isNotEmpty || japanese.isNotEmpty) {
      item.description = japanese.isNotEmpty && japanese != title && title.isNotEmpty
          ? '$title\n$japanese'
          : (title.isNotEmpty ? title : japanese);
    }

    final List files = gallery['files'] as List? ?? const [];
    if (files.isEmpty) return (item: null, failed: true, error: 'gallery has no pages');

    final List<BooruItem> pages = [];
    try {
      for (final file in files) {
        if (file is! Map) continue;
        final String hash = file['hash']?.toString() ?? '';
        if (hash.isEmpty) continue;
        final String full = imageUrlFor(gg, hash);
        pages.add(
          BooruItem(
            fileURL: full,
            sampleURL: full,
            thumbnailURL: thumbnailUrlFor(gg, hash),
            tagsList: const [],
            postURL: makePostURL(id),
            fileWidth: (file['width'] as num?)?.toDouble(),
            fileHeight: (file['height'] as num?)?.toDouble(),
          ),
        );
      }
    } on HitomiFormatException catch (e) {
      return (item: null, failed: true, error: e.message);
    }

    if (pages.isEmpty) return (item: null, failed: true, error: 'gallery has no readable pages');

    ReaderHandler.instance.registerBook(item, pages);
    item.fileCountHint.value = pages.length;
    return (item: item, failed: false, error: null);
  }

  // ── Related / Recommended ─────────────────────────────────────────────

  /// hitomi publishes its own related list on every gallery, so Related is the
  /// site's answer, only re-ranked for title/series closeness.
  Future<List<BooruItem>> _fetchRelated(String id, HitomiGg gg) async {
    final Map<String, dynamic>? gallery = await _gallery(id);
    if (gallery == null) return [];
    final BooruItem? source = _itemFromGallery(gallery, gg);
    if (source == null) return [];

    final List<int> relatedIds = [
      for (final value in gallery['related'] as List? ?? const [])
        if (value is num) value.toInt(),
    ];
    final List<BooruItem> candidates = [
      for (final related in await _galleries(relatedIds))
        if (_itemFromGallery(related, gg) case final BooruItem item) item,
    ];
    if (candidates.isEmpty) {
      return DoujinRecommendationEngine.related(source, await _candidatesFor(source, gg));
    }
    // hitomi's own list is authoritative, so nothing is dropped from it. The
    // engine is used only to float same-work entries - other languages, chapter
    // splits - to the front, with the rest kept in the order hitomi gave them.
    final List<BooruItem> ranked = DoujinRecommendationEngine.related(source, candidates);
    final Set<String> promoted = {for (final item in ranked) item.postURL};
    return [
      ...ranked,
      ...candidates.where((item) => !promoted.contains(item.postURL)),
    ];
  }

  Future<List<BooruItem>> _fetchRecommended(String id, HitomiGg gg) async {
    final Map<String, dynamic>? gallery = await _gallery(id);
    if (gallery == null) return [];
    final BooruItem? source = _itemFromGallery(gallery, gg);
    if (source == null) return [];

    // The tag TYPE, not an `artist:` prefix: names are bare now, so a prefix


    // test finds nothing and the same-artist cap below quietly stops working.


    String? artist;


    for (final tag in source.tagsList) {


      if (tag.tagType == TagType.artist) {


        artist = tag.fullString;


        break;


      }


    }

    return DoujinRecommendationEngine.rank(
      source,
      await _candidatesFor(source, gg),
      count: limit,
      sourceArtist: (artist?.isEmpty ?? true) ? null : artist,
    );
  }

  /// Pulls a pool to rank, from the source's own strongest tags. Each nozomi
  /// read is a small range request, so a handful of them is cheap.
  Future<List<BooruItem>> _candidatesFor(BooruItem source, HitomiGg gg) async {
    const int perTag = 12;
    final List<String> terms = [
      for (final tag in source.tagsList)
        if (nozomiTargetFor(qualifyTag(tag.fullString)) != null) qualifyTag(tag.fullString),
    ];
    // Artist and series buckets are the most informative and the smallest.
    terms.sort((a, b) => _termWeight(b).compareTo(_termWeight(a)));

    final Set<int> ids = {};
    final int sourceId = int.tryParse(source.serverId ?? '') ?? -1;
    for (final term in terms.take(5)) {
      final target = nozomiTargetFor(term);
      if (target == null) continue;
      for (final id in await _nozomi(target, start: 0, count: perTag)) {
        if (id != sourceId) ids.add(id);
      }
      if (ids.length >= perTag * 3) break;
    }

    return [
      for (final gallery in await _galleries(ids.take(perTag * 3).toList()))
        if (_itemFromGallery(gallery, gg) case final BooruItem item) item,
    ];
  }

  static int _termWeight(String term) => switch (term.split(':').first) {
    'artist' || 'circle' => 3,
    'parody' || 'character' => 2,
    'female' || 'male' || 'tag' => 1,
    _ => 0,
  };

  @override
  String? relatedVersionsQuery(BooruItem item) {
    final String id = item.serverId ?? '';
    return id.isEmpty ? null : 'related:$id';
  }

  // ── tag presentation ──────────────────────────────────────────────────


  @override
  List<(String, String)> get tagNamespaceSections => const [
    ('artist', 'Artists'),
    ('circle', 'Circles'),
    ('parody', 'Series'),
    ('character', 'Characters'),
    ('female', 'Female Tags'),
    ('male', 'Male Tags'),
    ('tag', 'Tags'),
    ('type', 'Type'),
    ('language', 'Language'),
  ];

  @override
  List<MetaTag> availableMetaTags() => [
    StringMetaTag(name: 'Artist', keyName: 'artist'),
    StringMetaTag(name: 'Circle', keyName: 'circle'),
    StringMetaTag(name: 'Series', keyName: 'parody'),
    StringMetaTag(name: 'Character', keyName: 'character'),
    StringMetaTag(name: 'Type', keyName: 'type'),
    StringMetaTag(name: 'Language', keyName: 'language'),
  ];
}
