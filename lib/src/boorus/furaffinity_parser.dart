import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';

/// One submission page, as read (r40).
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
    this.comments = 0,
    this.favorites = 0,
    this.rating = '',
    this.postedAt,
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
  final int comments;
  final int favorites;
  final String rating;
  final int? postedAt;
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
/// search, gallery, scraps and favorites page shares, one submission page,
/// an artist's profile.
class FurAffinityParser {
  const FurAffinityParser._();

  static String abs(String url) {
    final String u = url.trim();
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return '${FurAffinityQuery.site}$u';
    return u;
  }

  static int _int(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// The site's own kind of submission as a tag: image, music, text, flash.
  static Tag typeTag(String type) => Tag('type:$type', tagType: TagType.meta);

  static const Map<String, String> _types = {'image': 'image', 'audio': 'music', 'text': 'text', 'flash': 'flash'};

  static final RegExp _thumbSize = RegExp(r'@\d+-');

  static List<BooruItem> listing(String html) {
    final dom.Document doc = html_parser.parse(html);
    final List<BooruItem> out = [];
    final Set<String> seen = {};
    for (final dom.Element figure in doc.querySelectorAll('figure')) {
      final String fid = figure.id;
      if (!fid.startsWith('sid-')) continue;
      final BooruItem? item = _figure(figure, fid.substring(4));
      if (item != null && seen.add(item.serverId ?? '')) out.add(item);
    }
    return out;
  }

  static BooruItem? _figure(dom.Element figure, String id) {
    if (id.isEmpty) return null;
    final dom.Element? img = figure.querySelector('img');
    final String src = img?.attributes['src'] ?? '';
    if (src.isEmpty) return null;
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

    final List<String> siteTags = (img?.attributes['data-tags'] ?? '').split(' ').where((t) => t.isNotEmpty).toList();
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

  /// A gallery or scraps page links its next page with a "Next" form.
  static bool galleryHasNext(String html) =>
      RegExp(r'<form action="/(?:gallery|scraps)/[^"]+/\d+/" method="get">\s*<button[^>]*>\s*Next', caseSensitive: false).hasMatch(html);

  /// A favorites page links its next page by a cursor.
  static String? favoritesCursor(String html) => RegExp(r'/favorites/[^/"]+/(\d+)/next').firstMatch(html)?.group(1);

  static FurAffinitySubmission? submission(String html) {
    final dom.Document doc = html_parser.parse(html);
    final dom.Element? img = doc.querySelector('#submissionImg');
    String file = img?.attributes['data-fullview-src'] ?? img?.attributes['src'] ?? '';
    if (file.isEmpty) {
      for (final dom.Element a in doc.querySelectorAll('a')) {
        final String href = a.attributes['href'] ?? '';
        if (href.contains('d.furaffinity.net/art/')) {
          file = href;
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

    int views = 0, comments = 0, favorites = 0;
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
            comments = _int(value);
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

    return FurAffinitySubmission(
      fileUrl: abs(file),
      previewUrl: abs(img?.attributes['data-preview-src'] ?? ''),
      title: (doc.querySelector('.submission-title h2')?.text ?? '').trim(),
      artist: artist,
      artistName: (doc.querySelector('.c-usernameBlockSimple__displayName')?.text ?? '').trim(),
      avatarUrl: avatar.isEmpty ? '' : abs(avatar),
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
      favorites: favorites,
      rating: rating,
      postedAt: int.tryParse(doc.querySelector('.popup_date')?.attributes['data-time'] ?? ''),
    );
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
