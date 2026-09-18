import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide MetaTag;
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/shimmie_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class R34HentaiHandler extends ShimmieHandler {
  R34HentaiHandler(super.booru, super.limit);

  @override
  bool get hasSizeData => true;

  // R34HentaiHandler serves rule34hentai.net. Verified against the site:
  // `animated` = 152366 posts is the umbrella (webm = 2076 and mp4 = 660 are
  // essentially all tagged animated too — `webm -animated` returns ~one page);
  // there is no standalone `video` tag (it 404s). So a single `animated` stop
  // catches everything without the dead second tap the old cycle produced.
  @override
  List<String> get animatedPreviewFilters => const ['animated'];

  @override
  String validateTags(String tags) {
    return tags;
  }

  @override
  Future<List> parseListFromResponse(dynamic response) async {
    final document = parse(response.data);
    return document.getElementsByClassName('thumb');
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem as Element;

    final String id = current.attributes['data-post-id']!;
    final String? rawMime = current.attributes['data-mime'];
    final String fileExt = rawMime?.split('/')[1] ?? 'png';
    final String thumbURL = current.firstChild!.attributes['src']!;
    final double? thumbWidth = double.tryParse(current.firstChild!.attributes['width'] ?? '');
    final double? thumbHeight = double.tryParse(current.firstChild!.attributes['height'] ?? '');
    final double? fileWidth = double.tryParse(current.attributes['data-width'] ?? '');
    final double? fileHeight = double.tryParse(current.attributes['data-height'] ?? '');
    final String fileURL = thumbURL
        .replaceFirst('_thumbs', '_images')
        .replaceFirst('thumbnails', 'images')
        .replaceFirst('thumbnail_', '')
        .replaceFirst('.jpg', '.$fileExt');
    final List<String> tags = current.attributes['data-tags']?.split(' ') ?? [];

    final BooruItem item = BooruItem(
      thumbnailURL: booru.baseURL! + thumbURL,
      sampleURL: booru.baseURL! + fileURL,
      fileURL: booru.baseURL! + fileURL,
      previewWidth: thumbWidth,
      previewHeight: thumbHeight,
      fileWidth: fileWidth,
      fileHeight: fileHeight,
      tagsList: tags.map(Tag.new).toList(),
      md5String: getHashFromURL(thumbURL),
      postURL: makePostURL(id),
      serverId: id,
    );

    // Diagnostic: if the post looks video-like (by tags or mime) but the
    // computed fileExt / mediaType isn't a video, log inputs + outputs so we
    // can see what's actually in data-mime and what URL we built. Catches the
    // "viewer shows static image for a video" case.
    final bool tagsSayVideo = tags.contains('video') || tags.contains('webm') || tags.contains('mp4');
    final bool mimeSaysVideo = rawMime?.startsWith('video/') == true;
    if ((tagsSayVideo || mimeSaysVideo) && !item.mediaType.value.isVideo) {
      Logger.Inst().log(
        'r34hentai: video-tagged item resolved to ${item.mediaType.value}. '
        'data-mime=$rawMime fileExt=$fileExt fileURL=${item.fileURL} thumbURL=$thumbURL '
        'tagsSayVideo=$tagsSayVideo postURL=${item.postURL}',
        className,
        'parseItemFromResponse',
        LogTypes.booruHandlerInfo,
      );
    }

    return item;
  }

  String getHashFromURL(String url) {
    final String hash = url.substring(url.lastIndexOf('_') + 1, url.lastIndexOf('.'));
    return hash;
  }

  /// The site's popular pages (2026-09-18): one page each, no search on them.
  static const Map<String, String> popularPages = {'day': 'popular_by_day', 'month': 'popular_by_month', 'year': 'popular_by_year'};

  /// The Filters card's own terms (and a source's saved defaults, which
  /// compose the same way). They do not stop a Popular chip: the site's
  /// popular pages take no filters, so they are dropped there (r72 review).
  static final RegExp chipTerm = RegExp(r'^(order=|content:|ext=|score[><=]|favorites[><=]|comments[><=])', caseSensitive: false);

  @override
  String makeURL(String tags) {
    // r72 (checked in Chrome, 2026-09-18): the site's Sort menu writes
    // `order=score_desc` and ignores the colon form, so a typed `order:x`
    // becomes `order=x`; a Popular chip opens the site's page (the card's
    // other chips are dropped there), beside typed tags the search wins (as
    // on kusowanka).
    final List<String> terms = tags.split(' ').where((t) => t.isNotEmpty).toList();
    String? popular;
    final List<String> rest = [];
    for (final String t in terms) {
      final String lower = t.toLowerCase();
      if (lower.startsWith('popular:')) {
        popular = lower.substring(8);
      } else if (lower.startsWith('order:')) {
        rest.add('order=${t.substring(6)}');
      } else {
        rest.add(t);
      }
    }
    if (popular != null && rest.every(chipTerm.hasMatch)) {
      final String? page = popularPages[popular];
      if (page == null) {
        errorString = 'rule34hentai has no "$popular" popular page: day, month or year.';
        locked = true;
        return '';
      }
      // One page each: a second page is the end, not an error.
      if (pageNum > 1) {
        locked = true;
        return '';
      }
      return '${booru.baseURL}/$page';
    }
    final String tagsText = rest.join('+');
    return '${booru.baseURL}/post/list/${tagsText.isEmpty ? '' : '$tagsText/'}$pageNum';
  }

  /// rule34hentai's own search, checked in the user's Chrome on 2026-09-18
  /// (the site sits behind Cloudflare): the Sort menu is `order=id_desc`
  /// (newest, the default) and `order=score_desc` (top voted) - every other
  /// order form is ignored; `content:video|audio`, `ext=`, `score>`,
  /// `favorites>` and `comments>` filter, as do the Post List operators
  /// (size, ratio, filesize, width, height, id, posted, tags, source, user,
  /// hash, filename, upvoted_by, downvoted_by, favorited_by, commented_by).
  /// `rating:` matches only the ~2% of posts that carry a rating (explicit:
  /// none), so it is not offered.
  @override
  DoujinFilterSpec? get doujinFilters => const DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'order',
      label: 'Sort',
      divider: '=',
      options: [DoujinFilterOption('', 'Newest (site default)'), DoujinFilterOption('score_desc', 'Top voted')],
    ),
    DoujinFilterGroup(
      key: 'popular',
      label: 'Popular',
      options: [
        DoujinFilterOption('', 'Off'),
        DoujinFilterOption('day', 'Today'),
        DoujinFilterOption('month', 'This month'),
        DoujinFilterOption('year', 'This year'),
      ],
    ),
    DoujinFilterGroup(
      key: 'content',
      label: 'Content',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('video', 'Videos'), DoujinFilterOption('audio', 'With audio')],
    ),
    DoujinFilterGroup(
      key: 'ext',
      label: 'File type',
      divider: '=',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('webm', 'WebM'),
        DoujinFilterOption('mp4', 'MP4'),
        DoujinFilterOption('gif', 'GIF'),
        DoujinFilterOption('png', 'PNG'),
        DoujinFilterOption('jpg', 'JPG'),
      ],
    ),
    DoujinFilterGroup(
      key: 'score',
      label: 'Score',
      divider: '>',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('0', 'Above 0'),
        DoujinFilterOption('10', 'Above 10'),
        DoujinFilterOption('50', 'Above 50'),
        DoujinFilterOption('100', 'Above 100'),
      ],
    ),
    DoujinFilterGroup(
      key: 'favorites',
      label: 'Favorites',
      divider: '>',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('5', 'Above 5'),
        DoujinFilterOption('10', 'Above 10'),
        DoujinFilterOption('50', 'Above 50'),
        DoujinFilterOption('100', 'Above 100'),
      ],
    ),
    DoujinFilterGroup(
      key: 'comments',
      label: 'Comments',
      divider: '>',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('1', 'Above 1'),
        DoujinFilterOption('5', 'Above 5'),
        DoujinFilterOption('10', 'Above 10'),
      ],
    ),
  ]);

  /// The typed search fields, for the query editor. The site accepts `:` in
  /// place of `=` (checked: score:100, size:1920x1080, width:1920,
  /// filesize:>10mb) except on `order` and `ext`; `tags=N` and a bare
  /// `posted=date` answer nothing there, so neither is offered as such.
  @override
  List<MetaTag> availableMetaTags() => [
    MetaTagWithValues(
      name: 'Sort',
      keyName: 'order',
      divider: '=',
      values: [MetaTagValue(name: 'Top voted', value: 'score_desc'), MetaTagValue(name: 'Newest', value: 'id_desc')],
    ),
    MetaTagWithValues(
      name: 'Popular',
      keyName: 'popular',
      values: [MetaTagValue(name: 'Today', value: 'day'), MetaTagValue(name: 'This month', value: 'month'), MetaTagValue(name: 'This year', value: 'year')],
    ),
    MetaTagWithValues(
      name: 'Content',
      keyName: 'content',
      values: [MetaTagValue(name: 'Videos', value: 'video'), MetaTagValue(name: 'With audio', value: 'audio')],
    ),
    MetaTagWithValues(
      name: 'File type',
      keyName: 'ext',
      divider: '=',
      values: [
        MetaTagValue(name: 'WebM', value: 'webm'),
        MetaTagValue(name: 'MP4', value: 'mp4'),
        MetaTagValue(name: 'GIF', value: 'gif'),
        MetaTagValue(name: 'PNG', value: 'png'),
        MetaTagValue(name: 'JPG', value: 'jpg'),
      ],
    ),
    ComparableNumberMetaTag(name: 'Score', keyName: 'score'),
    ComparableNumberMetaTag(name: 'Favorites', keyName: 'favorites'),
    ComparableNumberMetaTag(name: 'Comments', keyName: 'comments'),
    ComparableNumberMetaTag(name: 'Width', keyName: 'width'),
    ComparableNumberMetaTag(name: 'Height', keyName: 'height'),
    ComparableNumberMetaTag(name: 'File size (bytes, or 3MB)', keyName: 'filesize'),
    ComparableNumberMetaTag(name: 'ID', keyName: 'id'),
    StringMetaTag(name: 'Size (WxH; size>=WxH works too)', keyName: 'size'),
    StringMetaTag(name: 'Ratio (W:H)', keyName: 'ratio'),
    // posted:2026-09-17 alone answers nothing on the site; posted:>=date does.
    DateMetaTag(name: 'Posted', keyName: 'posted', supportsRange: false),
    StringMetaTag(name: 'Source (url, any, none)', keyName: 'source'),
    StringMetaTag(name: 'Uploader', keyName: 'user'),
    StringMetaTag(name: 'MD5', keyName: 'hash'),
    StringMetaTag(name: 'Filename contains', keyName: 'filename'),
    StringMetaTag(name: 'Upvoted by', keyName: 'upvoted_by'),
    StringMetaTag(name: 'Downvoted by', keyName: 'downvoted_by'),
    StringMetaTag(name: 'Favorited by', keyName: 'favorited_by'),
    StringMetaTag(name: 'Commented by', keyName: 'commented_by'),
  ];

  // r72: the site's own autocomplete (the generic Shimmie handler only knew
  // paheal's). It answers a tag -> count JSON map. A non-JSON answer (a
  // Cloudflare page) throws: the base then answers a failure, which the
  // alias resolver does not record as "no such tag" (an empty list would be).
  @override
  String makeTagURL(String input) => '${booru.baseURL}/api/internal/autocomplete?s=$input';

  @override
  List parseTagSuggestionsList(dynamic response) {
    dynamic data = response.data;
    if (data is String) {
      data = jsonDecode(data);
    }
    if (data is Map) {
      return data.entries.map((e) => TagSuggestion(tag: e.key.toString(), count: int.tryParse(e.value.toString()) ?? 0)).toList();
    }
    if (data is List) {
      return data.map((e) => TagSuggestion(tag: e.toString())).toList();
    }
    return const [];
  }

  @override
  bool get hasSignInSupport => true;

  // The site login below reads both fields; the generic Shimmie handler hides
  // them on the edit page, which left the Account tile pointing at a page
  // with nothing to enter (r72 review).
  @override
  bool get usesUserId => true;
  @override
  bool get usesApiKey => true;
  @override
  String? get userIdLabel => 'Username';
  @override
  String? get apiKeyLabel => 'Password';

  @override
  Future<bool> signIn() async {
    final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
    List<String>? setCookies;
    try {
      final res = await DioNetwork.post(
        '${booru.baseURL}/user_admin/login',
        data: {
          'user': booru.userID,
          'pass': booru.apiKey,
          'gobu': 'Log+In',
        },
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
        headers: await Tools.getFileCustomHeaders(booru),
      );
      setCookies = res.headers['set-cookie'];
    } catch (e) {
      if (e is DioException) {
        setCookies = e.response?.headers['set-cookie'];
      }
    }
    if (setCookies != null) {
      for (final cookie in setCookies) {
        final name = cookie.split(';')[0].split('=')[0];
        final value = cookie.split(';')[0].split('=')[1];

        await cookieManager.setCookie(
          url: WebUri(booru.baseURL!),
          name: name,
          value: value,
        );
        if (Platform.isWindows) {
          globalWindowsCookies[WebUri(booru.baseURL!).host]?.add(
            Cookie(
              name: name,
              value: value,
              domain: WebUri(booru.baseURL!).host,
            ),
          );
        }
      }
      return true;
    } else {
      return false;
    }
  }

  @override
  Future<bool> isSignedIn() async {
    final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
    final cookies = await cookieManager.getCookies(url: WebUri(booru.baseURL!));
    if (Platform.isWindows) {
      cookies.addAll(globalWindowsCookies[WebUri(booru.baseURL!).host] ?? []);
    }
    final bool hasCookies = cookies.any((e) => e.name == 'shm_user') && cookies.any((e) => e.name == 'shm_session');

    if (!hasCookies) {
      return false;
    } else {
      final handler = _R34HentaiHandlerDummy(booru, limit);
      final res = await handler.search(
        'rating:explicit',
        0,
      );

      if (res is List && res.isEmpty) {
        await signOut(fromError: true);
        return false;
      } else {
        return true;
      }
    }
  }

  @override
  Future<bool?> signOut({bool fromError = false}) async {
    bool success = false;
    if (fromError) {
      success = true;
    } else {
      try {
        final res = await DioNetwork.get(
          '${booru.baseURL}/user_admin/logout',
          headers: await Tools.getFileCustomHeaders(booru),
        );
        success = res.statusCode == 200;
      } catch (e) {
        if (e is DioException) {
          success = false;
        }
      }
    }

    final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
    await cookieManager.deleteCookies(
      url: WebUri(booru.baseURL!),
    );
    if (Platform.isWindows) {
      globalWindowsCookies[WebUri(booru.baseURL!).host]?.clear();
    }

    return success;
  }
}

// copy of original to avoid recursion when checking isSignedIn
class _R34HentaiHandlerDummy extends R34HentaiHandler {
  _R34HentaiHandlerDummy(super.booru, super.limit) {
    // The signed-in check searches `rating:explicit`; a source's saved
    // default filters must not compose into it (r72 review).
    applySourceSettings = false;
  }

  @override
  Future<bool> searchSetup() async {
    return true;
  }
}

/// Booru Handler for the r34hentai engine
// TODO they removed their api, both shimmie and custom one, but maybe it is still hidden somewhere?
class R34HentaiHandlerOld extends R34HentaiHandler {
  R34HentaiHandlerOld(super.booru, super.limit);

  @override
  Future<List> parseListFromResponse(dynamic response) async {
    final List<dynamic> parsedResponse = BooruHandler.asResponseList(response.data);
    return parsedResponse; // Limit doesn't work with this api
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem;
    final String imageUrl = current['file_url'];
    final String sampleUrl = current['sample_url'];
    final String thumbnailUrl = current['preview_url'];

    final BooruItem item = BooruItem(
      fileURL: imageUrl,
      sampleURL: sampleUrl,
      thumbnailURL: thumbnailUrl,
      tagsList: current['tags'].split(' ').map(Tag.new).toList(),
      postURL: makePostURL(current['id'].toString()),
    );

    return item;
  }

  @override
  String makeURL(String tags) {
    return '${booru.baseURL}/post/index.json?limit=$limit&page=$pageNum&tags=$tags';
  }
}
