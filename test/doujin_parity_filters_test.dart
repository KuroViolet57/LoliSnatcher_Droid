import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_query.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_query.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/eahentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r70 parity sweep, the feed side: each doujin site's own sorts, shelves,
/// categories and options reach the search window, and the per-source
/// language and title settings work beyond nhentai where the site can do it.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

class _Resp {
  _Resp(this.data, {this.uri});
  final dynamic data;
  final Uri? uri;
  final int statusCode = 200;
  Uri get realUri => uri ?? Uri.parse('https://example.invalid/');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru of(BooruType type, String url) => Booru(type.name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('parity_filters');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    EaHentaiSessionHandler.instance.resetForTests();
    EHentaiSessionHandler.instance.resetForTests();
    EHentaiHandler.resetForTests();
    EaHentaiHandler.forgetFailedLoginsForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('e-hentai', () {
    final Booru eh = of(BooruType.EHentai, 'https://e-hentai.org');
    EHentaiHandler h() => EHentaiHandler(eh, 25);

    test('a compact listing (toplists, and any page the site serves compact) parses like the extended one', () {
      final List<BooruItem> items = h().itemsFromListing(fixture('ehentai_toplist_compact.html'));
      expect(items, hasLength(50));
      final BooruItem first = items.first;
      expect(first.serverId, '4191542');
      expect(first.postURL, 'https://e-hentai.org/g/4191542/90688f51d1/');
      expect(first.thumbnailURL, 'https://ehgt.org/w/02/650/48705-ljr10iv9.webp');
      expect(first.description, startsWith('[Misoshiru Senmonten (Nako Sir)]'));
      expect(first.tagsList.map((t) => t.fullString), containsAll(['chinese', 'translated', 'original', 'nako_sir', 'doujinshi']));
      expect(first.fileCountHint.value, 73);
      expect(first.postDate, '2026-09-15 14:28');
      expect(first.uploaderName, isNotNull);
      expect(first.score, isNotNull);
    });

    test('the toplists are pages, not cursors; watched and favourites are searches on their own paths', () {
      final EHentaiHandler yesterday = h()..pageNum = 0;
      expect(yesterday.makeURL('sort:toplist_yesterday'), 'https://e-hentai.org/toplist.php?tl=15');
      expect((h()..pageNum = 1).makeURL('sort:toplist_yesterday'), 'https://e-hentai.org/toplist.php?tl=15&p=1');
      expect((h()..pageNum = 0).makeURL('sort:toplist_alltime'), contains('tl=11'));
      expect((h()..pageNum = 0).makeURL('sort:toplist_year'), contains('tl=12'));
      expect((h()..pageNum = 0).makeURL('sort:toplist_month'), contains('tl=13'));
      expect((h()..pageNum = 0).makeURL('sort:watched'), 'https://e-hentai.org/watched?inline_set=dm_e');
      expect((h()..pageNum = 0).makeURL('sort:watched glasses'), 'https://e-hentai.org/watched?f_search=glasses&inline_set=dm_e');
      expect((h()..pageNum = 0).makeURL('sort:favorites'), 'https://e-hentai.org/favorites.php?inline_set=dm_e');
      expect((h()..pageNum = 0).makeURL('sort:favorites favcat:3'), 'https://e-hentai.org/favorites.php?favcat=3&inline_set=dm_e');
      expect((h()..pageNum = 0).makeURL('sort:favorites favcat:3 glasses'), 'https://e-hentai.org/favorites.php?favcat=3&f_search=glasses&inline_set=dm_e');
      // A toplist cannot be searched: typed words win and are never dropped.
      final String typed = (h()..pageNum = 0).makeURL('sort:toplist_yesterday glasses');
      expect(typed, contains('f_search=glasses'));
      expect(typed, isNot(contains('toplist')));
    });

    test('the popular page takes the category filter, as the site does, and ignores the options', () {
      expect((h()..pageNum = 0).makeURL('sort:popular category:manga'), 'https://e-hentai.org/popular?f_cats=1019');
      expect((h()..pageNum = 0).makeURL('sort:popular'), 'https://e-hentai.org/popular');
      expect((h()..pageNum = 0).makeURL('sort:popular options:expunged'), 'https://e-hentai.org/popular', reason: 'the popular page has no advanced options');
    });

    test('expunged and torrent-only are the advanced options they are on the site', () {
      final String url = (h()..pageNum = 0).makeURL('glasses expunged:on torrent:on');
      expect(url, contains('advsearch=1'));
      expect(url, contains('f_sh=on'));
      expect(url, contains('f_sto=on'));
      expect((h()..pageNum = 0).makeURL('glasses'), isNot(contains('f_sh')));
      final EHentaiSearch s = EHentaiQuery.parse('expunged:on');
      expect(s.showExpunged, isTrue);
      expect(s.terms, isEmpty);
    });

    test('the per-source language setting joins every search, once', () {
      expect(h().supportsLanguageFilter, isTrue);
      SourceSettingsHandler.instance.settingsFor(eh).languageFilter = 'english';
      final String url = (h()..pageNum = 0).makeURL('glasses');
      expect(url, contains(Uri.encodeQueryComponent('language:"english"\$')));
      final String explicit = (h()..pageNum = 0).makeURL('glasses language:japanese');
      expect(explicit, contains(Uri.encodeQueryComponent('language:"japanese"\$')));
      expect(explicit, isNot(contains('english')));
      expect((h()..pageNum = 0).makeURL('sort:toplist_yesterday'), isNot(contains('language')), reason: 'the toplists take no search');
    });

    test('the title language setting puts the Japanese title first', () async {
      expect(h().supportsTitleLanguage, isTrue);
      final String body = fixture('ehentai_gallery.html');
      final EHentaiHandler english = h();
      final gallery = english.galleryFromHtml(body, gid: '1', token: 'a');
      if (gallery.titleJpn.isEmpty) {
        markTestSkipped('the fixture gallery has no Japanese title');
        return;
      }
      expect(english.titlesFor(gallery.title, gallery.titleJpn), startsWith(gallery.title));
      SourceSettingsHandler.instance.settingsFor(eh).titleLanguage = 'japanese';
      expect(h().titlesFor(gallery.title, gallery.titleJpn), startsWith(gallery.titleJpn));
    });

    test('the search window offers the shelves, favourite categories and options', () {
      final DoujinFilterSpec spec = h().doujinFilters;
      expect(spec.group('sort')!.options.map((o) => o.value), containsAll(['latest', 'popular', 'watched', 'favorites', 'toplist_yesterday', 'toplist_month', 'toplist_year', 'toplist_alltime']));
      expect(spec.group('favcat')!.options.map((o) => o.value), containsAll(['0', '9']));
      final DoujinFilterGroup options = spec.group('options')!;
      expect(options.multi, isTrue);
      expect(options.options.map((o) => o.value), containsAll(['expunged', 'torrent']));
    });
  });

  group('hitomi', () {
    final Booru booru = of(BooruType.Hitomi, 'https://hitomi.la');
    HitomiHandler h() => HitomiHandler(booru, 20);

    test('the per-source language setting joins the query, once', () {
      expect(h().supportsLanguageFilter, isTrue);
      expect(h().withLanguageFilter('glasses'), 'glasses');
      SourceSettingsHandler.instance.settingsFor(booru).languageFilter = 'english';
      expect(h().withLanguageFilter('glasses'), 'glasses language:english');
      expect(h().withLanguageFilter(''), 'language:english');
      expect(h().withLanguageFilter('glasses language:japanese'), 'glasses language:japanese');
    });

    test('a language is a whole-site index and is read in full, never through the intersection window', () {
      expect(HitomiHandler.isWholeIndexTerm('language:english'), isTrue);
      expect(HitomiHandler.isWholeIndexTerm('artist:santa'), isFalse);
      expect(HitomiHandler.isWholeIndexTerm('female:glasses'), isFalse);
      expect(HitomiHandler.languageWindow, greaterThan(300000), reason: 'English alone lists 167,000 galleries today');
    });

    test('the title language setting puts the Japanese title first', () {
      expect(h().supportsTitleLanguage, isTrue);
      expect(HitomiHandler.titlesFor('Title', 'タイトル', preferJapanese: false), 'Title\nタイトル');
      expect(HitomiHandler.titlesFor('Title', 'タイトル', preferJapanese: true), 'タイトル\nTitle');
      expect(HitomiHandler.titlesFor('Title', '', preferJapanese: true), 'Title');
      expect(HitomiHandler.titlesFor('', 'タイトル', preferJapanese: false), 'タイトル');
    });
  });

  group('asmhentai', () {
    final Booru booru = of(BooruType.AsmHentai, 'https://asmhentai.com');
    AsmHentaiHandler h() => AsmHentaiHandler(booru, 20);

    test("the site's categories and random gallery reach the search window", () {
      final DoujinFilterSpec spec = h().doujinFilters;
      expect(spec.group('category')!.options.map((o) => o.value), containsAll(['doujinshi', 'manga']));
      expect((h()..pageNum = 1).makeURL('category:manga'), 'https://asmhentai.com/category/manga/?page=1');
      expect((h()..pageNum = 1).makeURL('random:'), 'https://asmhentai.com/random/');
      expect((h()..pageNum = 1).makeURL('random: category:manga'), 'https://asmhentai.com/random/', reason: 'a chip beside random changes nothing');
      final AsmHentaiHandler second = h()..pageNum = 2;
      expect(second.makeURL('random:'), '');
      expect(second.locked, isTrue);
    });

    test('a random gallery answers as one gallery, read from where the site sent us', () async {
      final AsmHentaiHandler handler = h();
      handler.currentTags = 'random:';
      final List items = await handler.parseListFromResponse(
        _Resp(fixture('asmhentai_gallery.html'), uri: Uri.parse('https://asmhentai.com/g/403849/')),
      );
      expect(items, hasLength(1));
      expect((items.single as BooruItem).postURL, 'https://asmhentai.com/g/403849/');
    });
  });

  group('hentaipaw', () {
    final Booru booru = of(BooruType.HentaiPaw, 'https://hentaipaw.com');
    HentaiPawHandler h() => HentaiPawHandler(booru, 20);

    test("the site's daily ranking is a shelf", () {
      expect(h().doujinFilters.group('sort')!.options.map((o) => o.value), containsAll(['latest', 'rank']));
      expect((h()..pageNum = 1).makeURL('sort:rank'), 'https://hentaipaw.com/articles/rank/?t=daily&page=1');
      expect((h()..pageNum = 3).makeURL('sort:rank'), 'https://hentaipaw.com/articles/rank/?t=daily&page=3');
      expect((h()..pageNum = 1).makeURL('sort:latest'), 'https://hentaipaw.com/?page=1');
      expect((h()..pageNum = 1).makeURL('sort:rank glasses'), contains('/articles/search?keyword=glasses'), reason: 'the ranking cannot be searched; the search wins');
    });

    test('the ranking page parses with the listing parser', () {
      final List<BooruItem> items = h().itemsFromListingForTests(fixture('hentaipaw_rank.html'));
      expect(items.length, greaterThanOrEqualTo(20));
      expect(items.every((i) => i.postURL.contains('/articles/')), isTrue);
    });
  });

  group('niyaniya / hdoujin', () {
    final Booru booru = of(BooruType.NiyaNiya, 'https://niyaniya.moe');
    SchaleHandler h() => SchaleHandler(booru, 20);

    test("the site's categories are a filter on the books request", () {
      final DoujinFilterSpec spec = h().doujinFilters;
      expect(spec.group('category')!.options.map((o) => o.value), containsAll(['doujinshi', 'manga', 'illustration']));
      final String browse = (h()..pageNum = 1).makeURL('category:doujinshi');
      expect(browse, endsWith('/books?page=1&cat=4'));
      final String search = (h()..pageNum = 1).makeURL('glasses category:manga');
      expect(search, contains('/books?s='));
      expect(search, endsWith('&page=1&cat=2'));
      expect((h()..pageNum = 1).makeURL('category:illustration'), endsWith('&cat=8'));
      expect((h()..pageNum = 1).makeURL('sort:popular category:manga'), contains('/books/popular?page=1'), reason: 'the popular shelf takes no category');
    });
  });

  group('hentalk', () {
    final Booru booru = of(BooruType.Faccina, 'https://hentalk.pw');
    FaccinaHandler h() => FaccinaHandler(booru, 24);

    test("faccina's sorts and order are filters, sent as its own parameters", () {
      final DoujinFilterSpec spec = h().doujinFilters;
      expect(spec.group('sort')!.options.map((o) => o.value), containsAll(['released', 'added', 'title', 'pages', 'random']));
      expect(spec.group('order')!.options.map((o) => o.value), containsAll(['desc', 'asc']));
      expect((h()..pageNum = 1).makeURL('glasses'), 'https://hentalk.pw/api/library?q=glasses&page=1');
      expect((h()..pageNum = 1).makeURL('glasses sort:title order:asc'), 'https://hentalk.pw/api/library?q=glasses&page=1&sort=title&order=asc');
      expect((h()..pageNum = 2).makeURL('sort:random'), 'https://hentalk.pw/api/library?page=2&sort=random');
      expect((h()..pageNum = 1).makeURL('sort:added'), contains('sort=created_at'));
      expect((h()..pageNum = 1).makeURL('sort:released'), 'https://hentalk.pw/api/library?page=1', reason: 'the site default needs no parameter');
    });
  });

  group('eahentai bookmarks and lists', () {
    final Booru booru = of(BooruType.EaHentai, 'https://eahentai.com');
    EaHentaiHandler h() => EaHentaiHandler(booru, 42);

    test('the account feeds are requests of their own, only with a login', () {
      const String api = 'https://eahentai.com/api';
      expect(EaHentaiQuery.parse('bookmarks:recent', page: 1, username: 'me').url, '$api/bookmarks/albums?type=all&page=0&take=42&orderby=bookmarked');
      expect(EaHentaiQuery.parse('bookmarks:latest', page: 2, username: 'me').url, contains('page=1&take=42&orderby=date_desc'));
      expect(EaHentaiQuery.parse('bookmarks:alltime', page: 1, username: 'me').url, contains('orderby=views_alltime'));
      expect(EaHentaiQuery.parse('bookmarks:recent glasses', page: 1, username: 'me').url, contains('&q=glasses'));
      expect(EaHentaiQuery.parse('list:12', page: 1, username: 'someone57').url, '$api/lists/users/someone57/12?page=0&take=42');
      expect(EaHentaiQuery.parse('list:12', page: 1).error, contains('log in'));
      expect(EaHentaiQuery.parse('bookmarks:recent', page: 1).error, contains('log in'));
      expect(EaHentaiQuery.parse('bookmarks:bogus', page: 1, username: 'me').error, contains('bookmarks:'));
    });

    test('logged out the handler refuses the account feeds with a message; logged in it asks', () {
      final EaHentaiHandler out = h()..pageNum = 0;
      expect(out.makeURL('bookmarks:recent'), '');
      expect(out.errorString, contains('og in'));
      EaHentaiSessionHandler.instance.store(token: 'tok', username: 'someone57', loginName: 'someone57');
      expect((h()..pageNum = 0).makeURL('bookmarks:recent'), contains('/api/bookmarks/albums?'));
      expect((h()..pageNum = 0).makeURL('list:3'), contains('/api/lists/users/someone57/3?'));
    });

    test('the heart is the site bookmark once logged in', () async {
      final EaHentaiHandler handler = h();
      expect(handler.hasSiteFavourites, isFalse);
      EaHentaiSessionHandler.instance.store(token: 'tok', username: 'someone57', loginName: 'someone57');
      expect(handler.hasSiteFavourites, isTrue);
      final List<(String, String)> calls = [];
      handler.accountWriter = (url, method) async {
        calls.add((url, method));
        return 200;
      };
      final BooruItem item = BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://eahentai.com/a/74609', serverId: '74609');
      final (bool ok, String message) = await handler.setSiteFavourite(item, true);
      expect(ok, isTrue, reason: message);
      final (bool ok2, _) = await handler.setSiteFavourite(item, false);
      expect(ok2, isTrue);
      expect(calls, [('https://eahentai.com/api/bookmarks/74609', 'POST'), ('https://eahentai.com/api/bookmarks/74609', 'DELETE')]);
    });

    test('the lists the account made are a filter group; they are learned at login', () async {
      final EaHentaiHandler handler = h();
      handler.booru
        ..userID = 'someone57'
        ..apiKey = 'pw';
      handler.fetcher = (url, {postJson}) async {
        if (url.endsWith('/api/auth/login')) return (status: 200, body: '{"accessToken":"tok"}', finalUrl: url);
        if (url.endsWith('/api/auth/me')) return (status: 200, body: '{"username":"someone57"}', finalUrl: url);
        if (url.endsWith('/api/lists/mine')) return (status: 200, body: '[{"listID":3,"name":"Best of 2026"},{"id":7,"title":"Later"}]', finalUrl: url);
        return (status: 404, body: '', finalUrl: url);
      };
      expect(await handler.signIn(), isTrue);
      expect(EaHentaiSessionHandler.instance.lists.map((l) => '${l.id}:${l.name}'), ['3:Best of 2026', '7:Later']);
      final DoujinFilterSpec spec = handler.doujinFilters;
      expect(spec.group('bookmarks')!.options.map((o) => o.value), containsAll(['recent', 'latest', 'alltime']));
      expect(spec.group('list')!.options.map((o) => o.value), ['3', '7']);
      expect(spec.group('list')!.options.first.label, 'Best of 2026');
      await handler.signOut();
      expect(EaHentaiSessionHandler.instance.lists, isEmpty);
      expect(h().doujinFilters.group('list'), isNull, reason: 'no lists without a login');
      EaHentaiSessionHandler.instance.setLists(const [(id: 1, name: 'stale')]);
      EaHentaiSessionHandler.instance.store(token: 'new', username: 'other', loginName: 'other');
      expect(EaHentaiSessionHandler.instance.lists, isEmpty, reason: 'a new login starts with no lists');
    });

    test('bookmarks and lists answer the same album entries', () {
      final EaHentaiHandler handler = h();
      expect(handler.itemsFromApi('{"items":[{"albumID":5,"title":"x","thumbnailUri":"galleries/a/thumbnail/01t.jpg"}],"totalResults":1}'), hasLength(1));
      expect(handler.itemsFromApi('[{"albumID":6,"title":"y","thumbnailUri":"galleries/b/thumbnail/01t.jpg"}]'), hasLength(1));
    });
  });
}
