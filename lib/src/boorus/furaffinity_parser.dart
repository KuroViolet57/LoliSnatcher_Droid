import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';

/// One of an artist's gallery folders (r42).
class FurAffinityFolder {
  const FurAffinityFolder({
    required this.user,
    required this.id,
    required this.slug,
    required this.name,
    this.group = '',
    this.count = 0,
  });

  final String user;
  final String id;
  final String slug;
  final String name;

  /// The heading the artist filed it under ("My fursona's"), or ''.
  final String group;
  final int count;

  /// The query that opens it as a feed.
  String get term => FurAffinityQuery.folderTerm(user, id, slug);
}

/// A comment under a submission (r42).
class FurAffinityComment {
  const FurAffinityComment({
    required this.id,
    required this.username,
    this.displayName = '',
    this.avatarUrl = '',
    this.text = '',
    this.postedAt,
  });

  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String text;
  final int? postedAt;
}

/// One row of a watch list (r42).
class FurAffinityWatchEntry {
  const FurAffinityWatchEntry({required this.username, this.displayName = ''});

  final String username;
  final String displayName;
}

/// The account's blocklist, as the site puts it on every page for its own
/// script (r42): blocked tags, blocked artists (as `u_name`), and whether
/// submissions without keywords are hidden too. The site's script only blurs
/// what it blocks; the app leaves it out.
class FurAffinityBlocklist {
  const FurAffinityBlocklist({this.tags = const {}, this.users = const {}, this.hideTagless = false});

  static const FurAffinityBlocklist none = FurAffinityBlocklist();

  final Set<String> tags;
  final Set<String> users;
  final bool hideTagless;

  bool get isEmpty => tags.isEmpty && users.isEmpty && !hideTagless;

  static bool _isMeta(String tag) => tag.startsWith('u_') || tag.startsWith('c_') || tag.startsWith('t_') || tag.startsWith('s_');

  /// A submission with these `data-tags` is blocked.
  bool blocks(List<String> dataTags) {
    if (isEmpty) return false;
    bool hasKeyword = false;
    for (final String raw in dataTags) {
      final String tag = raw.toLowerCase();
      if (tags.contains(tag) || users.contains(tag)) return true;
      if (!_isMeta(tag)) hasKeyword = true;
    }
    return hideTagless && !hasKeyword;
  }
}

/// One submission page, as read (r40; folders, description, comments,
/// neighbours and the account's favourite link since r42).
class FurAffinitySubmission {
  const FurAffinitySubmission({
    required this.fileUrl,
    this.previewUrl = '',
    this.title = '',
    this.artist = '',
    this.artistName = '',
    this.avatarUrl = '',
    this.keywords = const [],
    this.category = '',
    this.theme = '',
    this.species = '',
    this.resolution = '',
    this.fileSize = '',
    this.views = 0,
    this.comments = const [],
    this.commentCount = 0,
    this.favorites = 0,
    this.rating = '',
    this.postedAt,
    this.descriptionHtml = '',
    this.folders = const [],
    this.olderId,
    this.newerId,
    this.gallery = const [],
    this.favLink,
  });

  final String fileUrl;
  final String previewUrl;
  final String title;
  final String artist;
  final String artistName;
  final String avatarUrl;
  final List<String> keywords;
  final String category;
  final String theme;
  final String species;
  final String resolution;
  final String fileSize;
  final int views;
  final List<FurAffinityComment> comments;
  final int commentCount;
  final int favorites;
  final String rating;
  final int? postedAt;
  final String descriptionHtml;
  final List<FurAffinityFolder> folders;

  /// The artist's previous (older) and next (newer) submission in the gallery.
  final String? olderId;
  final String? newerId;

  /// The mini gallery of the artist's work the page shows.
  final List<BooruItem> gallery;

  /// Logged in: the link that favourites (or unfavourites) it.
  final ({String path, bool faved})? favLink;
}

/// An artist's profile header, as read (r40).
class FurAffinityUser {
  const FurAffinityUser({
    required this.username,
    this.displayName = '',
    this.avatarUrl = '',
    this.submissions = 0,
    this.favorites = 0,
    this.views = 0,
  });

  final String username;
  final String displayName;
  final String avatarUrl;
  final int submissions;
  final int favorites;
  final int views;
}

/// Reads FurAffinity's pages (r40): the listing figures every browse,
/// search, gallery, scraps, favorites, folder and inbox page shares, one
/// submission page, an artist's profile, folders and watch list.
class FurAffinityParser {
  const FurAffinityParser._();

  static String abs(String url) {
    final String u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return '${FurAffinityQuery.site}$u';
    return u;
  }

  static int _int(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// The site's own kind of submission as a tag: image, music, text, flash.
  static Tag typeTag(String type) => Tag('type:$type', tagType: TagType.meta);

  static const Map<String, String> _types = {'image': 'image', 'audio': 'music', 'text': 'text', 'flash': 'flash'};

  static final RegExp _thumbSize = RegExp(r'@\d+-');
  static final RegExp _sid = RegExp(r'^sid[-_](\d+)$');

  /// The blocklist the page carries for the site's script; none logged out.
  static FurAffinityBlocklist blocklist(String html) {
    final RegExpMatch? body = RegExp(r'<body\b[^>]*>').firstMatch(html);
    if (body == null) return FurAffinityBlocklist.none;
    final String tag = body.group(0)!;
    String attr(String name) => RegExp('$name="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
    if (attr('data-user-logged-in') != '1') return FurAffinityBlocklist.none;
    Set<String> words(String value) => value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w.toLowerCase()).toSet();
    return FurAffinityBlocklist(
      tags: words(attr('data-tag-blocklist')),
      users: words(attr('data-user-blocklist')),
      hideTagless: attr('data-tag-blocklist-hide-tagless') == '1',
    );
  }

  /// Every submission figure on a listing page, without the ones the
  /// account's blocklist blocks ([blocklist]: the page's own by default).
  static List<BooruItem> listing(String html, {FurAffinityBlocklist? blocklist}) {
    final FurAffinityBlocklist block = blocklist ?? FurAffinityParser.blocklist(html);
    return _figures(html_parser.parse(html).querySelectorAll('figure'), block);
  }

  static List<BooruItem> _figures(List<dom.Element> figures, FurAffinityBlocklist block) {
    final List<BooruItem> out = [];
    final Set<String> seen = {};
    for (final dom.Element figure in figures) {
      final RegExpMatch? id = _sid.firstMatch(figure.id);
      if (id == null) continue;
      final BooruItem? item = _figure(figure, id.group(1)!, block);
      if (item != null && seen.add(item.serverId ?? '')) out.add(item);
    }
    return out;
  }

  static BooruItem? _figure(dom.Element figure, String id, FurAffinityBlocklist block) {
    final dom.Element? img = figure.querySelector('img');
    final String src = img?.attributes['src'] ?? '';
    if (src.isEmpty) return null;
    final List<String> siteTags = (img?.attributes['data-tags'] ?? '').split(' ').where((t) => t.isNotEmpty).toList();
    if (block.blocks(siteTags)) return null;

    String rating = '';
    String type = '';
    String classUser = '';
    for (final String c in figure.classes) {
      if (c.startsWith('r-')) rating = c.substring(2);
      if (c.startsWith('t-')) type = _types[c.substring(2)] ?? c.substring(2);
      if (c.startsWith('u-')) classUser = c.substring(2);
    }

    String title = '';
    String artist = '';
    String artistName = '';
    final dom.Element? caption = figure.querySelector('figcaption');
    if (caption != null) {
      for (final dom.Element a in caption.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.startsWith('/view/') && title.isEmpty) {
          title = (a.attributes['title'] ?? a.text).trim();
        } else if (href.startsWith('/user/') && artist.isEmpty) {
          artist = href.split('/').where((p) => p.isNotEmpty).last.toLowerCase();
          artistName = (a.attributes['title'] ?? a.text).trim();
        }
      }
    }
    if (title.isEmpty) title = (img?.attributes['alt'] ?? '').trim();

    final List<Tag> tags = [];
    final Set<String> names = {};
    void add(String name, TagType type) {
      if (name.isEmpty || !names.add(name)) return;
      tags.add(Tag(name, tagType: type));
    }

    if (artist.isEmpty) {
      final String fromTags = siteTags.firstWhere((t) => t.startsWith('u_'), orElse: () => '');
      artist = fromTags.isNotEmpty ? fromTags.substring(2) : classUser;
    }
    if (artist.isNotEmpty) add('artist:$artist', TagType.artist);
    if (rating.isNotEmpty) add('rating:$rating', TagType.meta);
    if (type.isNotEmpty) add('type:$type', TagType.meta);
    for (final String t in siteTags) {
      if (t.startsWith('u_')) continue;
      if (t.startsWith('c_')) {
        if (t != 'c_all') add('category:${t.substring(2)}', TagType.meta);
      } else if (t.startsWith('t_')) {
        if (t != 't_all') add('theme:${t.substring(2)}', TagType.meta);
      } else if (t.startsWith('s_')) {
        if (t != 's_unspecified_any') add('species:${t.substring(2)}', TagType.meta);
      } else {
        add(t, TagType.none);
      }
    }

    final String thumb = abs(src);
    final String sample = thumb.replaceFirst(_thumbSize, '@600-');
    final BooruItem item = BooruItem(
      fileURL: sample,
      sampleURL: sample,
      thumbnailURL: thumb,
      tagsList: tags,
      postURL: '${FurAffinityQuery.site}/view/$id/',
      serverId: id,
      description: title,
      rating: rating.isEmpty ? null : rating,
      uploaderName: artistName.isNotEmpty ? artistName : (artist.isEmpty ? null : artist),
      previewWidth: double.tryParse(img?.attributes['data-width'] ?? ''),
      previewHeight: double.tryParse(img?.attributes['data-height'] ?? ''),
    );
    item.possibleMediaType.value = type == 'image' || type.isEmpty ? MediaType.image : MediaType.unknown;
    item.mediaType.value = MediaType.needToLoadItem;
    return item;
  }

  /// The Ruffle (Flash emulator) script a Flash submission page loads (r42b).
  static String? ruffleScript(String html) {
    final String? src = RegExp(r'<script[^>]*src="([^"]*ruffle[^"]*\.js)"').firstMatch(html)?.group(1);
    return src == null ? null : abs(src);
  }

  /// A gallery, scraps or folder page links its next page with a "Next" form.
  static bool galleryHasNext(String html) =>
      RegExp(r'<form action="/(?:gallery|scraps)/[^"]+/\d+/" method="get">\s*<button[^>]*>\s*Next', caseSensitive: false).hasMatch(html);

  /// A favorites page links its next page by a cursor.
  static String? favoritesCursor(String html) => RegExp(r'/favorites/[^/"]+/(\d+)/next').firstMatch(html)?.group(1);

  /// The submissions inbox links its next page as `new~<id>@<count>`.
  static String? inboxCursor(String html) =>
      RegExp(r'href="/msg/submissions/((?:new|old)~\d+@\d+)/"[^>]*>\s*Next', caseSensitive: false).firstMatch(html)?.group(1);

  static final RegExp _folderHref = RegExp(r'^/gallery/([^/]+)/folder/(\d+)/?([^/]*)');

  static FurAffinityFolder? _folderFrom(dom.Element a, {String group = '', String? name}) {
    final RegExpMatch? m = _folderHref.firstMatch(a.attributes['href'] ?? '');
    if (m == null) return null;
    return FurAffinityFolder(
      user: m.group(1)!.toLowerCase(),
      id: m.group(2)!,
      slug: m.group(3) ?? '',
      name: (name ?? a.text).trim(),
      group: group.trim(),
      count: _int(a.attributes['title'] ?? ''),
    );
  }

  static FurAffinitySubmission? submission(String html) {
    final dom.Document doc = html_parser.parse(html);
    final dom.Element? img = doc.querySelector('#submissionImg');
    String file = img?.attributes['data-fullview-src'] ?? img?.attributes['src'] ?? '';
    // Flash (r42b): the movie is the embed's data.
    if (file.isEmpty) {
      final dom.Element? embed = doc.querySelector('object#flash_embed') ?? doc.querySelector('object[type="application/x-shockwave-flash"]');
      file = embed?.attributes['data'] ?? embed?.querySelector('param[name="movie"]')?.attributes['value'] ?? '';
    }
    if (file.isEmpty) {
      for (final dom.Element a in doc.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.contains('d.furaffinity.net/art/')) {
          file = href;
          break;
        }
      }
    }
    if (file.isEmpty) {
      // The download link carries the same file under /download/.
      for (final dom.Element a in doc.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.contains('d.furaffinity.net/download/')) {
          file = href.replaceFirst('/download/', '/');
          break;
        }
      }
    }
    if (file.isEmpty) return null;

    String artist = '';
    String avatar = '';
    final dom.Element? artistBlock = doc.querySelector('.submission-description-artist');
    if (artistBlock != null) {
      for (final dom.Element a in artistBlock.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.startsWith('/user/')) {
          artist = href.split('/').where((p) => p.isNotEmpty).last.toLowerCase();
          break;
        }
      }
      avatar = artistBlock.querySelector('img')?.attributes['src'] ?? '';
    }

    final Map<String, String> content = {};
    final dom.Element? contentStats = doc.querySelector('.submission-content-stats');
    if (contentStats != null && contentStats.children.length >= 2) {
      final List<dom.Element> labels = contentStats.children[0].children;
      final List<dom.Element> values = contentStats.children[1].children;
      for (int i = 0; i < labels.length && i < values.length; i++) {
        content[labels[i].text.trim().toLowerCase()] = values[i].text.trim();
      }
    }

    int views = 0, commentCount = 0, favorites = 0;
    String rating = '';
    final dom.Element? pageStats = doc.querySelector('.submission-page-stats');
    if (pageStats != null) {
      for (final dom.Element stat in pageStats.children) {
        final String label = stat.attributes['title'] ?? '';
        final String value = stat.children.isEmpty ? '' : stat.children.first.text;
        switch (label) {
          case 'Views':
            views = _int(value);
          case 'Comments':
            commentCount = _int(value);
          case 'Favorites':
            favorites = _int(value);
        }
        for (final dom.Element e in stat.querySelectorAll('div')) {
          for (final String c in e.classes) {
            if (c.startsWith('c-contentRating--')) rating = c.substring('c-contentRating--'.length);
          }
        }
      }
    }

    final List<FurAffinityFolder> folders = [
      for (final dom.Element a in doc.querySelectorAll('.submission-folder a'))
        ?_folderFrom(a, group: a.querySelector('strong')?.text ?? '', name: a.querySelector('span')?.text),
    ];

    final List<FurAffinityComment> comments = [];
    for (final dom.Element c in doc.querySelectorAll('.comment_container')) {
      final String cid = (c.querySelector('a.comment_anchor')?.id ?? '').replaceFirst('cid:', '');
      String username = '';
      for (final dom.Element a in c.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.startsWith('/user/')) {
          username = href.split('/').where((p) => p.isNotEmpty).last.toLowerCase();
          break;
        }
      }
      comments.add(
        FurAffinityComment(
          id: cid,
          username: username,
          displayName: (c.querySelector('.js-displayName')?.text ?? '').trim(),
          avatarUrl: abs(c.querySelector('img.comment_useravatar')?.attributes['src'] ?? ''),
          text: (c.querySelector('.comment_text')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
          postedAt: int.tryParse(c.attributes['data-timestamp'] ?? ''),
        ),
      );
    }

    String? older;
    String? newer;
    for (final dom.Element a in doc.querySelectorAll('.minigallery-navigation a')) {
      final String? target = RegExp(r'/view/(\d+)/').firstMatch(a.attributes['href'] ?? '')?.group(1);
      if (target == null) continue;
      final String label = a.text.toLowerCase();
      if (label.contains('older')) older ??= target;
      if (label.contains('newer')) newer ??= target;
    }

    final FurAffinityBlocklist block = blocklist(html);
    final List<BooruItem> gallery = [
      for (final dom.Element section in doc.querySelectorAll('section.minigallery-container')) ..._figures(section.querySelectorAll('figure'), block),
    ];

    return FurAffinitySubmission(
      fileUrl: abs(file),
      previewUrl: abs(img?.attributes['data-preview-src'] ?? ''),
      title: (doc.querySelector('.submission-title h2')?.text ?? '').trim(),
      artist: artist,
      artistName: (doc.querySelector('.c-usernameBlockSimple__displayName')?.text ?? '').trim(),
      avatarUrl: abs(avatar),
      keywords: [
        for (final dom.Element a in doc.querySelectorAll('.submission-tags a'))
          if ((a.attributes['href'] ?? '').startsWith('/search/@keywords') && a.text.trim().isNotEmpty) a.text.trim(),
      ],
      category: content['category'] ?? '',
      theme: content['theme'] ?? '',
      species: content['species'] ?? '',
      resolution: content['resolution'] ?? '',
      fileSize: content['file size'] ?? '',
      views: views,
      comments: comments,
      commentCount: commentCount,
      favorites: favorites,
      rating: rating,
      postedAt: int.tryParse(doc.querySelector('.popup_date')?.attributes['data-time'] ?? ''),
      descriptionHtml: (doc.querySelector('.submission-description .submission-description-text')?.innerHtml ?? '').trim(),
      folders: folders,
      olderId: older,
      newerId: newer,
      gallery: gallery,
      favLink: favLink(html),
    );
  }

  /// An artist's gallery folders, from the folder list of their gallery page,
  /// each under the heading it is filed under.
  static List<FurAffinityFolder> userFolders(String html) {
    final dom.Element? list = html_parser.parse(html).querySelector('.user-folders');
    if (list == null) return const [];
    final List<FurAffinityFolder> out = [];
    String group = '';
    for (final dom.Element e in list.querySelectorAll('h4, a')) {
      if (e.localName == 'h4') {
        group = e.text.trim();
        continue;
      }
      final FurAffinityFolder? f = _folderFrom(e, group: group);
      if (f != null) out.add(f);
    }
    return out;
  }

  /// The watch button's link on a profile, when it works (logged in it
  /// carries a key); null otherwise.
  static ({String path, bool watching})? watchLink(String html) {
    final RegExpMatch? m = RegExp(r'href="(/(un)?watch/[^/"]+/\?key=([^"]*))"').firstMatch(html);
    if (m == null || (m.group(3) ?? '').isEmpty) return null;
    return (path: m.group(1)!, watching: m.group(2) != null);
  }

  /// The favourite link on a submission page (logged in); null otherwise.
  static ({String path, bool faved})? favLink(String html) {
    final RegExpMatch? m = RegExp(r'href="(/(un)?fav/\d+/\?key=([^"]+))"').firstMatch(html);
    if (m == null) return null;
    return (path: m.group(1)!, faved: m.group(2) != null);
  }

  /// The account a logged-in page belongs to, from its avatar in the header.
  static String? loggedInUser(String html) {
    final RegExpMatch? img = RegExp(r'<img\b[^>]*class="[^"]*loggedin_user_avatar[^"]*"[^>]*>').firstMatch(html);
    if (img == null) return null;
    final String tag = img.group(0)!;
    final String? fromSrc = RegExp(r'src="[^"]*/([^/"]+)\.(?:gif|png|jpe?g)"').firstMatch(tag)?.group(1);
    final String? name = fromSrc ?? RegExp(r'alt="([^"]+)"').firstMatch(tag)?.group(1);
    return name?.trim().toLowerCase();
  }

  /// A page of a watch list (`/watchlist/by/name/`), and whether it goes on.
  static ({List<FurAffinityWatchEntry> users, bool hasNext}) watchlist(String html) {
    final dom.Document doc = html_parser.parse(html);
    final List<FurAffinityWatchEntry> users = [];
    for (final dom.Element row in doc.querySelectorAll('.watch-list-items')) {
      final dom.Element? a = row.querySelector('a[href^="/user/"]');
      if (a == null) continue;
      final String username = (a.attributes['href'] ?? '').split('/').where((p) => p.isNotEmpty).last.toLowerCase();
      users.add(
        FurAffinityWatchEntry(
          username: username,
          displayName: (row.querySelector('.c-usernameBlockSimple__displayName')?.text ?? username).trim(),
        ),
      );
    }
    bool hasNext = false;
    for (final RegExpMatch f in RegExp(r'<form[^>]*action="/watchlist/[^"]*"[^>]*>(.*?)</form>', dotAll: true).allMatches(html)) {
      final String inner = f.group(1)!;
      if (RegExp(r'>\s*Next').hasMatch(inner) && !inner.contains('disabled')) hasNext = true;
    }
    return (users: users, hasNext: hasNext);
  }

  static FurAffinityUser? user(String html) {
    final dom.Document doc = html_parser.parse(html);
    final dom.Element? avatarLink = doc.querySelector('userpage-nav-avatar a');
    final String href = avatarLink?.attributes['href'] ?? '';
    final String username = href.startsWith('/user/') ? href.split('/').where((p) => p.isNotEmpty).last.toLowerCase() : '';
    if (username.isEmpty) return null;
    int stat(String label) => _int(RegExp('$label:</span>\\s*([\\d,]+)').firstMatch(html)?.group(1) ?? '');
    return FurAffinityUser(
      username: username,
      displayName: (doc.querySelector('.js-displayName')?.text ?? '').trim(),
      avatarUrl: abs(avatarLink?.querySelector('img')?.attributes['src'] ?? ''),
      submissions: stat('Submissions'),
      favorites: stat('Favs'),
      views: stat('Views'),
    );
  }
}
