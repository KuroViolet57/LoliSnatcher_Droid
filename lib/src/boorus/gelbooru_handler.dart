import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:xml/xml.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/note_item.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_utils.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/post_files_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class GelbooruHandler extends BooruHandler {
  GelbooruHandler(super.booru, super.limit);

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

  static String get credentialsWarningText =>
      '<p><b>You may need to add your User ID and API key. You can find them on <a href="https://gelbooru.com/index.php?page=account&s=options">Gelbooru settings page</a> under "API Access Credentials". Note: Anonymous access is NOT allowed.</b></p>';

  @override
  Map<String, String> getHeaders() {
    return {
      ...super.getHeaders(),
      'Cookie': 'fringeBenefits=yup;', // unlocks restricted content (but it's probably not necessary)
    };
  }

  @override
  String validateTags(String tags) {
    if (tags.toLowerCase().contains('rating:safe')) {
      tags = tags.toLowerCase().replaceAll('rating:safe', 'rating:general');
    }
    return super.validateTags(tags);
  }

  // Gelbooru's OR syntax is `{tag1 ~ tag2 ~ tag3}` (curly braces, infix
  // tilde), per its cheatsheet wiki page. Prefix-tilde (Danbooru style)
  // silently returns no results here.
  @override
  String translateOrSyntax(String tags) => BooruHandler.orSyntaxBraced(tags, '{', '}');

  @override
  List parseListFromResponse(dynamic response) {
    dynamic parsedResponse;
    try {
      parsedResponse = response.data;
    } catch (e) {
      // gelbooru returns xml response if request was denied for some reason
      // i.e. user hit a rate limit because he didn't include api key
      parsedResponse = XmlDocument.parse(response.data);
      final String? errorMessage = (parsedResponse as XmlDocument)
          .getElement('response')
          ?.getAttribute('reason')
          ?.toString();
      if (errorMessage != null) {
        throw Exception(errorMessage);
      }
    }

    try {
      parseSearchCount(parsedResponse);
    } catch (e, s) {
      Logger.Inst().log(
        'Error parsing search count: $e',
        className,
        'parseListFromResponse::parseSearchCount',
        LogTypes.exception,
        s: s,
      );
    }

    return (parsedResponse['post'] ?? []) as List;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem as Map<String, dynamic>;

    if (current['file_url'] != null) {
      // Fix for bleachbooru
      String fileURL = '', sampleURL = '', previewURL = '';
      fileURL += current['file_url']!.toString();
      // sample url is optional, on gelbooru there is sample == 0/1 to tell if it exists
      sampleURL += current['sample_url']?.toString() ?? current['file_url']!.toString();
      previewURL += current['preview_url']!.toString();
      if (!fileURL.contains('http')) {
        fileURL = booru.baseURL! + fileURL;
        sampleURL = booru.baseURL! + sampleURL;
        previewURL = booru.baseURL! + previewURL;
      }

      final BooruItem item = BooruItem(
        fileURL: fileURL,
        sampleURL: sampleURL,
        thumbnailURL: previewURL,
        // parseFragment to parse html elements (i.e. &amp; => &)
        tagsList: splitTagsClean(parseFragment(current['tags']).text).map(Tag.new).toList(),
        postURL: makePostURL(current['id']!.toString()),
        fileWidth: double.tryParse(current['width']?.toString() ?? ''),
        fileHeight: double.tryParse(current['height']?.toString() ?? ''),
        sampleWidth: double.tryParse(current['sample_width']?.toString() ?? ''),
        sampleHeight: double.tryParse(current['sample_height']?.toString() ?? ''),
        previewWidth: double.tryParse(current['preview_width']?.toString() ?? ''),
        previewHeight: double.tryParse(current['preview_height']?.toString() ?? ''),
        hasNotes: current['has_notes']?.toString() == 'true',
        hasComments: current['has_comments']?.toString() == 'true',
        serverId: current['id']?.toString(),
        rating: current['rating']?.toString(),
        score: current['score']?.toString(),
        sources: (current['source'] != null && current['source'] is String) ? [current['source']] : null,
        md5String: current['md5']?.toString(),
        uploaderName: current['owner'],
        postDate: current['created_at']?.toString(), // Fri Jun 18 02:13:45 -0500 2021
        postDateFormat: 'EEE MMM dd HH:mm:ss  yyyy', // when timezone support added: "EEE MMM dd HH:mm:ss Z yyyy",
      );

      return item;
    }
    return null;
  }

  @override
  String makePostURL(String id) {
    // EXAMPLE: https://gelbooru.com/index.php?page=post&s=view&id=7296350
    return '${booru.baseURL}/index.php?page=post&s=view&id=$id';
  }

  String buildApiStr() {
    final String apiKeyStr = booru.apiKey?.isNotEmpty == true
        ? (booru.apiKey?.contains('api_key') == true ? booru.apiKey! : '&api_key=${booru.apiKey}')
        : '';
    final String userIdStr = booru.userID?.isNotEmpty == true
        ? (apiKeyStr.contains('user_id') ? '' : '&user_id=${booru.userID}')
        : '';

    return '$apiKeyStr$userIdStr';
  }

  @override
  String makeURL(String tags) {
    final int cappedPage = max(0, pageNum);

    // Hybrid fetch: the documented API is the default browse path (it returns
    // several times more items per request), but some sites can't serve every
    // query through it — e.g. bakemono's dapi silently ignores sort and source
    // filters while its HTML listing honours both. The profile decides; when
    // it hands back a URL we parse that page instead (see parseResponse).
    if (!_listingDisabled) {
      final String? listing = siteProfile?.listingUrl(booru, tags, cappedPage, limit);
      if (listing != null) {
        _listingTags = tags;
        _usingListing = true;
        return listing;
      }
    }
    _usingListing = false;
    _lastApiTags = tags;

    // EXAMPLE: https://gelbooru.com/index.php?page=dapi&s=post&q=index&tags=rating:general%20order:score&limit=20&pid=0&json=1
    return _apiUrl(tags, cappedPage);
  }

  String _apiUrl(String tags, int page) =>
      "${booru.baseURL}/index.php?page=dapi&s=post&q=index&tags=${tags.replaceAll(" ", "+")}&limit=$limit&pid=$page&json=1${buildApiStr()}";

  // Whether the CURRENT request went to the site's HTML listing.
  bool _usingListing = false;
  // Set when scraping breaks (markup shifted): stop using the listing for the
  // rest of this handler's life and stay on the documented API.
  bool _listingDisabled = false;
  String _listingTags = '';
  String _lastApiTags = '';

  @override
  FutureOr<List<BooruItem>> parseResponse(dynamic response) async {
    if (!_usingListing) {
      final List<BooruItem> items = await super.parseResponse(response);
      // Backfill anything the API can't tell us (file counts for gallery
      // posts) in the background — never block the page on it.
      if (siteProfile != null) {
        unawaited(PostFilesHandler.instance.enrichCounts(items, booru, _lastApiTags));
      }
      return items;
    }

    final SiteProfile? profile = siteProfile;
    final List<BooruItem>? scraped = profile?.parseListing(response.data?.toString() ?? '', booru);
    if (scraped != null) return scraped;

    // Fail soft: never show an empty grid because a site changed its markup —
    // log it, drop back to the API permanently, and serve this page from there.
    Logger.Inst().log(
      'listing scrape failed for ${booru.name} (${profile?.id}); falling back to the API',
      className,
      'parseResponse',
      LogTypes.booruHandlerParseFailed,
    );
    _listingDisabled = true;
    _usingListing = false;
    try {
      final apiResponse = await DioNetwork.get(
        _apiUrl(_listingTags, max(0, pageNum)),
        headers: getHeaders(),
      );
      return await super.parseResponse(apiResponse);
    } catch (e, st) {
      Logger.Inst().log(
        'API fallback after listing failure also failed: $e',
        className,
        'parseResponse',
        LogTypes.exception,
        s: st,
      );
      return [];
    }
  }

  // ----------------- Tag suggestions and tag handler stuff

  Map<String, TagType> get tagSuggestionsTypeMap => {
    'metadata': TagType.meta,
    'copyright': TagType.copyright,
    'character': TagType.character,
    'artist': TagType.artist,
    'tag': TagType.none,
  };

  @override
  String makeTagURL(String input) {
    // Gelbooru-compatible sites don't all implement autocomplete2 — bakemono
    // ignores the unknown page= and answers with the post index instead, so
    // the suggestion parser silently received posts. Sites that differ say so
    // through their profile.
    final String? profileUrl = siteProfile?.tagSuggestionsUrl(booru, input);
    if (profileUrl != null) return profileUrl;

    // EXAMPLE https://gelbooru.com/index.php?page=dapi&s=tag&q=index&name_pattern=nagat%25&limit=20&json=1
    return '${booru.baseURL}/index.php?page=autocomplete2&term=$input&type=tag_query&limit=20${buildApiStr()}'; // limit doesnt work
    // return '${booru.baseURL}/index.php?page=dapi&s=tag&q=index&name_pattern=$input%&limit=20&order=post_count&direction=desc&json=1$apiKeyStr$userIdStr'; // order doesnt work
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final parsedResponse = response.data is List ? response.data : response.data['tag'] ?? [];
    return parsedResponse;
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final String tagStr = responseItem['value'] ?? responseItem['name'] ?? '';
    if (tagStr.isEmpty) {
      return null;
    }

    // record tag data for future use
    final String rawTagType = (responseItem['category'] ?? responseItem['type'])?.toString() ?? '';
    TagType tagType = TagType.none;
    if (rawTagType.isNotEmpty &&
        (tagTypeMap.containsKey(rawTagType) || tagSuggestionsTypeMap.containsKey(rawTagType))) {
      tagType = tagTypeMap[rawTagType] ?? tagSuggestionsTypeMap[rawTagType] ?? TagType.none;
    }
    addTagsWithType([tagStr], tagType);
    return TagSuggestion(
      tag: tagStr,
      type: tagType,
      // Some sites only expose the count inside a display label.
      count: siteProfile?.tagSuggestionCount(responseItem) ??
          int.tryParse((responseItem['count'] ?? responseItem['post_count'])?.toString() ?? '0') ??
          0,
    );
  }

  @override
  bool get shouldPopulateTags => true;

  @override
  String makeDirectTagURL(List<String> tags) {
    // `name=` is singular and exact — see genTagObjects for why the old
    // `names=` batch form is gone.
    return '${booru.baseURL}/index.php?page=dapi&s=tag&q=index'
        '&name=${Uri.encodeComponent(tags.isEmpty ? '' : tags.first)}&limit=1${buildApiStr()}';
  }

  /// Resolves tag types against the site's own tag database.
  ///
  /// This used to issue one request with `&names=a b c&json=1` and parse
  /// `response.data['tag']`. Both halves of that are wrong on the Gelbooru
  /// 0.2 family, verified live against rule34.xxx and xbooru with valid
  /// credentials:
  ///   * `names=` is ignored completely — the site answers with the first
  ///     page of its entire tag index, so the tags actually asked about were
  ///     never in the response;
  ///   * `json=1` is ignored too on rule34.xxx, which always replies XML, so
  ///     the `['tag']` lookup threw on a String and the catch below swallowed
  ///     it. Net effect: this method returned an empty list every time and no
  ///     tag on those sites ever got a type from here.
  ///
  /// `name=` (singular) *is* honoured and returns exactly one authoritative
  /// row, so types are resolved one tag at a time with bounded concurrency,
  /// answers already in the per-booru snapshot are reused instead of being
  /// re-requested, and everything learned is written back to that snapshot.
  @override
  Future<List<Tag>> genTagObjects(List<String> tags) async {
    final TagIndexSource? source = TagIndexSource.forBooru(booru);
    if (source == null) return [];

    final List<String> wanted = [
      for (final t in tags.map((t) => t.trim().toLowerCase()).toSet())
        if (t.isNotEmpty) t,
    ];
    if (wanted.isEmpty) return [];

    final List<Tag> tagObjects = [];
    final List<String> toFetch = [];

    // Anything a previous snapshot pull already answered costs no request.
    final Map<String, BooruTagEntry> known = await BooruTagStore.lookup(booru, wanted);
    for (final name in wanted) {
      final BooruTagEntry? hit = known[name];
      if (hit != null) {
        tagObjects.add(Tag(hit.name, tagType: hit.tagType, count: hit.count));
      } else {
        toFetch.add(name);
      }
    }

    // Politeness cap: the background queue re-feeds whatever is left over on
    // its next pass, so this never turns a big post into a request storm.
    const int concurrency = 3;
    const int maxPerCall = 45;
    final List<String> batchList = toFetch.take(maxPerCall).toList();
    final List<BooruTagEntry> learned = [];

    for (int i = 0; i < batchList.length; i += concurrency) {
      final Iterable<String> batch = batchList.skip(i).take(concurrency);
      final results = await Future.wait(
        batch.map((name) async {
          try {
            return await source.exact(booru, name);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final entry in results.whereType<BooruTagEntry>()) {
        learned.add(entry);
        tagObjects.add(Tag(entry.name, tagType: entry.tagType, count: entry.count));
      }
    }

    if (learned.isNotEmpty) {
      unawaited(BooruTagStore.record(booru, learned));
    }
    Logger.Inst().log(
      'resolved ${tagObjects.length}/${wanted.length} tag types (${learned.length} fetched)',
      className,
      'genTagObjects',
      LogTypes.booruHandlerTagInfo,
    );
    return tagObjects;
  }

  // ----------------- Search count

  void parseSearchCount(dynamic response) {
    final parsedResponse = response['@attributes']['count'] ?? 0;
    totalCount.value = parsedResponse;
  }

  // ----------------- Comments

  @override
  bool get hasCommentsSupport => true;

  @override
  String makeCommentsURL(String postID, int pageNum) {
    return makePostURL(postID) + (pageNum == 0 ? '' : '&pid=${pageNum * 10}');

    // EXAMPLE: https://gelbooru.com/index.php?page=dapi&s=comment&q=index&post_id=7296350
    // ignore: dead_code
    return '${booru.baseURL}/index.php?page=dapi&s=comment&q=index&post_id=$postID${buildApiStr()}';
  }

  @override
  List parseCommentsList(dynamic response) {
    final document = parse(response.data);
    final avatars = document.querySelectorAll('div.commentAvatar');
    final bodies = document.querySelectorAll('div.commentBody');
    // avatars/bodies counts should match, but guard against mismatched markup
    final int count = min(avatars.length, bodies.length);
    return List.generate(count, (i) => [avatars[i], bodies[i]]);
  }

  @override
  CommentItem? parseComment(dynamic responseItem, int index) {
    // The comment markup is scraped HTML, so node positions can shift on
    // malformed/changed pages. Parse defensively and skip a single bad
    // comment rather than dropping the whole list.
    try {
      final Element avatarNode = responseItem[0];
      final List<String> avatarParts = avatarNode.outerHtml.split("url('");
      final String? avatarUrl = avatarParts.length > 1
          ? 'https://gelbooru.com/${avatarParts[1].split("')")[0]}'
          : null;
      final Element bodyNode = responseItem[1];

      final List<String>? dateParts = bodyNode.nodes.elementAtOrNull(2)?.text?.split('at ');
      final String? createDate = (dateParts != null && dateParts.length > 1)
          ? dateParts[1].split(' »')[0]
          : null;

      return CommentItem(
        content: bodyNode.nodes.elementAtOrNull(5)?.text,
        authorName: bodyNode.nodes.elementAtOrNull(1)?.nodes.elementAtOrNull(0)?.text,
        avatarUrl: avatarUrl,
        score: int.tryParse(bodyNode.querySelector('span span.info span')?.text ?? '0'),
        createDate: createDate,
        createDateFormat: 'yyyy-MM-dd HH:mm:ss',
      );
    } catch (e) {
      Logger.Inst().log(e.toString(), className, 'parseComment', LogTypes.exception);
      return null;
    }
  }

  List parseCommentsListOld(dynamic response) {
    final parsedResponse = XmlDocument.parse(response.data);
    return parsedResponse.findAllElements('comment').toList();
  }

  CommentItem? parseCommentOld(dynamic responseItem, int index) {
    final current = responseItem;
    final String avatar = current.getAttribute('creator_id')!.isEmpty
        ? "${booru.baseURL}/user_avatars/avatar_${current.getAttribute("creator")}.jpg"
        : '${booru.baseURL}/user_avatars/honkonymous.png';

    return CommentItem(
      id: current.getAttribute('id'),
      title: current.getAttribute('id'),
      content: current.getAttribute('body'),
      authorID: current.getAttribute('creator_id'),
      authorName: current.getAttribute('creator'),
      postID: current.getAttribute('post_id'),
      avatarUrl: avatar,
      createDate: current.getAttribute('created_at'), // 2021-11-15 12:09
      createDateFormat: 'yyyy-MM-dd HH:mm',
    );
  }

  // ----------------- Notes

  @override
  bool get hasNotesSupport => true;

  @override
  String makeNotesURL(String postID) {
    // EXAMPLE: https://gelbooru.com/index.php?page=dapi&s=note&q=index&post_id=6512262
    return '${booru.baseURL}/index.php?page=dapi&s=note&q=index&post_id=$postID${buildApiStr()}';
  }

  @override
  List parseNotesList(dynamic response) {
    final parsedResponse = XmlDocument.parse(response.data);
    return parsedResponse.findAllElements('note').toList();
  }

  @override
  NoteItem? parseNote(dynamic responseItem, int index) {
    final current = responseItem;
    if (current.getAttribute('is_active') == false) return null;
    return NoteItem(
      id: current.getAttribute('id'),
      postID: current.getAttribute('post_id'),
      content: current.getAttribute('body'),
      posX: int.tryParse(current.getAttribute('x') ?? '0') ?? 0,
      posY: int.tryParse(current.getAttribute('y') ?? '0') ?? 0,
      width: int.tryParse(current.getAttribute('width') ?? '0') ?? 0,
      height: int.tryParse(current.getAttribute('height') ?? '0') ?? 0,
    );
  }

  @override
  String? get metatagsCheatSheetLink => 'https://gelbooru.com/index.php?page=wiki&s=view&id=26263';

  @override
  List<MetaTag> availableMetaTags() {
    // The family list advertises sorts/filters most compatible sites don't
    // implement; a profile replaces it with what the site really supports.
    final List<MetaTag>? profileTags = siteProfile?.metaTags();
    if (profileTags != null) return profileTags;

    return [
      DanbooruGelbooruRatingMetaTag(),
      SortMetaTag(
        values: [
          MetaTagValue(name: 'ID', value: 'id'),
          MetaTagValue(name: 'ID (ascending)', value: 'id:asc'),
          MetaTagValue(name: 'Score', value: 'score'),
          MetaTagValue(name: 'Score (ascending)', value: 'score:asc'),
          MetaTagValue(name: 'Rating', value: 'rating'),
          MetaTagValue(name: 'Rating (ascending)', value: 'rating:asc'),
          MetaTagValue(name: 'User', value: 'user'),
          MetaTagValue(name: 'User (ascending)', value: 'user:asc'),
          MetaTagValue(name: 'Height', value: 'height'),
          MetaTagValue(name: 'Height (ascending)', value: 'height:asc'),
          MetaTagValue(name: 'Width', value: 'width'),
          MetaTagValue(name: 'Width (ascending)', value: 'width:asc'),
          MetaTagValue(name: 'Source', value: 'source'),
          MetaTagValue(name: 'Source (ascending)', value: 'source:asc'),
          MetaTagValue(name: 'Updated', value: 'updated'),
          MetaTagValue(name: 'Updated (ascending)', value: 'updated:asc'),
          MetaTagValue(name: 'Random', value: 'random'), // can add seed at the end (sort:random:{seed})
        ],
      ),
      ComparableNumberMetaTag(name: 'Score', keyName: 'score'),
      StringMetaTag(name: 'ID', keyName: 'id'),
      UserMetaTag(),
      // StringMetaTag(name: 'Favourites of user ID (fav:{id})', keyName: 'fav'),
      StringMetaTag(name: 'MD5', keyName: 'md5'),
      ComparableNumberMetaTag(name: 'Width', keyName: 'width'),
      ComparableNumberMetaTag(name: 'Height', keyName: 'height'),
    ];
  }

  //

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final response = await DioNetwork.get(
        item.postURL,
        headers: {
          ...getHeaders(),
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
        cancelToken: cancelToken,
        customInterceptor: withCapcthaCheck ? DioNetwork.captchaInterceptor : null,
      );

      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      } else {
        final html = parse(response.data);

        Element? source = html.getElementById('gelcomVideoPlayer');
        if (source != null) {
          // video
          item.thumbnailURL = source.attributes['poster'] ?? item.thumbnailURL;
          item.sampleURL = source.attributes['poster'] ?? item.sampleURL;
          item.fileURL = source.attributes['src'] ?? source.children.firstOrNull?.attributes['src'] ?? item.fileURL;
        } else {
          // image
          source = html.getElementById('image');
          if (source != null) {
            final String? src = source.attributes['src'];
            final isSample = src?.contains('sample') ?? false;
            if (isSample) {
              item.sampleURL = src ?? item.sampleURL;
              item.fileURL = html.querySelector('meta[property="og:image"]')?.attributes['content'] ?? item.fileURL;
            } else {
              item.fileURL = src ?? item.fileURL;
            }
          }
        }

        item.thumbnailURL = item.thumbnailURL.replaceAll('(?<!https?:)//', '/');
        item.sampleURL = item.sampleURL.replaceAll('(?<!https?:)//', '/');
        item.fileURL = item.fileURL.replaceAll('(?<!https?:)//', '/');

        final sidebar = html.getElementById('tag-list');
        final copyrightTags = parseTagsFromGelbooruHtml(sidebar?.getElementsByClassName('tag-type-copyright'));
        addTagsWithType(copyrightTags.map((t) => t.tag).toList(), TagType.copyright);
        final characterTags = parseTagsFromGelbooruHtml(sidebar?.getElementsByClassName('tag-type-character'));
        addTagsWithType(characterTags.map((t) => t.tag).toList(), TagType.character);
        final artistTags = parseTagsFromGelbooruHtml(sidebar?.getElementsByClassName('tag-type-artist'));
        addTagsWithType(artistTags.map((t) => t.tag).toList(), TagType.artist);
        final generalTags = parseTagsFromGelbooruHtml(sidebar?.getElementsByClassName('tag-type-general'));
        addTagsWithType(generalTags.map((t) => t.tag).toList(), TagType.none);
        final metaTags = parseTagsFromGelbooruHtml(sidebar?.getElementsByClassName('tag-type-metadata'));
        addTagsWithType(metaTags.map((t) => t.tag).toList(), TagType.meta);

        for (final t in [...copyrightTags, ...characterTags, ...artistTags, ...generalTags, ...metaTags]) {
          final tagIndex = item.tagsList.indexWhere((tt) => tt.fullString == t.tag);
          if (tagIndex != -1) {
            item.tagsList[tagIndex].count = t.count;
          }
        }
        item.isUpdated = true;
        return (item: item, failed: false, error: null);
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        className,
        'loadItem',
        LogTypes.exception,
        s: s,
      );
      return (item: null, failed: true, error: e.toString());
    }
  }
}
