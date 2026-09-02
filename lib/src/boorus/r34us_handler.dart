import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class R34USHandler extends BooruHandler {
  R34USHandler(super.booru, super.limit);

  // Reads neither field (audited): the fields are hidden on the edit page.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;


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
  /// Agent, and both are parsed below.
  ///
  /// Under a mobile UA — what `Tools.browserUserAgent` returns on Android,
  /// since it prefers the device WebView's own UA — the grid lazy-loads
  /// (`data-src`, no `src`) and the post page drops `.content_push` and
  /// `.tag-list-left` entirely.
  ///
  /// An earlier fix forced a desktop UA here to get the layout the parser
  /// already understood. That was the wrong trade: the captcha WebView signs
  /// in with `Tools.browserUserAgent`, and Cloudflare-style clearance cookies
  /// are bound to (IP + User-Agent). Sending a different UA from the app than
  /// the one that solved the captcha gets the cookie rejected — loosely
  /// tolerated on a trusted home IP, strictly refused on mobile data (see the
  /// note on `Tools.deviceWebViewUserAgent`). So the UA stays whatever the
  /// rest of the app uses, and the parsing below adapts instead.
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
        Element? imageEl = html.querySelector('div.content_push > img');
        Element? videoEl = html.querySelector('div.content_push > video');

        // Mobile layout: the media sits bare inside .container with no
        // wrapper, so select it by where it POINTS rather than where it sits.
        if (imageEl == null && videoEl == null) {
          videoEl = html.querySelector('video');
          imageEl = html
              .querySelectorAll('img')
              .firstWhereOrNull((e) => _isMediaUrl(e.attributes['src'] ?? ''));
        }

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

        // Prefer an mp4 <source> over the first child: the mobile player
        // lists mp4 and webm as siblings and the order is not guaranteed.
        final List<Element> sources = videoEl?.querySelectorAll('source') ?? const [];
        final String? videoSrc =
            sources.firstWhereOrNull((e) => (e.attributes['src'] ?? '').contains('.mp4'))?.attributes['src'] ??
            sources.firstOrNull?.attributes['src'] ??
            videoEl?.attributes['src'];

        item.fileURL =
            imageEl?.attributes['src'] ??
            (videoEl != null ? origEl?.attributes['href'] ?? videoSrc : null) ??
            item.fileURL;
        item.sampleURL = imageEl?.attributes['src'] ?? videoEl?.attributes['poster'] ?? item.sampleURL;
        if (videoEl != null && (item.fileURL.isEmpty || !_isMediaUrl(item.fileURL))) {
          item.fileURL = videoSrc ?? item.fileURL;
        }
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

        // The desktop markup is `<ul id="tag-list " class="tag-list-left">` —
        // note the TRAILING SPACE in the id, which makes getElementById('tag-list')
        // return null and silently cost every post its tag types. Match the
        // class instead, and keep the id lookup as a fallback in case they
        // ever fix it.
        final Element? sidebar =
            html.querySelector('.tag-list-left') ??
            html.querySelector('[id^="tag-list"]') ??
            html.getElementById('tag-list');
        if (sidebar != null) {
          addTagsWithType(_tagsFromHtml(sidebar.getElementsByClassName('copyright-tag')), TagType.copyright);
          addTagsWithType(_tagsFromHtml(sidebar.getElementsByClassName('character-tag')), TagType.character);
          addTagsWithType(_tagsFromHtml(sidebar.getElementsByClassName('artist-tag')), TagType.artist);
          addTagsWithType(_tagsFromHtml(sidebar.getElementsByClassName('general-tag')), TagType.none);
          addTagsWithType(_tagsFromHtml(sidebar.getElementsByClassName('metadata-tag')), TagType.meta);
        } else {
          // Mobile layout: one <a class="card-light"> per tag, carrying an
          // EMPTY type div as a child and the underscored tag name in its
          // href (the visible text is space-separated and would not search).
          final Map<TagType, List<String>> byType = {};
          for (final link in html.querySelectorAll('a.card-light')) {
            final String href = link.attributes['href'] ?? '';
            final String name = RegExp('q=([^&]+)').firstMatch(href)?.group(1) ?? '';
            if (name.isEmpty) continue;
            final TagType type = link.querySelector('.artist-tag') != null
                ? TagType.artist
                : link.querySelector('.character-tag') != null
                ? TagType.character
                : link.querySelector('.copyright-tag') != null
                ? TagType.copyright
                : link.querySelector('.metadata-tag') != null
                ? TagType.meta
                : TagType.none;
            byType.putIfAbsent(type, () => []).add(Uri.decodeComponent(name));
          }
          for (final entry in byType.entries) {
            addTagsWithType(entry.value, entry.key);
          }
        }
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

  /// Whether a URL points at rule34.us post media rather than site chrome
  /// (the mobile layout's header is full of `/v1/icons/*.svg`).
  static bool _isMediaUrl(String url) =>
      RegExp(r'rule34\.us/(?:images|videos)/').hasMatch(url) && !url.contains('/v1/');

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
