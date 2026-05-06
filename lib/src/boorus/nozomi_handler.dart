import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:get_it/get_it.dart';

class NozomiHandler extends BooruHandler {
  NozomiHandler(super.booru, super.limit);

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => false;

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
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    // searchStr will be the tags. If empty, fetch index.nozomi
    // Nozomi returns array buffers of post IDs.
    // If we have multiple tags, we need to fetch them all and compute intersection.
    // However, to integrate with the existing pagination, we override the normal flow here
    // or just fetch all IDs on the first page, and slice them.

    final List<String> terms = input.isEmpty ? [] : input.split(' ');
    final List<String> positiveTerms = [];
    final List<String> negativeTerms = [];

    for (final term in terms) {
      if (term.startsWith('-')) {
        negativeTerms.add(term.substring(1));
      } else {
        positiveTerms.add(term);
      }
    }

    List<int> resultIds = [];

    Future<List<int>> fetchNozomi(String term, bool isPopular) async {
      String nozomiAddress;
      if (term.isEmpty) {
        nozomiAddress = isPopular
            ? 'https://j.gold-usergeneratedcontent.net/index-Popular.nozomi'
            : 'https://j.gold-usergeneratedcontent.net/index.nozomi';
      } else {
        nozomiAddress = isPopular
            ? 'https://j.gold-usergeneratedcontent.net/nozomi/popular/${Uri.encodeComponent(term)}-Popular.nozomi'
            : 'https://j.gold-usergeneratedcontent.net/nozomi/${Uri.encodeComponent(term)}.nozomi';
      }

      try {
        final response = await Dio().get<List<int>>(
          nozomiAddress,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data;
        if (bytes != null) {
          final byteData = ByteData.view(Uint8List.fromList(bytes).buffer);
          final List<int> ids = [];
          for (int i = 0; i < byteData.lengthInBytes; i += 4) {
            ids.add(byteData.getUint32(i, Endian.big)); // Big-endian
          }
          return ids;
        }
      } catch (e) {
        // Handle 404 or other errors
      }
      return [];
    }

    if (positiveTerms.isEmpty) {
      resultIds = await fetchNozomi('', false); // or true for popular?
    } else {
      // Fetch the first term
      resultIds = await fetchNozomi(positiveTerms[0], false);
      for (int i = 1; i < positiveTerms.length; i++) {
        final termIds = await fetchNozomi(positiveTerms[i], false);
        resultIds = resultIds.toSet().intersection(termIds.toSet()).toList();
      }
    }

    if (negativeTerms.isNotEmpty) {
      for (final term in negativeTerms) {
        final termIds = await fetchNozomi(term, false);
        resultIds = resultIds.toSet().difference(termIds.toSet()).toList();
      }
    }

    // Now we have the full list of IDs. We must paginate them.
    // In LoliSnatcher, usually handlers start with `startingPage = 0`, and when test adds 1 it searches page 1.
    // So 1 means first page. Let's make page 1 mapping to index 0, and so on.
    final int safePage = pageNum < 1 ? 1 : pageNum;
    final int effectivePage = safePage - 1;

    final startIndex = effectivePage * limit;
    List<int> pagedIds = [];
    if (startIndex < resultIds.length) {
      pagedIds = resultIds.skip(startIndex).take(limit).toList();
    }

    // Now we need to fetch the JSON for each ID in the page
    final List<dynamic> items = [];
    for (final id in pagedIds) {
      final jsonUrl = 'https://j.gold-usergeneratedcontent.net/post/${fullPathFromHash(id.toString())}.json';
      try {
        final response = await Dio().get(jsonUrl);
        if (response.statusCode == 200) {
          dynamic decodedData;
          if (response.data is String) {
            decodedData = jsonDecode(response.data);
          } else {
            decodedData = response.data;
          }
          items.add(decodedData);
        }
      } catch (e) {
        // Skip on error
      }
    }

    return Response(
      requestOptions: RequestOptions(path: uri.toString()),
      data: items,
      statusCode: 200,
    );
  }

  @override
  List parseListFromResponse(dynamic response) {
    return response.data as List;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final Map<String, dynamic> current = responseItem as Map<String, dynamic>;

    // Nozomi JSON structure has:
    // postid, date, imageurls: [{dataid, type, is_video}], tags: {character, copyright, artist, general}

    if (current['imageurls'] == null || current['imageurls'].isEmpty) {
      return null;
    }

    final imageUrlData = current['imageurls'][0];
    final bool isVideo = imageUrlData['is_video'] == 1 || imageUrlData['is_video'] == true;
    final String dataId = imageUrlData['dataid'].toString();
    final String type = imageUrlData['type'].toString();

    String fileURL;
    String sampleURL;
    String thumbURL;

    final String path = fullPathFromHash(dataId);

    if (isVideo) {
      fileURL = 'https://v.gold-usergeneratedcontent.net/$path.$type';
      sampleURL = fileURL;
      thumbURL = 'https://tn.gold-usergeneratedcontent.net/$path.webp';
    } else {
      final String prefix = type == 'gif' ? 'g' : 'w';
      final String ext = type == 'gif' ? 'gif' : 'webp';
      fileURL = 'https://$prefix.gold-usergeneratedcontent.net/$path.$ext';
      sampleURL = fileURL;
      thumbURL = 'https://tn.gold-usergeneratedcontent.net/$path.webp'; // thumbnails usually webp
    }

    final List<Tag> tags = [];

    void parseTags(String category, TagType tagType) {
      if (current[category] != null) {
        for (final tagData in current[category]) {
          final String tagName = tagData['tagname_display'] ?? tagData['tag'];
          tags.add(Tag(tagName));
          if (GetIt.instance.isRegistered<TagHandler>()) {
            addTagsWithType([tagName], tagType);
          }
        }
      }
    }

    parseTags('character', TagType.character);
    parseTags('copyright', TagType.copyright);
    parseTags('artist', TagType.artist);
    parseTags('general', TagType.none);

    final String postId = current['postid'].toString();

    return BooruItem(
      fileURL: fileURL,
      sampleURL: sampleURL,
      thumbnailURL: thumbURL,
      tagsList: tags,
      postURL: makePostURL(postId),
      serverId: postId,
      postDate: current['date'],
    );
  }

  @override
  String makePostURL(String id) {
    return 'https://nozomi.la/post/$id.html';
  }

  @override
  String validateTags(String tags) {
    // Override validateTags so it does NOT encode the string,
    // as fetchSearch does its own manual encoding where appropriate
    // and expects space-separated string for multi-tag logic.
    return tags;
  }

  @override
  String makeURL(String tags) {
    return tags; // Search handled by fetchSearch entirely
  }
}
