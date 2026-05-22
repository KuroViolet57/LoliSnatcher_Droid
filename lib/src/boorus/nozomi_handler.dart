import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class NozomiHandler extends BooruHandler {
  NozomiHandler(super.booru, super.limit);

  static const String _jsonHost = 'https://j.gold-usergeneratedcontent.net';
  static const String _imageHost = 'https://w.gold-usergeneratedcontent.net';
  static const String _gifHost = 'https://g.gold-usergeneratedcontent.net';
  static const String _videoHost = 'https://v.gold-usergeneratedcontent.net';
  static const String _thumbHost = 'https://tn.gold-usergeneratedcontent.net';

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => false;

  // Mirrors nozomi.la's `full_path_from_hash`: last char / 2 chars before / full.
  // Used for both image dataids and the post JSON path keyed by postid.
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

    tags = tags.trim();
    if (prevTags != tags) {
      fetched.value = [];
      totalCount.value = 0;
    }
    final int length = fetched.length;

    try {
      final List<int> allIds = await _resolveIds(tags);
      if (allIds.isEmpty) {
        prevTags = tags;
        locked = true;
        return fetched;
      }

      final int effectivePage = pageNum < 1 ? 0 : pageNum - 1;
      final int startIndex = effectivePage * limit;
      if (startIndex >= allIds.length) {
        prevTags = tags;
        locked = true;
        return fetched;
      }
      final List<int> pageIds = allIds.skip(startIndex).take(limit).toList();

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

  Future<List<int>> _resolveIds(String input) async {
    final List<String> terms = input.isEmpty ? [] : input.split(' ').where((t) => t.isNotEmpty).toList();
    final List<String> positive = [];
    final List<String> negative = [];
    for (final term in terms) {
      if (term.startsWith('-') && term.length > 1) {
        negative.add(term.substring(1));
      } else {
        positive.add(term);
      }
    }

    List<int> result;
    if (positive.isEmpty) {
      result = await _fetchIdList('');
    } else {
      result = await _fetchIdList(positive.first);
      for (int i = 1; i < positive.length; i++) {
        final next = await _fetchIdList(positive[i]);
        result = result.toSet().intersection(next.toSet()).toList();
        if (result.isEmpty) break;
      }
    }

    for (final term in negative) {
      if (result.isEmpty) break;
      final exclude = await _fetchIdList(term);
      result = result.toSet().difference(exclude.toSet()).toList();
    }

    return result;
  }

  Future<List<int>> _fetchIdList(String term) async {
    final String url = term.isEmpty
        ? '$_jsonHost/index.nozomi'
        : '$_jsonHost/nozomi/${Uri.encodeComponent(term)}.nozomi';

    try {
      final Response response = await DioNetwork.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }
      final List<int> bytes = (response.data as List).cast<int>();
      final ByteData view = ByteData.view(Uint8List.fromList(bytes).buffer);
      final List<int> ids = [];
      for (int i = 0; i + 4 <= view.lengthInBytes; i += 4) {
        ids.add(view.getUint32(i));
      }
      return ids;
    } catch (e, s) {
      Logger.Inst().log(
        'failed to fetch id list for "$term": $e',
        className,
        '_fetchIdList',
        LogTypes.booruHandlerFetchFailed,
        s: s,
      );
      return const [];
    }
  }

  Future<dynamic> _fetchPostJson(int id) async {
    final String url = '$_jsonHost/post/${fullPathFromHash(id.toString())}.json';
    try {
      final Response response = await DioNetwork.get(url);
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
    final Map imageData = imageUrls.first as Map;
    final String dataId = imageData['dataid']?.toString() ?? '';
    final String type = (imageData['type'] ?? 'jpg').toString();
    final bool isVideo = imageData['is_video'] == 1 || imageData['is_video'] == true;
    if (dataId.isEmpty) return null;

    final String path = fullPathFromHash(dataId);
    String fileURL;
    String sampleURL;
    String thumbURL;
    if (isVideo) {
      fileURL = '$_videoHost/$path.$type';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.webp';
    } else if (type == 'gif') {
      fileURL = '$_gifHost/$path.gif';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.webp';
    } else {
      fileURL = '$_imageHost/$path.webp';
      sampleURL = fileURL;
      thumbURL = '$_thumbHost/$path.webp';
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
        name = (entry['tagname_display'] ?? entry['tag'] ?? entry['tagname'] ?? entry['name'])?.toString();
      }
      if (name == null || name.isEmpty) continue;
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

  // search() is overridden, so the base URL/encoding flow is intentionally bypassed.
  @override
  String validateTags(String tags) => tags;

  @override
  String makeURL(String tags) => '';
}
