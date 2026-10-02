import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/linked_media_sheet.dart';

enum IncomingLinkKind { post, search, doujin, other }

/// r85: what a link from another app (Link Sheet, a browser's "open with")
/// is, among your sources: a post, a search, a doujin gallery - or anything
/// else. Search and gallery addresses were checked live on 2026-10-02.
class IncomingLink {
  const IncomingLink._(this.kind, this.url, {this.booru, this.query = '', this.media, this.postURL});

  final IncomingLinkKind kind;
  final String url;

  /// The source the link belongs to (none for [IncomingLinkKind.other]).
  final Booru? booru;

  /// The search a search or gallery link opens as a tab.
  final String query;

  /// What a post or another link opens (LinkedMediaOpener).
  final LinkedMedia? media;

  /// A gallery's own address: its detail tab's identity.
  final String? postURL;

  static IncomingLink parse(String url, Iterable<Booru> boorus) {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      for (final Booru b in boorus) {
        if (!DoujinDataHandler.isDoujinBooru(b) || b.type == BooruType.ForYouDoujin || !_sameDoujinSite(b, uri)) continue;
        final ({String id, String postURL})? g = doujinGallery(b, uri);
        if (g != null) {
          return IncomingLink._(
            IncomingLinkKind.doujin,
            url,
            booru: b,
            query: SearchTab.doujinIdQueryFrom(serverId: g.id, postURL: g.postURL),
            postURL: g.postURL,
          );
        }
      }
    }
    final List<Booru> sources = [for (final Booru b in boorus) if (!DoujinDataHandler.isDoujinBooru(b)) b];
    final LinkedMedia media = LinkedMediaResolver.resolve(url, sources);
    if (media.kind == LinkedMediaKind.sourcePost) {
      return IncomingLink._(IncomingLinkKind.post, url, booru: media.booru, media: media);
    }
    if (uri != null && media.kind == LinkedMediaKind.page) {
      for (final Booru b in sources) {
        if (!LinkedMediaResolver.sameSite(b, uri)) continue;
        final String? q = searchQueryFor(b, uri);
        if (q != null) return IncomingLink._(IncomingLinkKind.search, url, booru: b, query: q);
      }
    }
    return IncomingLink._(IncomingLinkKind.other, url, media: media);
  }

  static String _tags(String raw) => raw.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).join(' ');

  /// The app's search for a search page of [booru]'s engine, or null.
  static String? searchQueryFor(Booru booru, Uri uri) {
    final String path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final Map<String, String> q = uri.queryParameters;
    switch (booru.type) {
      case BooruType.Danbooru || BooruType.e621:
        return path == '/posts' ? _tags(q['tags'] ?? '') : null;
      case BooruType.Gelbooru || BooruType.GelbooruAlike || BooruType.GelbooruV1 || BooruType.Realbooru:
        if (q['page'] != 'post' || q['s'] != 'list') return null;
        final String tags = _tags(q['tags'] ?? '');
        return tags == 'all' ? '' : tags;
      case BooruType.Moebooru:
        return path == '/post' || path == '/post/index' ? _tags(q['tags'] ?? '') : null;
      case BooruType.Sankaku || BooruType.IdolSankaku:
        // r86: `/?tags=` is the sites' own search (open-search.xml), behind
        // an optional language like `/en/`.
        final bool listing = RegExp(r'^(?:/[a-z]{2}(?:-[a-zA-Z]{2,4})?)?(?:/posts|/post/index)?$').hasMatch(path);
        return listing && q.containsKey('tags') ? _tags(q['tags']!) : null;
      case BooruType.Shimmie:
        if (path == '/post/list') return '';
        final RegExpMatch? m = RegExp(r'^/post/list/([^/]+)(?:/\d+)?$').firstMatch(path);
        return m == null ? null : _tags(Uri.decodeComponent(m.group(1)!));
      case BooruType.Philomena:
        if (path != '/search') return null;
        // The site's tags are comma-separated, with spaces; the app's are
        // space-separated, with underscores (PhilomenaHandler.makeURL).
        return (q['q'] ?? '').split(',').map((t) => t.trim().replaceAll(RegExp(r'\s+'), '_')).where((t) => t.isNotEmpty).join(' ');
      case BooruType.R34US:
        return q['r'] == 'posts/index' ? _tags(q['q'] ?? '') : null;
      default:
        return null;
    }
  }

  static const Map<String, String> _doujinMirrors = {
    'exhentai.org': 'e-hentai.org',
    'shupogaki.moe': 'niyaniya.moe',
  };

  static String _site(String host) {
    final String h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    return _doujinMirrors[h] ?? h;
  }

  static bool _sameDoujinSite(Booru booru, Uri uri) {
    final String own = _site(DoujinDataHandler.hostOf(booru));
    return own.isNotEmpty && own == _site(uri.host);
  }

  /// A gallery address on [booru]'s doujin source: its id, and the address
  /// the source's own listings give it (the detail tab's identity).
  static ({String id, String postURL})? doujinGallery(Booru booru, Uri uri) {
    final Uri? site = Uri.tryParse(booru.baseURL ?? '');
    if (site == null || site.host.isEmpty) return null;
    final String origin = '${site.scheme.isEmpty ? 'https' : site.scheme}://${site.host}';
    final String path = uri.path;
    String? one(String pattern) => RegExp(pattern).firstMatch(path)?.group(1);
    switch (booru.type) {
      case BooruType.NHentai || BooruType.AsmHentai:
        final String? id = one(r'^/g/(\d+)');
        return id == null ? null : (id: id, postURL: '$origin/g/$id/');
      case BooruType.Faccina:
        final String? id = one(r'^/g/(\d+)');
        return id == null ? null : (id: id, postURL: '$origin/g/$id');
      case BooruType.NiyaNiya || BooruType.HDoujin:
        final RegExpMatch? m = RegExp(r'^/g/(\d+)/([A-Za-z0-9]+)').firstMatch(path);
        return m == null ? null : (id: m.group(1)!, postURL: '$origin/g/${m.group(1)}/${m.group(2)}');
      case BooruType.EHentai:
        final RegExpMatch? m = RegExp(r'^/g/(\d+)/([0-9a-f]+)').firstMatch(path);
        return m == null ? null : (id: m.group(1)!, postURL: '$origin/g/${m.group(1)}/${m.group(2)}/');
      case BooruType.EaHentai:
        final String? id = one(r'^/a/(\d+)');
        return id == null ? null : (id: id, postURL: '$origin/a/$id');
      case BooruType.Hitomi:
        if (!RegExp('^/(galleries|reader|doujinshi|manga|cg|gamecg|imageset|anime)/').hasMatch(path)) return null;
        final String? id = one(r'(\d+)\.html$');
        return id == null ? null : (id: id, postURL: '$origin/galleries/$id.html');
      case BooruType.HentaiPaw:
        final String? id = one(r'^/articles/(\d+)');
        return id == null ? null : (id: id, postURL: '$origin/articles/$id');
      default:
        return null;
    }
  }
}

/// r85: opens a link another app handed over (main.dart's openAppLink).
class IncomingLinks {
  const IncomingLinks._();

  /// A search or a gallery: a new tab, switched to - the link was opened on
  /// purpose, the one more exception to "tabs never kidnap".
  static void Function(String query, Booru booru, {String? doujinPostURL}) openTab = _defaultOpenTab;

  /// A post (the viewer, over the current page) or any other link (the
  /// app's own page view, so it never bounces back to the app).
  static Future<void> Function(BuildContext context, LinkedMedia media) openMedia = _defaultOpenMedia;

  static void resetForTests() {
    openTab = _defaultOpenTab;
    openMedia = _defaultOpenMedia;
  }

  static Future<void> open(BuildContext context, String url, Iterable<Booru> boorus) async {
    final IncomingLink link = IncomingLink.parse(url, boorus);
    Logger.Inst().log(
      'link from another app: ${link.kind.name}${link.booru != null ? ' on ${link.booru!.name}' : ''}',
      'IncomingLinks',
      'open',
      LogTypes.booruHandlerInfo,
    );
    switch (link.kind) {
      case IncomingLinkKind.search:
        openTab(link.query, link.booru!);
      case IncomingLinkKind.doujin:
        openTab(link.query, link.booru!, doujinPostURL: link.postURL);
      case IncomingLinkKind.post || IncomingLinkKind.other:
        await openMedia(context, link.media!);
    }
  }

  static void _defaultOpenTab(String query, Booru booru, {String? doujinPostURL}) {
    SearchHandler.instance.addTabByString(query, customBooru: booru, switchToNew: true, doujinPostURL: doujinPostURL);
  }

  static Future<void> _defaultOpenMedia(BuildContext context, LinkedMedia media) => LinkedMediaOpener.open(context, media);
}
