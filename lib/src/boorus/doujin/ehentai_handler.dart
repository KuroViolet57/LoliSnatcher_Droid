import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_query.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
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

  /// Forward-only paging: the cursor each page starts at, per query.
  final Map<int, String> _cursors = {};
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
    _paceChain = Future.value();
    _bulkPaceChain = Future.value();
    _warnedFor = '';
  }

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
  Map<int, String> _cursorsFor(String source) {
    if (_cursorQuery != source) {
      _cursors.clear();
      _cursorQuery = source;
    }
    return _cursors;
  }

  @visibleForTesting
  void rememberCursor({required int page, required String cursor}) => _cursors[page] = cursor;

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
    final EHentaiSearch search = EHentaiQuery.parse(qualifyQuery(tags));
    if (search.error != null) {
      errorString = search.error!;
      locked = true;
      return '';
    }
    final Map<int, String> cursors = _cursorsFor(search.source);
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
    if (cursor != null) _cursorsFor(EHentaiQuery.parse(currentTags).source)[page + 1] = cursor;
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

  /// Page number -> image key from one gallery block.
  static Map<int, String> pageKeysFromHtml(String html) {
    final dom.Document doc = parse(html);
    final Map<int, String> keys = {};
    for (final dom.Element a in doc.querySelectorAll('#gdt a[href]')) {
      final RegExpMatch? m = _pageHref.firstMatch(a.attributes['href'] ?? '');
      if (m != null) keys[int.parse(m.group(3)!)] = m.group(1)!;
    }
    return keys;
  }

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

    final Map<int, String> keys = pageKeysFromHtml(html);
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
      blockSize: blockSize,
      newerVersions: newer,
      parentGid: parentGid,
      parentToken: parentToken,
      cover: cover,
    );
    _galleries[gid] = gallery;
    (_pageKeys[gid] ??= {}).addAll(keys);
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

  BooruItem _pageShell({required String gid, required int page, required String cover, required String postURL}) {
    final BooruItem item = BooruItem(
      fileURL: cover,
      sampleURL: cover,
      thumbnailURL: cover,
      tagsList: const [],
      postURL: postURL,
      serverId: '${gid}_$page',
      fileNameExtras: '${gid}_${page.toString().padLeft(4, '0')}',
    );
    item.possibleMediaType.value = MediaType.image;
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  BooruItem pageItem({required String gid, required String token, required int page, required String key, required String cover}) {
    _tokens[gid] = token;
    (_pageKeys[gid] ??= {})[page] = key;
    return _pageShell(gid: gid, page: page, cover: cover, postURL: '$site/s/$key/$gid-$page');
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
              ? pageItem(gid: gid, token: token, page: n, key: gallery.pageKeys[n]!, cover: cover)
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
        await _pace(bulk: bulk);
        final ({String? body, String? error}) block = await _sitePage(blockUrl('$site/g/$gid/$token/', ph.block), cancelToken: cancelToken);
        if (block.body == null) return block.error;
        final Map<int, String> keys = pageKeysFromHtml(block.body!);
        if (keys.isEmpty) return 'the gallery block listed no pages (the page changed?)';
        (_pageKeys[gid] ??= {}).addAll(keys);
        key = keys[page];
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
    return DoujinRecommendationEngine.rank(source, candidates, count: limit, sourceArtist: artist);
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
