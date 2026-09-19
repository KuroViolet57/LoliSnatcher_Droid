import 'dart:convert';

import 'package:lolisnatcher/src/boorus/booru_site_filters.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class SzurubooruHandler extends BooruHandler {
  SzurubooruHandler(super.booru, super.limit);

  @override
  bool get hasTagSuggestions => true;

  @override
  String validateTags(String tags) {
    if (tags == '' || tags == ' ') {
      return '*';
    } else {
      return super.validateTags(tags);
    }
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return (parsedResponse['results'] ?? []) as List;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem as Map<String, dynamic>;

    final List<String> tags = [];
    for (int x = 0; x < current['tags'].length; x++) {
      String currentTags = current['tags'][x]['names'].toString().replaceAll(':', r'\:');
      currentTags = currentTags.substring(1, currentTags.length - 1);
      if (currentTags.contains(',')) {
        tags.addAll(currentTags.split(', '));
      } else {
        tags.add(currentTags);
      }
    }
    if (current['contentUrl'] != null) {
      final BooruItem item = BooruItem(
        fileURL: "${booru.baseURL}/${current['contentUrl']}",
        fileWidth: current['canvasWidth'].toDouble(),
        fileHeight: current['canvasHeight'].toDouble(),
        sampleURL: "${booru.baseURL}/${current['contentUrl']}",
        thumbnailURL: "${booru.baseURL}/${current['thumbnailUrl']}",
        tagsList: tags.map(Tag.new).toList(),
        hasComments: (int.tryParse(current['commentCount']?.toString() ?? '') ?? 0) > 0,
        serverId: current['id'].toString(),
        score: current['score'].toString(),
        postURL: makePostURL(current['id'].toString()),
        rating: current['safety'],
        postDate: (current['creationTime'].replaceAll('Z', '') + '.0000').substring(0, 22),
        postDateFormat: 'iso',
      );

      return item;
    } else {
      return null;
    }
  }

  @override
  Map<String, String> getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': Tools.browserUserAgent,
      if (booru.apiKey?.isNotEmpty == true)
        'Authorization': "Token ${base64Encode(utf8.encode("${booru.userID}:${booru.apiKey}"))}",
    };
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/post/$id';
  }

  /// szurubooru reverses a sort with a leading minus (`-sort:score`); the
  /// app's order:asc / order:desc terms become that sign (r71). The input
  /// may arrive URL-encoded (validateTags); it goes back the same way.
  static String withDirection(String tags) {
    final bool encoded = tags.contains('%');
    final String raw = encoded ? Uri.decodeComponent(tags) : tags;
    final List<String> terms = raw.split(' ').where((t) => t.isNotEmpty).toList();
    final String order = terms.firstWhere((t) => t.toLowerCase().startsWith('order:'), orElse: () => '').toLowerCase();
    if (order.isEmpty) return tags;
    final bool ascending = order == 'order:asc';
    final List<String> out = [];
    for (final String t in terms) {
      final String lower = t.toLowerCase();
      if (lower.startsWith('order:')) continue;
      if (lower.startsWith('sort:')) {
        out.add(ascending ? '-$t' : t);
      } else if (lower.startsWith('-sort:')) {
        out.add(ascending ? t : t.substring(1));
      } else {
        out.add(t);
      }
    }
    final String result = out.join(' ');
    return encoded ? Uri.encodeComponent(result) : result;
  }

  @override
  String makeURL(String tags) {
    return '${booru.baseURL}/api/posts/?offset=${pageNum * limit}&limit=$limit&query=${withDirection(tags)}';
  }

  /// szurubooru's query language (its API docs): sort fields, safety, type,
  /// special, flags, and ranges written `score:100..`, `score:..100`,
  /// `score:10..20`.
  @override
  List<MetaTag> availableMetaTags() => [
    SortMetaTag(
      values: [
        MetaTagValue(name: 'Date posted', value: 'date'),
        MetaTagValue(name: 'Score', value: 'score'),
        MetaTagValue(name: 'Random', value: 'random'),
        MetaTagValue(name: 'ID', value: 'id'),
        MetaTagValue(name: 'Favorites', value: 'fav-count'),
        MetaTagValue(name: 'Comments', value: 'comment-count'),
        MetaTagValue(name: 'Tag count', value: 'tag-count'),
        MetaTagValue(name: 'Notes', value: 'note-count'),
        MetaTagValue(name: 'Relations', value: 'relation-count'),
        MetaTagValue(name: 'Features', value: 'feature-count'),
        MetaTagValue(name: 'File size', value: 'file-size'),
        MetaTagValue(name: 'Width', value: 'image-width'),
        MetaTagValue(name: 'Height', value: 'image-height'),
        MetaTagValue(name: 'Area', value: 'image-area'),
        MetaTagValue(name: 'Aspect ratio', value: 'image-aspect-ratio'),
        MetaTagValue(name: 'Last edit', value: 'edit-date'),
        MetaTagValue(name: 'Last comment', value: 'comment-date'),
        MetaTagValue(name: 'Last favorite', value: 'fav-date'),
        MetaTagValue(name: 'Last feature', value: 'feature-date'),
      ],
    ),
    OrderMetaTag(values: [MetaTagValue(name: 'Descending', value: 'desc'), MetaTagValue(name: 'Ascending', value: 'asc')]),
    MetaTagWithValues(
      name: 'Safety',
      keyName: 'safety',
      values: [
        MetaTagValue(name: 'Safe', value: 'safe'),
        MetaTagValue(name: 'Sketchy', value: 'sketchy'),
        MetaTagValue(name: 'Unsafe', value: 'unsafe'),
      ],
    ),
    MetaTagWithValues(
      name: 'Type',
      keyName: 'type',
      values: [
        MetaTagValue(name: 'Image', value: 'image'),
        MetaTagValue(name: 'Animation', value: 'animation'),
        MetaTagValue(name: 'Video', value: 'video'),
        MetaTagValue(name: 'Flash', value: 'flash'),
      ],
    ),
    MetaTagWithValues(
      name: 'Special (your account)',
      keyName: 'special',
      values: [
        MetaTagValue(name: 'Liked', value: 'liked'),
        MetaTagValue(name: 'Disliked', value: 'disliked'),
        MetaTagValue(name: 'Favorited', value: 'fav'),
        MetaTagValue(name: 'Tumbleweed (no votes, favs, comments)', value: 'tumbleweed'),
      ],
    ),
    MetaTagWithValues(
      name: 'Flag',
      keyName: 'flag',
      values: [MetaTagValue(name: 'Has sound', value: 'sound'), MetaTagValue(name: 'Loops', value: 'loop')],
    ),
    StringMetaTag(name: 'Score (n, n.., ..n, a..b)', keyName: 'score'),
    StringMetaTag(name: 'Tag count', keyName: 'tag-count'),
    StringMetaTag(name: 'Uploader', keyName: 'uploader'),
    StringMetaTag(name: 'ID', keyName: 'id'),
    StringMetaTag(name: 'Date (yyyy-mm-dd, a..b, today, yesterday)', keyName: 'date'),
    StringMetaTag(name: 'Pool', keyName: 'pool'),
    StringMetaTag(name: 'Source contains', keyName: 'source'),
    StringMetaTag(name: 'Content checksum', keyName: 'content-checksum'),
  ];

  /// The chips from the lists above, with a real Direction group (the
  /// generic card drops "asc" as a sort twin).
  @override
  DoujinFilterSpec? get doujinFilters {
    final DoujinFilterSpec? base = BooruSiteFilters.fromMetaTags(availableMetaTags());
    if (base == null) return null;
    return DoujinFilterSpec([
      for (final DoujinFilterGroup g in base.groups)
        if (g.key != 'order') g,
      const DoujinFilterGroup(
        key: 'order',
        label: 'Direction',
        defaultValue: '',
        options: [DoujinFilterOption('', 'Descending (default)'), DoujinFilterOption('asc', 'Ascending')],
      ),
    ]);
  }

  // r71: comments ride on the post resource (szurubooru API: /api/post/<id>,
  // comments[] with user, text, creationTime, score) - one answer, no pages.
  @override
  bool get hasCommentsSupport => true;

  @override
  String makeCommentsURL(String postID, int pageNum) => pageNum > 0 ? '' : '${booru.baseURL}/api/post/$postID';

  @override
  List parseCommentsList(dynamic response) {
    final dynamic data = response.data;
    if (data is Map && data['comments'] is List) return data['comments'] as List;
    return const [];
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    final Map<String, dynamic> c = Map<String, dynamic>.from(responseItem as Map);
    final Map<String, dynamic> user = c['user'] is Map ? Map<String, dynamic>.from(c['user'] as Map) : const {};
    final String avatar = user['avatarUrl']?.toString() ?? '';
    return CommentItem(
      id: c['id']?.toString(),
      title: c['postId']?.toString(),
      content: c['text']?.toString(),
      authorName: user['name']?.toString(),
      avatarUrl: avatar.isEmpty ? null : (avatar.startsWith('http') ? avatar : '${booru.baseURL}/$avatar'),
      score: int.tryParse(c['score']?.toString() ?? ''),
      postID: c['postId']?.toString(),
      createDate: c['creationTime']?.toString(), // 2024-01-02T03:04:05.000000Z, zone kept for the dialog
      createDateFormat: 'iso',
    );
  }

  @override
  String makeTagURL(String input) {
    return '${booru.baseURL}/api/tags/?offset=0&limit=20&query=$input*';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return parsedResponse['results'] ?? [];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final String? tag = responseItem['names']?[0]?.toString().replaceAll(':', r'\:');
    return tag != null ? TagSuggestion(tag: tag) : null;
  }
}
