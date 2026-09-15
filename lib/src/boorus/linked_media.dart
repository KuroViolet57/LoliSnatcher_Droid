import 'package:flutter/foundation.dart';

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

/// A link as the description writes it: where it goes, its words, and the
/// words before it on its line (r50, r52).
class LinkedAnchor {
  const LinkedAnchor(this.url, this.text, [this.label = '']);

  final String url;
  final String text;

  /// "WEBM version with sound only" for `WEBM version with sound only: <link>`:
  /// names a link whose own words are its address, or a link in plain text.
  final String label;
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

  bool get hasOwnWords => _words.isNotEmpty;

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

/// The media links of the posts seen this session (r52): the viewer's link
/// button shows once a post's description has been read, for any file.
class LinkedMediaStore {
  const LinkedMediaStore._();

  static final Map<String, List<LinkedMedia>> _byPost = {};

  /// Bumped whenever a post's links become known.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static void remember(String postUrl, List<LinkedMedia> links) {
    _byPost[postUrl] = List.unmodifiable(links);
    revision.value++;
  }

  /// Null until the post's description has been read.
  static List<LinkedMedia>? linksFor(String postUrl) => _byPost[postUrl];

  static bool hasLinks(String postUrl) => _byPost[postUrl]?.isNotEmpty ?? false;

  @visibleForTesting
  static void resetForTests() => _byPost.clear();
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
  static final RegExp _bare = RegExp('https?://[^\\s<>"\']+', caseSensitive: false);
  static final RegExp _lineBreak = RegExp(r'<br\s*/?>|</p>|</div>|\n', caseSensitive: false);

  /// Pages that are media (a video, a post, a file host), by site and path.
  /// A profile, a shop or a personal site is not: the voice actor's site sat
  /// among the media links of the user's example (r52).
  static final List<(String, RegExp)> _mediaPages = [
    ('youtube.com', RegExp(r'^/(watch|shorts/|live/|embed/)')),
    ('youtu.be', RegExp(r'^/.+')),
    ('vimeo.com', RegExp(r'^/(\d+|video/\d+)')),
    for (final String site in ['x.com', 'twitter.com', 'fxtwitter.com', 'vxtwitter.com', 'fixupx.com'])
      (site, RegExp(r'^/[^/]+/status/\d+')),
    ('bsky.app', RegExp(r'^/profile/[^/]+/post/')),
    ('newgrounds.com', RegExp(r'^/(portal/view|art/view|audio/listen)/')),
    ('redgifs.com', RegExp(r'^/(watch|ifr)/')),
    ('gfycat.com', RegExp(r'^/.+')),
    ('imgur.com', RegExp(r'^/(a/|gallery/|[A-Za-z0-9]{5,8}$)')),
    ('streamable.com', RegExp(r'^/[a-z0-9]+$')),
    ('iwara.tv', RegExp(r'^/videos?/')),
    ('rule34video.com', RegExp(r'^/videos?/')),
    ('pornhub.com', RegExp(r'^/view_video')),
    ('xvideos.com', RegExp(r'^/video')),
    ('spankbang.com', RegExp(r'/video/')),
    ('mega.nz', RegExp(r'^/(file|folder)/')),
    ('drive.google.com', RegExp(r'^/(file/d/|open)')),
    ('dropbox.com', RegExp(r'^/(s|scl)/')),
    ('tiktok.com', RegExp(r'/video/\d+')),
    ('instagram.com', RegExp(r'^/(p|reel|reels|tv)/')),
    ('tumblr.com', RegExp(r'/post/')),
    ('deviantart.com', RegExp(r'/art/')),
    ('inkbunny.net', RegExp(r'^/s/\d+')),
    ('weasyl.com', RegExp(r'/submissions?/\d+')),
    ('sofurry.com', RegExp(r'^/view/\d+')),
    ('itaku.ee', RegExp(r'^/(images|posts)/\d+')),
    ('pixiv.net', RegExp(r'^/(en/)?artworks/\d+')),
    ('patreon.com', RegExp(r'^/posts/')),
    ('twitch.tv', RegExp(r'^/(videos/\d+|[^/]+/clip/)')),
    ('clips.twitch.tv', RegExp(r'^/.+')),
    ('reddit.com', RegExp(r'/comments/')),
    ('v.redd.it', RegExp(r'^/.+')),
    ('catbox.moe', RegExp(r'^/.+')),
    ('e621.net', RegExp(r'^/(posts|pools)/\d+')),
    ('e926.net', RegExp(r'^/(posts|pools)/\d+')),
    ('furaffinity.net', RegExp(r'^/(view|full)/\d+')),
  ];

  static bool isMediaPage(Uri uri) {
    final String host = uri.host.toLowerCase();
    for (final (String site, RegExp path) in _mediaPages) {
      if ((host == site || host.endsWith('.$site')) && path.hasMatch(uri.path)) return true;
    }
    return false;
  }

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
  static List<LinkedAnchor> anchorsIn(String html, {String? base}) => [
    for (final (_, LinkedAnchor a) in _anchorsAt(html, base)) a,
  ];

  /// The addresses of [anchorsIn].
  static List<String> linksIn(String html, {String? base}) => [for (final LinkedAnchor a in anchorsIn(html, base: base)) a.url];

  /// The post's media among the links of its description (r52): posts on
  /// installed sources, files and media pages, with links written as plain
  /// text too; not profiles, personal sites or the post itself ([self]).
  static List<LinkedMedia> mediaLinksIn(String html, Iterable<Booru> boorus, {String? base, String? self}) {
    final List<(int, LinkedAnchor)> found = [..._anchorsAt(html, base), ..._bareAt(html, base)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final LinkedMedia? own = self == null ? null : resolve(self, boorus);
    final Set<String> seen = {};
    final List<LinkedMedia> out = [];
    for (final (_, LinkedAnchor a) in found) {
      final LinkedMedia byWords = resolve(a.url, boorus, text: a.text);
      final LinkedMedia media = byWords.hasOwnWords ? byWords : resolve(a.url, boorus, text: a.label);
      if (!seen.add(media.url)) continue;
      if (own != null &&
          (media.url == own.url ||
              (media.kind == LinkedMediaKind.sourcePost && own.kind == LinkedMediaKind.sourcePost && media.booru == own.booru && media.postId == own.postId))) {
        continue;
      }
      final bool keep = switch (media.kind) {
        LinkedMediaKind.sourcePost || LinkedMediaKind.media => true,
        LinkedMediaKind.page => isMediaPage(Uri.parse(media.url)),
      };
      if (keep) out.add(media);
    }
    return out;
  }

  static List<(int, LinkedAnchor)> _anchorsAt(String html, String? base) {
    final List<(int, LinkedAnchor)> out = [];
    final Set<String> seen = {};
    for (final RegExpMatch m in _anchor.allMatches(html)) {
      final String? raw = _href.firstMatch(m.group(1)!)?.group(1);
      final String? url = raw == null ? null : _clean(raw, base);
      if (url != null && seen.add(url)) out.add((m.start, LinkedAnchor(url, _text(m.group(2)!), _labelBefore(html, m.start))));
    }
    return out;
  }

  /// Addresses written as plain text: anchors and tags are blanked to spaces
  /// first, so what is left keeps its offsets.
  static List<(int, LinkedAnchor)> _bareAt(String html, String? base) {
    final String masked = html
        .replaceAllMapped(_anchor, (m) => ' ' * m.group(0)!.length)
        .replaceAllMapped(RegExp('<[^>]+>'), (m) => ' ' * m.group(0)!.length);
    final List<(int, LinkedAnchor)> out = [];
    for (final RegExpMatch m in _bare.allMatches(masked)) {
      final String raw = m.group(0)!.split(RegExp(r'&(lt|gt|quot|#\d+);')).first;
      final String? url = _clean(raw, base);
      if (url != null) out.add((m.start, LinkedAnchor(url, '', _labelBefore(html, m.start))));
    }
    return out;
  }

  static String _labelBefore(String html, int offset) {
    final String before = html.substring(0, offset);
    final Iterable<RegExpMatch> breaks = _lineBreak.allMatches(before);
    final String line = breaks.isEmpty ? before : before.substring(breaks.last.end);
    String t = _text(line).replaceAll(RegExp(r'https?://\S+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'[\s:\-–—•|·>»]+$'), '').trim();
    if (t.length > 60) {
      t = t.substring(t.length - 60);
      final int space = t.indexOf(' ');
      if (space > 0) t = t.substring(space + 1);
    }
    return t;
  }

  static String? _clean(String raw, String? base) {
    String href = raw.replaceAll('&amp;', '&').trim();
    if (href.startsWith('//')) href = 'https:$href';
    if (href.startsWith('/') && base != null) href = '${base.replaceAll(RegExp(r'/+$'), '')}$href';
    Uri? uri = Uri.tryParse(unwrap(href));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    if (RegExp(r'^/users?/').hasMatch(uri.path)) return null;
    uri = Uri.tryParse(uri.toString().replaceAll(RegExp(r'[).,;:!]+$'), ''));
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

  /// The post's own address, without what a description glued to it
  /// ("…/posts/2197699Character(s)").
  static String _postUrl(Booru booru, Uri uri, String id) => switch (booru.type) {
    BooruType.e621 || BooruType.Danbooru => '${uri.scheme}://${uri.host}/posts/$id',
    BooruType.FurAffinity => '${uri.scheme}://${uri.host}/view/$id/',
    _ => uri.toString(),
  };

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
          return LinkedMedia(url: _postUrl(booru, uri, id), kind: LinkedMediaKind.sourcePost, booru: booru, postId: id, text: text);
        }
      }
    }
    return LinkedMedia(url: url, kind: LinkedMediaKind.page, text: text);
  }

  /// The search for one post by id: `id=N` on Shimmie, `id:N` elsewhere.
  static String searchTermFor(Booru booru, String id) => booru.type == BooruType.Shimmie ? 'id=$id' : 'id:$id';
}
