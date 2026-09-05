import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/data/booru.dart';

enum KemonoSiteId { kemono, pawchive }

/// One kemono-style site: kemono.cr itself, or pawchive.pw — the archive
/// running the older kemono API. Same handler, same pages, same sidebar;
/// what differs is written down here and nowhere else: hosts, the Accept
/// header, which endpoints exist, how a post detail is shaped, how sign-in
/// works. Checked live 2026-09-04 (kemono) and 2026-09-05 (pawchive).
// ignore: use_enums
class KemonoSite {
  const KemonoSite._({
    required this.id,
    required this.name,
    required this.site,
    required this.thumbBase,
    required this.iconBase,
    required this.fileHosts,
    required this.fixedFileHost,
    required this.acceptHeader,
    required this.mediaHeaders,
    required this.services,
    required this.detailIsEnvelope,
    required this.hasRandom,
    required this.hasPopular,
    required this.hasTagList,
    required this.hasDms,
    required this.hasUpdatedArtists,
    required this.hasApiLogin,
    required this.hasSearchCount,
    required this.minQueryLength,
    required this.creatorTable,
    required this.indexMetaFile,
  });

  final KemonoSiteId id;

  /// Lower-case, as in messages ("pawchive has no popular feed").
  final String name;

  /// `https://kemono.cr`
  final String site;

  /// Host of `/thumbnail/data{path}` (800 px).
  final String thumbBase;

  /// Host of `/icons/{service}/{id}` and `/banners/{service}/{id}`.
  final String iconBase;

  /// The hosts full files come from, for the reachability probe.
  final List<String> fileHosts;

  /// One host for every file (pawchive); null = kemono's hashed pick.
  final String? fixedFileHost;

  /// kemono's DDoS-Guard 403s a browser Accept on the API; pawchive is plain.
  final String acceptHeader;

  /// What a file request carries beyond the browser UA.
  final Map<String, String> mediaHeaders;

  /// The services the index can hold, for the Artists page chips.
  final List<String> services;

  /// kemono wraps a post detail as `{post, attachments, previews, videos}`;
  /// pawchive returns the post itself.
  final bool detailIsEnvelope;
  final bool hasRandom;
  final bool hasPopular;
  final bool hasTagList;
  final bool hasDms;
  final bool hasUpdatedArtists;

  /// `POST /api/v1/authentication/login` (kemono) vs the site's login form.
  final bool hasApiLogin;

  /// kemono's `/posts` answers `count`/`true_count`; pawchive a bare array.
  final bool hasSearchCount;
  final int minQueryLength;
  final String creatorTable;
  final String indexMetaFile;

  String get api => '$site/api/v1';

  bool get isKemono => id == KemonoSiteId.kemono;

  static const KemonoSite kemono = KemonoSite._(
    id: KemonoSiteId.kemono,
    name: 'kemono',
    site: 'https://kemono.cr',
    thumbBase: 'https://img.kemono.cr',
    iconBase: 'https://img.kemono.cr',
    fileHosts: ['n1.kemono.cr', 'n2.kemono.cr', 'n3.kemono.cr', 'n4.kemono.cr'],
    fixedFileHost: null,
    acceptHeader: 'text/css',
    mediaHeaders: {'Referer': 'https://kemono.cr/'},
    services: ['patreon', 'fanbox', 'gumroad', 'discord', 'fantia', 'boosty', 'subscribestar', 'dlsite'],
    detailIsEnvelope: true,
    hasRandom: true,
    hasPopular: true,
    hasTagList: true,
    hasDms: true,
    hasUpdatedArtists: true,
    hasApiLogin: true,
    hasSearchCount: true,
    minQueryLength: 3,
    creatorTable: 'KemonoCreator',
    indexMetaFile: 'kemono_creators.json',
  );

  /// pawchive.pw: kemono's archive on the older API — no random, popular,
  /// tag list, DMs or "updated" feed (all 404), a flat post detail, the site
  /// login form instead of an API login, one file host, and a plain JSON
  /// Accept. The file host answers heavy fetching with a 403 that threatens
  /// IP blocks, so nothing here prefetches files.
  static const KemonoSite pawchive = KemonoSite._(
    id: KemonoSiteId.pawchive,
    name: 'pawchive',
    site: 'https://pawchive.pw',
    thumbBase: 'https://img.pawchive.pw',
    iconBase: 'https://pawchive.pw',
    fileHosts: ['file.pawchive.pw'],
    fixedFileHost: 'https://file.pawchive.pw',
    acceptHeader: 'application/json',
    mediaHeaders: {},
    services: ['patreon', 'fanbox'],
    detailIsEnvelope: false,
    hasRandom: false,
    hasPopular: false,
    hasTagList: false,
    hasDms: false,
    hasUpdatedArtists: false,
    hasApiLogin: false,
    hasSearchCount: false,
    minQueryLength: 2,
    creatorTable: 'PawchiveCreator',
    indexMetaFile: 'pawchive_creators.json',
  );

  static const List<KemonoSite> all = [kemono, pawchive];

  static KemonoSite ofId(KemonoSiteId id) => id == KemonoSiteId.pawchive ? pawchive : kemono;

  static KemonoSite ofType(BooruType? type) => type == BooruType.Pawchive ? pawchive : kemono;

  static KemonoSite of(Booru? booru) => ofType(booru?.type);

  /// The site a file host belongs to, if any.
  static KemonoSite? ofFileHost(String host) {
    final String h = host.toLowerCase();
    for (final s in all) {
      if (s.fileHosts.contains(h)) return s;
    }
    return null;
  }

  // ── URLs ─────────────────────────────────────────────────────────────

  String creatorPath(String service, String id) => '$api/$service/user/$id';

  /// `/posts?q=&o=&tag=&tag=` — `tag` repeats, so the query is built by hand.
  String postsUrl({String? base, String q = '', int offset = 0, List<String> tags = const []}) {
    final List<String> parts = [];
    if (q.isNotEmpty) parts.add('q=${Uri.encodeQueryComponent(q)}');
    parts.add('o=$offset');
    for (final String t in tags) {
      parts.add('tag=${Uri.encodeQueryComponent(t)}');
    }
    return '${base ?? '$api/posts'}?${parts.join('&')}';
  }

  String creatorPostsUrl(String service, String id, {String q = '', int offset = 0, List<String> tags = const []}) =>
      postsUrl(base: '${creatorPath(service, id)}/posts', q: q, offset: offset, tags: tags);

  String popularUrl({required String period, required String date, int offset = 0}) =>
      '$api/posts/popular?date=$date&period=$period&o=$offset';

  String postUrl(String service, String user, String postId) => '$site/$service/user/$user/post/$postId';

  String thumbUrl(String path) => '$thumbBase/thumbnail/data$path';

  /// A file's URL: the host the detail names when there is one, else the
  /// site's own — pawchive's single host, kemono's hashed pick.
  String fileUrl(String path, {String? server}) {
    if (server != null && server.isNotEmpty) return '$server/data$path';
    if (fixedFileHost != null) return '$fixedFileHost/data$path';
    return '${KemonoApi.fileServer(path)}/data$path';
  }

  String iconUrl(String service, String id) => '$iconBase/icons/$service/$id';

  String bannerUrl(String service, String id) => '$iconBase/banners/$service/$id';

  String get loginUrl => hasApiLogin ? '$api/authentication/login' : '$site/account/login';

  String get logoutUrl => hasApiLogin ? '$api/authentication/logout' : '$site/account/logout';

  String get favicon => isKemono ? '$site/favicon.ico' : '$site/static/favicon.png';
}
