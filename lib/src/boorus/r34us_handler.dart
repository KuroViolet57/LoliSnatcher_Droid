import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class R34USHandler extends BooruHandler {
  R34USHandler(super.booru, super.limit);

  @override
  String validateTags(String tags) {
    if (tags == ' ' || tags == '') {
      return 'all';
    } else {
      return super.validateTags(tags);
    }
  }

  // R34US is a Shimmie-style HTML-scraped booru with no native OR.
  // Drop OR groups with a warning and route the UI to the 3-state cycle.
  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  bool get hasNativeOrSupport => false;

  // R34USHandler serves rule34.us. Verified against the site: unlike the
  // rule34hentai/paheal Shimmie sites, `animated` and `video` are independent
  // here (`video -animated` still returns a full page), so both stops are
  // meaningful. Cycle off → animated → video → off.
  @override
  List<String> get animatedPreviewFilters => const ['animated', 'video'];

  /// rule34.us serves TWO COMPLETELY DIFFERENT LAYOUTS depending on the User
  /// Agent, and everything below is written against the desktop one.
  ///
  /// Under a mobile UA — which is what `Tools.browserUserAgent` returns on
  /// Android, since it prefers the device WebView's UA — the site switches to
  /// a lazy-loading grid whose thumbnails carry `data-src` and NO `src` at
  /// all, and to a post page with neither `.content_push` nor
  /// `.tag-list-left` (the media is injected by script into `#ci`). The
  /// result was a booru that returned "no posts found" for every query, with
  /// no error anywhere, because each item simply parsed to null.
  ///
  /// So ask for the desktop layout explicitly. A user who has deliberately
  /// set a custom User Agent still gets theirs — that is an explicit choice,
  /// and the parser below also tolerates `data-src` for that case.
  @override
  Map<String, String> getHeaders() {
    final String custom = SettingsHandler.instance.customUserAgent;
    return {
      'Accept': 'text/html,application/xml,application/json',
      'User-Agent': custom.isNotEmpty ? custom : Constants.defaultDesktopBrowserUserAgent,
    };
  }

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  List parseListFromResponse(dynamic response) {
    final document = parse(response.data);
    return document.querySelectorAll('div.thumbail-container > div');
  }

  @override
  Future<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) async {
    final Element container = responseItem as Element;
    // querySelector rather than children[0]/firstChild: those walk raw nodes,
    // so a stray text node between the tags is enough to lose the image.
    final Element? link = container.querySelector('a');
    final Element? image = container.querySelector('img');
    if (link == null || image == null) return null;

    final String id = link.attributes['id'] ?? '';
    // `data-src` is the lazy-loading (mobile layout) spelling — see
    // getHeaders above. Kept as a fallback so a layout switch degrades into
    // "still works" rather than "silently finds nothing".
    final String rawSrc = image.attributes['src'] ?? '';
    final String thumbURL = (rawSrc.isEmpty || rawSrc.startsWith('data:'))
        ? (image.attributes['data-src'] ?? '')
        : rawSrc;

    if (id.isNotEmpty && thumbURL.isNotEmpty) {
      final List<String> tags = [];
      (image.attributes['title'] ?? '').split(', ').forEach((tag) {
        if (tag.trim().isNotEmpty) tags.add(tag.trim().replaceAll(' ', '_'));
      });

      final mediaType = (tags.contains('gif') || tags.contains('animated_gif'))
          ? MediaType.animation
          : tags.contains('video') || (tags.contains('webm') || tags.contains('mp4') || tags.contains('sound'))
          ? MediaType.video
          : null;

      String fullURL = thumbURL
          .replaceFirst('thumbnail', 'image')
          .replaceFirst('thumbnail_', '')
          .replaceFirst('.jpg', '.jpeg');
      if (mediaType == MediaType.video) fullURL = fullURL.replaceFirst(RegExp(r'img\d+'), 'video');

      final BooruItem item = BooruItem(
        fileURL: fullURL,
        sampleURL: fullURL,
        thumbnailURL: thumbURL,
        tagsList: tags.map(Tag.new).toList(),
        md5String: getHashFromURL(thumbURL),
        postURL: makePostURL(id),
      );

      item.possibleMediaType.value = mediaType;
      item.mediaType.value = MediaType.needToLoadItem;

      return item;
    } else {
      return null;
    }
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final String cookies = await getCookies() ?? '';
      final response = await DioNetwork.get(
        item.postURL,
        headers: {
          ...getHeaders(),
          if (cookies.isNotEmpty) 'Cookie': cookies,
        },
      );
      if (response.statusCode != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.statusCode}');
      } else {
        final html = parse(response.data);
        final Element? imageEl = html.querySelector('div.content_push > img');
        final Element? videoEl = html.querySelector('div.content_push > video');

        // link to full res has the same html as a tag, but is the only/first(?) element inside .tag-list-left which is wrapped into <a>
        final Element? origEl = html.querySelector('.tag-list-left > a');
        if (imageEl == null && videoEl == null) {
          // Diagnostic: site may have changed its post-page markup. Log a
          // short HTML snippet so we can see what's actually there instead
          // of guessing at the next selector.
          final String snippet = (response.data is String)
              ? (response.data as String).length > 600
                    ? (response.data as String).substring(0, 600)
                    : response.data as String
              : '<non-string response>';
          Logger.Inst().log(
            'r34us: no img/video in .content_push for ${item.postURL}. '
            'origEl=${origEl?.outerHtml.length ?? 0}b. html head: $snippet',
            className,
            'loadItem',
            LogTypes.booruHandlerInfo,
          );
          return (item: null, failed: true, error: 'Failed to parse html');
        }

        item.fileURL =
            imageEl?.attributes['src'] ??
            (videoEl != null ? origEl?.attributes['href'] ?? videoEl.children.firstOrNull?.attributes['src'] : null) ??
            item.fileURL;
        item.sampleURL = imageEl?.attributes['src'] ?? videoEl?.attributes['poster'] ?? item.sampleURL;
        item.fileHeight = double.tryParse((imageEl ?? videoEl)?.attributes['height'] ?? '');
        item.fileWidth = double.tryParse((imageEl ?? videoEl)?.attributes['width'] ?? '');
        item.fileAspectRatio = (item.fileWidth != null && item.fileHeight != null)
            ? item.fileWidth! / item.fileHeight!
            : null;
        item.fileExt = Tools.getFileExt(item.fileURL);
        item.possibleMediaType.value = null;
        item.mediaType.value = MediaType.fromExtension(item.fileExt);

        // Diagnostic: when we end up with an unknown media type, that's the
        // exact moment the viewer falls back to "?". Log the inputs so we
        // can see which one (URL pattern? unknown extension?) drove it.
        if (item.mediaType.value == MediaType.unknown) {
          Logger.Inst().log(
            'r34us: unresolved mediaType after loadItem. '
            'imageEl=${imageEl != null} videoEl=${videoEl != null} origElHref=${origEl?.attributes['href']} '
            'fileURL=${item.fileURL} fileExt=${item.fileExt}',
            className,
            'loadItem',
            LogTypes.booruHandlerInfo,
          );
        }

        final sidebar = html.getElementById('tag-list');
        final copyrightTags = _tagsFromHtml(sidebar?.getElementsByClassName('copyright-tag'));
        addTagsWithType(copyrightTags, TagType.copyright);
        final characterTags = _tagsFromHtml(sidebar?.getElementsByClassName('character-tag'));
        addTagsWithType(characterTags, TagType.character);
        final artistTags = _tagsFromHtml(sidebar?.getElementsByClassName('artist-tag'));
        addTagsWithType(artistTags, TagType.artist);
        final generalTags = _tagsFromHtml(sidebar?.getElementsByClassName('general-tag'));
        addTagsWithType(generalTags, TagType.none);
        final metaTags = _tagsFromHtml(sidebar?.getElementsByClassName('metadata-tag'));
        addTagsWithType(metaTags, TagType.meta);
        item.isUpdated = true;
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        className,
        'getPostData',
        LogTypes.exception,
        s: s,
      );
      return (item: null, failed: true, error: e.toString());
    }

    return (item: item, failed: false, error: null);
  }

  String getHashFromURL(String url) {
    final String hash = url.substring(url.lastIndexOf('_') + 1, url.lastIndexOf('.'));
    return hash;
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/index.php?r=posts/view&id=$id';
  }

  @override
  String makeURL(String tags) {
    return "${booru.baseURL}/index.php?r=posts/index&q=${tags.replaceAll(" ", "+")}&page=$pageNum";
  }
}

List<String> _tagsFromHtml(List<Element>? elements) {
  if (elements == null || elements.isEmpty) {
    return [];
  }

  final tags = <String>[];
  for (final element in elements) {
    final tag = element.getElementsByTagName('a').firstWhereOrNull((e) => e.text.isNotEmpty && e.text != '?');
    if (tag != null) {
      tags.add(tag.text.replaceAll(' ', '_'));
    }
  }
  return tags;
}
