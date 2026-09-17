import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_recommendation_engine.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_query.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/eahentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// eahentai.com — read through the JSON API its own pages use (r69; the
/// paths come from the site's scripts, the shapes from fetching them on
/// 2026-09-17). See [EaHentaiQuery] for the endpoints.
///
/// Every answer lists a gallery with its tags, author, parody, characters and
/// kind, so cards are complete at once - the HTML listing carried none of
/// that and cost a gallery-page fetch per card. An album answer lists the
/// pages, so the reader needs one request. The HTML parsers stay as the
/// fallback for an answer that is not JSON.
///
/// ## Login
/// `POST /api/auth/login` with `{"login": <username or email>, "password"}`
/// answers `{"accessToken"}`; the token goes to the site's API as a bearer
/// header and lives in [EaHentaiSessionHandler]. The app used to POST a form
/// to the HTML `/login` route, which answers 405 to everything.
class EaHentaiHandler extends BooruHandler with DoujinNamespacedTags {
  EaHentaiHandler(super.booru, super.limit);

  // Site login: username/email + password (see signIn). Optional.
  @override
  String? get userIdLabel => 'Username or email (optional)';
  @override
  String? get apiKeyLabel => 'Password (optional)';

  static const String _site = EaHentaiQuery.site;
  static const String _cdn = 'https://i.eahentai.com/file/ea-gallery';

  /// Test seam: answers requests in place of the network.
  @visibleForTesting
  Future<({int status, String body, String finalUrl})> Function(String url, {String? postJson})? fetcher;

  /// What the last login attempt said, for the settings page.
  String? loginMessage;

  /// The full first page of every gallery seen this session, by id: the
  /// detail cover (see [detailCoverImage]) without another request.
  static final Map<String, String> _firstPages = {};

  /// Credentials the site refused, and when: a refused pair is not sent
  /// again for [loginRetryAfter] (the base class would otherwise log in on
  /// every feed page, against a real auth endpoint).
  static final Map<String, int> _failedLogins = {};
  static const Duration loginRetryAfter = Duration(minutes: 10);

  String get _credentialKey => Object.hash(booru.baseURL, booru.userID, booru.apiKey).toString();

  @visibleForTesting
  static void forgetFailedLoginsForTests() {
    _failedLogins.clear();
    _firstPages.clear();
  }

  @override
  bool get hasReader => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  bool get hasNativeOrSupport => false;

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  List<String> get animatedPreviewFilters => const [];

  /// The API is asked with the token when there is one. The base class's
  /// listing fetch uses these too; they only ever reach the site itself.
  @override
  Map<String, String> getHeaders() => {
    ...super.getHeaders(),
    'Accept': 'application/json, text/html',
    'Referer': '$_site/',
    ...EaHentaiSessionHandler.instance.bearerHeaders,
  };

  /// eahentai's CDN serves without a referer today; sending the one a browser
  /// would send keeps a future hotlink rule from silently blanking covers.
  /// Never the token: the images are not the API.
  @override
  Map<String, String> getMediaHeaders() => {'Referer': '$_site/'};

  @override
  String validateTags(String tags) => tags.trim();

  @override
  String makePostURL(String id) => '$_site/a/$id';

  // ── login ─────────────────────────────────────────────────────────────

  @override
  bool get hasSignInSupport => true;

  @override
  Future<bool> canSignIn() async {
    if (!((booru.userID?.isNotEmpty ?? false) && (booru.apiKey?.isNotEmpty ?? false))) return false;
    final int? failedAt = _failedLogins[_credentialKey];
    return failedAt == null || DateTime.now().millisecondsSinceEpoch - failedAt > loginRetryAfter.inMilliseconds;
  }

  /// A token counts only for the credentials it was obtained with: a changed
  /// username or password logs in again instead of keeping the old account.
  @override
  Future<bool> isSignedIn() async {
    final EaHentaiSessionHandler session = EaHentaiSessionHandler.instance;
    if (!session.isLoggedIn) return false;
    final String? loginName = session.loginName;
    return loginName == null || loginName == booru.userID;
  }

  @override
  Future<bool> signIn() async {
    if (!await canSignIn()) return false;
    final EaHentaiSessionHandler session = EaHentaiSessionHandler.instance;
    try {
      final r = await _fetch(
        '$_site/api/auth/login',
        postJson: jsonEncode({'login': booru.userID, 'password': booru.apiKey}),
      );
      final dynamic decoded = _decode(r.body);
      final String? token = decoded is Map ? decoded['accessToken']?.toString() : null;
      if (r.status != 200 || token == null || token.isEmpty) {
        _failedLogins[_credentialKey] = DateTime.now().millisecondsSinceEpoch;
        loginMessage = 'eahentai refused the login: ${_errorText(decoded, r.status)}';
        Logger.Inst().log('POST /api/auth/login answered ${r.status}: ${_errorText(decoded, r.status)}', className, 'signIn', LogTypes.booruHandlerInfo);
        return false;
      }
      _failedLogins.remove(_credentialKey);
      session.store(token: token, username: booru.userID, loginName: booru.userID);
      final String? name = await _whoAmI();
      if (name != null) session.setUsername(name);
      loginMessage = 'Logged in to eahentai as ${session.username ?? booru.userID}.';
      Logger.Inst().log('POST /api/auth/login answered 200; token kept', className, 'signIn', LogTypes.booruHandlerInfo);
      return true;
    } catch (e) {
      loginMessage = 'eahentai login failed: $e';
      Logger.Inst().log(loginMessage!, className, 'signIn', LogTypes.booruHandlerFetchFailed);
      return false;
    }
  }

  /// The account's name from `auth/me`, whatever field the site spells it in.
  Future<String?> _whoAmI() async {
    try {
      final r = await _fetch('$_site/api/auth/me');
      if (r.status != 200) return null;
      final dynamic me = _decode(r.body);
      if (me is! Map) return null;
      for (final String key in const ['username', 'userName', 'name', 'login', 'displayName']) {
        final String value = me[key]?.toString() ?? '';
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return null;
  }

  /// The site's own words for a refusal: `{"error": "..."}` on a wrong
  /// password, a validation object on a malformed call.
  static String _errorText(dynamic decoded, int status) {
    if (decoded is Map) {
      final String? error = decoded['error']?.toString();
      if (error != null && error.isNotEmpty) return error;
      final dynamic errors = decoded['errors'];
      if (errors is Map) {
        final List<String> lines = [
          for (final v in errors.values) v is List ? v.join(' ') : v.toString(),
        ];
        if (lines.isNotEmpty) return lines.join(' ');
      }
      final String? title = decoded['title']?.toString();
      if (title != null && title.isNotEmpty) return title;
    }
    return 'status $status';
  }

  @override
  Future<dynamic> signOut({bool fromError = false}) async {
    EaHentaiSessionHandler.instance.logout();
    _failedLogins.remove(_credentialKey);
    loginMessage = null;
    return true;
  }

  // ── the doujin query protocol ─────────────────────────────────────────

  static final RegExp _protocol = RegExp(r'^(id|related|recommend):(.+)$', caseSensitive: false);

  static ({String kind, String id})? _parseProtocol(String tags) {
    final match = _protocol.firstMatch(tags.trim());
    if (match == null) return null;
    return (kind: match.group(1)!.toLowerCase(), id: match.group(2)!.trim());
  }

  /// 1-based listing page: the counter starts at -1 and is stepped before
  /// each fetch, so 0 is the first page.
  int get _page => pageNum < 0 ? 1 : pageNum + 1;

  @override
  String makeURL(String tags) {
    final protocol = _parseProtocol(tags);
    if (protocol != null) {
      if (protocol.kind == 'id') return '${EaHentaiQuery.api}/album/${protocol.id}';
      // related/recommend fetch for themselves; this is the cheapest valid
      // answer for the base class to fetch and ignore.
      return '${EaHentaiQuery.api}/latest/?page=0&take=1';
    }
    final EaHentaiRequest request = EaHentaiQuery.parse(tags, page: _page, take: limit);
    if (request.error != null) {
      errorString = 'eahentai: ${request.error}';
      locked = true;
      return '';
    }
    if (request.atEnd) {
      locked = true;
      return '';
    }
    return request.url;
  }

  // ── the JSON answers ──────────────────────────────────────────────────

  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static String _cdnUrl(String? uri) {
    final String u = (uri ?? '').trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http')) return u;
    return '$_cdn/${u.startsWith('/') ? u.substring(1) : u}';
  }

  /// The gallery entries of an answer: `{items: [...]}` (latest, search) or a
  /// bare array (popular, random, album). Text is decoded first; HTML falls
  /// back to the old listing parser.
  @visibleForTesting
  List<BooruItem> itemsFromApi(dynamic json) {
    dynamic data = json;
    if (data is String) {
      if (data.trimLeft().startsWith('<')) return itemsFromListing(data);
      data = _decode(data);
    }
    final List entries = data is Map ? (data['items'] as List? ?? const []) : (data is List ? data : const []);
    final List<BooruItem> out = [];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final BooruItem? item = itemFromAlbum(entry.cast<String, dynamic>());
      if (item != null) out.add(item);
    }
    return out;
  }

  /// `totalResults` of a search or latest answer; popular and random say
  /// nothing.
  @visibleForTesting
  int? totalFromApi(dynamic json) {
    dynamic data = json;
    if (data is String) data = _decode(data);
    if (data is! Map) return null;
    return int.tryParse(data['totalResults']?.toString() ?? '');
  }

  /// One album entry as the app's item: cover from `thumbnailUri`, the full
  /// first page from `imageUri` as the sample, the pipe-separated tags,
  /// author, parody and characters in their namespaces, the kind as the
  /// category, and the site's one language.
  @visibleForTesting
  BooruItem? itemFromAlbum(Map<String, dynamic> a) {
    final String id = a['albumID']?.toString() ?? a['albumId']?.toString() ?? '';
    if (id.isEmpty) return null;
    final String cover = _cdnUrl(a['thumbnailUri']?.toString());
    final String full = _cdnUrl(a['imageUri']?.toString());
    if (full.isNotEmpty) _firstPages[id] = full;
    final List<Tag> tags = tagsFromAlbum(a);
    final String posted = a['addDt']?.toString() ?? '';
    // The 450-px cover is the card's whole image, sample included: a feed
    // must not download a full first page per card. The full page is the
    // detail cover instead (see detailCoverImage).
    final String shown = cover.isNotEmpty ? cover : full;
    final BooruItem item = BooruItem(
      fileURL: shown,
      sampleURL: shown,
      thumbnailURL: shown,
      tagsList: tags,
      postURL: '$_site/a/$id',
      serverId: id,
      description: (a['title']?.toString() ?? '').trim(),
      postDate: posted.isEmpty ? null : posted,
      postDateFormat: posted.isEmpty ? null : 'iso',
    );
    final List images = a['images'] is List ? a['images'] as List : const [];
    if (images.isNotEmpty) item.fileCountHint.value = images.length;
    return item;
  }

  static List<String> _pipe(dynamic raw) => [
    for (final part in (raw?.toString() ?? '').split('|'))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// The kinds that are the app's category; the rest are plain tags.
  static const Set<String> _categoryKinds = {'doujinshi', 'manga'};

  @visibleForTesting
  List<Tag> tagsFromAlbum(Map<String, dynamic> a) {
    final List<Tag> tags = [];
    final Set<String> seen = {};

    void add(String name, String? namespace) {
      if (name.trim().isEmpty) return;
      final Tag tag = namespacedTag(name, namespace);
      if (tag.fullString.isEmpty || !seen.add(tag.fullString)) return;
      tags.add(tag);
    }

    for (final String author in _pipe(a['author'])) {
      add(author, 'artist');
    }
    for (final String kind in _pipe(a['albumType'])) {
      add(kind, _categoryKinds.contains(kind.toLowerCase()) ? 'category' : null);
    }
    for (final String t in _pipe(a['tags'])) {
      add(t, null);
    }
    final String from = (a['from']?.toString() ?? '').trim();
    if (from.isNotEmpty) add(from, 'parody');
    for (final String c in _pipe(a['characters'])) {
      add(c, 'character');
    }
    // English-translated by the site's own description; the card's language
    // label and the language filter read it.
    add('english', 'language');
    return tags;
  }

  @override
  FutureOr<List> parseListFromResponse(dynamic response) async {
    final protocol = _parseProtocol(currentTags);
    if (protocol != null && protocol.kind != 'id') {
      return protocol.kind == 'related' ? await _fetchRelated(protocol.id) : await _fetchRecommended(protocol.id);
    }
    final dynamic data = response.data;
    if (protocol != null && protocol.kind == 'id') {
      final List<BooruItem> items = itemsFromApi(data);
      if (items.isNotEmpty) return [items.first];
      final String body = data?.toString() ?? '';
      final BooruItem? item = body.trimLeft().startsWith('<') ? _itemFromGalleryPage(protocol.id, body) : null;
      return item == null ? const [] : [item];
    }
    final List<BooruItem> items = itemsFromApi(data);
    final int? total = totalFromApi(data);
    if (total != null) totalCount.value = total;
    return items;
  }

  /// [parseListFromResponse] already builds finished items, so the base class's
  /// per-entry hook is a passthrough. Without this override it would replace
  /// every one of them with the default blank [BooruItem] and the grid would
  /// fill with empty cards.
  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) =>
      responseItem is BooruItem ? responseItem : null;

  // ── requests ──────────────────────────────────────────────────────────

  Future<({int status, String body, String finalUrl})> _fetch(String url, {String? postJson, CancelToken? cancelToken}) async {
    final r = fetcher != null ? await fetcher!(url, postJson: postJson) : await _network(url, postJson: postJson, cancelToken: cancelToken);
    // A token the site no longer accepts is dropped, so the next search logs
    // in again instead of failing every account call. Not on the auth calls
    // themselves: a `/auth/me` the site answers 401 must not undo a login
    // that just succeeded.
    if (r.status == 401 && url.contains('/api/') && !url.contains('/api/auth/') && EaHentaiSessionHandler.instance.isLoggedIn) {
      Logger.Inst().log('eahentai answered 401 with a token; forgetting it', className, '_fetch', LogTypes.booruHandlerInfo);
      EaHentaiSessionHandler.instance.logout();
    }
    return r;
  }

  Future<({int status, String body, String finalUrl})> _network(String url, {String? postJson, CancelToken? cancelToken}) async {
    if (postJson != null) {
      // The login body carries the password: it stays out of the request
      // inspector and the talker log alike (the outcome is logged by hand).
      final Response response = await DioNetwork.post(
        url,
        data: postJson,
        headers: {...getHeaders(), 'Content-Type': 'application/json', 'Accept': 'application/json'},
        options: Options(validateStatus: (_) => true),
        cancelToken: cancelToken,
        skipLogging: url.contains('/api/auth/'),
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

  // ── the hydration payload (the HTML fallback) ─────────────────────────

  /// Joins and unescapes the streamed `self.__next_f.push([1,"…"])` chunks.
  /// Everything the site's HTML knows about a gallery lives in there.
  @visibleForTesting
  static String decodeNextPayload(String body) {
    final chunks = RegExp(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', dotAll: true)
        .allMatches(body)
        .map((m) => m.group(1) ?? '')
        .join();
    if (chunks.isEmpty) return '';
    return _unescape(chunks);
  }

  /// The chunks are JS string literals: \" \\ \n and \uXXXX.
  static String _unescape(String s) {
    final out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (s[i] != r'\' || i + 1 >= s.length) {
        out.write(s[i]);
        continue;
      }
      final String next = s[i + 1];
      switch (next) {
        case 'n':
          out.write('\n');
          i++;
        case 't':
          out.write('\t');
          i++;
        case 'r':
          out.write('\r');
          i++;
        case '"':
          out.write('"');
          i++;
        case r'\':
          out.write(r'\');
          i++;
        case '/':
          out.write('/');
          i++;
        case 'u':
          if (i + 5 < s.length) {
            final int? code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
            if (code != null) {
              out.writeCharCode(code);
              i += 5;
            } else {
              out.write(s[i]);
            }
          } else {
            out.write(s[i]);
          }
        default:
          out.write(s[i]);
      }
    }
    return out.toString();
  }

  /// Pipe-separated values of a payload field, e.g. `"tags":"a|b|c"`.
  @visibleForTesting
  static List<String> pipeField(String payload, String field) {
    final match = RegExp('"$field":"([^"]*)"').firstMatch(payload);
    return _pipe(match?.group(1));
  }

  /// The per-gallery hash the CDN paths are built from.
  @visibleForTesting
  static String galleryHash(String body) => RegExp('galleries/([0-9a-f]{16,})/').firstMatch(body)?.group(1) ?? '';

  /// Tags and authors out of the HTML payload, namespaced the way the rest
  /// of the app expects.
  @visibleForTesting
  List<Tag> tagsFromPayload(String payload) => tagsFromAlbum({
    'author': pipeField(payload, 'author').join('|'),
    'tags': pipeField(payload, 'tags').join('|'),
    'from': pipeField(payload, 'parody').join('|'),
    'characters': pipeField(payload, 'character').join('|'),
  });

  /// Listing cards are `/a/{id}` links wrapping a cover image, with the title
  /// on the anchor's `aria-label` (the `<img alt>` is deliberately empty).
  /// The hero card also renders a "Read Now" button pointing at itself with
  /// only an icon inside, so the anchor that carries an image wins.
  @visibleForTesting
  List<BooruItem> itemsFromListing(String body) {
    final dom.Document doc = parse(body);
    final Map<String, BooruItem> byId = {};
    final List<String> order = [];

    for (final a in doc.querySelectorAll('a[href^="/a/"]')) {
      final String href = a.attributes['href'] ?? '';
      final match = RegExp(r'^/a/(\d+)$').firstMatch(href);
      if (match == null) continue;
      final String id = match.group(1)!;

      final img = a.querySelector('img');
      final String thumb = (img?.attributes['src'] ?? img?.attributes['data-src'] ?? '').trim();
      final String title = (a.attributes['aria-label'] ?? a.querySelector('p')?.text ?? img?.attributes['alt'] ?? '').trim();

      final BooruItem? existing = byId[id];
      if (existing != null) {
        if (thumb.isEmpty) continue;
        if (existing.thumbnailURL.isNotEmpty) continue;
      } else {
        order.add(id);
      }

      final item = BooruItem(
        fileURL: thumb,
        sampleURL: thumb,
        thumbnailURL: thumb,
        tagsList: const [],
        postURL: '$_site/a/$id',
        serverId: id,
      );
      item.description = title;
      byId[id] = item;
    }

    return [for (final id in order) byId[id]!];
  }

  BooruItem? _itemFromGalleryPage(String id, String body) {
    final dom.Document doc = parse(body);
    final String payload = decodeNextPayload(body);
    final String hash = galleryHash(body);
    final String cover = hash.isEmpty ? '' : '$_cdn/galleries/$hash/thumbnail/image1t.jpg';

    final item = BooruItem(
      fileURL: cover,
      sampleURL: cover,
      thumbnailURL: cover,
      tagsList: tagsFromPayload(payload),
      postURL: '$_site/a/$id',
      serverId: id,
    );
    item.description = doc.querySelector('h1')?.text.trim() ?? '';
    return item;
  }

  @override
  List<(String, String)> get tagNamespaceSections => const [
    ('artist', 'Artists'),
    ('parody', 'Parodies'),
    ('character', 'Characters'),
    ('category', 'Kind'),
    ('language', 'Language'),
    ('tag', 'Tags'),
  ];

  // ── the search window ─────────────────────────────────────────────────

  @override
  DoujinFilterSpec get doujinFilters => const DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'sort',
      label: 'Sort',
      defaultValue: 'latest',
      options: [
        DoujinFilterOption('latest', 'Latest'),
        DoujinFilterOption('today', 'Popular today'),
        DoujinFilterOption('weekly', 'Popular this week'),
        DoujinFilterOption('monthly', 'Popular this month'),
        DoujinFilterOption('alltime', 'Popular all time'),
      ],
    ),
    DoujinFilterGroup(
      key: 'type',
      label: 'Search in',
      options: [
        DoujinFilterOption('', 'Everything'),
        DoujinFilterOption('artist', 'Artists'),
        DoujinFilterOption('character', 'Characters'),
        DoujinFilterOption('parody', 'Parodies'),
        DoujinFilterOption('tag', 'Tags'),
      ],
    ),
    DoujinFilterGroup(
      key: 'filter',
      label: 'Quick filters',
      multi: true,
      options: [
        DoujinFilterOption('original', 'Original'),
        DoujinFilterOption('full_color', 'Full color'),
        DoujinFilterOption('doujins', 'Doujins'),
        DoujinFilterOption('manga', 'Manga'),
        DoujinFilterOption('uncensored', 'Uncensored'),
        DoujinFilterOption('lolicon', 'Lolicon'),
        DoujinFilterOption('yuri', 'Yuri'),
        DoujinFilterOption('yaoi', 'Yaoi'),
      ],
    ),
  ]);

  @override
  List<MetaTag> availableMetaTags() => [
    StringMetaTag(name: 'Artist', keyName: 'artist'),
    StringMetaTag(name: 'Series', keyName: 'parody'),
    StringMetaTag(name: 'Character', keyName: 'character'),
    StringMetaTag(name: 'Tag', keyName: 'tag'),
    MetaTagWithValues(
      name: 'Sort',
      keyName: 'sort',
      values: [
        MetaTagValue(name: 'Latest', value: 'latest'),
        MetaTagValue(name: 'Popular today', value: 'today'),
        MetaTagValue(name: 'Popular this week', value: 'weekly'),
        MetaTagValue(name: 'Popular this month', value: 'monthly'),
        MetaTagValue(name: 'Popular all time', value: 'alltime'),
      ],
    ),
    MetaTagWithValues(
      name: 'Search in',
      keyName: 'type',
      values: [
        MetaTagValue(name: 'Artists', value: 'artist'),
        MetaTagValue(name: 'Characters', value: 'character'),
        MetaTagValue(name: 'Parodies', value: 'parody'),
        MetaTagValue(name: 'Tags', value: 'tag'),
      ],
    ),
    MetaTagWithValues(
      name: 'Quick filter',
      keyName: 'filter',
      values: [for (final e in EaHentaiQuery.filterWords.entries) MetaTagValue(name: e.value, value: e.key)],
    ),
  ];

  /// `GET /api/image/search/suggestions?q=&type=all&limit=8`: the site's own
  /// autocomplete, typed by namespace.
  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(String input, {CancelToken? cancelToken}) async {
    final String q = input.trim().replaceAll('_', ' ');
    if (q.isEmpty) return const Right([]);
    try {
      final r = await _fetch(
        '${EaHentaiQuery.api}/search/suggestions?q=${Uri.encodeComponent(q)}&type=all&limit=8',
        cancelToken: cancelToken,
      );
      if (r.status != 200) return Left(ResponseError(message: 'eahentai suggestions answered ${r.status}', statusCode: r.status));
      return Right(parseSuggestions(_decode(r.body)));
    } catch (e, s) {
      Logger.Inst().log(e.toString(), className, 'getTagSuggestions', LogTypes.exception, s: s);
      return Left(ResponseError(message: 'tag suggestions failed', error: e));
    }
  }

  @visibleForTesting
  static List<TagSuggestion> parseSuggestions(dynamic json) {
    final List entries = json is Map ? (json['items'] as List? ?? const []) : (json is List ? json : const []);
    final List<TagSuggestion> out = [];
    for (final e in entries) {
      if (e is! Map) continue;
      final String value = normalizeDoujinTagName(e['value']?.toString() ?? '');
      if (value.isEmpty) continue;
      final String type = (e['type']?.toString() ?? 'tag').toLowerCase();
      final int count = int.tryParse(e['albumCount']?.toString() ?? '') ?? 0;
      out.add(
        TagSuggestion(
          tag: type == 'tag' ? value : '$type:$value',
          count: count,
          type: switch (type) {
            'artist' => TagType.artist,
            'character' => TagType.character,
            'parody' => TagType.copyright,
            _ => TagType.none,
          },
        ),
      );
    }
    return out;
  }

  // ── detail + reader ───────────────────────────────────────────────────

  /// The album's pages, from `images[]` in `sort` order: the full page and
  /// its own thumbnail. Empty when the answer lists none.
  @visibleForTesting
  List<BooruItem> pagesFromAlbum(dynamic json, {required String postURL}) {
    dynamic data = json;
    if (data is String) data = _decode(data);
    if (data is List && data.isNotEmpty) data = data.first;
    if (data is! Map) return const [];
    final List images = data['images'] is List ? data['images'] as List : const [];
    final List<Map> entries = [for (final e in images) if (e is Map) e];
    entries.sort((a, b) {
      final int sa = int.tryParse(a['sort']?.toString() ?? '') ?? 0;
      final int sb = int.tryParse(b['sort']?.toString() ?? '') ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return (int.tryParse(a['imageID']?.toString() ?? '') ?? 0).compareTo(int.tryParse(b['imageID']?.toString() ?? '') ?? 0);
    });
    final String id = data['albumID']?.toString() ?? '';
    final List<BooruItem> pages = [];
    for (int i = 0; i < entries.length; i++) {
      final String full = _cdnUrl(entries[i]['imageUri']?.toString());
      if (full.isEmpty) continue;
      final String thumb = _cdnUrl(entries[i]['thumbnailUri']?.toString());
      pages.add(
        BooruItem(
          fileURL: full,
          sampleURL: full,
          thumbnailURL: thumb.isNotEmpty ? thumb : full,
          tagsList: const [],
          postURL: postURL,
          fileNameExtras: id.isEmpty ? '' : '${id}_${(i + 1).toString().padLeft(4, '0')}',
        ),
      );
    }
    return pages;
  }

  static String _idOf(BooruItem item) {
    final String id = item.serverId ?? '';
    if (id.isNotEmpty) return id;
    return RegExp(r'/a/(\d+)').firstMatch(item.postURL)?.group(1) ?? '';
  }

  /// The gallery's full first page (`imageUri`, ~1280 px) as the detail
  /// cover - known from the listing or the album answer, so no request; the
  /// item is named like the reader's page 1 and shares its cached file.
  @override
  Future<BooruItem?> detailCoverImage(BooruItem item) async {
    if (!SourceSettingsHandler.instance.detailCoverFromFirstPage(booru)) return null;
    final String id = _idOf(item);
    String? full = _firstPages[id];
    if (full == null || full.isEmpty) {
      final List<BooruItem>? pages = ReaderHandler.instance.pagesFor(item);
      if (pages != null && pages.isNotEmpty && pages.first.fileURL.isNotEmpty) full = pages.first.fileURL;
    }
    if (full == null || full.isEmpty || full == item.thumbnailURL) return null;
    final BooruItem cover = BooruItem(
      fileURL: full,
      sampleURL: full,
      thumbnailURL: full,
      tagsList: const [],
      postURL: item.postURL,
      serverId: item.serverId,
      fileNameExtras: id.isEmpty ? '' : '${id}_0001',
    );
    cover.mediaType.value = MediaType.image;
    return cover;
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    dynamic cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    final String id = _idOf(item);
    if (id.isEmpty) return (item: null, failed: true, error: 'no gallery id');
    final CancelToken? token = cancelToken is CancelToken ? cancelToken : null;

    try {
      // The album answer: metadata and every page in one request.
      try {
        final r = await _fetch('${EaHentaiQuery.api}/album/$id', cancelToken: token);
        if (r.status == 200) {
          final dynamic decoded = _decode(r.body);
          final Map<String, dynamic>? album = decoded is List && decoded.isNotEmpty && decoded.first is Map
              ? (decoded.first as Map).cast<String, dynamic>()
              : (decoded is Map ? decoded.cast<String, dynamic>() : null);
          if (album != null) {
            final List<BooruItem> pages = pagesFromAlbum(album, postURL: '$_site/a/$id');
            if (pages.isNotEmpty) {
              final BooruItem? meta = itemFromAlbum(album);
              if (meta != null) {
                item.tagsList = meta.tagsList;
                if ((meta.description ?? '').isNotEmpty) item.description = meta.description;
                if (item.thumbnailURL.isEmpty) item.thumbnailURL = meta.thumbnailURL;
                if (item.sampleURL.isEmpty) item.sampleURL = meta.sampleURL;
                if (item.fileURL.isEmpty) item.fileURL = meta.fileURL;
                item.postDate ??= meta.postDate;
                item.postDateFormat ??= meta.postDateFormat;
              }
              ReaderHandler.instance.registerBook(item, pages);
              item.fileCountHint.value = pages.length;
              return (item: item, failed: false, error: null);
            }
          }
        }
        Logger.Inst().log('album $id: no pages in the API answer (${r.status}); reading the pages', className, 'loadItem', LogTypes.booruHandlerInfo);
      } catch (e) {
        Logger.Inst().log('album $id could not be read from the API: $e; reading the pages', className, 'loadItem', LogTypes.booruHandlerInfo);
      }

      // The gallery page carries the metadata...
      final gallery = await _fetch('$_site/a/$id', cancelToken: token);
      if (gallery.status != 200) return (item: null, failed: true, error: 'status ${gallery.status}');
      final String galleryBody = gallery.body;
      final String payload = decodeNextPayload(galleryBody);
      item.tagsList = tagsFromPayload(payload);
      final String title = parse(galleryBody).querySelector('h1')?.text.trim() ?? '';
      if (title.isNotEmpty) item.description = title;

      // ...and any single reader page lists every image in the book.
      final reader = await _fetch('$_site/a/$id/0', cancelToken: token);
      final String readerBody = reader.body;
      final List<String> images = fullImageUrls(readerBody);
      if (images.isEmpty) return (item: null, failed: true, error: 'could not resolve the page images');

      final String hash = galleryHash(readerBody.isEmpty ? galleryBody : readerBody);
      _firstPages[id] = images.first;
      final List<BooruItem> pages = [
        for (int i = 0; i < images.length; i++)
          BooruItem(
            fileURL: images[i],
            sampleURL: images[i],
            thumbnailURL: hash.isEmpty ? images[i] : '$_cdn/galleries/$hash/thumbnail/image${i + 1}t.jpg',
            tagsList: const [],
            postURL: '$_site/a/$id',
            fileNameExtras: '${id}_${(i + 1).toString().padLeft(4, '0')}',
          ),
      ];
      ReaderHandler.instance.registerBook(item, pages);
      item.fileCountHint.value = pages.length;
      return (item: item, failed: false, error: null);
    } catch (e) {
      return (item: null, failed: true, error: e.toString());
    }
  }

  /// Every full-size page image on a reader page, in page order. The CDN
  /// serves them as `image<N>.webp`; the `thumbnail/` variants are excluded.
  @visibleForTesting
  static List<String> fullImageUrls(String body) {
    final matches = RegExp(r'https://i\.eahentai\.com/file/ea-gallery/galleries/[0-9a-f]+/image(\d+)\.(?:webp|jpg|png)').allMatches(body);
    final Map<int, String> byIndex = {};
    for (final m in matches) {
      final int? n = int.tryParse(m.group(1) ?? '');
      if (n == null) continue;
      byIndex.putIfAbsent(n, () => m.group(0)!);
    }
    final keys = byIndex.keys.toList()..sort();
    return [for (final k in keys) byIndex[k]!];
  }

  // ── generated Related / Recommended ───────────────────────────────────

  Future<BooruItem?> _sourceItem(String id) async {
    try {
      final r = await _fetch('${EaHentaiQuery.api}/album/$id');
      if (r.status == 200) {
        final List<BooruItem> items = itemsFromApi(r.body);
        if (items.isNotEmpty) return items.first;
      }
      final page = await _fetch('$_site/a/$id');
      if (page.status != 200) return null;
      return _itemFromGalleryPage(id, page.body);
    } catch (_) {
      return null;
    }
  }

  Future<List<BooruItem>> _candidatesFor(BooruItem source) async {
    final List<String> queries = [
      for (final t in source.tagsList.take(4)) t.fullString.split(':').last.replaceAll('_', ' '),
      DoujinRecommendationEngine.baseTitle(
        (source.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
      ),
    ].where((q) => q.trim().length > 2).toList();

    final List<BooruItem> out = [];
    final Set<String> seen = {source.postURL};
    for (final query in queries) {
      try {
        final EaHentaiRequest request = EaHentaiQuery.parse(query, page: 1, take: 42);
        if (request.url.isEmpty) continue;
        final r = await _fetch(request.url);
        if (r.status != 200) continue;
        for (final item in itemsFromApi(r.body)) {
          if (seen.add(item.postURL)) out.add(item);
        }
      } catch (_) {
        // One dead query means fewer candidates, never a failed section.
      }
    }
    return out;
  }

  Future<List<BooruItem>> _fetchRelated(String id) async {
    final source = await _sourceItem(id);
    if (source == null) return [];
    return DoujinRecommendationEngine.related(source, await _candidatesFor(source));
  }

  Future<List<BooruItem>> _fetchRecommended(String id) async {
    final source = await _sourceItem(id);
    if (source == null) return [];
    final candidates = await _candidatesFor(source);
    String? artist;
    for (final tag in source.tagsList) {
      if (tag.tagType == TagType.artist) {
        artist = tag.fullString;
        break;
      }
    }
    return DoujinRecommendationEngine.rankPersonal(
      handler: this,
      source,
      candidates,
      count: limit,
      sourceArtist: (artist?.isEmpty ?? true) ? null : artist,
    );
  }

  @override
  String? relatedVersionsQuery(BooruItem item) {
    final String id = item.serverId ?? '';
    return id.isEmpty ? null : 'related:$id';
  }
}
