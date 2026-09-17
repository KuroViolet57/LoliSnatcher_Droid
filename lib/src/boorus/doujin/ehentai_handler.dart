import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_query.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/sprite_tile_image.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// What a gallery page says about a gallery.
class EHentaiGallery {
  const EHentaiGallery({
    required this.gid,
    required this.token,
    required this.title,
    required this.titleJpn,
    required this.category,
    required this.uploader,
    required this.posted,
    required this.language,
    required this.pages,
    required this.favorited,
    required this.rating,
    required this.tags,
    required this.pageKeys,
    required this.pageThumbs,
    required this.blockSize,
    required this.newerVersions,
    required this.parentGid,
    required this.parentToken,
    required this.cover,
  });

  final String gid;
  final String token;
  final String title;
  final String titleJpn;
  final String category;
  final String uploader;
  final String posted;
  final String language;
  final int pages;
  final int favorited;
  final String rating;
  final List<Tag> tags;

  /// Page number -> image key, for the pages the fetched block showed.
  final Map<int, String> pageKeys;

  /// Page number -> thumbnail for the same pages: a tile of the block's
  /// sprite strip (`strip.webp#xywh=x,y,w,h`), or an image URL in an
  /// account's individual-image mode. Strip links expire within days, so
  /// these are session data (`BooruItem.transientThumbnailURL`).
  final Map<int, String> pageThumbs;

  /// Pages per gallery page (20, or 40 with the account setting).
  final int blockSize;
  final List<(String gid, String token)> newerVersions;
  final String? parentGid;
  final String? parentToken;
  final String cover;
}

/// e-hentai.org / exhentai.org — the galleries system, probed anonymously
/// from the PC on 2026-09-09.
///
/// ## Reading the site
/// - Listing: `/?f_search=…&f_cats=…&inline_set=dm_e` (the extended view,
///   so every row carries its tags): 25 rows of `table.itg.glte tr`, thumb
///   in `td.gl1e`, category / posted / rating / uploader / "N pages" in
///   `.gl3e`, title `.glink`, tags `div.gt|gtl|gtw[title="ns:name"]`. The
///   next page is a cursor, `#unext` → `?next=<gid>`; there is no page N.
///   "Found about N results" is the total.
/// - Gallery `/g/<gid>/<token>/`: `#gn` / `#gj` titles, `#gdd` rows, tags in
///   `#taglist` by namespace, one `/s/<key>/<gid>-<n>` link per page in
///   `#gdt` — 20 per block, `?p=N` (0-based) for the next block, `p.gpc`
///   "Showing 1 - 20 of 1,997 images" for the total.
/// - Page `/s/<key>/<gid>-<n>`: `#img` on a hath.network node (volunteer
///   H@H clients — they must never see a session cookie), `var showkey`,
///   `nl('…')` reload key. With a showkey, `api.php` `showpage` answers the
///   image for any page of the gallery without the HTML. `gdata` gives a
///   gallery's metadata for up to 25 gids.
/// - The multi-page viewer is blank for anonymous clients. Thumbnails on
///   ehgt.org are open; `s.exhentai.org` needs cookies, and the same path
///   exists on ehgt.org.
///
/// ## Pages are resolved on open
/// One request per page is the site's shape, so `loadItem(gallery)` reads
/// ONE gallery page and registers N page items marked `needToLoadItem`;
/// the reader (and the snatcher) call `loadItem(page)` when a page is
/// shown, which fetches its block of keys once and then the image through
/// `showpage`. Requests are paced 300 ms apart: the site bans an address
/// for "excessive pageloads".
///
/// ## Login
/// The forum login lives in a WebView (`EHentaiLoginPage`); the two forum
/// cookies go to `EHentaiSessionHandler` and are removed from the shared
/// jar, because the jar's cookies ride on every media request of a source.
/// exhentai.org is used only when the session has a usable `igneous`.
class EHentaiHandler extends BooruHandler with DoujinNamespacedTags {
  EHentaiHandler(super.booru, super.limit) {
    // A session left in the jar by a crash mid-visit, an older build, or the
    // app's generic in-app browser would otherwise ride along on requests
    // this source makes to third parties.
    EHentaiSessionHandler.instance.scrubJarOnce();
  }

  static const String defaultSite = 'https://e-hentai.org';
  static const String exSite = 'https://exhentai.org';
  static const String apiUrl = 'https://api.e-hentai.org/api.php';
  static const String variantEHentai = 'e-hentai';
  static const String variantExHentai = 'exhentai';

  /// Rows per listing page, fixed by the site.
  static const int pageSize = 25;

  /// Space between two page resolutions.
  static const Duration pagePace = Duration(milliseconds: 300);

  /// The display mode the extended listing needs. `?inline_set=dm_e` only
  /// SETS this cookie and redirects — a client that sends its own Cookie
  /// header on every request (this one does, for the session) never keeps
  /// it and is served the compact rows, which carry no tags. Observed
  /// 2026-09-09: the site answers `sl=dm_2` to `inline_set=dm_e`.
  static const String displayCookie = 'sl=dm_2';

  /// Session memory shared by every handler instance: gallery tokens,
  /// page keys, showkeys, the galleries read.
  static final Map<String, String> _tokens = {};
  static final Map<String, Map<int, String>> _pageKeys = {};
  static final Map<String, int> _blockSizes = {};
  static final Map<String, String> _showkeys = {};
  static final Map<String, EHentaiGallery> _galleries = {};

  /// Page number -> thumbnail per gallery, learned a block at a time (r32).
  static final Map<String, Map<int, String>> _pageThumbs = {};

  /// `gid|block` of every block read, so a block that carried keys but no
  /// tiles (an account's image mode, a changed page) is not read again for
  /// every tile that scrolls by.
  static final Set<String> _blocksRead = {};

  /// Block reads queued or in flight, so twenty tiles of one block share one
  /// request; the lane each was queued on, and the HTTP request itself once
  /// it has gone out (a read that starts while another is on the wire rides
  /// along instead of asking twice).
  static final Map<String, Future<String?>> _blockFetches = {};
  static final Map<String, bool> _blockLane = {};
  static final Map<String, Future<String?>> _blockRequest = {};

  /// Who is waiting for a block: a request is skipped once every waiter has
  /// scrolled away before its turn.
  static final Map<String, List<CancelToken>> _blockWaiters = {};

  /// When a block last failed to read, so tiles do not hammer a refusal.
  static final Map<String, int> _blockFailedAt = {};
  static const Duration blockRetryAfter = Duration(seconds: 30);

  /// The tail of the paced queue: every request chains onto it, so pages
  /// opened at once (the reader preloads two or three slides) go out one
  /// after another instead of all seeing the same old timestamp.
  static Future<void> _paceChain = Future.value();

  /// A second lane for a whole-book download, so queueing 2,000 pages does
  /// not put the page the person is looking at behind all of them.
  static Future<void> _bulkPaceChain = Future.value();

  /// The session state the "exhentai cannot be read" line was last said
  /// for. `site` is read several times per request, so the line is said
  /// once — and again after a login or logout changes the state.
  static String _warnedFor = '';

  /// The access re-check running behind a page, if any (see [usingExHentai]).
  static Future<void>? _recheck;

  @visibleForTesting
  Future<void>? get pendingRecheck => _recheck;

  /// Forward-only paging: the cursor each page starts at, per query.
  /// Next-page cursors per query, in the order the queries were last used.
  final Map<String, Map<int, String>> _cursorsByQuery = {};
  String _cursorQuery = '';

  /// Test seam: answers requests in place of the network.
  @visibleForTesting
  Future<({int status, String body, String finalUrl})> Function(String url, {String? postJson})? fetcher;

  static String? tokenFor(String gid) => _tokens[gid];

  @visibleForTesting
  static void resetForTests() {
    _tokens.clear();
    _pageKeys.clear();
    _blockSizes.clear();
    _showkeys.clear();
    _galleries.clear();
    _pageThumbs.clear();
    _blocksRead.clear();
    _blockFetches.clear();
    _blockLane.clear();
    _blockRequest.clear();
    _blockWaiters.clear();
    _blockFailedAt.clear();
    _paceChain = Future.value();
    _bulkPaceChain = Future.value();
    _warnedFor = '';
  }

  /// Lets a test retry a block without waiting out [blockRetryAfter].
  @visibleForTesting
  static void forgetBlockFailuresForTests() => _blockFailedAt.clear();

  // ── site and session ─────────────────────────────────────────────────

  /// True when the per-source choice is exhentai AND the session can read it.
  bool get usingExHentai {
    String variant;
    try {
      variant = SourceSettingsHandler.instance.siteVariant(booru) ?? variantEHentai;
    } catch (_) {
      variant = variantEHentai;
    }
    if (variant != variantExHentai) return false;
    if (EHentaiSessionHandler.instance.hasExHentai) return true;
    final EHentaiSessionHandler session = EHentaiSessionHandler.instance;
    // r36: a refusal is not for ever — the account matures, the address
    // changes. Asked again behind this page, once a day at most; the page
    // after a real answer reads exhentai.
    if (session.needsRecheck && _recheck == null) {
      _recheck = session
          .fetchIgneous()
          .then((r) {
            Logger.Inst().log('exhentai access re-checked: ${r.$2}', className, 'usingExHentai', LogTypes.booruHandlerInfo);
          })
          .catchError((Object e) {
            Logger.Inst().log('exhentai access re-check failed: $e', className, 'usingExHentai', LogTypes.booruHandlerInfo);
          })
          .whenComplete(() {
            _recheck = null;
          });
    }
    final String state = '${session.memberId ?? '-'}|${session.igneous ?? '-'}';
    if (_warnedFor == state) return false;
    _warnedFor = state;
    Logger.Inst().log(
      'exhentai chosen but the session cannot read it (not logged in, or no access); using e-hentai',
      className,
      'usingExHentai',
      LogTypes.booruHandlerInfo,
    );
    return false;
  }

  String get site => usingExHentai ? exSite : defaultSite;

  /// Post URLs are always spelled on e-hentai.org, whichever host served
  /// them: favourites, history, the per-source blacklist and the download
  /// folder are all keyed by that URL, and the same gallery must not split
  /// in two when the site choice changes. Fetches use [site].
  static String galleryUrl(String gid, String token) => '$defaultSite/g/$gid/$token/';

  /// The Tag builder's chips. The site publishes no tag index, so the lists
  /// come from the community tag database — see [EHentaiTagCatalog].
  @override
  late final TagCatalogSource? tagCatalog = EHentaiTagCatalog(this);

  @override
  List<(String value, String label)> get siteVariants => const [
    (variantEHentai, 'e-hentai.org'),
    (variantExHentai, 'exhentai.org (needs the login)'),
  ];

  // Reads neither field: the login is the WebView page, kept in its own file.
  @override
  bool get usesUserId => false;
  @override
  bool get usesApiKey => false;

  @override
  bool get hasReader => true;
  @override
  bool get hasLoadItemSupport => true;
  @override
  bool get shouldUpdateIteminTagView => true;
  @override
  bool get hasSizeData => false;
  @override
  bool get hasNativeOrSupport => false;
  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);
  @override
  List<String> get animatedPreviewFilters => const [];
  @override
  String validateTags(String tags) => tags.trim();
  @override
  bool get hasAccountBlacklist => true;

  @override
  Map<String, String> getHeaders() => {
    'Accept': 'text/html,application/xml,application/json',
    'User-Agent': Tools.browserUserAgent,
    'Referer': '$site/',
    'Cookie': '${EHentaiSessionHandler.instance.cookieHeader(exhentai: usingExHentai)}; $displayCookie',
  };

  /// Images come from hath nodes and thumbnails from ehgt.org: a Referer is
  /// harmless, a cookie would be a session handed to a stranger.
  @override
  Map<String, String> getMediaHeaders() => {'Referer': '$site/'};

  /// Even if a browser session for e-hentai.org ends up in the shared jar
  /// (the in-app browser, an older build), it must never reach a hath node.
  @override
  bool get sendsJarCookiesToMedia => false;

  @override
  String makePostURL(String id) => galleryUrl(id, _tokens[id] ?? '');

  @override
  List<(String key, String label)> get tagNamespaceSections => const [
    ('language', 'Language'),
    ('parody', 'Parodies'),
    ('character', 'Characters'),
    ('group', 'Groups'),
    ('artist', 'Artists'),
    ('cosplayer', 'Cosplayers'),
    ('female', 'Female'),
    ('male', 'Male'),
    ('mixed', 'Mixed'),
    ('other', 'Other'),
    ('category', 'Category'),
    ('uploader', 'Uploader'),
    ('reclass', 'Reclass'),
    ('temp', 'Temp'),
  ];

  @override
  DoujinFilterSpec get doujinFilters => DoujinFilterSpec([
    const DoujinFilterGroup(
      key: 'sort',
      label: 'Sort',
      defaultValue: 'latest',
      options: [DoujinFilterOption('latest', 'Latest'), DoujinFilterOption('popular', 'Popular')],
    ),
    DoujinFilterGroup(
      key: 'category',
      label: 'Categories',
      multi: true,
      options: [for (final String k in EHentaiQuery.categoryBits.keys) DoujinFilterOption(k, k)],
    ),
    const DoujinFilterGroup(key: 'language', label: 'Language', options: DoujinFilters.commonLanguages),
  ]);

  @override
  List<MetaTag> availableMetaTags() => [
    MetaTagWithValues(
      name: 'Category',
      keyName: 'category',
      isFree: true,
      values: [for (final k in EHentaiQuery.categoryBits.keys) MetaTagValue(name: k, value: k)],
    ),
    MetaTagWithValues(
      name: 'Minimum rating',
      keyName: 'rating',
      values: [for (int n = 2; n <= 5; n++) MetaTagValue(name: '$n stars', value: '$n')],
    ),
    StringMetaTag(name: 'Pages (count or range, e.g. 10-50)', keyName: 'pages', isFree: true),
    StringMetaTag(name: 'Uploader', keyName: 'uploader', isFree: true),
  ];

  @override
  String? relatedVersionsQuery(BooruItem item) {
    final String id = item.serverId ?? '';
    return id.isEmpty ? null : 'related:$id';
  }

  // ── the query protocol ───────────────────────────────────────────────

  static final RegExp _protocol = RegExp(r'^(id|related|recommend):(.+)$', caseSensitive: false);

  ({String kind, String id})? _parseProtocol(String tags) {
    final match = _protocol.firstMatch(tags.trim());
    if (match == null) return null;
    return (kind: match.group(1)!.toLowerCase(), id: match.group(2)!.trim());
  }

  /// Puts back the namespace of every bare tag this source has seen, so a
  /// tapped chip searches the site's TAG (`language:"english"\$`) and not
  /// every title containing the word. Words the source never saw stay words.
  @visibleForTesting
  String qualifyQuery(String tags) => [
    for (final String token in EHentaiQuery.tokenize(tags))
      if (token.contains(':') || token.startsWith('"'))
        token
      else if (token.startsWith('-') && !token.substring(1).contains(':'))
        '-${qualifyTag(token.substring(1))}'
      else
        qualifyTag(token),
  ].join(' ');

  /// 1-based listing page for the handler's counter (first fetch -1 or 0).
  int get page => pageNum < 0 ? 1 : pageNum + 1;

  /// The cursors of one query; a different query starts over.
  ///
  /// Keyed by the query AS TYPED, never by the parsed or qualified form:
  /// `makeURL` qualifies bare tags before parsing, and parsing page 1 is
  /// what teaches those namespaces — so the qualified spelling can change
  /// between the two calls of a single fetch. Keying on it made the two
  /// sides clear each other's map, and every tag search stopped after one
  /// page (r30, reported).
  ///
  /// One map per query, kept for the last few queries: the doujin For You
  /// feed asks one handler several facets in turn, and a map cleared on
  /// every change of query could never serve page 2 of any of them (r33).
  Map<int, String> _cursorsFor(String source) {
    _cursorQuery = source;
    final Map<int, String>? known = _cursorsByQuery.remove(source);
    final Map<int, String> cursors = known ?? {};
    _cursorsByQuery[source] = cursors;
    while (_cursorsByQuery.length > _cursorQueriesKept) {
      _cursorsByQuery.remove(_cursorsByQuery.keys.first);
    }
    return cursors;
  }

  static const int _cursorQueriesKept = 32;

  @visibleForTesting
  void rememberCursor({required int page, required String cursor}) => _cursorsFor(_cursorQuery)[page] = cursor;

  @override
  String makeURL(String tags) {
    final protocol = _parseProtocol(tags);
    if (protocol != null) {
      if (protocol.kind == 'id') {
        final String url = _galleryUrlFor(protocol.id);
        if (url.isEmpty) {
          errorString = 'e-hentai needs the gallery token as well: open the gallery from a list once, or use id:<gid>/<token>.';
          return '';
        }
        return url;
      }
      // related/recommend do their own fetching below; this is the cheapest
      // valid 200 on the site (the front page is a full listing, and this
      // site bans for excessive page loads).
      return '$site/robots.txt';
    }
    // r37: `sort:popular` is the site's own popular page — one list, no
    // search, no pages. With a search the search wins. The term is the
    // app's and is never sent (the site would read it as a title word).
    // The cursor map is keyed by the query AS TYPED (see _cursorsFor); the
    // sort term is taken out only of what is parsed, and only when there
    // is one, so a query without it keeps its exact spelling.
    final String sort = DoujinFilters.selected(tags, 'sort').lastOrNull ?? '';
    final String searchTags = sort.isEmpty ? tags : DoujinFilters.strip(tags, 'sort');
    if (sort == 'popular' && searchTags.trim().isEmpty) {
      if (page > 1) {
        locked = true;
        return '';
      }
      return '$site/popular';
    }
    final EHentaiSearch search = EHentaiQuery.parse(qualifyQuery(searchTags));
    if (search.error != null) {
      errorString = search.error!;
      locked = true;
      return '';
    }
    final Map<int, String> cursors = _cursorsFor(tags.trim());
    final int p = page;
    if (p == 1) return EHentaiQuery.listingUrl(site, search);
    final String? cursor = cursors[p];
    if (cursor == null) {
      // The site links the next page with a cursor; the last page has none.
      // That is the end of the results, not a failure — lock instead of
      // showing the grid an error it cannot act on.
      locked = true;
      return '';
    }
    return EHentaiQuery.listingUrl(site, search, cursor: cursor);
  }

  /// `id:<gid>` with a remembered token, or `id:<gid>/<token>`.
  String _galleryUrlFor(String id) {
    final List<String> parts = id.split('/');
    final String gid = parts.first.trim();
    final String token = parts.length > 1 ? parts[1].trim() : (_tokens[gid] ?? '');
    if (gid.isEmpty || token.isEmpty) return '';
    _tokens[gid] = token;
    return '$site/g/$gid/$token/';
  }

  // ── listing ──────────────────────────────────────────────────────────

  static final RegExp _galleryHref = RegExp(r'/g/(\d+)/([0-9a-f]+)/?');
  static final RegExp _nextParam = RegExp(r'[?&]next=(\d+)');
  static final RegExp _resultCount = RegExp(r'(?:Found|Showing)\s+(?:about\s+)?([\d,]+)\s+results?', caseSensitive: false);
  static final RegExp _pagesText = RegExp(r'([\d,]+)\s+pages?');
  static final RegExp _ratingPos = RegExp(r'background-position:\s*(-?\d+)px\s+(-?\d+)px');

  /// exhentai's thumbnail host wants cookies; ehgt.org serves the same path.
  static String thumbUrl(String url) => url.replaceFirst(RegExp(r'^https?://s\.exhentai\.org/'), 'https://ehgt.org/');

  static String? nextCursor(String html) {
    final dom.Document doc = parse(html);
    final String href = doc.querySelector('#unext')?.attributes['href'] ?? '';
    return _nextParam.firstMatch(href)?.group(1);
  }

  static int? resultCount(String html) {
    final RegExpMatch? m = _resultCount.firstMatch(html);
    if (m == null) return null;
    return int.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  /// The star widget's sprite offset: x steps of 16 px from 5 stars down,
  /// y = -21 px for a half star.
  static String? ratingFromStyle(String? style) {
    if (style == null) return null;
    final RegExpMatch? m = _ratingPos.firstMatch(style);
    if (m == null) return null;
    final int x = int.parse(m.group(1)!);
    final int y = int.parse(m.group(2)!);
    double stars = 5 + x / 16;
    if (y <= -21) stars -= 0.5;
    if (stars < 0) stars = 0;
    return stars == stars.roundToDouble() ? stars.toInt().toString() : stars.toString();
  }

  /// One extended-view listing into finished items.
  List<BooruItem> itemsFromListing(String html) {
    final dom.Document doc = parse(html);
    final List<BooruItem> out = [];
    for (final dom.Element row in doc.querySelectorAll('table.itg tr')) {
      final dom.Element? thumbCell = row.querySelector('td.gl1e');
      final dom.Element? infoCell = row.querySelector('td.gl2e');
      if (thumbCell == null || infoCell == null) continue;
      final String href = thumbCell.querySelector('a[href]')?.attributes['href'] ?? '';
      final RegExpMatch? g = _galleryHref.firstMatch(href);
      if (g == null) continue;
      final String gid = g.group(1)!;
      final String token = g.group(2)!;
      _tokens[gid] = token;
      final dom.Element? img = thumbCell.querySelector('img');
      final String thumb = thumbUrl(img?.attributes['src'] ?? '');
      final String title = (infoCell.querySelector('.glink')?.text ?? img?.attributes['title'] ?? '').trim();
      final dom.Element? meta = infoCell.querySelector('.gl3e');
      final String category = (meta?.querySelector('.cn')?.text ?? '').trim();
      final String posted = (meta?.querySelector('#posted_$gid')?.text ?? '').trim();
      final String uploader = (meta?.querySelector('a[href*="/uploader/"]')?.text ?? '').trim();
      final String? rating = ratingFromStyle(meta?.querySelector('.ir')?.attributes['style']);
      int? pages;
      for (final dom.Element div in meta?.children ?? const <dom.Element>[]) {
        final RegExpMatch? m = _pagesText.firstMatch(div.text);
        if (m != null) pages = int.tryParse(m.group(1)!.replaceAll(',', ''));
      }
      final List<Tag> tags = [];
      if (category.isNotEmpty) tags.add(namespacedTag(category, 'category'));
      for (final dom.Element t in infoCell.querySelectorAll('div.gt, div.gtl, div.gtw')) {
        final String full = t.attributes['title'] ?? t.text;
        final int colon = full.indexOf(':');
        if (colon <= 0) continue;
        tags.add(namespacedTag(full.substring(colon + 1), full.substring(0, colon)));
      }
      final BooruItem item = BooruItem(
        fileURL: thumb,
        sampleURL: thumb,
        thumbnailURL: thumb,
        tagsList: tags,
        postURL: galleryUrl(gid, token),
        serverId: gid,
        description: title,
        uploaderName: uploader.isEmpty ? null : uploader,
        postDate: posted.isEmpty ? null : posted,
        postDateFormat: posted.isEmpty ? null : 'yyyy-MM-dd HH:mm',
        score: rating,
      );
      if (pages != null) item.fileCountHint.value = pages;
      out.add(item);
    }
    return out;
  }

  /// Nothing but whitespace: exhentai's answer to a client it does not know.
  static bool isBlankExHentai(String body) => body.trim().isEmpty;

  static bool looksLikeLoginBounce(String finalUrl, String body) =>
      finalUrl.contains('bounce_login.php') || body.contains('<title>E-Hentai.org Login</title>');

  @override
  FutureOr<List> parseListFromResponse(dynamic response) async {
    final protocol = _parseProtocol(currentTags);
    if (protocol != null && protocol.kind != 'id') {
      return protocol.kind == 'related' ? await _fetchRelated(protocol.id) : await _fetchRecommended(protocol.id);
    }
    final String body = response.data?.toString() ?? '';
    String finalUrl = '';
    try {
      finalUrl = response.realUri.toString();
    } catch (_) {}
    if (isBlankExHentai(body)) {
      errorString = usingExHentai
          ? 'exhentai.org answered an empty page: the session is not accepted (log in again, or the account has no exhentai access).'
          : 'e-hentai answered an empty page. Try again in a moment.';
      return const [];
    }
    if (looksLikeLoginBounce(finalUrl, body)) {
      errorString = 'e-hentai asked for a login. Log in from Source settings.';
      return const [];
    }
    if (protocol != null && protocol.kind == 'id') {
      final RegExpMatch? g = _galleryHref.firstMatch(finalUrl.isEmpty ? _galleryUrlFor(protocol.id) : finalUrl);
      if (g == null) return const [];
      final EHentaiGallery gallery = galleryFromHtml(body, gid: g.group(1)!, token: g.group(2)!);
      return [_itemFromGallery(gallery)];
    }
    final List<BooruItem> items = itemsFromListing(body);
    if (items.isEmpty && body.contains('class="itg')) {
      errorString = 'e-hentai served a listing the app cannot read (its display mode is not the extended one). '
          'Open the site settings from Source settings and pick the Extended display, then try again.';
      Logger.Inst().log(
        'listing parsed 0 rows; table classes: ${RegExp('<table class="(itg[^"]*)"').allMatches(body).map((m) => m.group(1)).toSet()}',
        className,
        'parseListFromResponse',
        LogTypes.booruHandlerParseFailed,
      );
    }
    final String? cursor = nextCursor(body);
    if (cursor != null) _cursorsFor(currentTags.trim())[page + 1] = cursor;
    final int? total = resultCount(body);
    if (total != null) totalCount.value = total;
    return items;
  }

  /// [parseListFromResponse] already builds finished items.
  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) =>
      responseItem is BooruItem ? responseItem : null;

  // ── gallery page ─────────────────────────────────────────────────────

  static final RegExp _pageHref = RegExp(r'/s/([0-9a-f]+)/(\d+)-(\d+)');
  static final RegExp _showing = RegExp(r'Showing\s+([\d,]+)\s*-\s*([\d,]+)\s+of\s+([\d,]+)\s+images', caseSensitive: false);

  static int _int(String s) => int.tryParse(s.replaceAll(',', '')) ?? 0;

  static final RegExp _tileSize = RegExp(r'width:\s*(\d+)px;\s*height:\s*(\d+)px');
  static final RegExp _tileBackground = RegExp(r'''url\(['"]?([^'")]+)['"]?\)\s+(-?\d+)(?:px)?\s+(-?\d+)(?:px)?''');

  /// Page number -> image key and thumbnail from one gallery block.
  ///
  /// The default layout draws each thumbnail as one tile of a sprite strip,
  /// a div styled `width:200px;height:277px;background:transparent
  /// url(https://NODE.hath.network/c2/SEGMENT/GID-BLOCK.webp) -200px 0
  /// no-repeat` — the tile is `#xywh=200,0,200,277` of that strip, its
  /// height the div's own (the strip is as tall as the block's tallest
  /// tile; the y offset is written `0`, without `px`). An account's
  /// individual-image mode puts an `img` in the anchor instead; an anchor
  /// with neither gives a key alone.
  static Map<int, ({String key, String? thumb})> pageEntriesFromHtml(String html) {
    final dom.Document doc = parse(html);
    final Map<int, ({String key, String? thumb})> entries = {};
    for (final dom.Element a in doc.querySelectorAll('#gdt a[href]')) {
      final RegExpMatch? m = _pageHref.firstMatch(a.attributes['href'] ?? '');
      if (m == null) continue;
      entries[int.parse(m.group(3)!)] = (key: m.group(1)!, thumb: _thumbOf(a));
    }
    return entries;
  }

  static String? _thumbOf(dom.Element a) {
    final String? style = a.querySelector('div[style]')?.attributes['style'];
    if (style != null) {
      final RegExpMatch? size = _tileSize.firstMatch(style);
      final RegExpMatch? background = _tileBackground.firstMatch(style);
      if (size != null && background != null) {
        return SpriteTile(
          thumbUrl(background.group(1)!.trim()),
          Rect.fromLTWH(
            -int.parse(background.group(2)!).toDouble(),
            -int.parse(background.group(3)!).toDouble(),
            int.parse(size.group(1)!).toDouble(),
            int.parse(size.group(2)!).toDouble(),
          ),
        ).encode();
      }
    }
    final String? img = a.querySelector('img[src]')?.attributes['src']?.trim();
    return (img == null || img.isEmpty) ? null : thumbUrl(img);
  }

  /// Page number -> image key from one gallery block.
  static Map<int, String> pageKeysFromHtml(String html) =>
      pageEntriesFromHtml(html).map((int page, ({String key, String? thumb}) e) => MapEntry(page, e.key));

  /// `Showing 1 - 20 of 1,997 images` -> (first, last, total).
  static ({int first, int last, int total})? showingRange(String html) {
    final RegExpMatch? m = _showing.firstMatch(html);
    if (m == null) return null;
    return (first: _int(m.group(1)!), last: _int(m.group(2)!), total: _int(m.group(3)!));
  }

  /// `…/g/<gid>/<token>/` block N is `?p=N` (0-based); block 0 is the page itself.
  static String blockUrl(String galleryUrl, int block) => block <= 0 ? galleryUrl : '$galleryUrl?p=$block';

  EHentaiGallery galleryFromHtml(String html, {required String gid, required String token}) {
    final dom.Document doc = parse(html);
    _tokens[gid] = token;
    final String title = (doc.querySelector('#gn')?.text ?? '').trim();
    final String titleJpn = (doc.querySelector('#gj')?.text ?? '').trim();
    final String category = (doc.querySelector('#gdc')?.text ?? '').trim();
    final String uploader = (doc.querySelector('#gdn')?.text ?? '').trim();
    String posted = '';
    String language = '';
    int pages = 0;
    int favorited = 0;
    String? parentGid;
    String? parentToken;
    for (final dom.Element tr in doc.querySelectorAll('#gdd tr')) {
      final String label = (tr.querySelector('.gdt1')?.text ?? '').trim().toLowerCase();
      final dom.Element? valueCell = tr.querySelector('.gdt2');
      final String value = (valueCell?.text ?? '').trim();
      if (label.startsWith('posted')) {
        posted = value;
      } else if (label.startsWith('language')) {
        language = value.replaceAll(RegExp(r'\s*TR\s*$'), '').trim();
      } else if (label.startsWith('length')) {
        pages = _int(_pagesText.firstMatch(value)?.group(1) ?? '0');
      } else if (label.startsWith('favorited')) {
        favorited = _int(RegExp(r'[\d,]+').firstMatch(value)?.group(0) ?? '0');
      } else if (label.startsWith('parent')) {
        final RegExpMatch? m = _galleryHref.firstMatch(valueCell?.querySelector('a')?.attributes['href'] ?? '');
        if (m != null) {
          parentGid = m.group(1);
          parentToken = m.group(2);
        }
      }
    }
    final String ratingText = (doc.querySelector('#rating_label')?.text ?? '').trim();
    final String rating = RegExp(r'[\d.]+').firstMatch(ratingText)?.group(0) ?? '';

    final List<Tag> tags = [];
    if (category.isNotEmpty) tags.add(namespacedTag(category, 'category'));
    if (uploader.isNotEmpty) tags.add(namespacedTag(uploader, 'uploader'));
    for (final dom.Element tr in doc.querySelectorAll('#taglist tr')) {
      final String ns = (tr.querySelector('td.tc')?.text ?? '').trim().replaceAll(':', '');
      if (ns.isEmpty) continue;
      for (final dom.Element t in tr.querySelectorAll('div[id^="td_"]')) {
        final String name = (t.querySelector('a')?.text ?? t.text).trim();
        if (name.isEmpty) continue;
        tags.add(namespacedTag(name, ns));
      }
    }

    final Map<int, ({String key, String? thumb})> entries = pageEntriesFromHtml(html);
    final Map<int, String> keys = entries.map((int page, ({String key, String? thumb}) e) => MapEntry(page, e.key));
    final Map<int, String> thumbs = {
      for (final MapEntry<int, ({String key, String? thumb})> e in entries.entries)
        if (e.value.thumb != null) e.key: e.value.thumb!,
    };
    final ({int first, int last, int total})? range = showingRange(html);
    if (pages == 0 && range != null) pages = range.total;
    if (pages == 0) pages = keys.length;
    final int blockSize = range != null && range.first == 1 && range.last > 0 ? range.last : (keys.isEmpty ? 20 : keys.length);

    final List<(String, String)> newer = [];
    for (final dom.Element a in doc.querySelectorAll('#gnd a[href]')) {
      final RegExpMatch? m = _galleryHref.firstMatch(a.attributes['href'] ?? '');
      if (m != null) newer.add((m.group(1)!, m.group(2)!));
    }
    final String cover = thumbUrl(doc.querySelector('#gd1 div')?.attributes['style'] != null
        ? (RegExp(r'url\(([^)]+)\)').firstMatch(doc.querySelector('#gd1 div')!.attributes['style']!)?.group(1) ?? '')
        : '');

    final EHentaiGallery gallery = EHentaiGallery(
      gid: gid,
      token: token,
      title: title,
      titleJpn: titleJpn,
      category: category,
      uploader: uploader,
      posted: posted,
      language: language,
      pages: pages,
      favorited: favorited,
      rating: rating,
      tags: tags,
      pageKeys: keys,
      pageThumbs: thumbs,
      blockSize: blockSize,
      newerVersions: newer,
      parentGid: parentGid,
      parentToken: parentToken,
      cover: cover,
    );
    _galleries[gid] = gallery;
    (_pageKeys[gid] ??= {}).addAll(keys);
    (_pageThumbs[gid] ??= {}).addAll(thumbs);
    _blocksRead.add('$gid|0');
    _blockSizes[gid] = blockSize;
    return gallery;
  }

  BooruItem _itemFromGallery(EHentaiGallery g) {
    final BooruItem item = BooruItem(
      fileURL: g.cover,
      sampleURL: g.cover,
      thumbnailURL: g.cover,
      tagsList: g.tags,
      postURL: galleryUrl(g.gid, g.token),
      serverId: g.gid,
      description: g.titleJpn.isEmpty ? g.title : '${g.title}\n${g.titleJpn}',
      uploaderName: g.uploader.isEmpty ? null : g.uploader,
      postDate: g.posted.isEmpty ? null : g.posted,
      postDateFormat: g.posted.isEmpty ? null : 'yyyy-MM-dd HH:mm',
      score: g.rating.isEmpty ? null : g.rating,
    );
    item.fileCountHint.value = g.pages;
    return item;
  }

  // ── page items ───────────────────────────────────────────────────────

  static final RegExp _placeholder = RegExp(r'/g/(\d+)/([0-9a-f]+)/\?p=(\d+)#page-(\d+)$');

  /// A page whose block is not read yet. Carries everything `loadItem`
  /// needs to fetch it: gallery, block, page number.
  String pagePlaceholderUrl({required String gid, required String token, required int page, int blockSize = 20}) =>
      '$site/g/$gid/$token/?p=${(page - 1) ~/ blockSize}#page-$page';

  static ({String gid, String token, int block, int page})? parsePagePlaceholder(String url) {
    final RegExpMatch? m = _placeholder.firstMatch(url);
    if (m == null) return null;
    return (gid: m.group(1)!, token: m.group(2)!, block: int.parse(m.group(3)!), page: int.parse(m.group(4)!));
  }

  static ({String key, String gid, int page})? parsePageViewUrl(String url) {
    if (url.contains('#page-')) return null;
    final RegExpMatch? m = _pageHref.firstMatch(url);
    if (m == null) return null;
    return (key: m.group(1)!, gid: m.group(2)!, page: int.parse(m.group(3)!));
  }

  /// A page before it is resolved. The persisted thumbnail is the gallery
  /// cover (stable); the page's own tile, when its block has been read, is
  /// the session-only [BooruItem.transientThumbnailURL].
  BooruItem _pageShell({required String gid, required int page, required String cover, required String postURL, String? thumb}) {
    final BooruItem item = BooruItem(
      fileURL: cover,
      sampleURL: cover,
      thumbnailURL: cover,
      tagsList: const [],
      postURL: postURL,
      serverId: '${gid}_$page',
      fileNameExtras: '${gid}_${page.toString().padLeft(4, '0')}',
    );
    item.transientThumbnailURL = thumb ?? _pageThumbs[gid]?[page];
    item.possibleMediaType.value = MediaType.image;
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  BooruItem pageItem({
    required String gid,
    required String token,
    required int page,
    required String key,
    required String cover,
    String? thumb,
  }) {
    _tokens[gid] = token;
    (_pageKeys[gid] ??= {})[page] = key;
    return _pageShell(gid: gid, page: page, cover: cover, postURL: '$site/s/$key/$gid-$page', thumb: thumb);
  }

  BooruItem placeholderItem({required String gid, required String token, required int page, required String cover}) {
    _tokens[gid] = token;
    return _pageShell(
      gid: gid,
      page: page,
      cover: cover,
      postURL: pagePlaceholderUrl(gid: gid, token: token, page: page, blockSize: _blockSizes[gid] ?? 20),
    );
  }

  // ── page view / showpage ─────────────────────────────────────────────

  static final RegExp _showkeyVar = RegExp(r'var\s+showkey\s*=\s*"([^"]+)"');
  static final RegExp _nlCall = RegExp(r"nl\('([^']+)'\)");
  static final RegExp _dims = RegExp(r'::\s*(\d+)\s*x\s*(\d+)\s*::');

  static ({String? imageUrl, String? showkey, String? reloadKey, int? width, int? height, bool quotaExceeded}) parsePageHtml(String html) {
    final dom.Document doc = parse(html);
    final String? src = doc.querySelector('#img')?.attributes['src'];
    final RegExpMatch? dims = _dims.firstMatch(html);
    return (
      imageUrl: src,
      showkey: _showkeyVar.firstMatch(html)?.group(1),
      reloadKey: _nlCall.firstMatch(html)?.group(1),
      width: dims == null ? null : int.tryParse(dims.group(1)!),
      height: dims == null ? null : int.tryParse(dims.group(2)!),
      quotaExceeded: src != null && src.contains('509.gif'),
    );
  }

  static ({String? imageUrl, int? width, int? height}) parseShowpage(Map<String, dynamic> json) {
    final String i3 = json['i3']?.toString() ?? '';
    final String? src = parse(i3).querySelector('#img')?.attributes['src'] ?? RegExp('src="([^"]+)"').firstMatch(i3)?.group(1);
    return (
      imageUrl: src,
      width: int.tryParse(json['x']?.toString() ?? ''),
      height: int.tryParse(json['y']?.toString() ?? ''),
    );
  }

  static String _extOf(String url) {
    final String path = Uri.tryParse(url)?.path ?? url;
    final String last = path.split('/').last;
    final int dot = last.lastIndexOf('.');
    final String ext = dot < 0 ? '' : last.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'avif'}.contains(ext) ? ext : 'jpg';
  }

  // ── requests ─────────────────────────────────────────────────────────

  Future<({int status, String body, String finalUrl})> _fetch(String url, {String? postJson, CancelToken? cancelToken}) async {
    if (fetcher != null) return fetcher!(url, postJson: postJson);
    if (postJson != null) {
      final Response response = await DioNetwork.post(
        url,
        data: postJson,
        headers: {...getHeaders(), 'Content-Type': 'application/json', 'Accept': 'application/json'},
        options: Options(validateStatus: (_) => true),
        cancelToken: cancelToken,
      );
      return (status: response.statusCode ?? 0, body: _bodyOf(response), finalUrl: url);
    }
    final Response response = await DioNetwork.get(
      url,
      headers: getHeaders(),
      options: Options(validateStatus: (_) => true),
      cancelToken: cancelToken,
    );
    return (status: response.statusCode ?? 0, body: _bodyOf(response), finalUrl: response.realUri.toString());
  }

  static String _bodyOf(Response response) {
    final data = response.data;
    if (data == null) return '';
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  /// A gallery or page fetch, with the content-warning interstitial stepped
  /// over and the two refusal shapes named.
  Future<({String? body, String? error})> _sitePage(String url, {CancelToken? cancelToken}) async {
    var r = await _fetch(url, cancelToken: cancelToken);
    if (r.status == 200 && r.body.contains('Content Warning') && !url.contains('nw=')) {
      r = await _fetch(url.contains('?') ? '$url&nw=always' : '$url?nw=always', cancelToken: cancelToken);
    }
    if (r.status != 200) return (body: null, error: 'e-hentai answered ${r.status}');
    if (isBlankExHentai(r.body)) {
      return (
        body: null,
        error: usingExHentai
            ? 'exhentai.org answered an empty page: the session is not accepted (log in again, or the account has no exhentai access).'
            : 'e-hentai answered an empty page. Try again in a moment.',
      );
    }
    if (looksLikeLoginBounce(r.finalUrl, r.body)) return (body: null, error: 'e-hentai asked for a login. Log in from Source settings.');
    return (body: r.body, error: null);
  }

  Future<void> _pace({bool bulk = false}) {
    if (bulk) {
      final Future<void> mine = _bulkPaceChain.then((_) => Future<void>.delayed(pagePace));
      _bulkPaceChain = mine;
      return mine;
    }
    final Future<void> mine = _paceChain.then((_) => Future<void>.delayed(pagePace));
    _paceChain = mine;
    return mine;
  }

  /// Runs [body] in its lane's next slot. Unlike [_pace] the wait comes
  /// AFTER the body, so a body that decides not to fetch costs the lane
  /// nothing, and the next slot waits for the request to be answered.
  Future<T> _paced<T>(bool bulk, Future<T> Function() body) {
    final Future<void> before = bulk ? _bulkPaceChain : _paceChain;
    final Future<T> mine = before.then((_) => body());
    final Future<void> after = mine.then<void>(
      (_) => Future<void>.delayed(pagePace),
      onError: (Object _) => Future<void>.delayed(pagePace),
    );
    if (bulk) {
      _bulkPaceChain = after;
    } else {
      _paceChain = after;
    }
    return mine;
  }

  // ── loadItem: a gallery, or one page ─────────────────────────────────

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    dynamic cancelToken,
    bool withCapcthaCheck = false,
    // A whole-book download queues thousands of page fetches; they wait in
    // their own lane so the page being read is not stuck behind them.
    bool bulk = false,
  }) async {
    try {
      if (parsePagePlaceholder(item.postURL) != null || parsePageViewUrl(item.postURL) != null) {
        final String? error = await _resolvePage(item, bulk: bulk, cancelToken: cancelToken is CancelToken ? cancelToken : null);
        return error == null ? (item: item, failed: false, error: null) : (item: null, failed: true, error: error);
      }
      final RegExpMatch? g = _galleryHref.firstMatch(item.postURL);
      if (g == null) return (item: null, failed: true, error: 'not an e-hentai gallery: ${item.postURL}');
      final String gid = g.group(1)!;
      final String token = g.group(2)!;
      final String galleryUrl = '$site/g/$gid/$token/';
      final ({String? body, String? error}) page0 = await _sitePage(galleryUrl);
      if (page0.body == null) return (item: null, failed: true, error: page0.error);
      final EHentaiGallery gallery = galleryFromHtml(page0.body!, gid: gid, token: token);
      if (gallery.pages == 0) return (item: null, failed: true, error: 'the gallery page listed no pages (removed, or the page changed)');
      final String cover = item.thumbnailURL.isNotEmpty ? item.thumbnailURL : gallery.cover;
      final List<BooruItem> pages = [
        for (int n = 1; n <= gallery.pages; n++)
          gallery.pageKeys.containsKey(n)
              ? pageItem(gid: gid, token: token, page: n, key: gallery.pageKeys[n]!, cover: cover, thumb: gallery.pageThumbs[n])
              : placeholderItem(gid: gid, token: token, page: n, cover: cover),
      ];
      item
        ..tagsList = gallery.tags
        ..description = gallery.titleJpn.isEmpty ? gallery.title : '${gallery.title}\n${gallery.titleJpn}'
        ..uploaderName = gallery.uploader.isEmpty ? item.uploaderName : gallery.uploader
        ..postDate = gallery.posted.isEmpty ? item.postDate : gallery.posted
        ..postDateFormat = gallery.posted.isEmpty ? item.postDateFormat : 'yyyy-MM-dd HH:mm'
        ..score = gallery.rating.isEmpty ? item.score : gallery.rating
        ..isUpdated = true;
      item.fileCountHint.value = gallery.pages;
      ReaderHandler.instance.registerBook(item, pages);
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log('loadItem failed: $e', className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  /// One page: its key (fetching the block once), then the image through the
  /// showpage API when the gallery's showkey is known, the page view
  /// otherwise (which also teaches the showkey).
  Future<String?> _resolvePage(BooruItem item, {bool bulk = false, CancelToken? cancelToken}) async {
    String gid;
    int page;
    String? key;
    String? token;
    final ({String key, String gid, int page})? view = parsePageViewUrl(item.postURL);
    if (view != null) {
      gid = view.gid;
      page = view.page;
      key = view.key;
      token = _tokens[gid];
    } else {
      final ({String gid, String token, int block, int page}) ph = parsePagePlaceholder(item.postURL)!;
      gid = ph.gid;
      page = ph.page;
      token = ph.token;
      key = _pageKeys[gid]?[page];
      if (key == null) {
        final String? error = await _fetchBlock(gid, token, ph.block, bulk: bulk, waiter: cancelToken);
        if (error != null) return error;
        key = _pageKeys[gid]?[page];
        if (key == null) return 'page $page is not in its block (the gallery was edited?)';
      }
      item.postURL = '$site/s/$key/$gid-$page';
    }

    String? imageUrl;
    int? width;
    int? height;
    final String? showkey = _showkeys[gid];
    if (showkey != null) {
      await _pace(bulk: bulk);
      try {
        final r = await _fetch(
          apiUrl,
          postJson: jsonEncode({'method': 'showpage', 'gid': int.parse(gid), 'page': page, 'imgkey': key, 'showkey': showkey}),
          cancelToken: cancelToken,
        );
        if (r.status == 200) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map<String, dynamic> && decoded['i3'] != null) {
            final info = parseShowpage(decoded);
            imageUrl = info.imageUrl;
            width = info.width;
            height = info.height;
          }
        }
      } catch (e) {
        Logger.Inst().log('showpage failed for $gid-$page: $e; using the page view', className, '_resolvePage', LogTypes.booruHandlerInfo);
      }
    }
    if (imageUrl == null) {
      await _pace(bulk: bulk);
      final ({String? body, String? error}) view = await _sitePage('$site/s/$key/$gid-$page', cancelToken: cancelToken);
      if (view.body == null) return view.error;
      final info = parsePageHtml(view.body!);
      if (info.quotaExceeded) return 'e-hentai image quota exceeded for this address (509). Wait, or log in.';
      if (info.showkey != null) _showkeys[gid] = info.showkey!;
      imageUrl = info.imageUrl;
      width = info.width;
      height = info.height;
    }
    if (imageUrl == null || imageUrl.isEmpty) return 'no image on the page view (blocked, or the page changed)';
    if (imageUrl.contains('509.gif')) return 'e-hentai image quota exceeded for this address (509). Wait, or log in.';
    item
      ..fileURL = imageUrl
      ..sampleURL = imageUrl
      ..fileExt = _extOf(imageUrl)
      ..fileWidth = width?.toDouble()
      ..fileHeight = height?.toDouble()
      ..isUpdated = true;
    if (width != null && height != null && width > 0 && height > 0) item.fileAspectRatio = width / height;
    item.possibleMediaType.value = null;
    item.mediaType.value = MediaType.image;
    return null;
  }

  // ── the detail cover: the first page (r69) ────────────────────────────

  /// The site's covers are 250 px wide and nothing bigger exists on its
  /// thumbnail host; the detail page shows the first page instead, resolved
  /// exactly as the reader resolves it (paced, showkey learned on the way),
  /// once - a resolved page is not fetched again, and the reader starts warm.
  /// Per-source switch, on by default; nothing before the gallery is loaded.
  /// The item's name is the page's, so the reader finds the bytes in the
  /// media cache instead of asking the hath node again.
  @override
  Future<BooruItem?> detailCoverImage(BooruItem item) async {
    if (!SourceSettingsHandler.instance.detailCoverFromFirstPage(booru)) return null;
    final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
    if (pages == null || pages.isEmpty) return null;
    final BooruItem first = pages.first;
    if (!first.mediaType.value.isImage || first.fileURL.isEmpty || first.fileURL == first.thumbnailURL) {
      final r = await loadItem(item: first);
      if (r.failed || r.item == null || r.item!.fileURL.isEmpty) return null;
    }
    final String url = first.fileURL;
    if (url.isEmpty || url == first.thumbnailURL) return null;
    final BooruItem cover = BooruItem(
      fileURL: url,
      sampleURL: url,
      thumbnailURL: url,
      tagsList: const [],
      postURL: item.postURL,
      serverId: item.serverId,
      fileExt: first.fileExt,
      // The page's own name: the detail cover and the reader share one
      // cached file, so the hath node serves the bytes once.
      fileNameExtras: first.fileNameExtras,
      fileWidth: first.fileWidth,
      fileHeight: first.fileHeight,
    );
    if (first.fileAspectRatio != null) cover.fileAspectRatio = first.fileAspectRatio;
    cover.mediaType.value = MediaType.image;
    return cover;
  }

  // ── page thumbnails: one strip per block, read as its pages come into view ──

  /// A page's tile of its block's sprite strip: known already when its
  /// block was read, else read now — on the bulk lane, once for every tile
  /// of the block that is asking, skipped when they have all scrolled away.
  /// Never throws: a page that cannot learn its tile keeps showing the cover.
  @override
  Future<void> ensurePageThumbnail(BooruItem page, {CancelToken? cancelToken}) async {
    try {
      final ({String gid, String token, int block, int page})? placeholder = parsePagePlaceholder(page.postURL);
      final ({String key, String gid, int page})? view = placeholder == null ? parsePageViewUrl(page.postURL) : null;
      if (placeholder == null && view == null) return;
      final String gid = placeholder?.gid ?? view!.gid;
      final int n = placeholder?.page ?? view!.page;
      final String? token = placeholder?.token ?? _tokens[gid];
      if (token == null) return;
      // A page in view form names no block; the block size is only known
      // once its gallery page was read this session (20, or 40 with an
      // account setting) — a guess would read, and mark read, the wrong block.
      if (placeholder == null && !_blockSizes.containsKey(gid)) return;
      final int block = placeholder?.block ?? (n - 1) ~/ _blockSizes[gid]!;
      String? thumb = _pageThumbs[gid]?[n];
      if (thumb == null) {
        final String id = '$gid|$block';
        if (_blocksRead.contains(id)) return;
        final int? failedAt = _blockFailedAt[id];
        if (failedAt != null && DateTime.now().millisecondsSinceEpoch - failedAt < blockRetryAfter.inMilliseconds) return;
        final String? error = await _fetchBlock(gid, token, block, bulk: true, waiter: cancelToken);
        if (error != null) {
          Logger.Inst().log('block $block of $gid not read for its thumbnails: $error', className, 'ensurePageThumbnail', LogTypes.booruHandlerInfo);
          return;
        }
        thumb = _pageThumbs[gid]?[n];
      }
      if (thumb != null) page.transientThumbnailURL = thumb;
    } catch (e, s) {
      Logger.Inst().log('ensurePageThumbnail failed: $e', className, 'ensurePageThumbnail', LogTypes.exception, s: s);
    }
  }

  /// Reads gallery block [block] once — the keys and thumbnails of its pages
  /// — for however many callers ask at the same time; the registered book's
  /// pages of that block learn their tiles on the way. Null on success, else
  /// the message.
  ///
  /// [waiter] is the caller's interest, not the request's cancel token: a
  /// shared request must not be killed because one tile scrolled away. When
  /// every waiter has cancelled before the block's turn, the request is
  /// skipped and the slot costs nothing.
  Future<String?> _fetchBlock(String gid, String token, int block, {bool bulk = false, CancelToken? waiter}) {
    final String id = '$gid|$block';
    // A caller without a token (Save all, a detail page resolving a page) is
    // an interest that never leaves.
    (_blockWaiters[id] ??= []).add(waiter ?? CancelToken());
    final Future<String?>? queued = _blockFetches[id];
    // A page being read must not wait behind tiles: when the block is only
    // QUEUED on the bulk lane, read it on the priority lane now; the queued
    // read stands down when its turn comes (or rides along if the request
    // has already gone out).
    final bool overtake = queued != null && !bulk && _blockLane[id] == true && !_blockRequest.containsKey(id);
    if (queued != null && !overtake) return queued;
    final Future<String?> mine = _paced<String?>(bulk, () => _readBlock(gid, token, block, id));
    if (overtake) return mine;
    _blockLane[id] = bulk;
    return _blockFetches[id] = mine.whenComplete(() {
      _blockFetches.remove(id);
      _blockLane.remove(id);
      _blockWaiters.remove(id);
    });
  }

  /// One lane slot's worth of work for block [id]: nothing when the block was
  /// read meanwhile or nobody waits any more, the request in flight when
  /// another read already sent it, else the request.
  Future<String?> _readBlock(String gid, String token, int block, String id) async {
    if (_blocksRead.contains(id)) return null;
    final Future<String?>? onTheWire = _blockRequest[id];
    if (onTheWire != null) return onTheWire;
    final List<CancelToken> waiters = _blockWaiters[id] ?? const [];
    if (waiters.isNotEmpty && waiters.every((CancelToken t) => t.isCancelled)) return 'cancelled before block $block was read';
    final Future<String?> request = _requestBlock(gid, token, block, id);
    _blockRequest[id] = request;
    try {
      return await request;
    } finally {
      _blockRequest.removeWhere((String key, _) => key == id);
    }
  }

  Future<String?> _requestBlock(String gid, String token, int block, String id) async {
    try {
      final ({String? body, String? error}) r = await _sitePage(blockUrl('$site/g/$gid/$token/', block));
      if (r.body == null) {
        _blockFailedAt[id] = DateTime.now().millisecondsSinceEpoch;
        return r.error;
      }
      final Map<int, ({String key, String? thumb})> entries = pageEntriesFromHtml(r.body!);
      if (entries.isEmpty) {
        _blockFailedAt[id] = DateTime.now().millisecondsSinceEpoch;
        return 'the gallery block listed no pages (the page changed?)';
      }
      final Map<int, String> keys = _pageKeys[gid] ??= {};
      final Map<int, String> thumbs = _pageThumbs[gid] ??= {};
      for (final MapEntry<int, ({String key, String? thumb})> e in entries.entries) {
        keys[e.key] = e.value.key;
        if (e.value.thumb != null) thumbs[e.key] = e.value.thumb!;
      }
      _blocksRead.add(id);
      _blockFailedAt.remove(id);
      _applyThumbs(gid, token, entries.keys);
      return null;
    } catch (e) {
      // Offline, a timeout: as much a refusal as a 4xx for the backoff's sake.
      _blockFailedAt[id] = DateTime.now().millisecondsSinceEpoch;
      return 'block $block of $gid could not be read: $e';
    }
  }

  /// The tile [ensurePageThumbnail] gave [page] could not be loaded: its
  /// strip link expired (they last days), or the strip changed under it.
  /// The whole block shares that strip, so the block's tiles go, the block is
  /// no longer "read", and — held for [blockRetryAfter] so twenty failing
  /// tiles do not each trigger a re-read — the next visit reads a fresh one.
  @override
  void forgetPageThumbnail(BooruItem page) {
    final ({String gid, String token, int block, int page})? placeholder = parsePagePlaceholder(page.postURL);
    final ({String key, String gid, int page})? view = placeholder == null ? parsePageViewUrl(page.postURL) : null;
    if (placeholder == null && view == null) return;
    final String gid = placeholder?.gid ?? view!.gid;
    final int n = placeholder?.page ?? view!.page;
    final int size = _blockSizes[gid] ?? 20;
    final int block = placeholder?.block ?? (n - 1) ~/ size;
    final int first = block * size + 1;
    final int last = first + size - 1;
    final String id = '$gid|$block';
    _pageThumbs[gid]?.removeWhere((int p, _) => p >= first && p <= last);
    _blocksRead.remove(id);
    _blockFailedAt[id] = DateTime.now().millisecondsSinceEpoch;
    page.transientThumbnailURL = null;
    final String? token = placeholder?.token ?? _tokens[gid];
    if (token == null) return;
    final List<BooruItem>? book = ReaderHandler.instance.books[galleryUrl(gid, token)] ?? ReaderHandler.instance.books['$site/g/$gid/$token/'];
    if (book == null) return;
    for (int p = first; p <= last && p <= book.length; p++) {
      book[p - 1].transientThumbnailURL = null;
    }
  }

  /// Hands the registered book's pages [pageNumbers] their tiles.
  void _applyThumbs(String gid, String token, Iterable<int> pageNumbers) {
    final Map<int, String>? thumbs = _pageThumbs[gid];
    // Books are keyed by the gallery item's postURL: the default host from a
    // listing, or the session's host.
    final List<BooruItem>? book = ReaderHandler.instance.books[galleryUrl(gid, token)] ?? ReaderHandler.instance.books['$site/g/$gid/$token/'];
    if (thumbs == null || book == null) return;
    for (final int n in pageNumbers) {
      final String? thumb = thumbs[n];
      if (thumb == null || n < 1 || n > book.length) continue;
      book[n - 1].transientThumbnailURL = thumb;
    }
  }

  // ── gdata, related, recommended ──────────────────────────────────────

  /// Items out of an `api.php` `gdata` answer.
  List<BooruItem> itemsFromGdata(Map<String, dynamic> json) {
    final List<BooruItem> out = [];
    final list = json['gmetadata'];
    if (list is! List) return out;
    for (final entry in list) {
      if (entry is! Map || entry['error'] != null) continue;
      final String gid = entry['gid'].toString();
      final String token = entry['token']?.toString() ?? '';
      if (token.isEmpty) continue;
      _tokens[gid] = token;
      final List<Tag> tags = [];
      final String category = entry['category']?.toString() ?? '';
      if (category.isNotEmpty) tags.add(namespacedTag(category, 'category'));
      for (final t in (entry['tags'] as List? ?? const [])) {
        final String full = t.toString();
        final int colon = full.indexOf(':');
        if (colon > 0) {
          tags.add(namespacedTag(full.substring(colon + 1), full.substring(0, colon)));
        } else {
          tags.add(namespacedTag(full, 'other'));
        }
      }
      final String thumb = thumbUrl(entry['thumb']?.toString() ?? '');
      final String title = entry['title']?.toString() ?? '';
      final String titleJpn = entry['title_jpn']?.toString() ?? '';
      final int? posted = int.tryParse(entry['posted']?.toString() ?? '');
      final BooruItem item = BooruItem(
        fileURL: thumb,
        sampleURL: thumb,
        thumbnailURL: thumb,
        tagsList: tags,
        postURL: galleryUrl(gid, token),
        serverId: gid,
        description: titleJpn.isEmpty ? title : '$title\n$titleJpn',
        uploaderName: entry['uploader']?.toString(),
        postDate: posted?.toString(),
        postDateFormat: posted == null ? null : 'unix',
        score: entry['rating']?.toString(),
      );
      final int? count = int.tryParse(entry['filecount']?.toString() ?? '');
      if (count != null) item.fileCountHint.value = count;
      out.add(item);
    }
    return out;
  }

  Future<List<BooruItem>> _gdata(List<(String gid, String token)> gids) async {
    if (gids.isEmpty) return const [];
    final r = await _fetch(
      apiUrl,
      postJson: jsonEncode({
        'method': 'gdata',
        'gidlist': [
          for (final g in gids.take(25)) [int.parse(g.$1), g.$2],
        ],
        'namespace': 1,
      }),
    );
    if (r.status != 200) return const [];
    final decoded = jsonDecode(r.body);
    return decoded is Map<String, dynamic> ? itemsFromGdata(decoded) : const [];
  }

  Future<EHentaiGallery?> _galleryFor(String gid) async {
    final EHentaiGallery? cached = _galleries[gid];
    if (cached != null) return cached;
    final String? token = _tokens[gid];
    if (token == null) return null;
    final ({String? body, String? error}) page0 = await _sitePage('$site/g/$gid/$token/');
    if (page0.body == null) return null;
    return galleryFromHtml(page0.body!, gid: gid, token: token);
  }

  /// Newer versions and the parent, as the gallery page lists them.
  Future<List<BooruItem>> _fetchRelated(String gid) async {
    final EHentaiGallery? g = await _galleryFor(gid);
    if (g == null) return const [];
    final List<(String, String)> ids = [
      ...g.newerVersions,
      if (g.parentGid != null && g.parentToken != null) (g.parentGid!, g.parentToken!),
    ];
    return _gdata(ids);
  }

  Future<List<BooruItem>> _fetchRecommended(String gid) async {
    final EHentaiGallery? g = await _galleryFor(gid);
    if (g == null) return const [];
    final BooruItem source = _itemFromGallery(g);
    final List<String> queries = [
      for (final Tag t in g.tags.where((t) => t.tagType != TagType.meta && tagNamespace(t.fullString) != 'uploader').take(4))
        qualifyTag(t.fullString),
      DoujinRecommendationEngine.baseTitle(g.title),
    ].where((q) => q.trim().length > 2).toList();
    final List<BooruItem> candidates = [];
    final Set<String> seen = {source.postURL};
    for (final String query in queries) {
      try {
        final r = await _fetch(EHentaiQuery.listingUrl(site, EHentaiQuery.parse(query)));
        if (r.status != 200) continue;
        for (final BooruItem item in itemsFromListing(r.body)) {
          if (seen.add(item.postURL)) candidates.add(item);
        }
      } catch (_) {
        // One dead query means fewer candidates, never a failed section.
      }
    }
    String? artist;
    for (final Tag tag in source.tagsList) {
      if (tag.tagType == TagType.artist) {
        artist = tag.fullString;
        break;
      }
    }
    return DoujinRecommendationEngine.rankPersonal(handler: this, source, candidates, count: limit, sourceArtist: artist);
  }

  // ── My Tags → blacklist ──────────────────────────────────────────────

  /// Tags the account hides (or weights below zero) on `/mytags`, as
  /// `namespace:name`. Written from the page's known shape; UNVERIFIED — no
  /// account was available where this was built.
  static List<String> blacklistFromMyTags(String html) {
    final dom.Document doc = parse(html);
    final List<String> out = [];
    for (final dom.Element row in doc.querySelectorAll('.usertag, [id^="usertag_"]')) {
      final dom.Element? link = row.querySelector('a[href*="/tag/"]');
      String name = (link?.text ?? '').trim();
      if (name.isEmpty) {
        final String href = link?.attributes['href'] ?? '';
        name = Uri.decodeComponent(href.split('/tag/').last).replaceAll('+', ' ');
      }
      if (name.isEmpty) continue;
      final bool hidden = row.querySelector('input[id^="taghide_"]')?.attributes.containsKey('checked') ?? false;
      final int weight = int.tryParse(row.querySelector('input[id^="tagweight_"]')?.attributes['value'] ?? '') ?? 0;
      if (!hidden && weight >= 0) continue;
      // Bare, like every tag this source stores: `matchesBlacklist` strips the
      // namespace off the item's tag, so a `female:x` entry would never match.
      final int colon = name.indexOf(':');
      final String token = normalizeDoujinTagName(colon > 0 ? name.substring(colon + 1) : name);
      if (token.isNotEmpty && !out.contains(token)) out.add(token);
    }
    return out;
  }

  @override
  Future<(bool, String, List<String>)> fetchAccountBlacklist() async {
    if (!EHentaiSessionHandler.instance.isLoggedIn) return (false, 'Log in first (Source settings → Log in).', const <String>[]);
    try {
      final r = await _fetch('$site/mytags');
      if (r.status != 200) return (false, 'e-hentai answered ${r.status} for My Tags.', const <String>[]);
      if (looksLikeLoginBounce(r.finalUrl, r.body)) return (false, 'e-hentai asked for a login again; log in from Source settings.', const <String>[]);
      final List<String> names = blacklistFromMyTags(r.body);
      return (true, '${names.length} hidden tags on My Tags.', names);
    } catch (e) {
      return (false, 'My Tags could not be read: $e', const <String>[]);
    }
  }
}
