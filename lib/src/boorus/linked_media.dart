import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';

/// What a link in a post's description leads to (r49).
enum LinkedMediaKind {
  /// A post on one of the person's own sources: opens in the app's viewer.
  sourcePost,

  /// A video or animation file: plays in the linked media player.
  media,

  /// Any other page: opens in the linked media player's webview.
  page,
}

/// One link from a post's description, resolved.
class LinkedMedia {
  const LinkedMedia({required this.url, required this.kind, this.booru, this.postId});

  final String url;
  final LinkedMediaKind kind;

  /// The installed source a [LinkedMediaKind.sourcePost] belongs to, and its post id.
  final Booru? booru;
  final String? postId;

  String get host => (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp('^www\\.'), '');

  /// An animation file that shows as a picture (GIF), not a video.
  bool get isImage => LinkedMediaResolver.imageExtensions.contains(LinkedMediaResolver.extensionOf(url));

  /// The search that finds a [LinkedMediaKind.sourcePost] on its source.
  String get searchTerm => LinkedMediaResolver.searchTermFor(booru!, postId!);

  String get label => switch (kind) {
    LinkedMediaKind.sourcePost => 'Open on ${booru?.name ?? host}',
    LinkedMediaKind.media => isImage ? 'Show the animation' : 'Play the video',
    LinkedMediaKind.page => 'Open $host',
  };
}

/// Reads the links a post's description gives for its animation or video
/// (r49): many FurAffinity "animated" posts are a still picture whose
/// description links to the real thing — a post on e621 or another booru, a
/// video file, or a page elsewhere.
class LinkedMediaResolver {
  const LinkedMediaResolver._();

  static const Set<String> videoExtensions = {'mp4', 'webm', 'mov', 'm4v', 'mkv'};
  static const Set<String> imageExtensions = {'gif', 'apng'};

  static final RegExp _href = RegExp('href\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false);

  /// The lower-case extension of [url]'s path, or ''.
  static String extensionOf(String url) {
    final String path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    final String last = path.split('/').last;
    final int dot = last.lastIndexOf('.');
    return dot < 0 ? '' : last.substring(dot + 1);
  }

  /// Every web link in [html], once each, in order; relative links against
  /// [base]. Profile links (an artist's name) and script links are left out.
  static List<String> linksIn(String html, {String? base}) {
    final List<String> out = [];
    final Set<String> seen = {};
    for (final RegExpMatch m in _href.allMatches(html)) {
      String href = m.group(1)!.replaceAll('&amp;', '&').trim();
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/') && base != null) href = '${base.replaceAll(RegExp(r'/+$'), '')}$href';
      final Uri? uri = Uri.tryParse(href);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) continue;
      if (RegExp(r'^/users?/').hasMatch(uri.path)) continue;
      final String clean = uri.toString().replaceAll(RegExp(r'[).,;!]+$'), '');
      if (seen.add(clean)) out.add(clean);
    }
    return out;
  }

  static String _site(String host) => host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  /// [uri] is on [booru]'s site.
  static bool sameSite(Booru booru, Uri uri) {
    final String own = _site(Uri.tryParse(booru.baseURL ?? '')?.host ?? '');
    return own.isNotEmpty && own == _site(uri.host);
  }

  /// The post id in [uri] for [booru]'s engine, or null when it is not a post.
  static String? postIdFor(Booru booru, Uri uri) {
    String? path(String pattern) => RegExp(pattern).firstMatch(uri.path)?.group(1);
    switch (booru.type) {
      case BooruType.e621 || BooruType.Danbooru:
        return path(r'^/posts/(\d+)');
      case BooruType.Gelbooru || BooruType.GelbooruAlike || BooruType.GelbooruV1 || BooruType.Realbooru:
        final String id = uri.queryParameters['id'] ?? '';
        return uri.queryParameters['page'] == 'post' && RegExp(r'^\d+$').hasMatch(id) ? id : null;
      case BooruType.FurAffinity:
        return path(r'^/(?:view|full)/(\d+)');
      case BooruType.Philomena:
        return path(r'^/(?:images/)?(\d+)/?$');
      case BooruType.Shimmie:
        return path(r'^/post/view/(\d+)');
      case BooruType.Moebooru || BooruType.Sankaku || BooruType.IdolSankaku:
        return path(r'^/post/show/(\d+)');
      default:
        return null;
    }
  }

  /// A file first (even on a source's own file host), then a post on an
  /// installed source, else a page.
  static LinkedMedia resolve(String url, Iterable<Booru> boorus) {
    final String ext = extensionOf(url);
    if (videoExtensions.contains(ext) || imageExtensions.contains(ext)) {
      return LinkedMedia(url: url, kind: LinkedMediaKind.media);
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      for (final Booru booru in boorus) {
        if (!sameSite(booru, uri)) continue;
        final String? id = postIdFor(booru, uri);
        if (id != null) return LinkedMedia(url: url, kind: LinkedMediaKind.sourcePost, booru: booru, postId: id);
      }
    }
    return LinkedMedia(url: url, kind: LinkedMediaKind.page);
  }

  /// The search for one post by id: `id=N` on Shimmie, `id:N` elsewhere.
  static String searchTermFor(Booru booru, String id) => booru.type == BooruType.Shimmie ? 'id=$id' : 'id:$id';
}
