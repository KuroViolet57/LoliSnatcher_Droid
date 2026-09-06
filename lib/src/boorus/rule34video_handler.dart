import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/rule34video_query.dart';
import 'package:lolisnatcher/src/boorus/rule34video_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// rule34video.com — a KVS (Kernel Video Sharing) tube behind DDoS-Guard,
/// probed 2026-09-06. No account, no API; everything is HTML.
///
/// ## Routes (one list per query — the site cannot combine them)
/// - newest: `/latest-updates/` (+`/N/`), 24 cards a page;
/// - text search: `/search/{words}/`, page N = `?from_videos=N`
///   (`/search/{q}/N/` is a trap: it answers the newest site videos);
/// - one tag: `/tags/{id}/` — id-keyed, so a name needs an id from the tag
///   snapshot (Tag builder pull) or from a video page seen this session;
/// - one artist ("model"): `/models/{slug}/`; one category:
///   `/categories/{slug}/`; one uploader: `/members/{id}/videos/`.
/// `?sort_by=post_date|video_viewed|rating|duration|pseudo_rand|most_favourited`
/// works everywhere; the text search adds its own relevance order (default).
///
/// ## Content types (the site's All / Straight / Gay / Futa / Music / Iwara)
/// Tag ids 2109 / 192 / 15 / 4747 / 1821. `?flag1=a,b` (a union) filters
/// every route EXCEPT the text search, which ignores it. Cards carry a
/// `div.futa` badge for Gay and Futa only ("Gay", "Futa", "Gay & Futa");
/// Straight, Music and Iwara cards look alike. So on a text search with a
/// type the phone drops cards itself, walking up to [maxFilterHops] extra
/// pages, and can only tell gay/futa apart. The per-source default lives in
/// Source settings (`SourceSettings.contentTypes`).
///
/// ## Video page
/// A `flashvars = {…}` object: `video_url` (360p), `video_alt_url` (480p),
/// `video_alt_url2` (720p) … with `*_text` labels, `preview_url`,
/// `video_tags`, `video_categories`, `video_models`. The mp4 links carry a
/// `v-acctoken` bound to the client IP that expires within a day, so items
/// are resolved when opened (`needToLoadItem`) and Retry re-resolves. The
/// 302 target (boomio CDN) needs no cookies or Referer; thumbnails are open.
///
/// The site's autocomplete (`/search_ajax.php`) is switched off, so
/// suggestions come from the tag snapshot the Tag builder fills
/// ([Rule34VideoTagCatalog]) plus what this session's video pages taught.
class Rule34VideoHandler extends BooruHandler {
  Rule34VideoHandler(super.booru, super.limit);

  static const String defaultSite = 'https://rule34video.com';

  /// Cards per listing page, fixed by the site.
  static const int pageSize = 24;

  /// Extra pages one fetch may walk when the phone filters a text search
  /// and a page had nothing passing.
  static const int maxFilterHops = 3;

  /// Ids the site taught this session (video pages, index pulls), shared by
  /// every handler instance so a throwaway handler routes the same way.
  static final Map<String, String> knownTagIds = {};
  static final Map<String, String> knownUploaderIds = {};

  /// The query the last `search()` resolved; `makeURL` re-parses when asked
  /// about something else.
  Rule34VideoQuery current = const Rule34VideoQuery(source: '', route: Rule34VideoRoute.latest);

  @override
  late final TagCatalogSource? tagCatalog = Rule34VideoTagCatalog(this);

  String get site {
    String url = (booru.baseURL ?? '').trim();
    if (url.isEmpty) url = defaultSite;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  // Reads neither field (audited): the site has no login the app could use.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;

  @override
  bool get hasSizeData => false;

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  /// Video-only site: nothing to tell animated previews apart by.
  @override
  List<String> get animatedPreviewFilters => const [];

  /// On a phone-filtered text search the site's total counts every type.
  @override
  bool get countIsQuestionable => current.filtersOnPhone;

  @override
  String validateTags(String tags) => tags.trim();

  @override
  Map<String, String> getHeaders() => {
    'Accept': 'text/html,application/xml,application/json',
    'User-Agent': Tools.browserUserAgent,
    'Referer': '$site/',
  };

  /// The signed CDN redirect target wants no cookies or Referer (verified).
  @override
  Map<String, String> getMediaHeaders() => const {};

  @override
  List<MetaTagValue> get contentTypeOptions => [
    MetaTagValue(name: 'Straight', value: 'straight'),
    MetaTagValue(name: 'Gay', value: 'gay'),
    MetaTagValue(name: 'Futa', value: 'futa'),
    MetaTagValue(name: 'Music', value: 'music'),
    MetaTagValue(name: 'Iwara', value: 'iwara'),
  ];

  static const Map<String, String> _sortLabels = {
    'relevant': "Site's order (relevance on text search, newest elsewhere)",
    'newest': 'Newest',
    'viewed': 'Most viewed',
    'rated': 'Top rated',
    'longest': 'Longest',
    'random': 'Random',
    'favourited': 'Most favourited',
  };

  @override
  List<MetaTag> availableMetaTags() => [
    SortMetaTag(
      isFree: true,
      values: [for (final k in Rule34VideoQuery.sorts.keys) MetaTagValue(name: _sortLabels[k] ?? k, value: k)],
    ),
    MetaTagWithValues(
      name: 'Type (text search: phone filters gay/futa only)',
      keyName: 'type',
      isFree: true,
      values: contentTypeOptions,
    ),
    StringMetaTag(name: 'Tag (one, by name)', keyName: 'tag', isFree: true),
    StringMetaTag(name: 'Artist', keyName: 'artist', isFree: true),
    StringMetaTag(name: 'Category', keyName: 'category', isFree: true),
    StringMetaTag(name: 'Uploader (member id, or a name seen this session)', keyName: 'uploader', isFree: true),
  ];

  /// The per-source content-type default as group ids; empty = everything.
  List<String> get defaultGroupIds {
    List<String> keys;
    try {
      keys = SourceSettingsHandler.instance.contentTypes(booru);
    } catch (_) {
      // Not registered (tests, tools): no default.
      return const [];
    }
    return [
      for (final k in keys)
        if (Rule34VideoQuery.groupIdOf(k) != null) Rule34VideoQuery.groupIdOf(k)!,
    ];
  }

  String? get _defaultSort {
    try {
      return SourceSettingsHandler.instance.defaultSort(booru);
    } catch (_) {
      return null;
    }
  }

  Rule34VideoQuery parseQuery(String source) => Rule34VideoQuery.parse(
    source,
    defaultGroups: defaultGroupIds,
    defaultSort: _defaultSort,
    knownTagIds: knownTagIds,
    knownUploaderIds: knownUploaderIds,
  );

  /// Resolves the parts of a query the site keys by id or slug, through the
  /// tag snapshot: a `tag:`/bare name to `/tags/{id}/`, an artist or
  /// category to the slug the index stored (the derived slug otherwise). A
  /// tag or uploader nobody knows falls back to a text search of the name —
  /// never to "everything".
  Future<Rule34VideoQuery> resolveQuery(String source) async {
    Rule34VideoQuery q = parseQuery(source);
    if (q.error != null) return q;
    switch (q.route) {
      case Rule34VideoRoute.tag when q.key == null:
        final String? id = await BooruTagStore.findId(booru, 'tag', q.name!);
        if (id != null) {
          knownTagIds[q.name!] = id;
          q = q.copyWith(key: id);
        } else {
          Logger.Inst().log(
            'no id known for tag "${q.name}", searching the words instead',
            className,
            'resolveQuery',
            LogTypes.booruHandlerInfo,
          );
          q = q.copyWith(route: Rule34VideoRoute.search, text: q.name!.replaceAll('_', ' '));
        }
      case Rule34VideoRoute.uploader when q.key == null:
        q = q.copyWith(route: Rule34VideoRoute.search, text: q.name!.replaceAll('_', ' '));
      case Rule34VideoRoute.search when q.key == null && !q.text.contains(' '):
        // One word the snapshot knows as a tag: its own page is exhaustive
        // and the content filter works there.
        final String name = Rule34VideoQuery.normalizeName(q.text);
        final String? id = name.isEmpty ? null : await BooruTagStore.findId(booru, 'tag', name);
        if (id != null) {
          knownTagIds[name] = id;
          q = q.copyWith(route: Rule34VideoRoute.tag, name: name, key: id);
        }
      case Rule34VideoRoute.artist || Rule34VideoRoute.category:
        final String ns = q.route == Rule34VideoRoute.artist ? 'artist' : 'category';
        final String? stored = await BooruTagStore.findId(booru, ns, q.name!);
        if (stored != null && stored.isNotEmpty) q = q.copyWith(key: stored);
      default:
        break;
    }
    return q;
  }

  /// Resolution needs the database, so it happens here and `makeURL` stays
  /// synchronous.
  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    final String source = validateTags(translateOrSyntax(tags.trim()).trim());
    if (current.source != source || current.needsResolution) {
      current = await resolveQuery(source);
    }
    return super.search(tags, pageNumCustom, withCaptchaCheck: withCaptchaCheck);
  }

  /// 1-based site page for the handler's page counter (first fetch -1 or 0).
  int get page => pageNum < 0 ? 1 : pageNum + 1;

  @override
  String makeURL(String tags) {
    final String source = tags.trim();
    if (current.source != source) {
      // A throwaway handler, or a caller that skipped search(): no database
      // walk here, so an unknown tag name becomes a text search.
      current = parseQuery(source);
    }
    if (current.error != null) {
      errorString = current.error!;
      locked = true;
      return '';
    }
    return urlFor(current, page);
  }

  /// The URL of one page of a query. `flag1` is written by hand: the site
  /// wants a literal comma between ids, and it is pointless on the search
  /// route, which ignores it.
  String urlFor(Rule34VideoQuery q, int page) {
    final List<String> params = [];
    if (q.sort != null) params.add('sort_by=${q.sort}');
    final String pagePath = page > 1 ? '$page/' : '';
    late String base;
    bool search = false;
    switch (q.route) {
      case Rule34VideoRoute.latest:
        base = '$site/latest-updates/$pagePath';
      case Rule34VideoRoute.tag when q.key != null:
        base = '$site/tags/${q.key}/$pagePath';
      case Rule34VideoRoute.artist:
        base = '$site/models/${q.key}/$pagePath';
      case Rule34VideoRoute.category:
        base = '$site/categories/${q.key}/$pagePath';
      case Rule34VideoRoute.uploader when q.key != null:
        // The members' video list; page paths past 1 are not verified.
        base = '$site/members/${q.key}/videos/$pagePath';
      case Rule34VideoRoute.search || Rule34VideoRoute.tag || Rule34VideoRoute.uploader:
        search = true;
        final String text = q.route == Rule34VideoRoute.search ? q.text : (q.name ?? '').replaceAll('_', ' ');
        base = '$site/search/${Uri.encodeComponent(text)}/';
        if (page > 1) params.add('from_videos=$page');
    }
    if (!search && q.groups.isNotEmpty) params.add('flag1=${q.groups.join(',')}');
    return params.isEmpty ? base : '$base?${params.join('&')}';
  }

  /// A text search filtered on the phone may leave a page with nothing to
  /// show; walk on a few pages so the grid does not look finished.
  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    Response<dynamic> response = await super.fetchSearch(
      uri,
      input,
      withCaptchaCheck: withCaptchaCheck,
      queryParams: queryParams,
    );
    if (!current.filtersOnPhone) return response;
    for (int hop = 0; hop < maxFilterHops; hop++) {
      if (response.statusCode != 200) return response;
      final dom.Document doc = parse(response.data?.toString() ?? '');
      final List<dom.Element> cards = cardsOf(doc);
      if (cards.isEmpty || cards.any((c) => cardPasses(c, current.groups))) return response;
      final int here = page;
      if (!hasNextPage(doc, here)) return response;
      pageNum = here; // page is pageNum + 1: the next fetch continues after the hop
      final String next = urlFor(current, here + 1);
      Logger.Inst().log(
        'page $here had no card of the wanted type, trying $next',
        className,
        'fetchSearch',
        LogTypes.booruHandlerInfo,
      );
      response = await super.fetchSearch(Uri.parse(next), input, withCaptchaCheck: withCaptchaCheck);
    }
    return response;
  }

  static final RegExp _fromParam = RegExp(r'from[a-z_+]*:(\d+)');

  /// True when the page's pagination block links a page past [page].
  static bool hasNextPage(dom.Document doc, int page) {
    for (final dom.Element e in doc.querySelectorAll('[data-parameters]')) {
      for (final m in _fromParam.allMatches(e.attributes['data-parameters'] ?? '')) {
        if (int.parse(m.group(1)!) > page) return true;
      }
    }
    return false;
  }

  /// The listing's cards: those inside the `custom_list_videos_*_items`
  /// container, or every card on the page when the container moved.
  static List<dom.Element> cardsOf(dom.Document doc) {
    for (final dom.Element e in doc.querySelectorAll('[id]')) {
      if (e.id.startsWith('custom_list_videos_') && e.id.endsWith('_items')) {
        final List<dom.Element> cards = e.querySelectorAll('div.item.thumb[data-video-card-id]');
        if (cards.isNotEmpty) return cards;
      }
    }
    return doc.querySelectorAll('div.item.thumb[data-video-card-id]');
  }

  /// The groups a card can be seen to belong to. A badge names Gay and/or
  /// Futa; no badge means straight, music or iwara — the site gives no way
  /// to tell those three apart on a card.
  static const Set<String> unbadgedGroups = {'2109', '4747', '1821'};

  static Set<String> groupsOfCard(dom.Element card) {
    final Set<String> out = {};
    for (final dom.Element badge in card.querySelectorAll('div.futa')) {
      for (final String part in badge.text.split('&')) {
        final String? id = Rule34VideoQuery.groupIdOf(part);
        if (id != null) out.add(id);
      }
    }
    return out.isEmpty ? unbadgedGroups : out;
  }

  static bool cardPasses(dom.Element card, List<String> groups) =>
      groups.isEmpty || groupsOfCard(card).any(groups.contains);

  static int? totalOf(dom.Document doc) {
    final String digits = (doc.querySelector('.total_results')?.text ?? '').replaceAll(RegExp('[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  static bool looksBlocked(String body) => body.toLowerCase().contains('ddos-guard');

  @override
  List<dom.Element> parseListFromResponse(dynamic response) {
    final String body = response.data?.toString() ?? '';
    final dom.Document doc = parse(body);
    final List<dom.Element> cards = cardsOf(doc);
    if (cards.isEmpty && looksBlocked(body)) {
      errorString = 'rule34video answered with a DDoS-Guard challenge page instead of a listing. '
          'Retry in a moment, or open the site once in the app browser.';
    }
    final int? total = totalOf(doc);
    if (total != null) totalCount.value = total;
    if (!current.filtersOnPhone) return cards;
    return [
      for (final c in cards)
        if (cardPasses(c, current.groups)) c,
    ];
  }

  static String _text(dom.Element root, String selector) =>
      (root.querySelector(selector)?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final dom.Element card = responseItem as dom.Element;
    final String id = card.attributes['data-video-card-id'] ?? '';
    final dom.Element? link = card.querySelector('a.th[href]') ?? card.querySelector('a[href]');
    final String href = link?.attributes['href'] ?? '';
    final dom.Element? img = card.querySelector('img.thumb') ?? card.querySelector('img[data-original]');
    final String thumb = img?.attributes['data-original'] ?? img?.attributes['src'] ?? '';
    if (id.isEmpty || href.isEmpty || thumb.isEmpty) return null;
    final String webp = img?.attributes['data-webp'] ?? '';
    final String title = _text(card, '.thumb_title').isNotEmpty ? _text(card, '.thumb_title') : (link?.attributes['title'] ?? '').trim();
    final String duration = _text(card, '.time');
    final String views = _text(card, '.video-views-count').isNotEmpty ? _text(card, '.video-views-count') : _text(card, '.views');
    final String added = _text(card, '.added');
    final String rating = _text(card, '.rating');

    final List<Tag> tags = [];
    final Set<String> groups = groupsOfCard(card);
    if (groups.contains('192')) tags.add(Tag('type:gay', tagType: TagType.meta));
    if (groups.contains('15')) tags.add(Tag('type:futa', tagType: TagType.meta));
    if (card.querySelector('.quality') != null) tags.add(Tag('hd', tagType: TagType.meta));

    final String info = [
      duration,
      if (views.isNotEmpty) '$views views',
      added,
    ].where((s) => s.isNotEmpty).join(' · ');

    final BooruItem item = BooruItem(
      // Placeholder until the video page is read: the mp4 link is signed
      // per client and expires.
      fileURL: thumb,
      sampleURL: webp.isNotEmpty ? webp : thumb,
      thumbnailURL: thumb,
      tagsList: tags,
      postURL: href,
      fileExt: 'mp4',
      serverId: id,
      score: rating.isEmpty ? null : rating,
      description: info.isEmpty ? title : '$title\n$info',
    );
    item.possibleMediaType.value = MediaType.video;
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  /// One GET with the site headers and the app's cookies; a non-2xx answer
  /// comes back as its status instead of throwing.
  Future<({int status, String body})> fetchPage(String url, {CancelToken? cancelToken}) async {
    final Map<String, String> headers = Map.of(getHeaders());
    final String? cookies = await getCookies();
    if (cookies != null && cookies.isNotEmpty) headers['Cookie'] = cookies;
    try {
      final Response response = await DioNetwork.get(url, headers: headers, cancelToken: cancelToken);
      return (status: response.statusCode ?? 0, body: response.data?.toString() ?? '');
    } on DioException catch (e) {
      if (e.response == null) rethrow;
      return (status: e.response!.statusCode ?? 0, body: e.response!.data?.toString() ?? '');
    }
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final ({int status, String body}) response = await fetchPage(item.postURL, cancelToken: cancelToken);
      if (response.status != 200) {
        return (item: null, failed: true, error: 'Invalid status code ${response.status}');
      }
      final String? error = await applyVideoPage(item, response.body);
      if (error != null) return (item: null, failed: true, error: error);
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log('loadItem failed: $e', className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  static final RegExp _flashvarsStart = RegExp(r'flashvars\s*=\s*\{');
  static final RegExp _pair = RegExp(r"""([A-Za-z_][A-Za-z0-9_]*)\s*:\s*'((?:[^'\\]|\\.)*)'""");

  /// The `flashvars = {…}` object of a video page as key -> unescaped string.
  /// Empty when the page has none (a blocked or moved page).
  static Map<String, String> flashvarsOf(String body) {
    final RegExpMatch? start = _flashvarsStart.firstMatch(body);
    if (start == null) return const {};
    int depth = 0;
    bool quoted = false;
    int end = -1;
    for (int i = start.end - 1; i < body.length; i++) {
      final String c = body[i];
      if (quoted) {
        if (c == r'\') {
          i++;
        } else if (c == "'") {
          quoted = false;
        }
        continue;
      }
      if (c == "'") {
        quoted = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    final String section = body.substring(start.end, end < 0 ? body.length : end);
    return {
      for (final m in _pair.allMatches(section)) m.group(1)!: m.group(2)!.replaceAll(r"\'", "'").replaceAll(r'\/', '/'),
    };
  }

  static final RegExp _videoKey = RegExp(r'^video_(alt_)?url\d*$');

  /// The highest-resolution file among `video_url`, `video_alt_url`,
  /// `video_alt_urlN`, judged by the `*_text` label (`720p`, `1080p`, `4k`).
  static ({String url, String label})? bestVideoOf(Map<String, String> vars) {
    ({String url, String label})? best;
    int bestPixels = -1;
    for (final MapEntry<String, String> e in vars.entries) {
      if (!_videoKey.hasMatch(e.key) || e.value.isEmpty) continue;
      final String label = vars['${e.key}_text'] ?? '';
      final String digits = label.replaceAll(RegExp('[^0-9]'), '');
      int pixels = digits.isEmpty ? 0 : int.parse(digits);
      if (label.toLowerCase().contains('k') && pixels < 100) pixels *= 540; // 4k -> 2160
      if (pixels >= bestPixels) {
        bestPixels = pixels;
        best = (url: e.value, label: label);
      }
    }
    return best;
  }

  static final RegExp _tagHref = RegExp(r'/tags/(\d+)/?$');
  static final RegExp _slugHref = RegExp(r'/(models|categories)/([^/?#]+)/?$');
  static final RegExp _memberHref = RegExp(r'/members/(\d+)/?(videos/?)?$');

  static String _ownText(dom.Element e) =>
      e.nodes.whereType<dom.Text>().map((t) => t.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Reads a video page into [item]: the best mp4, the preview, the typed
  /// tags (tag / category: / artist: / uploader:), the info line. Returns an
  /// error message when the page carries no player data. With [remember]
  /// the names the snapshot does not have yet are stored with their ids.
  Future<String?> applyVideoPage(BooruItem item, String body, {bool remember = true}) async {
    final Map<String, String> vars = flashvarsOf(body);
    final ({String url, String label})? best = bestVideoOf(vars);
    if (best == null) {
      return looksBlocked(body)
          ? 'rule34video answered with a DDoS-Guard challenge page'
          : 'no player data on the video page (blocked, removed or the page changed)';
    }
    final dom.Document doc = parse(body);

    final List<Tag> tags = [];
    final Map<TagType, List<String>> byType = {};
    void add(String token, TagType type) {
      if (token.isEmpty || tags.any((t) => t.fullString == token)) return;
      tags.add(Tag(token, tagType: type));
      byType.putIfAbsent(type, () => []).add(token);
    }

    // What the card already told us survives the page read.
    for (final Tag t in item.tagsList) {
      if (t.fullString.startsWith('type:') || t.fullString == 'hd') add(t.fullString, TagType.meta);
    }

    final List<BooruTagEntry> learned = [];
    for (final dom.Element chip in doc.querySelectorAll('[data-item-type]')) {
      final dom.Element? a = chip.querySelector('a[href]');
      if (a == null) continue;
      final String href = a.attributes['href'] ?? '';
      switch (chip.attributes['data-item-type']) {
        case 'tag':
          final String name = Rule34VideoQuery.normalizeName(a.text);
          final String? id = _tagHref.firstMatch(href)?.group(1) ?? chip.attributes['data-tag-id'];
          if (name.isEmpty) continue;
          add(name, TagType.none);
          if (id != null) {
            knownTagIds[name] = id;
            learned.add(BooruTagEntry(name: name, tagType: TagType.none, namespace: 'tag', sourceId: id));
          }
        case 'category':
          final String name = Rule34VideoQuery.normalizeName(a.querySelector('span')?.text ?? a.text);
          if (name.isEmpty) continue;
          add('category:$name', TagType.copyright);
          learned.add(
            BooruTagEntry(
              name: name,
              tagType: TagType.copyright,
              namespace: 'category',
              sourceId: _slugHref.firstMatch(href)?.group(2),
            ),
          );
        case 'model':
          final String name = Rule34VideoQuery.normalizeName(a.querySelector('.name')?.text ?? a.text);
          if (name.isEmpty) continue;
          add('artist:$name', TagType.artist);
          learned.add(
            BooruTagEntry(
              name: name,
              tagType: TagType.artist,
              namespace: 'artist',
              sourceId: _slugHref.firstMatch(href)?.group(2),
            ),
          );
      }
    }
    // Chips gone (markup drift): the player data still names the tags.
    if (!byType.containsKey(TagType.none)) {
      for (final String raw in (vars['video_tags'] ?? '').split(',')) {
        add(Rule34VideoQuery.normalizeName(raw), TagType.none);
      }
    }

    // The uploader pill sits under the "Uploaded by" label; any other
    // /members/ link on the page (a commenter) is not it.
    dom.Element? member;
    for (final dom.Element label in doc.querySelectorAll('div.label')) {
      if (label.text.trim().toLowerCase() == 'uploaded by') {
        member = label.parent?.querySelector('a[href]');
        break;
      }
    }
    if (member != null) {
      final RegExpMatch? m = _memberHref.firstMatch(member.attributes['href'] ?? '');
      final String name = _ownText(member).isNotEmpty ? _ownText(member) : (member.querySelector('img')?.attributes['alt'] ?? '');
      if (m != null && name.isNotEmpty) {
        item
          ..uploaderId = m.group(1)
          ..uploaderName = name;
        knownUploaderIds[Rule34VideoQuery.normalizeName(name)] = m.group(1)!;
        add('uploader:${Rule34VideoQuery.normalizeName(name)}', TagType.meta);
      }
    }

    final String title = (vars['video_title'] ?? '').trim().isNotEmpty
        ? vars['video_title']!.trim()
        : (doc.querySelector('h1')?.text ?? item.description?.split('\n').first ?? '').trim();
    final List<String> info = [
      for (final dom.Element span in doc.querySelectorAll('#tab_video_info .item_info span'))
        if (span.text.trim().isNotEmpty) span.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ];
    // The row reads: date, views, duration.
    if (info.length >= 2) info[1] = '${info[1]} views';
    final String voters = _text(doc.documentElement!, '.voters');

    item
      ..fileURL = best.url
      ..fileExt = 'mp4'
      ..sampleURL = (vars['preview_url'] ?? '').isNotEmpty ? vars['preview_url']! : item.sampleURL
      ..description = info.isEmpty ? title : '$title\n${info.join(' · ')}'
      ..score = voters.isNotEmpty ? voters : item.score
      ..tagsList = tags
      ..isUpdated = true;
    item.possibleMediaType.value = null;
    item.mediaType.value = MediaType.video;
    for (final MapEntry<TagType, List<String>> e in byType.entries) {
      addTagsWithType(e.value, e.key);
    }

    if (remember && learned.isNotEmpty) {
      // `record` replaces rows, and would clobber an index row's count.
      final Map<String, BooruTagEntry> known = await BooruTagStore.lookup(booru, [for (final e in learned) e.name]);
      final List<BooruTagEntry> fresh = [
        for (final e in learned)
          if (!known.containsKey(e.name)) e,
      ];
      if (fresh.isNotEmpty) await BooruTagStore.record(booru, fresh);
    }
    return null;
  }

  @override
  String? tagNamespace(String tag) {
    if (tag.startsWith('artist:')) return 'artist';
    if (tag.startsWith('category:')) return 'category';
    if (tag.startsWith('uploader:')) return 'uploader';
    if (tag.startsWith('type:') || tag == 'hd') return 'type';
    return 'tag';
  }

  @override
  List<(String key, String label)> get tagNamespaceSections => const [
    ('artist', 'Artists'),
    ('category', 'Categories'),
    ('uploader', 'Uploader'),
    ('type', 'Type & quality'),
    ('tag', 'Tags'),
  ];

  /// The term the search accepts for a snapshot row.
  static String termFor(BooruTagEntry e) =>
      (e.namespace.isEmpty || e.namespace == 'tag') ? e.name : '${e.namespace}:${e.name}';

  /// No autocomplete on the site: answer from the snapshot (Tag builder
  /// pulls, video pages) and this session's ids.
  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(
    String input, {
    CancelToken? cancelToken,
  }) async {
    final String q = Rule34VideoQuery.normalizeName(input);
    if (q.isEmpty) return const Right([]);
    final List<TagSuggestion> out = [];
    final Set<String> seen = {};
    void push(String term, TagType type, int count) {
      if (seen.add(term)) out.add(TagSuggestion(tag: term, type: type, count: count));
    }

    for (final String key in Rule34VideoQuery.groupIds.keys) {
      if (key.startsWith(q) || 'type:$key'.startsWith(q)) push('type:$key', TagType.meta, 0);
    }
    for (final String name in knownTagIds.keys) {
      if (name.startsWith(q)) push(name, TagType.none, 0);
    }
    try {
      for (final BooruTagEntry e in await BooruTagStore.browse(booru, query: q, limit: 25)) {
        push(termFor(e), e.tagType, e.count);
      }
    } catch (e) {
      return Left(ResponseError(message: 'local tag lookup failed: $e'));
    }
    return Right(out.take(30).toList());
  }
}
