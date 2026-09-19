import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_utils.dart';

// TODO autoreplace both ways all that special symbol crap (see tag suggestions) to normal format for user
// TODO fix file names like we do with shimmie, probably should move file name encode/decode process to boorus themselves instead of image writer

class BooruOnRailsHandler extends BooruHandler {
  BooruOnRailsHandler(super.booru, super.limit);

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/$id';
  }

  @override
  String validateTags(String tags) {
    if (tags == '' || tags == ' ') {
      return '*';
    } else {
      return tags;
    }
  }

  @override
  String translateOrSyntax(String tags) {
    if (!tags.contains('|')) return tags;
    return tags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((token) {
          if (!token.contains('|')) return token;
          final parts = token.split('|').where((p) => p.isNotEmpty).toList();
          if (parts.isEmpty) return '';
          if (parts.length == 1) return parts.first;
          return '(${parts.join(' || ')})';
        })
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return (parsedResponse['posts'] as List?) ?? [];
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final List<String> currentTags = [];
    for (int x = 0; x < responseItem['tags'].length; x++) {
      currentTags.add(responseItem['tags'][x].toString().replaceAll(' ', '_'));
    }
    if (responseItem['representations']['full'] != null &&
        responseItem['representations']['medium'] != null &&
        responseItem['representations']['large'] != null) {
      final String id = responseItem['id']?.toString() ?? '';
      String fileURL = responseItem['representations']['full'] ?? responseItem['representations']['large'];
      String sampleURL = responseItem['representations']['large'];
      String thumbURL = responseItem['representations']['medium'];
      if (responseItem['mime_type'].toString().contains('video')) {
        final String tmpURL = "${sampleURL.substring(0, sampleURL.lastIndexOf("/") + 1)}thumb.gif";
        sampleURL = tmpURL;
        thumbURL = tmpURL;
      }
      if (!fileURL.contains('http')) {
        fileURL = '${booru.baseURL!}$fileURL';
        sampleURL = '${booru.baseURL!}$sampleURL';
        thumbURL = '${booru.baseURL!}$thumbURL';
      }
      // TODO caching broken because names are the same for every image
      fileURL = '$fileURL?$id';
      sampleURL = '$sampleURL?$id';
      thumbURL = '$thumbURL?$id';

      final BooruItem item = BooruItem(
        fileURL: fileURL,
        fileWidth: responseItem['width']?.toDouble(),
        fileHeight: responseItem['height']?.toDouble(),
        fileExt: responseItem['format']?.toString(),
        sampleURL: sampleURL,
        thumbnailURL: thumbURL,
        tagsList: currentTags.map(Tag.new).toList(),
        postURL: makePostURL(id),
        hasComments: (int.tryParse(responseItem['comment_count']?.toString() ?? '') ?? 0) > 0,
        serverId: id,
        score: responseItem['score']?.toString(),
        sources: [responseItem['source_url']?.toString() ?? ''],
        rating: currentTags[0][0],
        postDate: responseItem['created_at'], // 2021-06-13T02:09:45.138-04:00
        postDateFormat: 'iso',
        fileNameExtras: '${booru.name}_${id}_',
      );
      return item;
    } else {
      return null;
    }
  }

  String formatTagsWithUnderscores(String tags) => formatTagsWithUnderscoresPhilomena(tags);

  @override
  String makeURL(String tags) {
    // r71: the sort field and direction (sf/sd; checked live 2026-09-17:
    // sf=score and sf=random reorder /api/v3/search/posts) come as sf:/sd:
    // terms from the Filters card; range terms (score.gte:100) are ordinary
    // q terms, joined by commas like the rest.
    String first(String key) {
      final List<String> v = DoujinFilters.selected(tags, key);
      return v.isEmpty ? '' : v.first;
    }

    final String sf = first('sf');
    final String sd = first('sd');
    final String words = DoujinFilters.strip(DoujinFilters.strip(tags, 'sf'), 'sd').trim();
    final String formattedTags = formatTagsWithUnderscores(words.isEmpty ? '*' : words).replaceAll(' ', ',');
    final String limitStr = limit.toString();
    final String pageStr = pageNum.toString();
    final String apiKeyStr = booru.apiKey?.isNotEmpty == true ? 'key=${booru.apiKey}&' : '';
    final String sort = '${sf.isEmpty ? '' : '&sf=$sf'}${sd.isEmpty ? '' : '&sd=$sd'}';

    // EXAMPLE: https://twibooru.org/api/v3/search/posts?q=*&perpage=10&page=1
    return '${booru.baseURL}/api/v3/search/posts?${apiKeyStr}q=$formattedTags&perpage=$limitStr&page=$pageStr$sort';
  }

  /// The site's sort fields and range terms (twibooru, 2026-09-17).
  @override
  DoujinFilterSpec get doujinFilters => const DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'sf',
      label: 'Sort',
      defaultValue: '',
      options: [
        DoujinFilterOption('', 'Newest (site default)'),
        DoujinFilterOption('score', 'Score'),
        DoujinFilterOption('faves', 'Favorites'),
        DoujinFilterOption('upvotes', 'Upvotes'),
        DoujinFilterOption('comment_count', 'Comments'),
        DoujinFilterOption('tag_count', 'Tag count'),
        DoujinFilterOption('width', 'Width'),
        DoujinFilterOption('height', 'Height'),
        DoujinFilterOption('random', 'Random'),
      ],
    ),
    DoujinFilterGroup(
      key: 'sd',
      label: 'Direction',
      defaultValue: '',
      options: [DoujinFilterOption('', 'Descending (default)'), DoujinFilterOption('asc', 'Ascending')],
    ),
    // The site's scale (2026-09-17): the top scores are around 200 and
    // score.gte:100 matches 83 posts, so the steps stop at 100.
    DoujinFilterGroup(
      key: 'score.gte',
      label: 'Score',
      defaultValue: '',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('10', '10+'),
        DoujinFilterOption('25', '25+'),
        DoujinFilterOption('50', '50+'),
        DoujinFilterOption('100', '100+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'faves.gte',
      label: 'Favorites',
      defaultValue: '',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('10', '10+'),
        DoujinFilterOption('25', '25+'),
        DoujinFilterOption('50', '50+'),
        DoujinFilterOption('100', '100+'),
      ],
    ),
  ]);

  /// The fields the site's search understands, for the query editor.
  @override
  List<MetaTag> availableMetaTags() => [
    StringMetaTag(name: 'Uploader', keyName: 'uploader'),
    StringMetaTag(name: 'ID', keyName: 'id'),
    StringMetaTag(name: 'Score at least', keyName: 'score.gte'),
    StringMetaTag(name: 'Favorites at least', keyName: 'faves.gte'),
    StringMetaTag(name: 'Width at least', keyName: 'width.gte'),
    StringMetaTag(name: 'Height at least', keyName: 'height.gte'),
    StringMetaTag(name: 'Source URL contains', keyName: 'source_url'),
    StringMetaTag(name: 'Description contains', keyName: 'description'),
    StringMetaTag(name: 'SHA-512 hash', keyName: 'sha512_hash'),
  ];

  // r71: /api/v3/posts/<id>/comments - the whole thread in one answer,
  // anonymous rows (checked live 2026-09-17).
  @override
  bool get hasCommentsSupport => true;

  @override
  String makeCommentsURL(String postID, int pageNum) {
    // EXAMPLE: https://twibooru.org/api/v3/posts/3408660/comments
    return pageNum > 0 ? '' : '${booru.baseURL}/api/v3/posts/$postID/comments';
  }

  @override
  List parseCommentsList(dynamic response) {
    final dynamic data = response.data;
    if (data is Map && data['comments'] is List) return data['comments'] as List;
    return const [];
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    final Map<String, dynamic> c = Map<String, dynamic>.from(responseItem as Map);
    if (c['hidden_from_users'] == true) return null;
    return CommentItem(
      id: c['id']?.toString(),
      content: c['body']?.toString(),
      authorName: c['author']?.toString() ?? 'Anonymous',
      createDate: c['created_at']?.toString(), // 2024-12-13T06:37:44.421Z, zone kept for the dialog
      createDateFormat: 'iso',
    );
  }

  @override
  String makeTagURL(String input) {
    // EXAMPLE: https://twibooru.org/api/v3/search/tags?q=*rai*
    return '${booru.baseURL}/api/v3/search/tags?q=*${formatTagsWithUnderscores(input)}*';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final List<dynamic> parsedResponse = response.data['tags'];
    return parsedResponse;
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final List tagStringReplacements = [
      ['-colon-', ':'],
      ['-dash-', '-'],
      ['-fwslash-', '/'],
      ['-bwslash-', r'\'],
      ['-dot-', '.'],
      ['-plus-', '+'],
    ];

    String tag = responseItem['slug'].toString();
    for (int x = 0; x < tagStringReplacements.length; x++) {
      tag = tag.replaceAll(tagStringReplacements[x][0], tagStringReplacements[x][1]);
    }

    if (tag.contains('_')) {
      tag = '"$tag"';
    }

    tag = tag.replaceAll('+', '_');

    return TagSuggestion(tag: tag);
  }
}
