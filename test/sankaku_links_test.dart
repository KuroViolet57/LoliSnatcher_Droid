import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/services/incoming_link.dart';
import 'package:lolisnatcher/src/services/source_links.dart';

/// r86: a Sankaku source is stored under its API address (sankakuapi.com),
/// so links to the site itself never matched it. The site, checked live on
/// 2026-10-02 (its own router and open-search file): posts at
/// `/posts/<id>` and `/post/show/<id>`, with an optional `/en/` or `/ja/`,
/// on www.sankakucomplex.com and sankaku.app; search at `/?tags=`;
/// chan.sankakucomplex.com now leads to a login page. Idol moved from
/// idol.sankakucomplex.com to www.idolcomplex.com (same paths). The API
/// finds a post with `id:<n>`.
void main() {
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  final Booru sankaku = b('Sankaku', BooruType.Sankaku, 'https://sankakuapi.com');
  final Booru idol = b('Idol', BooruType.IdolSankaku, 'https://iapi.sankakucomplex.com');
  final List<Booru> mine = [b('Danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us'), sankaku, idol];

  group("posts on any of Sankaku's addresses open on the source", () {
    for (final (String url, Booru source) in [
      ('https://www.sankakucomplex.com/posts/62825356', sankaku),
      ('https://sankakucomplex.com/en/posts/62825356', sankaku),
      ('https://sankaku.app/ja/posts/62825356?tags=cat_ears', sankaku),
      ('https://chan.sankakucomplex.com/post/show/62825356', sankaku),
      ('https://www.idolcomplex.com/posts/1000000', idol),
      ('https://idol.sankakucomplex.com/post/show/1000000', idol),
    ]) {
      test(url, () {
        final IncomingLink link = IncomingLink.parse(url, mine);
        expect(link.kind, IncomingLinkKind.post);
        expect(link.booru!.name, source.name);
        expect(link.media!.searchTerm, 'id:${url.contains('idol') ? '1000000' : '62825356'}');
        // The same resolver reads links inside other posts' descriptions.
        expect(LinkedMediaResolver.resolve(url, mine).kind, LinkedMediaKind.sourcePost);
      });
    }
  });

  group("Sankaku's searches open as a tab", () {
    for (final (String url, String source, String query) in [
      ('https://www.sankakucomplex.com/?tags=cat_ears+solo', 'Sankaku', 'cat_ears solo'),
      ('https://sankaku.app/en/?tags=cat_ears', 'Sankaku', 'cat_ears'),
      ('https://www.sankakucomplex.com/posts?tags=rating%3Asafe', 'Sankaku', 'rating:safe'),
      ('https://www.idolcomplex.com/?tags=cosplay', 'Idol', 'cosplay'),
    ]) {
      test(url, () {
        final IncomingLink link = IncomingLink.parse(url, mine);
        expect(link.kind, IncomingLinkKind.search);
        expect(link.booru!.name, source);
        expect(link.query, query);
      });
    }
  });

  test('a Sankaku source on its own (self-hosted) address keeps only that address', () {
    final Booru mirror = b('Mirror', BooruType.Sankaku, 'https://my-mirror.example.org');
    expect(LinkedMediaResolver.siteHosts(mirror), {'my-mirror.example.org'});
    expect(LinkedMediaResolver.siteHosts(sankaku), containsAll(['sankakucomplex.com', 'www.sankakucomplex.com', 'chan.sankakucomplex.com', 'sankaku.app']));
    expect(LinkedMediaResolver.siteHosts(idol), containsAll(['www.idolcomplex.com', 'idol.sankakucomplex.com']));
  });

  test('"Open in browser" goes straight to the post, not to the login page', () {
    expect(LinkedMediaResolver.browserAddress('https://chan.sankakucomplex.com/post/show/62825356'), 'https://www.sankakucomplex.com/posts/62825356');
    expect(LinkedMediaResolver.browserAddress('https://beta.sankakucomplex.com/post/show/7'), 'https://www.sankakucomplex.com/posts/7');
    expect(LinkedMediaResolver.browserAddress('https://idol.sankakucomplex.com/post/show/1000000'), 'https://www.idolcomplex.com/posts/1000000');
    for (final String other in ['https://danbooru.donmai.us/posts/1', 'https://www.sankakucomplex.com/posts/5', 'not a link']) {
      expect(LinkedMediaResolver.browserAddress(other), other);
    }
  });

  test("every post's Open in browser and Share goes through the browser address", () {
    for (final String path in [
      'lib/src/widgets/gallery/hideable_appbar.dart',
      'lib/src/widgets/video/guess_extension_viewer.dart',
      'lib/src/widgets/video/load_item_viewer.dart',
      'lib/src/widgets/video/flash_play_viewer.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('LinkedMediaResolver.browserAddress('), reason: path);
      expect(RegExp(r'launchUrlString\(\s*(widget\.)?item\.postURL').hasMatch(source), isFalse, reason: path);
      expect(RegExp(r'shareTextAction\(\s*item\.postURL').hasMatch(source), isFalse, reason: path);
    }
  });

  test('Settings -> Links counts a Sankaku source as covered, Idol too', () {
    expect(SourceLinks.sites, containsAll(['sankakucomplex.com', 'sankaku.app', 'idolcomplex.com']));
    final r = SourceLinks.coverage([sankaku, idol]);
    expect(r.covered.map((b) => b.name), ['Sankaku', 'Idol']);
    expect(r.uncovered, isEmpty);
  });
}
