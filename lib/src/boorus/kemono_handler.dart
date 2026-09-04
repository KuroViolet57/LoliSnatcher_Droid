import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt, Response;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_query.dart';
import 'package:lolisnatcher/src/boorus/kemono_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/creator_info.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/response_error.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_file_hosts.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// kemono.cr — a creator archive (Patreon, Fanbox, Gumroad, Fantia, Boosty,
/// SubscribeStar, DLsite, Discord) with a JSON API under `/api/v1`. Verified
/// against the live API on 2026-09-04:
///
///   `GET /posts?q=&o=&tag=`                        newest / search, 50 a page
///   `GET /{service}/user/{id}/posts?o=&q=&tag=`    one creator (a plain array)
///   `GET /posts/popular?date=&period=&o=`          popular
///   `GET /posts/random`, `GET /artists/random`     one random post / creator
///   `GET /{service}/user/{id}/post/{post}`         the post with every file
///   `GET /account/favorites?type=post|artist`      the account (cookie)
///
/// Every call needs `Accept: text/css` (see [KemonoApi]). A post is a
/// gallery: the cover is `file`, the rest are `attachments`; the viewer's
/// files action lists them through [KemonoProfile]. Creators are artists:
/// the creator tag on every item, the creator index behind the Artists
/// page, and the kemono sidebar (see KemonoSidebar) mirror the site.
class KemonoHandler extends BooruHandler {
  KemonoHandler(super.booru, super.limit);

  static const int pageSize = 50;

  /// The parsed form of the tab's query, set by [makeURL].
  KemonoQuery current = KemonoQuery.parse('');

  /// The creator when the tab is one creator's posts (the header reads it).
  ({String service, String id})? get currentCreator => current.creator;

  /// The creator's profile, loaded once per creator tab.
  final Rxn<Map<String, dynamic>> creatorProfile = Rxn<Map<String, dynamic>>();
  String _profileFor = '';

  /// `service:id` of every creator the signed-in account favourited, once
  /// [loadFavouriteCreatorKeys] has run.
  final RxSet<String> favouriteCreatorKeys = <String>{}.obs;
  bool _favouriteKeysLoaded = false;

  @override
  late final TagCatalogSource tagCatalog = KemonoTagCatalog(this);

  int get offset => (pageNum < 0 ? 0 : pageNum) * pageSize;

  // ── capabilities ───────────────────────────────────────────────────

  @override
  bool get hasSizeData => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  bool get hasTagSuggestions => true;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  bool get hasCommentsSupport => true;

  @override
  bool get hasSignInSupport => true;

  @override
  String? get userIdLabel => 'Username (optional)';

  @override
  String? get apiKeyLabel => 'Password (optional)';

  @override
  String? get metatagsCheatSheetLink => 'https://kemono.cr/documentation/api';

  @override
  List<String> get animatedPreviewFilters => const [];

  @override
  String translateOrSyntax(String tags) => BooruHandler.dropOrGroupsWithWarning(tags, className);

  @override
  String validateTags(String tags) => tags.trim();

  @override
  Map<String, String> getHeaders() => KemonoApi.headers(booru);

  /// Only the referer: the media hosts want a browser's Accept, not the
  /// API's.
  @override
  Map<String, String> getMediaHeaders() => const {'Referer': '${KemonoApi.site}/'};

  static bool _isFileHostUrl(String url) => KemonoFileHosts.isFileHost(Uri.tryParse(url)?.host ?? '');

  /// The file hosts are unreachable from some networks (the site breaks the
  /// same way there); once a probe says so, the viewer says it at once.
  @override
  String? mediaOutageNotice(String url) {
    if (!_isFileHostUrl(url)) return null;
    final KemonoFileHosts hosts = KemonoFileHosts.instance;
    if (!hosts.checked) unawaited(hosts.check());
    return hosts.noticeFor(url);
  }

  @override
  void onMediaError(String url, Object error) {
    if (!_isFileHostUrl(url)) return;
    if (error is DioException &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.receiveTimeout)) {
      unawaited(KemonoFileHosts.instance.check(force: true));
    }
  }

  @override
  Future<void> beforeMediaRetry(String url) async {
    if (_isFileHostUrl(url)) await KemonoFileHosts.instance.check(force: true);
  }

  @override
  List<(String, String)> get tagNamespaceSections => const [
    ('creator', 'Creator'),
    ('service', 'Service'),
    ('tag', 'Tags'),
  ];

  @override
  String? tagNamespace(String tag) {
    final String lower = tag.toLowerCase();
    if (lower.startsWith('creator:')) return 'creator';
    if (lower.startsWith('service:')) return 'service';
    final int colon = lower.indexOf(':');
    if (colon > 0 && KemonoQuery.services.contains(lower.substring(0, colon))) return 'creator';
    return 'tag';
  }

  @override
  List<MetaTag> availableMetaTags() => [
    UserMetaTag(name: 'Creator', keyName: 'creator'),
    StringMetaTag(name: 'Tag', keyName: 'tag'),
    MetaTagWithValues(
      name: 'Service (filters on the phone)',
      keyName: 'service',
      values: [for (final s in KemonoQuery.services) MetaTagValue(name: s, value: s)],
    ),
    MetaTagWithValues(
      name: 'Popular',
      keyName: 'popular',
      values: [for (final p in KemonoQuery.periods) MetaTagValue(name: p, value: p)],
    ),
    MetaTagWithValues(name: 'Favorites', keyName: 'favorites', values: [MetaTagValue(name: 'posts', value: 'posts')]),
    StringMetaTag(name: 'Post id', keyName: 'id'),
  ];

  // ── the query → URL ────────────────────────────────────────────────

  static String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String urlFor(KemonoQuery query) {
    switch (query.kind) {
      case KemonoQueryKind.posts:
        return KemonoApi.postsUrl(q: query.q, offset: offset, tags: query.tags);
      case KemonoQueryKind.creatorPosts:
        if (query.creatorId == null) {
          // Resolved by name in fetchSearch; this address is never fetched.
          return '${KemonoApi.api}/creator-by-name?name=${Uri.encodeQueryComponent(query.creatorName ?? '')}';
        }
        return KemonoApi.postsUrl(
          base: '${KemonoApi.creatorPath(query.service!, query.creatorId!)}/posts',
          q: query.q,
          offset: offset,
          tags: query.tags,
        );
      case KemonoQueryKind.popular:
        return KemonoApi.popularUrl(period: query.period, date: query.date ?? today(), offset: offset);
      case KemonoQueryKind.randomPost:
        return '${KemonoApi.api}/posts/random';
      case KemonoQueryKind.favouritePosts:
        return '${KemonoApi.api}/account/favorites?type=post';
      case KemonoQueryKind.post:
        return '${KemonoApi.creatorPath(query.service!, query.creatorId!)}/post/${query.postId}';
    }
  }

  bool get _singlePage =>
      current.kind == KemonoQueryKind.randomPost ||
      current.kind == KemonoQueryKind.favouritePosts ||
      current.kind == KemonoQueryKind.post;

  @override
  String makeURL(String tags) {
    current = KemonoQuery.parse(tags);
    if (current.error != null) {
      errorString = current.error!;
      locked = true;
      return '';
    }
    if (_singlePage && pageNum > 0) {
      locked = true;
      return '';
    }
    if (current.kind == KemonoQueryKind.favouritePosts && !KemonoSessionHandler.instance.hasSession(booru)) {
      errorString = 'Favorites need your kemono username and password in the booru settings';
      locked = true;
      return '';
    }
    return urlFor(current);
  }

  // ── fetching ───────────────────────────────────────────────────────

  /// Rows that can be shown: a post with no media at all is text only, and
  /// the grid has nothing to draw for it.
  static bool hasMedia(Map row) {
    final file = row['file'];
    if (file is Map && (file['path']?.toString().isNotEmpty ?? false)) return true;
    final attachments = row['attachments'];
    if (attachments is List) {
      for (final a in attachments) {
        if (a is Map && (a['path']?.toString().isNotEmpty ?? false)) return true;
      }
    }
    return false;
  }

  /// The rows and count out of any of the API's list shapes.
  @visibleForTesting
  static ({List<Map> rows, int count}) rowsOf(dynamic data) {
    List raw = const [];
    int count = -1;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      if (data['posts'] is List) {
        raw = data['posts'] as List;
      } else if (data['results'] is List) {
        raw = data['results'] as List;
      } else if (data['post'] is Map) {
        raw = [data['post']];
      }
      final props = data['props'];
      count =
          int.tryParse(data['true_count']?.toString() ?? '') ??
          int.tryParse(data['count']?.toString() ?? '') ??
          int.tryParse((props is Map ? props['count'] : null)?.toString() ?? '') ??
          -1;
    }
    final List<Map> rows = [for (final r in raw) if (r is Map) r];
    return (rows: rows, count: count < 0 ? rows.length : count);
  }

  @visibleForTesting
  static List<Map> filterRows(List<Map> rows, {String? service}) => [
    for (final row in rows)
      if (hasMedia(row) && (service == null || row['service']?.toString() == service)) row,
  ];

  Response<dynamic> _synthetic(Uri uri, {required List<Map> rows, required int count}) => Response<dynamic>(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
    data: {'kind': current.kind.name, 'rows': rows, 'count': count},
  );

  @override
  Future<Response<dynamic>> fetchSearch(Uri uri, String input, {bool withCaptchaCheck = true, Map<String, dynamic>? queryParams}) async {
    KemonoQuery query = current;
    if (query.needsCreatorLookup) {
      final KemonoCreator? found = await KemonoCreatorStore.instance.findByName(query.creatorName!);
      if (found == null) {
        errorString = 'No creator called "${query.creatorName}" in the kemono index (open Artists to refresh it)';
        locked = true;
        return _synthetic(uri, rows: const [], count: 0);
      }
      query = query.copyWith(service: found.service, creatorId: found.id);
      current = query;
      uri = Uri.parse(urlFor(query));
    }
    // The first search kicks the creator index off; names fill in as it lands.
    unawaited(KemonoCreatorStore.instance.ensureFresh());

    if (query.kind == KemonoQueryKind.randomPost) {
      final ref = await KemonoApi.randomPost();
      if (ref == null) return _synthetic(uri, rows: const [], count: 0);
      final Map<String, dynamic>? detail = await KemonoApi.postDetail(ref.service, ref.id, ref.postId, booru: booru);
      final post = detail?['post'];
      return _synthetic(uri, rows: post is Map ? [post] : const [], count: 1);
    }

    final bool pageable =
        query.kind == KemonoQueryKind.posts ||
        query.kind == KemonoQueryKind.popular ||
        query.kind == KemonoQueryKind.creatorPosts;
    final String? serviceFilter = query.kind == KemonoQueryKind.creatorPosts ? null : query.service;
    int hops = 0;
    while (true) {
      final data = await KemonoApi.getJson(uri.toString(), booru: booru);
      final parsed = rowsOf(data);
      final List<Map> kept = filterRows(parsed.rows, service: serviceFilter);
      // A page the filter emptied is not the end of the feed: walk on, a
      // few pages at most, so the grid does not lock on a false empty.
      if (kept.isNotEmpty || !pageable || parsed.rows.length < pageSize || hops >= 3) {
        return _synthetic(uri, rows: kept, count: parsed.count);
      }
      hops++;
      pageNum++;
      uri = Uri.parse(urlFor(query));
    }
  }

  // ── parsing ────────────────────────────────────────────────────────

  @override
  FutureOr<List> parseListFromResponse(dynamic response) async {
    final data = response.data;
    if (data is! Map) return const [];
    final List<Map> rows = (data['rows'] as List?)?.whereType<Map>().toList() ?? const [];
    final int count = int.tryParse(data['count']?.toString() ?? '') ?? rows.length;
    if (count > 0) totalCount.value = count;

    final store = KemonoCreatorStore.instance;
    await store.warmNames([
      for (final row in rows) (service: row['service']?.toString() ?? '', id: row['user']?.toString() ?? ''),
    ]);

    final creator = currentCreator;
    if (creator != null) {
      relatedCreators = [];
      final String key = '${creator.service}:${creator.id}';
      if (_profileFor != key) {
        _profileFor = key;
        creatorProfile.value = null;
        unawaited(_loadCreatorProfile(creator));
      }
    } else if (pageNum <= 0) {
      relatedCreators = creatorsOf(rows);
    }
    return rows;
  }

  /// Distinct creators of a page, for the strip above a search feed.
  List<CreatorInfo> creatorsOf(List<Map> rows) {
    final List<CreatorInfo> out = [];
    final Set<String> seen = {};
    for (final row in rows) {
      final String service = row['service']?.toString() ?? '';
      final String user = row['user']?.toString() ?? '';
      if (service.isEmpty || user.isEmpty || !seen.add('$service:$user')) continue;
      out.add(
        CreatorInfo(
          searchQuery: 'creator:$service:$user',
          displayName: KemonoCreatorStore.instance.nameOf(service, user) ?? '$service:$user',
          avatarUrl: KemonoApi.iconUrl(service, user),
          coverUrl: KemonoApi.bannerUrl(service, user),
          subtitle: service,
        ),
      );
      if (out.length >= 10) break;
    }
    return out.length < 2 ? const [] : out;
  }

  Future<void> _loadCreatorProfile(({String service, String id}) creator) async {
    try {
      final profile = await KemonoApi.profile(creator.service, creator.id, booru: booru);
      if (profile != null && _profileFor == '${creator.service}:${creator.id}') creatorProfile.value = profile;
    } catch (e) {
      Logger.Inst().log('creator profile failed: $e', className, '_loadCreatorProfile', LogTypes.booruHandlerInfo);
    }
  }

  static String extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  /// Plain text out of the site's HTML content.
  static String textOf(String? content) {
    if (content == null || content.isEmpty) return '';
    try {
      return (html_parser.parse(content).body?.text ?? '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    } catch (_) {
      return content;
    }
  }

  /// The tag string for a creator: their name where the index knows it,
  /// else `service:id` — both forms route back to the creator's posts.
  static String creatorTag(String service, String user) {
    final String? name = KemonoCreatorStore.instance.nameOf(service, user);
    if (name == null) return '$service:$user';
    return name.trim().replaceAll(RegExp(r'\s+'), '_');
  }

  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map row = responseItem;
    final String service = row['service']?.toString() ?? '';
    final String user = row['user']?.toString() ?? '';
    final String id = row['id']?.toString() ?? '';
    if (service.isEmpty || user.isEmpty || id.isEmpty) return null;

    final List<String> paths = [];
    final Set<String> seen = {};
    void add(dynamic entry) {
      if (entry is! Map) return;
      final String path = entry['path']?.toString() ?? '';
      if (path.isNotEmpty && seen.add(path)) paths.add(path);
    }

    add(row['file']);
    final attachments = row['attachments'];
    if (attachments is List) attachments.forEach(add);
    if (paths.isEmpty) return null;

    final String cover = KemonoProfile.coverPath(paths);
    final bool video = KemonoProfile.isVideoPath(cover);
    final String thumb = video ? KemonoApi.iconUrl(service, user) : KemonoApi.thumbUrl(cover);
    final String title = row['title']?.toString().trim() ?? '';
    final String body = textOf(row['content']?.toString()) ;
    final String substring = row['substring']?.toString().trim() ?? '';
    final String description = [
      title,
      if (body.isNotEmpty) body else substring,
    ].where((s) => s.isNotEmpty).join('\n\n');

    final List<Tag> tags = [
      Tag(creatorTag(service, user), tagType: TagType.artist),
      Tag('service:$service', tagType: TagType.meta),
    ];
    final siteTags = row['tags'];
    if (siteTags is List) {
      for (final t in siteTags) {
        final String name = t.toString().trim().replaceAll(RegExp(r'\s+'), '_');
        if (name.isNotEmpty) tags.add(Tag(name, tagType: TagType.none));
      }
    }

    // Files live on the site's file hosts, addressed directly like the site
    // does; `kemono.cr/data` is a DDoS-Guard redirect nothing here uses.
    final item = BooruItem(
      fileURL: KemonoApi.fileUrl(cover),
      // The site's image service (up to 800 px) is the sample: it answers
      // everywhere the API does, the file hosts don't.
      sampleURL: video ? KemonoApi.fileUrl(cover) : thumb,
      thumbnailURL: thumb,
      tagsList: tags,
      postURL: KemonoApi.postUrl(service, user, id),
      fileExt: extensionOf(cover),
      serverId: '$service:$user:$id',
      uploaderId: '$service:$user',
      uploaderName: KemonoCreatorStore.instance.nameOf(service, user),
      description: description,
      sources: [KemonoApi.postUrl(service, user, id)],
      postDate: row['published']?.toString(),
      postDateFormat: 'iso',
    );
    if (paths.length > 1) item.fileCountHint.value = paths.length;
    return item;
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    dynamic cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    final ref = KemonoProfile.splitId(item.serverId);
    if (ref == null) return (item: item, failed: false, error: null);
    try {
      final detail = await KemonoApi.postDetail(ref.service, ref.user, ref.post, booru: booru);
      final post = detail?['post'];
      if (post is! Map) return (item: item, failed: true, error: 'the post is gone');
      final BooruItem? fresh = await parseItemFromResponse(post, 0);
      if (fresh == null) return (item: item, failed: false, error: null);
      item.tagsList = fresh.tagsList;
      item.description = fresh.description;
      final files = KemonoProfile.filesFromDetail(detail!);
      if (files != null && files.length > 1) item.fileCountHint.value = files.length;
      return (item: item, failed: false, error: null);
    } catch (e) {
      return (item: item, failed: true, error: e.toString());
    }
  }

  // ── suggestions ────────────────────────────────────────────────────

  @override
  Future<Either<ResponseError, List<TagSuggestion>>> getTagSuggestions(String input, {CancelToken? cancelToken}) async {
    final String text = input.trim();
    if (text.isEmpty) return const Right([]);
    final String lower = text.toLowerCase();
    final bool creatorsOnly = lower.startsWith('creator:');
    final bool tagsOnly = lower.startsWith('tag:');
    final String term = creatorsOnly ? text.substring(8) : (tagsOnly ? text.substring(4) : text);
    final List<TagSuggestion> out = [];
    if (!tagsOnly && term.trim().length >= 2) {
      final creators = await KemonoCreatorStore.instance.search(term, limit: 12);
      for (final c in creators) {
        out.add(
          TagSuggestion(
            tag: c.searchQuery,
            description: '${c.name} · ${c.service}',
            count: c.favorited,
            type: TagType.artist,
          ),
        );
      }
    }
    if (!creatorsOnly && term.trim().isNotEmpty) {
      final rows = await BooruTagStore.browse(booru, namespace: KemonoTagCatalog.tagKey, query: term, limit: 12);
      for (final e in rows) {
        out.add(TagSuggestion(tag: 'tag:${e.name}', count: e.count));
      }
    }
    return Right(out);
  }

  // ── comments ───────────────────────────────────────────────────────

  @override
  String makeCommentsURL(String postID, int pageNum) {
    final ref = KemonoProfile.splitId(postID);
    if (ref == null) return '';
    return '${KemonoApi.creatorPath(ref.service, ref.user)}/post/${ref.post}/comments';
  }

  @override
  FutureOr<List> parseCommentsList(dynamic response) {
    final data = KemonoApi.decode(response.data);
    return data is List ? data : const [];
  }

  @override
  FutureOr<CommentItem?> parseComment(dynamic responseItem, int index) {
    if (responseItem is! Map) return null;
    final Map row = responseItem;
    return CommentItem(
      id: row['id']?.toString(),
      content: textOf(row['content']?.toString()),
      authorID: row['commenter']?.toString(),
      authorName: (row['commenter_name'] ?? row['commenter'])?.toString(),
      postID: row['post_id']?.toString(),
      createDate: (row['published'] ?? row['added'])?.toString(),
      createDateFormat: 'iso',
    );
  }

  // ── the account ────────────────────────────────────────────────────

  KemonoSessionHandler get session => KemonoSessionHandler.instance;

  @override
  Future<bool> isSignedIn() async => session.hasSession(booru);

  /// Throttled: one attempt a minute, so a wrong password costs one request
  /// per minute, not one per search.
  @override
  Future<dynamic> signIn() => session.relogin(booru);

  @override
  Future<dynamic> signOut({bool fromError = false}) => session.logout(booru);

  @override
  Future<bool> searchSetup() async {
    // Credentials removed → the session goes with them.
    if (session.hasSession(booru) && !KemonoSessionHandler.hasCredentials(booru)) {
      await session.logout(booru, remote: false);
    }
    return super.searchSetup();
  }

  @override
  bool get hasSiteFavourites => session.hasSession(booru);

  @override
  Future<(bool, String)> setSiteFavourite(BooruItem item, bool value) async {
    final ref = KemonoProfile.splitId(item.serverId);
    if (ref == null) return (false, 'No post id');
    if (!hasSiteFavourites) return (false, 'Local only — sign in to kemono in the booru settings to sync');
    return KemonoApi.setPostFavourite(booru, ref.service, ref.user, ref.post, value);
  }

  Future<(bool, String)> setCreatorFavourite(String service, String id, bool value) async {
    if (!hasSiteFavourites) return (false, 'Sign in to kemono in the booru settings to favourite artists');
    final result = await KemonoApi.setCreatorFavourite(booru, service, id, value);
    if (result.$1) {
      if (value) {
        favouriteCreatorKeys.add('$service:$id');
      } else {
        favouriteCreatorKeys.remove('$service:$id');
      }
    }
    return result;
  }

  /// The account's favourite creators as `service:id`; empty when signed out.
  Future<Set<String>> loadFavouriteCreatorKeys({bool force = false}) async {
    if (!hasSiteFavourites) return const {};
    if (_favouriteKeysLoaded && !force) return favouriteCreatorKeys;
    try {
      final rows = await KemonoApi.favourites(booru, type: 'artist');
      favouriteCreatorKeys
        ..clear()
        ..addAll([
          for (final r in rows)
            if (r is Map) '${r['service']}:${r['id']}',
        ]);
      _favouriteKeysLoaded = true;
    } catch (e) {
      Logger.Inst().log('favourite creators failed: $e', className, 'loadFavouriteCreatorKeys', LogTypes.booruHandlerInfo);
    }
    return favouriteCreatorKeys;
  }
}
