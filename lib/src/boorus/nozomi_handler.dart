import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class NozomiHandler extends BooruHandler {
  NozomiHandler(super.booru, super.limit);

  static const String _jsonHost = 'https://j.gold-usergeneratedcontent.net';
  static const String _imageHost = 'https://w.gold-usergeneratedcontent.net';
  static const String _gifHost = 'https://g.gold-usergeneratedcontent.net';
  static const String _videoHost = 'https://v.gold-usergeneratedcontent.net';
  static const String _thumbHost = 'https://qtn.gold-usergeneratedcontent.net';
  static const String _siteOrigin = 'https://nozomi.la';

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => false;

  // Nozomi's CDN serves 403/404 unless the Referer matches nozomi.la.
  @override
  Map<String, String> getHeaders() {
    return {
      ...super.getHeaders(),
      'Referer': '$_siteOrigin/',
      'Origin': _siteOrigin,
      'User-Agent': Tools.browserUserAgent,
    };
  }

  // Mirrors nozomi.la's `full_path_from_hash`: last char / 2 chars before / full.
  // Used for both image dataids (hashes) and the post JSON path keyed by postid.
  String fullPathFromHash(String hash) {
    if (hash.length < 3) {
      return hash;
    }
    return hash.replaceFirstMapped(
      RegExp(r'^.*(..)(.)$'),
      (match) => '${match.group(2)}/${match.group(1)}/$hash',
    );
  }

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (pageNumCustom != null) {
      pageNum = pageNumCustom;
    }

    if (!await searchSetup()) {
      locked = true;
      return fetched;
    }

    tags = translateOrSyntax(tags.trim());
    if (prevTags != tags) {
      fetched.value = [];
      totalCount.value = 0;
    }
    final int length = fetched.length;

    try {
      final int effectivePage = pageNum < 1 ? 0 : pageNum - 1;
      final int startIndex = effectivePage * limit;

      final List<int> pageIds = await _resolvePageIds(tags, startIndex, limit);
      if (pageIds.isEmpty) {
        prevTags = tags;
        locked = true;
        return fetched;
      }

      final List<dynamic> jsons = await Future.wait(pageIds.map(_fetchPostJson));

      final List<BooruItem> newItems = [];
      for (int i = 0; i < jsons.length; i++) {
        final json = jsons[i];
        if (json == null) continue;
        final BooruItem? item = parseItemFromResponse(json, i);
        if (item != null) {
          newItems.add(item);
        }
      }

      await afterParseResponse(newItems);
      prevTags = tags;
      if (fetched.length == length) {
        locked = true;
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        className,
        'search',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
      errorString = e.toString();
    }

    return fetched;
  }

  Future<List<int>> _resolvePageIds(String input, int startIndex, int count) async {
    final List<String> terms = input.isEmpty ? [] : input.split(' ').where((t) => t.isNotEmpty).toList();
    final List<String> positive = [];
    final List<String> negative = [];
    bool popular = false;
    for (final term in terms) {
      // Sort toggle: `sort:popular` (and `sort:date`/default) switches between
      // index-Popular.nozomi and index.nozomi. For a single positive term + popular,
      // the per-tag nozomi/popular/{term}-Popular.nozomi file is used instead.
      if (term.toLowerCase() == 'sort:popular') {
        popular = true;
        continue;
      }
      if (term.toLowerCase() == 'sort:date') {
        popular = false;
        continue;
      }
      if (term.startsWith('-') && term.length > 1) {
        negative.add(term.substring(1));
      } else {
        positive.add(term);
      }
    }

    // Fast path: no tag filtering → byte-range-slice the global index, never
    // download the whole 100+ MB file.
    if (positive.isEmpty && negative.isEmpty) {
      return _fetchIdRange(_indexUrl('', popular: popular), startIndex, count);
    }

    // Filtered path: per-tag .nozomi files are smaller — fetch each in full, intersect/subtract.
    List<int> result;
    if (positive.isEmpty) {
      result = await _fetchAllIds(_indexUrl('', popular: popular));
    } else {
      result = await _fetchAllIds(_indexUrl(positive.first, popular: popular));
      for (int i = 1; i < positive.length; i++) {
        // Popular intersections aren't a thing in nozomi's index layout — fall
        // back to a date-ordered intersection beyond the first term, matching
        // nozomi.js's own behaviour.
        final next = await _fetchAllIds(_indexUrl(positive[i]));
        result = result.toSet().intersection(next.toSet()).toList();
        if (result.isEmpty) break;
      }
    }
    for (final term in negative) {
      if (result.isEmpty) break;
      final exclude = await _fetchAllIds(_indexUrl(term));
      result = result.toSet().difference(exclude.toSet()).toList();
    }

    // We have the full filtered id list here, so the count is exact.
    totalCount.value = result.length;
    if (startIndex >= result.length) return const [];
    return result.skip(startIndex).take(count).toList();
  }

  // Parses the total size out of a "bytes start-end/TOTAL" Content-Range header
  // and converts it to a post count (4 bytes per packed Int32 id).
  int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final int slashIdx = header.lastIndexOf('/');
    if (slashIdx < 0) return null;
    final int? totalBytes = int.tryParse(header.substring(slashIdx + 1).trim());
    if (totalBytes == null) return null;
    return totalBytes ~/ 4;
  }

  String _indexUrl(String term, {bool popular = false}) {
    if (term.isEmpty) {
      return popular
          ? '$_jsonHost/index-Popular.nozomi'
          : '$_jsonHost/index.nozomi';
    }
    final encoded = Uri.encodeComponent(term);
    return popular
        ? '$_jsonHost/nozomi/popular/$encoded-Popular.nozomi'
        : '$_jsonHost/nozomi/$encoded.nozomi';
  }

  Future<List<int>> _fetchIdRange(String url, int startIndex, int count) async {
    final int rangeStart = startIndex * 4;
    final int rangeEnd = rangeStart + count * 4 - 1;
    try {
      final Response response = await DioNetwork.get(
        url,
        headers: {
          ...getHeaders(),
          'Range': 'bytes=$rangeStart-$rangeEnd',
          // Critical: nozomi's CDN ignores Range and streams the entire ~110MB
          // gzipped file when any compression is allowed. Force identity so we
          // actually get a 206 partial.
          'Accept-Encoding': 'identity',
        },
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s == 206,
        ),
      );
      // The 206 response carries "Content-Range: bytes start-end/TOTAL"; the
      // index file is a packed Int32 array, so TOTAL / 4 is the post count.
      final int? total = _totalFromContentRange(response.headers.value('content-range'));
      if (total != null) {
        totalCount.value = total;
      }
      final ids = _decodeIds(response.data);
      return ids.take(count).toList();
    } catch (e, s) {
      Logger.Inst().log(
        'failed to range-fetch ids ($url $rangeStart-$rangeEnd): $e',
        className,
        '_fetchIdRange',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
      return const [];
    }
  }

  Future<List<int>> _fetchAllIds(String url) async {
    try {
      final Response response = await DioNetwork.get(
        url,
        headers: {
          ...getHeaders(),
          // Per-tag .nozomi files are usually small, but the global index can
          // still leak in here through fallbacks — keep identity so a runaway
          // stream can't OOM the device.
          'Accept-Encoding': 'identity',
        },
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode != 200) return const [];
      return _decodeIds(response.data);
    } catch (e, s) {
      Logger.Inst().log(
        'failed to fetch ids ($url): $e',
        className,
        '_fetchAllIds',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
      return const [];
    }
  }

  List<int> _decodeIds(dynamic raw) {
    if (raw == null) return const [];
    final Uint8List bytes;
    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is List<int>) {
      bytes = Uint8List.fromList(raw);
    } else if (raw is List) {
      // best-effort: drop any non-int entries instead of throwing on cast
      bytes = Uint8List.fromList(raw.whereType<int>().toList());
    } else {
      return const [];
    }
    final ByteData view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    final List<int> ids = [];
    for (int i = 0; i + 4 <= view.lengthInBytes; i += 4) {
      ids.add(view.getUint32(i));
    }
    return ids;
  }

  Future<dynamic> _fetchPostJson(int id) async {
    final String url = '$_jsonHost/post/${fullPathFromHash(id.toString())}.json';
    try {
      final Response response = await DioNetwork.get(url, headers: getHeaders());
      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is String) {
        return jsonDecode(data);
      }
      return data;
    } catch (e) {
      return null;
    }
  }

  @override
  List parseListFromResponse(dynamic response) {
    if (response is List) return response;
    if (response is Response && response.data is List) return response.data as List;
    return const [];
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map current = responseItem;

    final imageUrls = current['imageurls'];
    if (imageUrls is! List || imageUrls.isEmpty) {
      return null;
    }
    final dynamic firstImage = imageUrls.first;
    if (firstImage is! Map) {
      return null;
    }
    final Map imageData = firstImage;
    final String dataId = imageData['dataid']?.toString() ?? '';
    final String type = (imageData['type'] ?? 'jpg').toString();
    // is_video may come through as 1, true, "" (empty string for false) or "1".
    final dynamic isVideoRaw = imageData['is_video'];
    final bool isVideo = isVideoRaw == 1 || isVideoRaw == true || isVideoRaw == '1';
    if (dataId.isEmpty) return null;

    final String path = fullPathFromHash(dataId);
    String fileURL;
    String sampleURL;
    String thumbURL;
    if (isVideo) {
      fileURL = '$_videoHost/$path.$type';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.$type.webp';
    } else if (type == 'gif') {
      fileURL = '$_gifHost/$path.gif';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.$type.webp';
    } else {
      fileURL = '$_imageHost/$path.webp';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.$type.webp';
    }

    final List<Tag> tags = [];
    _collectTags(current, 'artist', TagType.artist, tags);
    _collectTags(current, 'character', TagType.character, tags);
    _collectTags(current, 'copyright', TagType.copyright, tags);
    _collectTags(current, 'general', TagType.none, tags);
    if (tags.isEmpty) {
      // Fallback: some payloads put general tags under "tags" instead of "general".
      _collectTags(current, 'tags', TagType.none, tags);
    }

    final String postId = (current['postid'] ?? current['id'] ?? '').toString();

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL,
      thumbnailURL: thumbURL,
      tagsList: tags,
      postURL: makePostURL(postId),
      serverId: postId.isEmpty ? null : postId,
      postDate: current['date']?.toString(),
    );
  }

  void _collectTags(Map json, String category, TagType type, List<Tag> out) {
    final dynamic raw = json[category];
    if (raw is! List) return;
    final List<String> names = [];
    for (final entry in raw) {
      String? name;
      if (entry is String) {
        name = entry;
      } else if (entry is Map) {
        // Prefer the underscored canonical form (`tag`) over the display form
        // (`tagname_display`). The display form contains spaces, and the
        // app's multi-tag parser splits queries on spaces — feeding it back
        // would turn a single "ju fufu" tag into two unrelated tokens.
        name = (entry['tag'] ?? entry['tagname'] ?? entry['name'] ?? entry['tagname_display'])?.toString();
      }
      if (name == null || name.isEmpty) continue;
      // Defensive: if only a display-form slipped through (whitespace inside),
      // convert spaces to the underscore convention every booru uses.
      if (name.contains(' ')) {
        name = name.trim().replaceAll(RegExp(r'\s+'), '_');
      }
      out.add(Tag(name));
      names.add(name);
    }
    if (names.isNotEmpty) {
      addTagsWithType(names, type);
    }
  }

  @override
  String makePostURL(String id) {
    return 'https://nozomi.la/post/$id.html';
  }

  // Surfaces as a `sort:` chip in the search bar with Date / Popular options.
  // Implementation: see _resolvePageIds + _indexUrl which switch between
  // index.nozomi and index-Popular.nozomi (or per-tag equivalents).
  @override
  List<MetaTag> availableMetaTags() {
    return [
      SortMetaTag(
        isFree: true,
        values: [
          MetaTagValue(name: 'Date', value: 'date'),
          MetaTagValue(name: 'Popular', value: 'popular'),
        ],
      ),
    ];
  }

  // search() is overridden, so the base URL/encoding flow is intentionally bypassed.
  @override
  String validateTags(String tags) => tags;

  // Nozomi has no native OR — it's set-intersection on packed index files.
  // Drop OR groups with a warning until a proper union implementation lands.
  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String makeURL(String tags) => '';
}
