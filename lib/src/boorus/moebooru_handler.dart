import 'dart:math';

import 'package:lolisnatcher/src/data/tag.dart';
import 'package:xml/xml.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/note_item.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_utils.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class MoebooruHandler extends BooruHandler {
  MoebooruHandler(super.booru, super.limit);

  /// Artists, characters, copyrights and general tags from tag.json, one type
  /// at a time (see MoebooruTagIndex).
  @override
  late final TagCatalogSource? tagCatalog = BooruTagCatalog.forHandler(this);

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  @override
  Map<String, TagType> get tagTypeMap => {
    '5': TagType.meta,
    '3': TagType.copyright,
    '4': TagType.character,
    '1': TagType.artist,
    '0': TagType.none,
  };

  @override
  List parseListFromResponse(dynamic response) {
    final parsedResponse = XmlDocument.parse(response.data);
    try {
      final int? count = int.tryParse(parsedResponse.findAllElements('posts').first.getAttribute('count') ?? '0');
      totalCount.value = count ?? 0;
    } catch (e, s) {
      Logger.Inst().log(
        '$e',
        className,
        'searchCount',
        LogTypes.exception,
        s: s,
      );
    }

    return parsedResponse.findAllElements('post').toList();
  }

  // TODO change to json
  // can probably use the same method as gelbooru when the individual BooruItem is moved to separate method
  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem as XmlElement;

    if (current.getAttribute('file_url') != null) {
      // Fix for bleachbooru
      String fileURL = '', sampleURL = '', previewURL = '';
      fileURL += current.getAttribute('file_url')!;
      // sample/preview can be missing on some posts; fall back to the file url
      sampleURL += current.getAttribute('sample_url') ?? current.getAttribute('file_url')!;
      previewURL += current.getAttribute('preview_url') ?? current.getAttribute('file_url')!;
      if (!fileURL.contains('http')) {
        fileURL = booru.baseURL! + fileURL;
        sampleURL = booru.baseURL! + sampleURL;
        previewURL = booru.baseURL! + previewURL;
      }

      final BooruItem item = BooruItem(
        fileURL: fileURL,
        sampleURL: sampleURL,
        thumbnailURL: previewURL,
        tagsList: splitTagsClean(current.getAttribute('tags')).map(Tag.new).toList(),
        postURL: makePostURL(current.getAttribute('id')!),
        fileWidth: double.tryParse(current.getAttribute('width') ?? ''),
        fileHeight: double.tryParse(current.getAttribute('height') ?? ''),
        sampleWidth: double.tryParse(current.getAttribute('sample_width') ?? ''),
        sampleHeight: double.tryParse(current.getAttribute('sample_height') ?? ''),
        previewWidth: double.tryParse(current.getAttribute('preview_width') ?? ''),
        previewHeight: double.tryParse(current.getAttribute('preview_height') ?? ''),
        serverId: current.getAttribute('id'),
        rating: current.getAttribute('rating'),
        score: current.getAttribute('score'),
        sources: cleanSourceList(current.getAttribute('source')),
        md5String: current.getAttribute('md5'),
        // r71 review: the viewer's notes button is gated on this flag;
        // post.xml carries last_noted_at="0" when a post has no notes.
        hasNotes: (current.getAttribute('last_noted_at') ?? '0') != '0',
        postDate: current.getAttribute('created_at'), // Fri Jun 18 02:13:45 -0500 2021
        postDateFormat: 'unix', // when timezone support added: "EEE MMM dd HH:mm:ss Z yyyy",
      );

      return item;
    } else {
      return null;
    }
  }

  @override
  String makeURL(String tags, {bool forceXML = false}) {
    final int cappedPage = max(1, pageNum);
    final String loginStr = booru.userID?.isNotEmpty == true ? '&login=${booru.userID}' : '';
    final String apiKeyStr = booru.apiKey?.isNotEmpty == true ? '&api_key=${booru.apiKey}' : '';

    return '${booru.baseURL}/post.xml?tags=$tags&limit=$limit&page=$cappedPage$loginStr$apiKeyStr';
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/post/show/$id/';
  }

  @override
  String makeTagURL(String input) {
    return '${booru.baseURL}/tag.xml?limit=20&order=count&name=$input*';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final parsedResponse = XmlDocument.parse(response.data);
    return parsedResponse.findAllElements('tag').toList();
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final String tagStr = responseItem.getAttribute('name')?.trim() ?? '';
    if (tagStr.isEmpty) {
      return null;
    }

    // record tag data for future use
    final String rawTagType = responseItem.getAttribute('type')?.toString() ?? '';
    TagType tagType = TagType.none;
    if (rawTagType.isNotEmpty && tagTypeMap.containsKey(rawTagType)) {
      tagType = tagTypeMap[rawTagType] ?? TagType.none;
    }
    addTagsWithType([tagStr], tagType);
    return TagSuggestion(
      tag: tagStr,
      type: tagType,
      count: int.tryParse(responseItem.getAttribute('count') ?? '0') ?? 0,
    );
  }

  /// The site's own search syntax (yande.re cheat sheet, checked 2026-09-17):
  /// order:, rating:, ranges on id/score/width/height/mpixels/ratio/date,
  /// user:, vote:, md5:, source:, parent:. Typed through to post.xml.
  @override
  List<MetaTag> availableMetaTags() => [
    GenericRatingMetaTag(),
    OrderMetaTag(
      values: [
        MetaTagValue(name: 'Newest first (id)', value: 'id_desc'),
        MetaTagValue(name: 'Oldest first (id)', value: 'id'),
        MetaTagValue(name: 'Score', value: 'score'),
        MetaTagValue(name: 'Score (ascending)', value: 'score_asc'),
        MetaTagValue(name: 'Megapixels', value: 'mpixels'),
        MetaTagValue(name: 'Megapixels (ascending)', value: 'mpixels_asc'),
        MetaTagValue(name: 'Landscape first', value: 'landscape'),
        MetaTagValue(name: 'Portrait first', value: 'portrait'),
        MetaTagValue(name: 'Votes', value: 'vote'),
      ],
    ),
    ComparableNumberMetaTag(name: 'ID', keyName: 'id'),
    ComparableNumberMetaTag(name: 'Score', keyName: 'score'),
    ComparableNumberMetaTag(name: 'Width', keyName: 'width'),
    ComparableNumberMetaTag(name: 'Height', keyName: 'height'),
    ComparableNumberMetaTag(name: 'Megapixels', keyName: 'mpixels'),
    StringMetaTag(name: 'Ratio (w:h)', keyName: 'ratio'),
    StringMetaTag(name: 'Date (yyyy-mm-dd, or a..b)', keyName: 'date'),
    UserMetaTag(),
    StringMetaTag(name: 'Voted by (vote:3:name)', keyName: 'vote'),
    StringMetaTag(name: 'MD5', keyName: 'md5'),
    StringMetaTag(name: 'Source contains', keyName: 'source'),
    StringMetaTag(name: 'Parent (id or none)', keyName: 'parent'),
  ];

  // r71: comment.json and note.json, the moebooru API (yande.re, 2026-09-17).
  // Both answer the whole list in one go, so only the first page (the
  // dialog counts from 0) asks.
  @override
  bool get hasCommentsSupport => true;

  @override
  String makeCommentsURL(String postID, int pageNum) {
    // EXAMPLE: https://yande.re/comment.json?post_id=1000000
    return pageNum > 0 ? '' : '${booru.baseURL}/comment.json?post_id=$postID';
  }

  @override
  List parseCommentsList(dynamic response) => BooruHandler.asResponseList(response.data);

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    final Map<String, dynamic> c = Map<String, dynamic>.from(responseItem as Map);
    return CommentItem(
      id: c['id']?.toString(),
      title: c['post_id']?.toString(),
      content: c['body']?.toString(),
      authorID: c['creator_id']?.toString(),
      authorName: c['creator']?.toString(),
      postID: c['post_id']?.toString(),
      createDate: c['created_at']?.toString(), // 2022-07-25T20:37:52.063Z, zone kept for the dialog
      createDateFormat: 'iso',
    );
  }

  @override
  bool get hasNotesSupport => true;

  @override
  String makeNotesURL(String postID) {
    // EXAMPLE: https://yande.re/note.json?post_id=1246878
    return '${booru.baseURL}/note.json?post_id=$postID';
  }

  @override
  List parseNotesList(dynamic response) => BooruHandler.asResponseList(response.data);

  @override
  NoteItem? parseNote(dynamic responseItem, int index) {
    final Map<String, dynamic> n = Map<String, dynamic>.from(responseItem as Map);
    if (n['is_active'] == false) return null;
    return NoteItem(
      id: n['id']?.toString(),
      postID: n['post_id']?.toString(),
      content: n['body']?.toString(),
      posX: int.tryParse(n['x']?.toString() ?? '') ?? 0,
      posY: int.tryParse(n['y']?.toString() ?? '') ?? 0,
      width: int.tryParse(n['width']?.toString() ?? '') ?? 0,
      height: int.tryParse(n['height']?.toString() ?? '') ?? 0,
    );
  }
}
