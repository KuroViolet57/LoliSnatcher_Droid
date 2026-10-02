import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/services/incoming_link.dart';

/// r85: a link from another app (Link Sheet, a browser's "open with") to a
/// site you have a source for opens in the app: a post in the viewer, a
/// search as a new tab, a doujin gallery as its page; anything else opens as
/// a web page inside the app. Addresses checked live on 2026-10-02.
void main() {
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  final List<Booru> mine = [
    b('Danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us'),
    b('AiBooru', BooruType.Danbooru, 'https://aibooru.online'),
    b('e621', BooruType.e621, 'https://e621.net'),
    b('gelbooru', BooruType.Gelbooru, 'https://gelbooru.com'),
    b('rule34xxx', BooruType.Gelbooru, 'https://rule34.xxx'),
    b('realbooru', BooruType.Realbooru, 'https://realbooru.com'),
    b('yandere', BooruType.Moebooru, 'https://yande.re'),
    b('rule34paheal', BooruType.Shimmie, 'https://rule34.paheal.net'),
    b('derpibooru', BooruType.Philomena, 'https://derpibooru.org'),
    b('Rule34Us', BooruType.R34US, 'https://rule34.us'),
    b('nhentai', BooruType.NHentai, 'https://nhentai.net'),
    b('E-Hentai', BooruType.EHentai, 'https://e-hentai.org'),
    b('hitomi', BooruType.Hitomi, 'https://hitomi.la'),
    b('eahentai', BooruType.EaHentai, 'https://eahentai.com'),
    b('hentaipaw', BooruType.HentaiPaw, 'https://hentaipaw.com'),
    b('niyaniya', BooruType.NiyaNiya, 'https://niyaniya.moe'),
    b('asm', BooruType.AsmHentai, 'https://asmhentai.com'),
  ];

  IncomingLink parse(String url) => IncomingLink.parse(url, mine);

  group('posts open in the viewer', () {
    for (final (String url, String source, String id) in [
      ('https://danbooru.donmai.us/posts/9876543', 'Danbooru', 'id:9876543'),
      ('https://aibooru.online/posts/177072?q=tomboy', 'AiBooru', 'id:177072'),
      ('https://e621.net/posts/12345', 'e621', 'id:12345'),
      ('https://gelbooru.com/index.php?page=post&s=view&id=111', 'gelbooru', 'id:111'),
      ('https://rule34.xxx/index.php?page=post&s=view&id=222', 'rule34xxx', 'id:222'),
      ('https://yande.re/post/show/333', 'yandere', 'id:333'),
      ('https://rule34.paheal.net/post/view/444', 'rule34paheal', 'id=444'),
      ('https://www.e621.net/posts/55', 'e621', 'id:55'),
    ]) {
      test(url, () {
        final IncomingLink link = parse(url);
        expect(link.kind, IncomingLinkKind.post);
        expect(link.booru!.name, source);
        expect(link.media!.kind, LinkedMediaKind.sourcePost);
        expect(link.media!.searchTerm, id);
      });
    }
  });

  group('searches open as a new tab', () {
    for (final (String url, String source, String query) in [
      ('https://danbooru.donmai.us/posts?tags=cat_ears+solo', 'Danbooru', 'cat_ears solo'),
      ('https://aibooru.online/posts?tags=tomboy', 'AiBooru', 'tomboy'),
      ('https://e621.net/posts?tags=cat%20rating%3As', 'e621', 'cat rating:s'),
      ('https://gelbooru.com/index.php?page=post&s=list&tags=cat_ears+solo', 'gelbooru', 'cat_ears solo'),
      ('https://rule34.xxx/index.php?page=post&s=list&tags=all', 'rule34xxx', ''),
      ('https://realbooru.com/index.php?page=post&s=list&tags=redhead', 'realbooru', 'redhead'),
      ('https://yande.re/post?tags=cat_ears', 'yandere', 'cat_ears'),
      ('https://rule34.paheal.net/post/list/Pokemon%20Pikachu/1', 'rule34paheal', 'Pokemon Pikachu'),
      ('https://derpibooru.org/search?q=safe%2C+cute+pony', 'derpibooru', 'safe cute_pony'),
      ('https://rule34.us/index.php?r=posts/index&q=cat_ears+solo', 'Rule34Us', 'cat_ears solo'),
    ]) {
      test(url, () {
        final IncomingLink link = parse(url);
        expect(link.kind, IncomingLinkKind.search);
        expect(link.booru!.name, source);
        expect(link.query, query);
      });
    }
  });

  group('doujin galleries open as their page', () {
    for (final (String url, String source, String query, String postURL) in [
      ('https://nhentai.net/g/500000/', 'nhentai', 'id:500000', 'https://nhentai.net/g/500000/'),
      ('https://nhentai.net/g/500000/3/', 'nhentai', 'id:500000', 'https://nhentai.net/g/500000/'),
      ('https://e-hentai.org/g/123456/0a1b2c3d4e/', 'E-Hentai', 'id:123456/0a1b2c3d4e', 'https://e-hentai.org/g/123456/0a1b2c3d4e/'),
      ('https://exhentai.org/g/123456/0a1b2c3d4e/', 'E-Hentai', 'id:123456/0a1b2c3d4e', 'https://e-hentai.org/g/123456/0a1b2c3d4e/'),
      ('https://hitomi.la/doujinshi/some-title-japanese-456.html', 'hitomi', 'id:456', 'https://hitomi.la/galleries/456.html'),
      ('https://hitomi.la/reader/456.html#3', 'hitomi', 'id:456', 'https://hitomi.la/galleries/456.html'),
      ('https://eahentai.com/a/789', 'eahentai', 'id:789', 'https://eahentai.com/a/789'),
      ('https://hentaipaw.com/articles/55', 'hentaipaw', 'id:55', 'https://hentaipaw.com/articles/55'),
      ('https://niyaniya.moe/g/1234/abcdef1234', 'niyaniya', 'id:1234/abcdef1234', 'https://niyaniya.moe/g/1234/abcdef1234'),
      ('https://asmhentai.com/g/321/', 'asm', 'id:321', 'https://asmhentai.com/g/321/'),
    ]) {
      test(url, () {
        final IncomingLink link = parse(url);
        expect(link.kind, IncomingLinkKind.doujin);
        expect(link.booru!.name, source);
        expect(link.query, query);
        expect(link.postURL, postURL);
      });
    }
  });

  group('anything else opens as a page inside the app', () {
    for (final String url in [
      'https://danbooru.donmai.us/wiki_pages/cat_ears',
      'https://konachan.com/post/show/1', // no konachan source here
      'https://example.org/some/page',
      'https://nhentai.net/tag/cat-ears/',
    ]) {
      test(url, () {
        final IncomingLink link = parse(url);
        expect(link.kind, IncomingLinkKind.other);
        expect(link.media!.url, url);
      });
    }
  });

  group('what each kind of link does', () {
    late List<String> did;

    setUp(() {
      did = [];
      IncomingLinks.openTab = (query, booru, {doujinPostURL}) => did.add('tab ${booru.name} "$query" ${doujinPostURL ?? ''}'.trim());
      IncomingLinks.openMedia = (context, media) async => did.add('open ${media.kind.name} ${media.url}');
    });

    tearDown(IncomingLinks.resetForTests);

    testWidgets('a post opens in the viewer, a search and a gallery as a tab', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final BuildContext context = tester.element(find.byType(SizedBox));
      await IncomingLinks.open(context, 'https://e621.net/posts/12345', mine);
      await IncomingLinks.open(context, 'https://gelbooru.com/index.php?page=post&s=list&tags=cat_ears', mine);
      await IncomingLinks.open(context, 'https://nhentai.net/g/500000/', mine);
      await IncomingLinks.open(context, 'https://example.org/x', mine);
      expect(did, [
        'open sourcePost https://e621.net/posts/12345',
        'tab gelbooru "cat_ears"',
        'tab nhentai "id:500000" https://nhentai.net/g/500000/',
        'open page https://example.org/x',
      ]);
    });
  });
}
