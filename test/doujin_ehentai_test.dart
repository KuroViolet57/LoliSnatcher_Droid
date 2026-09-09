import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_query.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_download_handler.dart';
import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';

/// e-hentai.org / exhentai.org, against pages captured anonymously from the
/// live site on 2026-09-09 (test/fixtures/ehentai_*): the extended listing,
/// a search and its cursor page, a 17-page gallery, a 1,997-page gallery
/// (blocks 0 and 1), one page view, the showpage and gdata API answers.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru booru = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  EHentaiHandler handler() => EHentaiHandler(booru, 25);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('ehentai');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    EHentaiSessionHandler.instance.resetForTests();
    EHentaiHandler.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    EHentaiSessionHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('query grammar', () {
    test("an app tag becomes the site's exact-match term; words and uploader: pass through", () {
      expect(EHentaiQuery.siteTerm('female:big_breasts'), r'female:"big breasts"$');
      expect(EHentaiQuery.siteTerm('-female:big_breasts'), r'-female:"big breasts"$');
      expect(EHentaiQuery.siteTerm('language:english'), r'language:"english"$');
      expect(EHentaiQuery.siteTerm('parody:genshin_impact'), r'parody:"genshin impact"$');
      expect(EHentaiQuery.siteTerm('yuri'), 'yuri', reason: 'a bare word is a title/keyword search');
      expect(EHentaiQuery.siteTerm('uploader:Jose222'), 'uploader:Jose222');
    });

    test('category chips exclude everything not picked; rating and pages go to the advanced search', () {
      final s = EHentaiQuery.parse('category:doujinshi category:manga female:x');
      expect(s.excludedCategories, 1023 - 2 - 4);
      expect(s.terms, [r'female:"x"$']);
      expect(EHentaiQuery.parse('').excludedCategories, 0);
      expect(EHentaiQuery.parse('rating:4').minRating, 4);
      expect(EHentaiQuery.parse('pages:10-50').minPages, 10);
      expect(EHentaiQuery.parse('pages:10-50').maxPages, 50);
      expect(EHentaiQuery.parse('category:blorp').error, contains('category'));
      // The site has no `category` namespace, so a negated one would search
      // a term that matches nothing at all.
      expect(EHentaiQuery.parse('-category:cosplay').error, contains('cannot be excluded'));
      expect(EHentaiQuery.parse('-rating:4').error, contains('cannot be excluded'));
      // A quoted phrase survives tokenising.
      expect(EHentaiQuery.parse('female:"big breasts"').terms, [r'female:"big breasts"$']);
      expect(EHentaiQuery.parse('"two words" solo').terms, ['"two words"', 'solo']);
    });

    test('listing URLs: extended view, encoded terms, the excluded mask, the cursor', () {
      const String site = 'https://e-hentai.org';
      expect(EHentaiQuery.listingUrl(site, EHentaiQuery.parse('')), 'https://e-hentai.org/?inline_set=dm_e');
      expect(
        EHentaiQuery.listingUrl(site, EHentaiQuery.parse('female:big_breasts language:english')),
        'https://e-hentai.org/?f_search=female%3A%22big+breasts%22%24+language%3A%22english%22%24&inline_set=dm_e',
      );
      expect(
        EHentaiQuery.listingUrl(site, EHentaiQuery.parse('category:doujinshi genshin')),
        'https://e-hentai.org/?f_search=genshin&f_cats=1021&inline_set=dm_e',
      );
      expect(
        EHentaiQuery.listingUrl(site, EHentaiQuery.parse('rating:4 pages:10-50 genshin')),
        'https://e-hentai.org/?f_search=genshin&advsearch=1&f_srdd=4&f_spf=10&f_spt=50&inline_set=dm_e',
      );
      expect(
        EHentaiQuery.listingUrl(site, EHentaiQuery.parse('genshin'), cursor: '4177729'),
        'https://e-hentai.org/?f_search=genshin&inline_set=dm_e&next=4177729',
      );
    });
  });

  group('listing', () {
    test('25 rows read in full from the extended view', () {
      final h = handler();
      final List<BooruItem> items = h.itemsFromListing(fixture('ehentai_listing.html'));
      expect(items, hasLength(25));
      final BooruItem first = items.first;
      expect(first.serverId, '4178435');
      expect(first.postURL, 'https://e-hentai.org/g/4178435/29ec786079/', reason: 'identity is always the e-hentai host, whichever host was read');
      expect(first.thumbnailURL, 'https://ehgt.org/w/02/626/10708-2os3py2j.webp');
      expect(first.description, startsWith('[ThiccWithaQ] August 2026 Archive'));
      expect(first.uploaderName, 'Jose222');
      expect(first.fileCountHint.value, 35);
      expect(first.postDate, '2026-09-09 00:55');
      final tags = {for (final t in first.tagsList) t.fullString: t.tagType};
      expect(tags.keys, contains('english'));
      expect(h.tagNamespace('english'), 'language');
      expect(tags.keys, contains('western'));
      expect(h.tagNamespace('western'), 'category');
      expect(tags.keys.every((k) => !k.contains(':')), isTrue, reason: 'names are stored bare');
      expect(EHentaiHandler.tokenFor('4178435'), '29ec786079', reason: 'the session remembers gallery tokens');
    });

    test('the cursor, the result count and the exhentai thumbnail rewrite', () {
      final String html = fixture('ehentai_listing.html');
      expect(EHentaiHandler.nextCursor(html), '4177729');
      expect(EHentaiHandler.resultCount(html), 43310);
      expect(EHentaiHandler.nextCursor(fixture('ehentai_search_p2.html')), isNotNull);
      expect(
        EHentaiHandler.thumbUrl('https://s.exhentai.org/w/02/626/10708-2os3py2j.webp'),
        'https://ehgt.org/w/02/626/10708-2os3py2j.webp',
        reason: 'exhentai thumbnails need cookies; the same path on ehgt.org does not',
      );
      expect(EHentaiHandler.thumbUrl('https://ehgt.org/w/1.webp'), 'https://ehgt.org/w/1.webp');
    });

    test('a bare tag the source knows is searched as that tag, not as a title word (review)', () {
      final h = handler();
      h.itemsFromListing(fixture('ehentai_listing.html'));
      // 'english' was seen under `language:` on the listing, so tapping the
      // chip must search the tag, not every title containing the word.
      expect(h.makeURL('english'), contains('f_search=${Uri.encodeQueryComponent(r'language:"english"$')}'));
      // 'western' is a CATEGORY on this site, and the site filters those
      // with the category mask rather than a search term: 1023 - 512.
      expect(h.makeURL('western'), 'https://e-hentai.org/?f_cats=511&inline_set=dm_e');
      expect(h.makeURL('a_word_no_source_knows'), contains('f_search=${Uri.encodeQueryComponent('"a word no source knows"')}'));
    });

    test('makeURL: page 1 from the grammar, page 2 only through the cursor the previous page gave', () {
      final h = handler();
      expect(h.makeURL('genshin'), 'https://e-hentai.org/?f_search=genshin&inline_set=dm_e');
      h.pageNum = 1;
      expect(h.makeURL('genshin'), '', reason: 'no cursor: this is the end of the list');
      expect(h.errorString, isEmpty, reason: 'the end of a list is not an error');
      expect(h.locked, isTrue, reason: 'the grid stops asking instead of showing a failure');
      h.locked = false;
      h.rememberCursor(page: 2, cursor: '4177729');
      expect(h.makeURL('genshin'), 'https://e-hentai.org/?f_search=genshin&inline_set=dm_e&next=4177729');
      h.pageNum = -1;
      expect(h.makeURL('category:blorp'), '');
      expect(h.locked, isTrue);
    });

    test('page 2 of a TAG search finds its cursor — the query the app qualifies is still one query (r31)', () async {
      // The reported bug: a tag search loaded 25 galleries and stopped. The
      // cursor was filed under the raw query and looked up under the
      // qualified one, and the map is cleared whenever the key changes.
      final h = handler();
      // Page 1 teaches the source that `english` is a `language:` tag, which
      // is exactly what makes the two spellings drift apart.
      h.currentTags = 'english';
      final List page1 = await h.parseListFromResponse(_Resp(fixture('ehentai_search.html')));
      expect(page1, hasLength(25));
      expect(h.qualifyQuery('english'), 'language:english', reason: 'the listing taught the namespace');
      h.pageNum = 1;
      final String page2 = h.makeURL('english');
      expect(page2, contains('next=3718414'), reason: 'the cursor page 1 handed over must survive');
      expect(page2, contains(Uri.encodeQueryComponent(r'language:"english"$')));
      expect(h.locked, isFalse);
      expect(h.errorString, isEmpty);
    });

    test('the same holds for a two-word query and for one that was already qualified', () async {
      for (final String query in ['big breasts', 'language:english', 'english  spaced']) {
        final h = handler();
        h.currentTags = query;
        await h.parseListFromResponse(_Resp(fixture('ehentai_search.html')));
        h.pageNum = 1;
        expect(h.makeURL(query), contains('next=3718414'), reason: query);
        expect(h.locked, isFalse, reason: query);
      }
    });

    test('a different query starts its own cursor list', () async {
      final h = handler();
      h.currentTags = 'english';
      await h.parseListFromResponse(_Resp(fixture('ehentai_search.html')));
      h.pageNum = 1;
      expect(h.makeURL('something else'), '', reason: 'no cursor was ever stored for this query');
      expect(h.locked, isTrue);
    });

    test('a listing the app cannot read is named, not shown as an empty grid (r30 live)', () async {
      final h = handler();
      h.currentTags = '';
      final List items = await h.parseListFromResponse(_Resp('<html><body><table class="itg gltc"><tr><td class="gl1c">x</td></tr></table></body></html>'));
      expect(items, isEmpty);
      expect(h.errorString, contains('display mode'));
    });

    test('a listing response records the cursor for the next page and the total', () async {
      final h = handler();
      h.currentTags = 'genshin';
      final List items = await h.parseListFromResponse(_Resp(fixture('ehentai_search.html')));
      expect(items, hasLength(25));
      h.pageNum = 1;
      expect(h.makeURL('genshin'), endsWith('&next=3718414'));
      expect(h.totalCount.value, 90);
    });
  });

  group('gallery page', () {
    test('titles, metadata, tags by namespace and the page keys of a 17-page gallery', () {
      final h = handler();
      final EHentaiGallery g = h.galleryFromHtml(fixture('ehentai_gallery.html'), gid: '4149118', token: '17c2f87e13');
      expect(g.title, '[Shakariki Pineapple (8kCud)] Yatare! Jahoda (Genshin impact) [English] [Itorio Fransuaza] [Digital]');
      expect(g.titleJpn, contains('やたれ'));
      expect(g.pages, 17);
      expect(g.uploader, 'Rogabute');
      expect(g.posted, '2026-08-26 23:39');
      expect(g.rating, '4.64');
      expect(g.favorited, 34);
      expect(g.parentGid, '4020276');
      expect(g.pageKeys[1], 'f5cad5dda2');
      expect(g.pageKeys[2], 'b177a328d5');
      expect(g.pageKeys[3], '03d4710290');
      expect(g.pageKeys, hasLength(17));
      expect(g.blockSize, 17, reason: 'one block holds the whole gallery');
      final names = {for (final t in g.tags) t.fullString: t.tagType};
      expect(names['english'], TagType.meta);
      expect(h.tagNamespace('english'), 'language');
      expect(names['genshin_impact'], TagType.copyright);
      expect(names['aether'], TagType.character);
      expect(h.tagNamespace('aether'), 'character');
      expect(names.keys, contains('non-h'), reason: 'this gallery is filed Non-H');
      expect(h.tagNamespace('non-h'), 'category');
      expect(names.keys, contains('rogabute'));
      expect(h.tagNamespace('rogabute'), 'uploader');
      expect(names.keys.every((k) => !k.contains(':')), isTrue);
    });

    test('a 1,997-page gallery: the count from the page counter, 20 keys per block, block 1 continues at 21', () {
      final h = handler();
      final EHentaiGallery g0 = h.galleryFromHtml(fixture('ehentai_gallery_multi.html'), gid: '4178032', token: '49d94b3d3c');
      expect(g0.pages, 1997);
      expect(g0.blockSize, 20);
      expect(g0.pageKeys.keys, [for (int i = 1; i <= 20; i++) i]);
      final Map<int, String> block1 = EHentaiHandler.pageKeysFromHtml(fixture('ehentai_gallery_multi_p1.html'));
      expect(block1.keys.first, 21);
      expect(block1.keys.last, 40);
      expect(EHentaiHandler.blockUrl('https://e-hentai.org/g/4178032/49d94b3d3c/', 0), 'https://e-hentai.org/g/4178032/49d94b3d3c/');
      expect(EHentaiHandler.blockUrl('https://e-hentai.org/g/4178032/49d94b3d3c/', 3), 'https://e-hentai.org/g/4178032/49d94b3d3c/?p=3');
    });

    test('loadItem(gallery) registers N pages: the first block by key, the rest as placeholders, all to be resolved on open', () async {
      final h = handler();
      h.fetcher = (url, {postJson}) async => (status: 200, body: fixture('ehentai_gallery_multi.html'), finalUrl: url);
      final item = BooruItem(
        fileURL: 'https://ehgt.org/c.webp',
        sampleURL: 'https://ehgt.org/c.webp',
        thumbnailURL: 'https://ehgt.org/c.webp',
        tagsList: const [],
        postURL: 'https://e-hentai.org/g/4178032/49d94b3d3c/',
        serverId: '4178032',
      );
      final res = await h.loadItem(item: item);
      expect(res.failed, isFalse, reason: res.error);
      final List<BooruItem> pages = ReaderHandler.instance.pagesFor(item)!;
      expect(pages, hasLength(1997));
      expect(item.fileCountHint.value, 1997);
      expect(pages.first.postURL, matches(RegExp(r'^https://e-hentai\.org/s/[0-9a-f]{10}/4178032-1$')));
      expect(pages.first.mediaType.value, MediaType.needToLoadItem);
      expect(pages[20].postURL, 'https://e-hentai.org/g/4178032/49d94b3d3c/?p=1#page-21', reason: 'block 1 not fetched yet');
      expect(pages.last.postURL, 'https://e-hentai.org/g/4178032/49d94b3d3c/?p=99#page-1997');
      expect(pages.every((p) => p.thumbnailURL == item.thumbnailURL), isTrue, reason: 'the site has no per-page thumbnails, only sprites');
      expect(item.tagsList, isNotEmpty);
      expect(item.description, startsWith('[patreon] NewtypeWaifu'), reason: 'this gallery has no japanese title');
    });

    test('an empty body is exhentai without access; a login bounce is named', () async {
      expect(EHentaiHandler.isBlankExHentai(''), isTrue);
      expect(EHentaiHandler.isBlankExHentai('<html>'), isFalse);
      final h = handler();
      h.currentTags = '';
      final List onEh = await h.parseListFromResponse(_Resp('   '));
      expect(onEh, isEmpty);
      expect(h.errorString, isNot(contains('exhentai')), reason: 'e-hentai was the host; do not blame the exhentai session');
      expect(EHentaiHandler.looksLikeLoginBounce('https://e-hentai.org/bounce_login.php?b=d&bt=1-13', ''), isTrue);
      expect(EHentaiHandler.looksLikeLoginBounce('https://e-hentai.org/g/1/a/', '<title>E-Hentai.org Login</title>'), isTrue);
      expect(EHentaiHandler.looksLikeLoginBounce('https://e-hentai.org/g/1/a/', fixture('ehentai_gallery.html')), isFalse);
    });
  });

  group('page resolution', () {
    test('a page view gives the image, its size, the showkey and the reload key', () {
      final info = EHentaiHandler.parsePageHtml(fixture('ehentai_page.html'));
      expect(info.imageUrl, startsWith('https://idzlahb.wkrmfenmiooq.hath.network/h/f5cad5dda21b76aa67a8c4e409e85231c1fc1478-310003-1272-1738-jpg/'));
      expect(info.showkey, '9b0xrd9anff');
      expect(info.reloadKey, '52900-496923');
      expect(info.width, 1272);
      expect(info.height, 1738);
      expect(info.quotaExceeded, isFalse);
      expect(EHentaiHandler.parsePageHtml('<img id="img" src="https://ehgt.org/g/509.gif" />').quotaExceeded, isTrue);
    });

    test('the showpage API answer gives the image and its size', () {
      final Map<String, dynamic> json = jsonDecode(fixture('ehentai_api_showpage.json')) as Map<String, dynamic>;
      final info = EHentaiHandler.parseShowpage(json);
      expect(info.imageUrl, startsWith('https://oxlyaea.gcryrgzkiclc.hath.network:'));
      expect(info.width, 1280);
      expect(info.height, 1771);
    });

    test('placeholders and page-view URLs round-trip', () {
      final h = handler();
      expect(h.pagePlaceholderUrl(gid: '4178032', token: '49d94b3d3c', page: 21), 'https://e-hentai.org/g/4178032/49d94b3d3c/?p=1#page-21');
      final p = EHentaiHandler.parsePagePlaceholder('https://e-hentai.org/g/4178032/49d94b3d3c/?p=1#page-21')!;
      expect((p.gid, p.token, p.block, p.page), ('4178032', '49d94b3d3c', 1, 21));
      final v = EHentaiHandler.parsePageViewUrl('https://e-hentai.org/s/f5cad5dda2/4149118-1')!;
      expect((v.key, v.gid, v.page), ('f5cad5dda2', '4149118', 1));
      expect(EHentaiHandler.parsePageViewUrl('https://e-hentai.org/g/1/a/'), isNull);
    });

    test('loadItem(page): a known key goes through the page view, then the showpage API once the showkey is known', () async {
      final h = handler();
      final List<String> asked = [];
      h.fetcher = (url, {postJson}) async {
        asked.add(postJson == null ? url : 'POST $url $postJson');
        if (postJson != null) return (status: 200, body: fixture('ehentai_api_showpage.json'), finalUrl: url);
        return (status: 200, body: fixture('ehentai_page.html'), finalUrl: url);
      };
      BooruItem page(int n, String key) => h.pageItem(gid: '4149118', token: '17c2f87e13', page: n, key: key, cover: 'https://ehgt.org/c.webp');
      final BooruItem p1 = page(1, 'f5cad5dda2');
      final r1 = await h.loadItem(item: p1);
      expect(r1.failed, isFalse, reason: r1.error);
      expect(p1.fileURL, startsWith('https://idzlahb.wkrmfenmiooq.hath.network/'));
      expect(p1.mediaType.value, MediaType.image);
      expect(p1.fileExt, 'jpg');
      expect(p1.fileWidth, 1272);
      expect(asked.single, 'https://e-hentai.org/s/f5cad5dda2/4149118-1');

      final BooruItem p2 = page(2, 'b177a328d5');
      final r2 = await h.loadItem(item: p2);
      expect(r2.failed, isFalse, reason: r2.error);
      expect(p2.fileURL, startsWith('https://oxlyaea.gcryrgzkiclc.hath.network:'));
      expect(asked.last, startsWith('POST https://api.e-hentai.org/api.php'));
      expect(asked.last, contains('"showkey":"9b0xrd9anff"'));
      expect(asked.last, contains('"imgkey":"b177a328d5"'));
      expect(asked.last, contains('"page":2'));
    });

    test('pages opened at once are still requested one after another, spaced (the reader preloads)', () async {
      final h = handler();
      final List<DateTime> at = [];
      h.fetcher = (url, {postJson}) async {
        at.add(DateTime.now());
        return (status: 200, body: fixture('ehentai_page.html'), finalUrl: url);
      };
      final List<BooruItem> pages = [
        for (int n = 1; n <= 3; n++) h.pageItem(gid: '4149118', token: '17c2f87e13', page: n, key: 'a${n}bcdef012', cover: 'c'),
      ];
      // All three at once, the way three preloaded slides ask.
      await Future.wait(pages.map((p) => h.loadItem(item: p)));
      expect(at, hasLength(3));
      at.sort();
      for (int i = 1; i < at.length; i++) {
        expect(
          at[i].difference(at[i - 1]),
          greaterThanOrEqualTo(EHentaiHandler.pagePace - const Duration(milliseconds: 40)),
          reason: 'request $i came ${at[i].difference(at[i - 1]).inMilliseconds}ms after the one before',
        );
      }
    });

    test('loadItem(page) on a placeholder fetches its block once and resolves every page of the block from the cache', () async {
      final h = handler();
      final List<String> asked = [];
      h.fetcher = (url, {postJson}) async {
        asked.add(url);
        if (url.contains('?p=1')) return (status: 200, body: fixture('ehentai_gallery_multi_p1.html'), finalUrl: url);
        if (url.contains('/s/')) return (status: 200, body: fixture('ehentai_page.html'), finalUrl: url);
        return (status: 404, body: '', finalUrl: url);
      };
      final BooruItem p21 = h.placeholderItem(gid: '4178032', token: '49d94b3d3c', page: 21, cover: 'c');
      final BooruItem p22 = h.placeholderItem(gid: '4178032', token: '49d94b3d3c', page: 22, cover: 'c');
      expect((await h.loadItem(item: p21)).failed, isFalse);
      expect(asked.where((u) => u.contains('?p=1')), hasLength(1));
      expect(p21.postURL, startsWith('https://e-hentai.org/s/'));
      expect(p21.postURL, endsWith('/4178032-21'));
      expect((await h.loadItem(item: p22)).failed, isFalse);
      expect(asked.where((u) => u.contains('?p=1')), hasLength(1), reason: 'the block is cached');
    });
  });

  group('downloading a book whose pages resolve one at a time', () {
    test('the manifest counts what was actually saved, not the pages the site refused', () {
      final List<BooruItem> pages = [
        for (int i = 1; i <= 3; i++)
          BooruItem(fileURL: 'https://n/$i.jpg', sampleURL: 'https://n/$i.jpg', thumbnailURL: 'c', tagsList: const [], postURL: 'https://e-hentai.org/s/aa$i/1-$i'),
      ];
      final gallery = BooruItem(fileURL: 'c', sampleURL: 'c', thumbnailURL: 'c', tagsList: const [], postURL: 'https://e-hentai.org/g/1/a/', serverId: '1', description: 'A book');
      final DoujinDownloadInfo full = DoujinDownloadInfo.fromGallery(gallery, booru, pages);
      expect(full.pages, hasLength(3));
      final DoujinDownloadInfo saved = full.withMissing([pages.first, pages.last]);
      expect(saved.pages, hasLength(3), reason: 'the page list stays the numbering authority');
      expect(saved.missingPages, [2], reason: 'page 2 was refused');
      // The third page keeps its own number: no silent renumbering.
      expect(DoujinDownloadHandler.pageFileName(saved, pages.last, 1), '003.jpg');
      expect(DoujinDownloadHandler.instance.manifestFor(saved)['pageCount'], 3);
      expect(DoujinDownloadHandler.instance.manifestFor(saved)['missingPages'], [2]);
      expect(saved.host, full.host);
      expect(saved.serverId, full.serverId);
      expect(saved.postURL, full.postURL);
      expect(saved.title, full.title);
      expect(saved.coverURL, full.coverURL);
      expect(saved.sourceName, full.sourceName);
      expect(identical(full.withMissing(pages), full), isTrue, reason: 'nothing dropped: the same info');
    });
  });

  group('session and site', () {
    test('cookies from the WebView become a session; the file survives a reload; logout clears it', () async {
      final s = EHentaiSessionHandler.instance;
      expect(s.isLoggedIn, isFalse);
      final parsed = EHentaiSessionHandler.fromCookiePairs({'ipb_member_id': '123', 'ipb_pass_hash': 'abc', 'sk': 'x'});
      expect((parsed.memberId, parsed.passHash), ('123', 'abc'));
      expect(EHentaiSessionHandler.fromCookiePairs({'sk': 'x'}).memberId, isNull);
      s.store(memberId: '123', passHash: 'abc');
      expect(s.isLoggedIn, isTrue);
      expect(s.hasExHentai, isFalse);
      expect(s.cookieHeader(exhentai: false), 'nw=1; ipb_member_id=123; ipb_pass_hash=abc');
      s.setIgneous('mystery');
      expect(s.hasExHentai, isFalse, reason: 'mystery = no access');
      s.setIgneous('deadbeef');
      expect(s.hasExHentai, isTrue);
      expect(s.cookieHeader(exhentai: true), 'nw=1; ipb_member_id=123; ipb_pass_hash=abc; igneous=deadbeef');
      expect(s.cookieHeader(exhentai: false), isNot(contains('igneous')));
      expect(File('${tempDir.path}${Platform.pathSeparator}${EHentaiSessionHandler.fileName}').existsSync(), isTrue);
      s.reloadForTests();
      expect(s.memberId, '123');
      expect(s.igneous, 'deadbeef');
      s.logout();
      expect(s.isLoggedIn, isFalse);
      expect(File('${tempDir.path}${Platform.pathSeparator}${EHentaiSessionHandler.fileName}').existsSync(), isFalse);
      expect(EHentaiSessionHandler.igneousFromSetCookie(['igneous=abc123; path=/; domain=.exhentai.org; secure', 'yay=louder; path=/']), 'abc123');
      expect(EHentaiSessionHandler.igneousFromSetCookie(['yay=louder']), isNull);
    });

    test('the site follows the per-source choice, but exhentai only with a usable session', () {
      final h = handler();
      expect(h.site, 'https://e-hentai.org');
      expect(h.getHeaders()['Cookie'], 'nw=1; sl=dm_2', reason: 'no content warnings, and the extended listing the parser reads');
      SourceSettingsHandler.instance.update(booru, (s) => s.siteVariant = 'exhentai');
      expect(h.site, 'https://e-hentai.org', reason: 'not logged in: exhentai would be a blank page');
      EHentaiSessionHandler.instance.store(memberId: '1', passHash: 'h');
      expect(h.site, 'https://e-hentai.org', reason: 'no igneous yet');
      EHentaiSessionHandler.instance.setIgneous('ok');
      expect(h.site, 'https://exhentai.org');
      expect(h.getHeaders()['Cookie'], 'nw=1; ipb_member_id=1; ipb_pass_hash=h; igneous=ok; sl=dm_2');
      expect(h.getHeaders()['Referer'], 'https://exhentai.org/');
      expect(h.makeURL(''), 'https://exhentai.org/?inline_set=dm_e');
      expect(h.getMediaHeaders()['Referer'], 'https://exhentai.org/');
      expect(h.getMediaHeaders().containsKey('Cookie'), isFalse, reason: 'image hosts are third-party hath nodes');
    });

    test('My Tags: hidden or negatively weighted tags become blacklist names (unverified page shape)', () {
      const String html = '''
<div id="usertags_outer">
 <div class="usertag" id="usertag_1"><div><a href="https://e-hentai.org/tag/female:netorare">female:netorare</a></div>
   <input type="checkbox" id="tagwatch_1" /> <input type="checkbox" id="taghide_1" checked="checked" /> <input type="text" id="tagweight_1" value="-99" /></div>
 <div class="usertag" id="usertag_2"><div><a href="https://e-hentai.org/tag/parody:genshin+impact">parody:genshin impact</a></div>
   <input type="checkbox" id="tagwatch_2" checked="checked" /> <input type="checkbox" id="taghide_2" /> <input type="text" id="tagweight_2" value="10" /></div>
 <div class="usertag" id="usertag_3"><div><a href="https://e-hentai.org/tag/male:yaoi">male:yaoi</a></div>
   <input type="checkbox" id="tagwatch_3" /> <input type="checkbox" id="taghide_3" /> <input type="text" id="tagweight_3" value="-5" /></div>
</div>''';
      // The app compares blacklist entries with the BARE names an item
      // carries (namespaces live beside the tag), so the import must be bare
      // or it can never match anything.
      expect(EHentaiHandler.blacklistFromMyTags(html), ['netorare', 'yaoi']);
      expect(EHentaiHandler.blacklistFromMyTags('<html></html>'), isEmpty);
    });
  });

  group('tag builder', () {
    test('one chip per site namespace, none of them a reserved query key', () {
      final catalog = handler().tagCatalog! as EHentaiTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), [
        'artist',
        'character',
        'parody',
        'group',
        'female',
        'male',
        'mixed',
        'cosplayer',
        'language',
        'other',
      ]);
      // `reclass:` is the namespace for reclassification VOTES: its rows are
      // the gallery categories, and searching `reclass:manga` answers almost
      // nothing. Those categories are already the `category:` metatag, which
      // becomes the site's own category mask.
      expect(catalog.namespaceFor('reclass'), isNull);
      expect(catalog.namespaces.every((n) => n.shards == 1), isTrue, reason: 'one file per namespace');
      expect(catalog.namespaces.every((n) => !EHentaiQuery.reservedKeys.contains(n.key)), isTrue);
      expect(catalog.namespaceFor('artist')!.type, TagType.artist);
      expect(catalog.namespaceFor('parody')!.type, TagType.copyright);
      expect(catalog.namespaceFor('character')!.type, TagType.character);
      expect(catalog.namespaceFor('language')!.type, TagType.meta);
      expect(catalog.namespaceFor('cosplayer')!.type, TagType.artist, reason: 'the chip colour must match the rows');
      expect(catalog.pullNote, contains('GitHub'), reason: 'the picker says where a pull goes');
      expect(
        EHentaiTagCatalog.fileUrl('female'),
        'https://raw.githubusercontent.com/EhTagTranslation/Database/master/database/female.md',
      );
    });

    test('a namespace file parses to bare names, skipping the front matter, the header and the section rows', () {
      final rows = EHentaiTagCatalog.parseNamespaceFile(fixture('ehtag_reclass.md'), 'reclass');
      expect(rows.map((e) => e.name), containsAll(['doujinshi', 'manga', 'artistcg', 'gamecg', 'western']));
      expect(rows.every((e) => e.namespace == 'reclass'), isTrue);
      expect(rows.every((e) => !e.name.contains(':') && e.name == e.name.toLowerCase()), isTrue);
      expect(rows.map((e) => e.name), isNot(contains('')));
      expect(rows.map((e) => e.name), isNot(contains('原始标签')), reason: 'the table header is not a tag');

      // The artist file's row shape differs from female's (its first data row
      // has an empty first cell), so it gets its own fixture.
      final artists = EHentaiTagCatalog.parseNamespaceFile(fixture('ehtag_artist_slice.md'), 'artist');
      expect(artists.map((e) => e.name), containsAll(['pop', 'oouso', 'peko']));
      expect(artists.every((e) => e.tagType == TagType.artist && e.name.isNotEmpty), isTrue);
      expect(artists.map((e) => e.name), isNot(contains('')), reason: 'the empty leading row is not a tag');

      final women = EHentaiTagCatalog.parseNamespaceFile(fixture('ehtag_female_slice.md'), 'female');
      expect(women, isNotEmpty);
      expect(women.every((e) => e.namespace == 'female' && e.name.isNotEmpty), isTrue);
      // `| | == Age == | … |` divides the table into sections; it is not a tag.
      expect(women.map((e) => e.name).where((n) => n.startsWith('==')), isEmpty);
      expect(women.every((e) => !e.name.contains(' ')), isTrue, reason: 'names are underscored like every other source');
    });

    test('every term a chip inserts reaches the site as a tag search, not a title keyword', () {
      final h = handler();
      final catalog = h.tagCatalog! as EHentaiTagCatalog;
      const BooruTagEntry entry = BooruTagEntry(name: 'big_breasts', tagType: TagType.none, namespace: 'female');
      final String term = catalog.searchTerm(entry);
      expect(term, 'female:big_breasts', reason: 'always qualified: a bare word would search titles');
      expect(h.makeURL(term), contains('f_search=${Uri.encodeQueryComponent(r'female:"big breasts"$')}'));
      // Even before any listing taught the namespace.
      expect(EHentaiHandler(booru, 25).makeURL(catalog.searchTerm(entry)), contains(Uri.encodeQueryComponent(r'female:"big breasts"$')));
    });

    test('one request per chip; a refusal from GitHub is said out loud', () async {
      final h = handler();
      final catalog = h.tagCatalog! as EHentaiTagCatalog;
      final List<String> asked = [];
      catalog.fetcher = (url) async {
        asked.add(url);
        return (status: 200, body: fixture('ehtag_language.md'));
      };
      final rows = await catalog.shardAt('language', 0);
      expect(rows, hasLength(greaterThan(80)), reason: 'the real language file has ~90 rows');
      expect(rows!.map((e) => e.name), containsAll(['english', 'japanese', 'chinese']));
      expect(rows.every((e) => e.namespace == 'language' && e.tagType == TagType.meta), isTrue);
      expect(asked, [EHentaiTagCatalog.fileUrl('language')]);
      expect(await catalog.shardAt('language', 1), isNull, reason: 'one shard only');
      expect(await catalog.shardAt('reclass', 0), isNull, reason: 'not offered as a chip');
      expect(await catalog.shardAt('nonsense', 0), isNull);

      catalog.fetcher = (url) async => (status: 404, body: '');
      await expectLater(
        catalog.shardAt('artist', 0),
        throwsA(predicate((e) => e.toString().contains('404') && e.toString().toLowerCase().contains('github'))),
      );
    });
  });

  group('wiring', () {
    test('a doujin source on both hosts, built by the factory, with a reader and no credential fields', () {
      expect(DoujinDataHandler.doujinTypes, contains(BooruType.EHentai));
      expect(DoujinDataHandler.knownDoujinHosts, containsAll(['e-hentai.org', 'exhentai.org']));
      expect(BooruType.EHentai.isDetectable, isFalse);
      expect(BooruType.EHentai.isEHentai, isTrue);
      final h = BooruHandlerFactory().getBooruHandler([booru], null).booruHandler;
      expect(h, isA<EHentaiHandler>());
      expect(h.hasReader, isTrue);
      expect(h.hasLoadItemSupport, isTrue);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.hasSignInSupport, isFalse, reason: 'the session is the WebView login, not the credential fields');
      expect(h.siteVariants.map((v) => v.$1), ['e-hentai', 'exhentai']);
      expect(h.hasAccountBlacklist, isTrue);
      expect(h.readerImageQualities, isEmpty);
      expect(h.tagNamespaceSections.map((s) => s.$1), containsAll(['language', 'parody', 'character', 'artist', 'female', 'male', 'uploader', 'category']));
      expect(h.tagCatalog, isNotNull, reason: 'the Tag builder card is gated on this');
      expect(h.tagCatalog!.namespaces, isNotEmpty);
      expect(h.relatedVersionsQuery(BooruItem(fileURL: 'a', sampleURL: 'a', thumbnailURL: 'a', tagsList: const [], postURL: 'p', serverId: '4149118')), 'related:4149118');
      expect(h.availableMetaTags().map((m) => m.keyName), containsAll(['category', 'rating', 'pages', 'uploader']));
    });

    test('id: opens the gallery when the token is known; related: reads newer versions and the parent through gdata', () async {
      final h = handler();
      h.itemsFromListing(fixture('ehentai_listing.html'));
      expect(h.makeURL('id:4178435'), 'https://e-hentai.org/g/4178435/29ec786079/');
      expect(h.makeURL('id:4149118/17c2f87e13'), 'https://e-hentai.org/g/4149118/17c2f87e13/');
      final Map<String, dynamic> gdata = jsonDecode(fixture('ehentai_api_gdata.json')) as Map<String, dynamic>;
      final List<BooruItem> items = h.itemsFromGdata(gdata);
      expect(items, hasLength(1));
      expect(items.first.serverId, '4149118');
      expect(items.first.fileCountHint.value, 17);
      expect(items.first.thumbnailURL, 'https://ehgt.org/w/02/602/91695-t91lu4og.webp');
      expect(items.first.tagsList.map((t) => t.fullString), contains('genshin_impact'));
      expect(items.first.uploaderName, 'Rogabute');
    });
  });
}

/// What `parseListFromResponse` reads off a Response.
class _Resp {
  _Resp(this.data);
  final String data;
  final int statusCode = 200;
}
