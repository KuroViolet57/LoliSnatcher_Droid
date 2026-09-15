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

/// A link as the description writes it: where it goes and its words (r50).
class LinkedAnchor {
  const LinkedAnchor(this.url, this.text);

  final String url;
  final String text;
}

/// One link from a post's description, resolved.
class LinkedMedia {
  const LinkedMedia({required this.url, required this.kind, this.booru, this.postId, this.text = ''});

  final String url;
  final LinkedMediaKind kind;

  /// The installed source a [LinkedMediaKind.sourcePost] belongs to, and its post id.
  final Booru? booru;
  final String? postId;

  /// The words of the link in the description.
  final String text;

  String get host => (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp('^www\\.'), '');

  /// An animation file that shows as a picture (GIF), not a video.
  bool get isImage => LinkedMediaResolver.imageExtensions.contains(LinkedMediaResolver.extensionOf(url));

  /// The search that finds a [LinkedMediaKind.sourcePost] on its source.
  String get searchTerm => LinkedMediaResolver.searchTermFor(booru!, postId!);

  static const Set<String> _vague = {'link', 'here', 'click here', 'this', 'url'};

  /// [text] when it says something: not empty, not "link", not the address.
  String get _words {
    final String t = text.replaceAll(RegExp(r'^[\s<>«»|:\-–—•*]+|[\s<>«»|:\-–—•*]+$'), '');
    if (t.isEmpty || _vague.contains(t.toLowerCase()) || t.toLowerCase().startsWith('http')) return '';
    if (t.contains('/')) {
      final String bare = url.replaceFirst(RegExp('^https?://'), '');
      final String shown = t.replaceAll(RegExp(r'(\.\.\.|…)$'), '');
      if (bare.startsWith(shown)) return '';
    }
    return t;
  }

  String get _fileName => (Uri.tryParse(url)?.pathSegments ?? const []).lastWhere((s) => s.isNotEmpty, orElse: () => '');

  /// What the link is: its words, else the post, the file or the site.
  String get title {
    final String words = _words;
    if (words.isNotEmpty) return words;
    return switch (kind) {
      LinkedMediaKind.sourcePost => '${booru?.name ?? host} post #$postId',
      LinkedMediaKind.media => _fileName.isEmpty ? host : _fileName,
      LinkedMediaKind.page => host,
    };
  }

  /// Where a tap takes it.
  String get destination => switch (kind) {
    LinkedMediaKind.sourcePost => 'Opens in the app · ${booru?.name ?? host}',
    LinkedMediaKind.media => 'Plays here · $host',
    LinkedMediaKind.page => 'Opens the web page · $host',
  };

  String get badge => switch (kind) {
    LinkedMediaKind.sourcePost => 'In app',
    LinkedMediaKind.media => isImage ? 'Animation' : 'Video',
    LinkedMediaKind.page => 'Web',
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

  static final RegExp _anchor = RegExp(r'<a\b([^>]*)>(.*?)</a\s*>', caseSensitive: false, dotAll: true);
  static final RegExp _href = RegExp('href\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false);

  /// The lower-case extension of [url]'s path, or ''.
  static String extensionOf(String url) {
    final String path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    final String last = path.split('/').last;
    final int dot = last.lastIndexOf('.');
    return dot < 0 ? '' : last.substring(dot + 1);
  }

  /// FurAffinity sends outside links through its `/externalurl/?q=` page;
  /// the link is where that page leads.
  static String unwrap(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.host.toLowerCase().endsWith('furaffinity.net') || !uri.path.startsWith('/externalurl')) return url;
    final String target = (uri.queryParameters['q'] ?? '').trim();
    return target.toLowerCase().startsWith('http') ? target : url;
  }

  /// Every web link in [html] with its words, once each, in order; relative
  /// links against [base], redirect pages unwrapped. Profile links (an
  /// artist's name) and script links are left out.
  static List<LinkedAnchor> anchorsIn(String html, {String? base}) {
    final List<LinkedAnchor> out = [];
    final Set<String> seen = {};
    for (final RegExpMatch m in _anchor.allMatches(html)) {
      final String? raw = _href.firstMatch(m.group(1)!)?.group(1);
      final String? url = raw == null ? null : _clean(raw, base);
      if (url != null && seen.add(url)) out.add(LinkedAnchor(url, _text(m.group(2)!)));
    }
    return out;
  }

  /// The addresses of [anchorsIn].
  static List<String> linksIn(String html, {String? base}) => [for (final LinkedAnchor a in anchorsIn(html, base: base)) a.url];

  static String? _clean(String raw, String? base) {
    String href = raw.replaceAll('&amp;', '&').trim();
    if (href.startsWith('//')) href = 'https:$href';
    if (href.startsWith('/') && base != null) href = '${base.replaceAll(RegExp(r'/+$'), '')}$href';
    Uri? uri = Uri.tryParse(unwrap(href));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    if (RegExp(r'^/users?/').hasMatch(uri.path)) return null;
    uri = Uri.tryParse(uri.toString().replaceAll(RegExp(r'[).,;!]+$'), ''));
    return uri?.toString();
  }

  static String _text(String inner) => inner
      .replaceAll(RegExp('<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

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
  /// installed source, else a page. [text] is the link's words.
  static LinkedMedia resolve(String url, Iterable<Booru> boorus, {String text = ''}) {
    final String ext = extensionOf(url);
    if (videoExtensions.contains(ext) || imageExtensions.contains(ext)) {
      return LinkedMedia(url: url, kind: LinkedMediaKind.media, text: text);
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      for (final Booru booru in boorus) {
        if (!sameSite(booru, uri)) continue;
        final String? id = postIdFor(booru, uri);
        if (id != null) {
          return LinkedMedia(url: url, kind: LinkedMediaKind.sourcePost, booru: booru, postId: id, text: text);
        }
      }
    }
    return LinkedMedia(url: url, kind: LinkedMediaKind.page, text: text);
  }

  /// The search for one post by id: `id=N` on Shimmie, `id:N` elsewhere.
  static String searchTermFor(Booru booru, String id) => booru.type == BooruType.Shimmie ? 'id=$id' : 'id:$id';
}
