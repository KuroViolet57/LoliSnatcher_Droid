import 'dart:convert';

import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_utils.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

// ignore: camel_case_types
class e621Handler extends BooruHandler {
  e621Handler(super.booru, super.limit);

  /// Artists, characters, copyrights, species, meta and general tags, one
  /// category at a time from tags.json (see E621TagIndex).
  @override
  late final TagCatalogSource? tagCatalog = BooruTagCatalog.forHandler(this);

  // e621 supports parenthesised OR groups, so multiple OR groups AND
  // together correctly (`( ~a ~b ) ( ~c ~d )`). Verified against the live API.
  @override
  String translateOrSyntax(String tags) => BooruHandler.orSyntaxPrefixTilde(tags, grouping: true);

  @override
  bool get hasSizeData => true;

  @override
  bool get hasTagSuggestions => true;

  /// r44: the choosable options of e621's search cheatsheet
  /// (e621.net/help/cheatsheet) as filters. Each is one choice: e621 ANDs a
  /// repeated metatag, so two ratings would find nothing.
  @override
  DoujinFilterSpec get doujinFilters => const DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'order',
      label: 'Order',
      options: [
        DoujinFilterOption('', 'Newest (site default)'),
        DoujinFilterOption('score', 'Score'),
        DoujinFilterOption('favcount', 'Favorites'),
        DoujinFilterOption('hot', 'Hot'),
        DoujinFilterOption('comment_count', 'Most comments'),
        DoujinFilterOption('comment_bumped', 'Recently commented'),
        DoujinFilterOption('created_asc', 'Oldest first'),
        DoujinFilterOption('updated', 'Recently updated'),
        DoujinFilterOption('duration', 'Longest videos'),
        DoujinFilterOption('mpixels', 'Largest resolution'),
        DoujinFilterOption('filesize', 'Largest files'),
        DoujinFilterOption('tagcount', 'Most tags'),
        DoujinFilterOption('landscape', 'Landscape'),
        DoujinFilterOption('portrait', 'Portrait'),
        DoujinFilterOption('random', 'Random'),
      ],
    ),
    DoujinFilterGroup(
      key: 'rating',
      label: 'Rating',
      options: [DoujinFilterOption('', 'All'), DoujinFilterOption('s', 'Safe'), DoujinFilterOption('q', 'Questionable'), DoujinFilterOption('e', 'Explicit')],
    ),
    DoujinFilterGroup(
      key: 'type',
      label: 'File type',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('webm', 'WebM video'),
        DoujinFilterOption('mp4', 'MP4 video'),
        DoujinFilterOption('gif', 'GIF'),
        DoujinFilterOption('png', 'PNG'),
        DoujinFilterOption('jpg', 'JPG'),
        DoujinFilterOption('webp', 'WebP'),
        DoujinFilterOption('swf', 'Flash'),
      ],
    ),
    DoujinFilterGroup(
      key: 'date',
      label: 'Posted within',
      options: [
        DoujinFilterOption('', 'Any time'),
        DoujinFilterOption('day', 'A day'),
        DoujinFilterOption('week', 'A week'),
        DoujinFilterOption('month', 'A month'),
        DoujinFilterOption('year', 'A year'),
        DoujinFilterOption('decade', 'A decade'),
      ],
    ),
    DoujinFilterGroup(
      key: 'score',
      label: 'Score',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10+'),
        DoujinFilterOption('>=50', '50+'),
        DoujinFilterOption('>=100', '100+'),
        DoujinFilterOption('>=500', '500+'),
        DoujinFilterOption('>=1000', '1000+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'favcount',
      label: 'Favorites',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10+'),
        DoujinFilterOption('>=50', '50+'),
        DoujinFilterOption('>=100', '100+'),
        DoujinFilterOption('>=500', '500+'),
        DoujinFilterOption('>=1000', '1000+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'duration',
      label: 'Video length',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10 s+'),
        DoujinFilterOption('>=30', '30 s+'),
        DoujinFilterOption('>=60', '1 min+'),
        DoujinFilterOption('>=180', '3 min+'),
        DoujinFilterOption('>=600', '10 min+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'status',
      label: 'Status',
      options: [
        DoujinFilterOption('', 'Active (site default)'),
        DoujinFilterOption('pending', 'Pending'),
        DoujinFilterOption('flagged', 'Flagged'),
        DoujinFilterOption('modqueue', 'Pending or flagged'),
        DoujinFilterOption('deleted', 'Deleted'),
        DoujinFilterOption('any', 'Everything, deleted too'),
      ],
    ),
    DoujinFilterGroup(
      key: 'ischild',
      label: 'Child post',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'Is a child'), DoujinFilterOption('false', 'Not a child')],
    ),
    DoujinFilterGroup(
      key: 'isparent',
      label: 'Parent post',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'Has children'), DoujinFilterOption('false', 'No children')],
    ),
    DoujinFilterGroup(
      key: 'inpool',
      label: 'Pool',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'In a pool'), DoujinFilterOption('false', 'Not in a pool')],
    ),
    DoujinFilterGroup(
      key: 'hassource',
      label: 'Source',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'Has a source'), DoujinFilterOption('false', 'No source')],
    ),
    DoujinFilterGroup(
      key: 'hasdescription',
      label: 'Description',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'Has a description'), DoujinFilterOption('false', 'No description')],
    ),
    DoujinFilterGroup(
      key: 'artverified',
      label: 'Artist uploads',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('true', 'By a verified artist'), DoujinFilterOption('false', 'Not by the artist')],
    ),
  ]);

  /// r44: the cheatsheet's text and number metatags, as builders in the
  /// search window (a name, a value or a range like `>=100`, `25..50`).
  @override
  List<MetaTag> availableMetaTags() => [
    UserMetaTag(),
    StringMetaTag(name: 'Favorited by', keyName: 'fav'),
    StringMetaTag(name: 'Commented by', keyName: 'commenter'),
    StringMetaTag(name: 'Approved by', keyName: 'approver'),
    StringMetaTag(name: 'Pool (id or name)', keyName: 'pool'),
    StringMetaTag(name: 'Set (id or short name)', keyName: 'set'),
    StringMetaTag(name: 'Source contains', keyName: 'source'),
    StringMetaTag(name: 'Description contains', keyName: 'description'),
    StringMetaTag(name: 'Note contains', keyName: 'note'),
    StringMetaTag(name: 'Parent post', keyName: 'parent'),
    StringMetaTag(name: 'MD5', keyName: 'md5'),
    ComparableNumberMetaTag(name: 'ID', keyName: 'id'),
    ComparableNumberMetaTag(name: 'Score', keyName: 'score'),
    ComparableNumberMetaTag(name: 'Favorites', keyName: 'favcount'),
    ComparableNumberMetaTag(name: 'Comments', keyName: 'comment_count'),
    ComparableNumberMetaTag(name: 'Tag count', keyName: 'tagcount'),
    ComparableNumberMetaTag(name: 'Contributor tags', keyName: 'conttags'),
    ComparableNumberMetaTag(name: 'Width', keyName: 'width'),
    ComparableNumberMetaTag(name: 'Height', keyName: 'height'),
    ComparableNumberMetaTag(name: 'Megapixels', keyName: 'mpixels'),
    ComparableNumberMetaTag(name: 'Video length (seconds)', keyName: 'duration'),
    StringMetaTag(name: 'Random seed', keyName: 'randseed'),
  ];

  @override
  Map<String, TagType> get tagTypeMap => {
    '7': TagType.meta,
    '3': TagType.copyright,
    '4': TagType.character,
    '1': TagType.artist,
    '5': TagType.species,
    '2': TagType.contributor,
    '8': TagType.lore,
    '6': TagType.none,
    '0': TagType.none,
  };

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return (parsedResponse['posts'] ?? []) as List;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final dynamic current = responseItem as Map<String, dynamic>;

    if (current['file']['md5'] != null) {
      String fileURL = '';
      String sampleURL = '';
      String thumbURL = '';
      if (current['file']['url'] == null) {
        final String md5FirstSplit = current['file']['md5'].toString().substring(0, 2);
        final String md5SecondSplit = current['file']['md5'].toString().substring(2, 4);
        fileURL = "https://static1.e621.net/data/$md5FirstSplit/$md5SecondSplit/${current['file']['md5']}.${current['file']['ext']}";
        sampleURL = fileURL.replaceFirst('data', 'data/sample').replaceFirst(current['file']['ext'], 'jpg');
        thumbURL = sampleURL.replaceFirst('data/sample', 'data/preview');
        if (current['file']['size'] <= 2694254) {
          sampleURL = fileURL;
        }
      } else {
        fileURL = current['file']['url'];
        sampleURL = current['sample']?['url'] ?? current['preview']['url'];
        thumbURL = current['preview']['url'];
      }

      final List<String> characterTags = (current['tags']?['character'] ?? []).cast<String>();
      final List<String> copyrightTags = (current['tags']?['copyright'] ?? []).cast<String>();
      final List<String> franchiseTags = (current['tags']?['franchise'] ?? []).cast<String>();
      final List<String> artistTags = (current['tags']?['artist'] ?? []).cast<String>();
      final List<String> directorTags = (current['tags']?['director'] ?? []).cast<String>();
      final List<String> metaTags = (current['tags']?['meta'] ?? []).cast<String>();
      final List<String> generalTags = (current['tags']?['general'] ?? []).cast<String>();
      final List<String> speciesTags = (current['tags']?['species'] ?? []).cast<String>();
      // r44: the three groups the app used to drop.
      final List<String> contributorTags = (current['tags']?['contributor'] ?? []).cast<String>();
      final List<String> loreTags = (current['tags']?['lore'] ?? []).cast<String>();
      final List<String> invalidTags = (current['tags']?['invalid'] ?? []).cast<String>();

      addTagsWithType([...characterTags], TagType.character);
      addTagsWithType([...copyrightTags], TagType.copyright);
      addTagsWithType([...franchiseTags], TagType.copyright);
      addTagsWithType([...artistTags], TagType.artist);
      addTagsWithType([...directorTags], TagType.artist);
      addTagsWithType([...metaTags], TagType.meta);
      addTagsWithType([...generalTags], TagType.none);
      addTagsWithType([...speciesTags], TagType.species);
      addTagsWithType([...contributorTags], TagType.contributor);
      addTagsWithType([...loreTags], TagType.lore);
      addTagsWithType([...invalidTags], TagType.none);

      final String? dateStr = safeIsoDateMinusTimezone(current['created_at']);

      final BooruItem item = BooruItem(
        fileURL: fileURL,
        sampleURL: sampleURL,
        thumbnailURL: thumbURL,
        tagsList: [
          ...characterTags.map(Tag.new),
          ...copyrightTags.map(Tag.new),
          ...franchiseTags.map(Tag.new),
          ...artistTags.map(Tag.new),
          ...directorTags.map(Tag.new),
          ...contributorTags.map(Tag.new),
          ...metaTags.map(Tag.new),
          ...generalTags.map(Tag.new),
          ...speciesTags.map(Tag.new),
          ...loreTags.map(Tag.new),
          ...invalidTags.map(Tag.new),
        ],
        postURL: makePostURL(current['id'].toString()),
        fileExt: current['file']['ext'],
        fileSize: current['file']['size'],
        fileWidth: current['file']['width']?.toDouble(),
        fileHeight: current['file']['height']?.toDouble(),
        sampleWidth: current['sample']?['width']?.toDouble() ?? current['preview']['width']?.toDouble(),
        sampleHeight: current['sample']?['height']?.toDouble() ?? current['preview']['height']?.toDouble(),
        previewWidth: current['preview']['width']?.toDouble(),
        previewHeight: current['preview']['height']?.toDouble(),
        hasNotes: current['has_notes'],
        serverId: current['id']?.toString(),
        rating: current['rating'],
        score: current['score']['total']?.toString(),
        sources: List<String>.from(current['sources'] ?? []),
        md5String: current['file']['md5'],
        uploaderId: current['uploader_id']?.toString(),
        postDate: dateStr, // 2021-06-13t02:09:45.138-04:00
        postDateFormat: 'iso',
      );

      return item;
    } else {
      return null;
    }
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/posts/$id?';
  }

  @override
  String makeURL(String tags) {
    return '${booru.baseURL}/posts.json?tags=$tags&limit=$limit&page=$pageNum';
  }

  @override
  String makeTagURL(String input) {
    return '${booru.baseURL}/tags.json?search[name_matches]=$input*&limit=20&search[order]=count';
  }

  @override
  Map<String, String> getHeaders() {
    final String? userName = booru.userID?.isNotEmpty == true ? booru.userID : null;
    final String? apiKey = booru.apiKey?.isNotEmpty == true ? booru.apiKey : null;

    return {
      'Accept': 'text/html,application/xml,application/json',
      'User-Agent': Tools.browserUserAgent,
      if (userName != null && apiKey != null) 'Authorization': "Basic ${base64.encode(utf8.encode("$userName:$apiKey"))}",
    };
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final List parsedResponse = response.data;
    return parsedResponse;
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final String tagStr = responseItem['name'] ?? '';
    if (tagStr.isEmpty) {
      return null;
    }

    // record tag data for future use
    final String rawTagType = responseItem['category']?.toString() ?? '';
    TagType tagType = TagType.none;
    if (rawTagType.isNotEmpty && tagTypeMap.containsKey(rawTagType)) {
      tagType = tagTypeMap[rawTagType] ?? TagType.none;
    }
    addTagsWithType([tagStr], tagType);
    return TagSuggestion(
      tag: tagStr,
      type: tagType,
      count: responseItem['post_count'] ?? 0,
    );
  }
}
