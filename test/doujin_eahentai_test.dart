import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_query.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/eahentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// eahentai.com. r69: the site is driven by a JSON API (found in its own
/// scripts and fetched on 2026-09-17): latest, search (typed and sorted),
/// popular, random, an album with its pages, suggestions, and a JSON login
/// that answers a bearer token. The app used to scrape the HTML listing (no
/// tags, no paging) and POST a form to the HTML `/login` route, which answers
/// 405 to every search. Fixtures test/fixtures/eahentai_api_*.json are the
/// live answers; the HTML fixtures stay for the fallback parsers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru ea() => Booru('eahentai', BooruType.EaHentai, '', 'https://eahentai.com', '')
    ..userID = 'someone57'
    ..apiKey = 'Sup3r-Secret!Pass';
  Booru anonymous() => Booru('eahentai', BooruType.EaHentai, '', 'https://eahentai.com', '');

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  dynamic json(String name) => jsonDecode(fixture(name));

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('ea_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    EaHentaiSessionHandler.instance.resetForTests();
    EaHentaiHandler.forgetFailedLoginsForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    EaHentaiSessionHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('query grammar -> one API request', () {
    const String api = 'https://eahentai.com/api/image';

    test('nothing typed is the latest feed, pages counted from 0', () {
      expect(EaHentaiQuery.parse('', page: 1).url, '$api/latest/?page=0&take=42');
      expect(EaHentaiQuery.parse('', page: 3).url, '$api/latest/?page=2&take=42');
    });

    test('words are a gallery search, newest first', () {
      expect(EaHentaiQuery.parse('glasses', page: 2).url, '$api/search/v2/?type=gallery&q=glasses&take=42&page=1&orderby=date_desc');
      expect(EaHentaiQuery.parse('big_breasts', page: 1).url, contains('q=big%20breasts'), reason: "the app's underscores are the site's spaces");
      expect(EaHentaiQuery.parse('"big breasts"', page: 1).url, contains('q=big%20breasts'));
    });

    test("sort: alone is the site's Popular section; with words it orders the search", () {
      expect(EaHentaiQuery.parse('sort:weekly', page: 1).url, '$api/popular/?page=0&take=42&orderby=views_weekly');
      expect(EaHentaiQuery.parse('sort:today', page: 2).url, '$api/popular/?page=1&take=42&orderby=views_daily');
      expect(EaHentaiQuery.parse('sort:monthly', page: 1).url, contains('orderby=views_monthly'));
      expect(EaHentaiQuery.parse('sort:alltime', page: 1).url, contains('orderby=views_alltime'));
      expect(EaHentaiQuery.parse('sort:latest', page: 1).url, '$api/latest/?page=0&take=42');
      expect(EaHentaiQuery.parse('glasses sort:weekly', page: 1).url, '$api/search/v2/?type=gallery&q=glasses&take=42&page=0&orderby=views_weekly');
    });

    test('one namespaced term is a typed search; type: names the scope; mixed terms search everything', () {
      expect(EaHentaiQuery.parse('artist:santa', page: 1).url, contains('type=artist&q=santa&'));
      expect(EaHentaiQuery.parse('parody:touhou_project', page: 1).url, contains('type=parody&q=touhou%20project&'));
      expect(EaHentaiQuery.parse('character:nami', page: 1).url, contains('type=character&q=nami&'));
      expect(EaHentaiQuery.parse('tag:glasses', page: 1).url, contains('type=tag&q=glasses&'));
      expect(EaHentaiQuery.parse('type:parody touhou', page: 1).url, contains('type=parody&q=touhou&'));
      expect(EaHentaiQuery.parse('artist:santa parody:touhou', page: 1).url, contains('type=gallery&q=santa%20touhou&'));
      expect(EaHentaiQuery.parse('artist:santa glasses', page: 1).url, contains('type=gallery&q=santa%20glasses&'));
    });

    test("quick filters append the site's own words, exactly as its buttons do", () {
      expect(EaHentaiQuery.parse('artist:santa filter:full_color', page: 1).url, contains('type=artist&q=santa%20Full%20Color&'));
      expect(EaHentaiQuery.parse('filter:manga', page: 1).url, contains('type=gallery&q=Manga&'));
      expect(EaHentaiQuery.parse('glasses filter:yuri filter:uncensored', page: 1).url, contains('q=glasses%20Yuri%20Uncensored&'));
      expect(EaHentaiQuery.parse('sort:weekly filter:doujins', page: 1).url, contains('search/v2/?type=gallery&q=Doujins&take=42&page=0&orderby=views_weekly'));
      expect(EaHentaiQuery.filterWords.keys, containsAll(['original', 'full_color', 'doujins', 'manga', 'uncensored', 'lolicon', 'yuri', 'yaoi']));
    });

    test('random is one page; a second page is the end', () {
      final EaHentaiRequest first = EaHentaiQuery.parse('random:', page: 1);
      expect(first.url, '$api/random/?take=42');
      expect(EaHentaiQuery.parse('random:', page: 2).atEnd, isTrue);
    });

    test('unknown sort, type or filter values are refused with a message, not sent', () {
      expect(EaHentaiQuery.parse('sort:bogus', page: 1).error, contains('sort:'));
      expect(EaHentaiQuery.parse('type:bogus', page: 1).error, contains('type:'));
      expect(EaHentaiQuery.parse('filter:bogus', page: 1).error, contains('filter:'));
      expect(EaHentaiQuery.parse('type:artist', page: 1).error, contains('type:'), reason: 'a scope with nothing to search is not the latest feed in disguise');
    });

    test("a language chip is nothing on an English-only site; a category chip is the site's own quick filter", () {
      expect(EaHentaiQuery.parse('language:english', page: 1).url, '$api/latest/?page=0&take=42');
      expect(EaHentaiQuery.parse('category:manga', page: 1).url, contains('q=Manga&'));
      expect(EaHentaiQuery.parse('category:doujinshi glasses', page: 1).url, contains('q=glasses%20Doujins&'));
    });

    test('the handler uses it, and keeps its gallery URLs', () {
      // The counter starts at -1 and is stepped before each fetch: 0 is the
      // first page, so 2 is the third - the site counts from 0 as well.
      final h = EaHentaiHandler(anonymous(), 42)..pageNum = 2;
      expect(h.makeURL(''), '$api/latest/?page=2&take=42');
      expect(h.makeURL('glasses'), contains('search/v2/?type=gallery&q=glasses&take=42&page=2'));
      expect((EaHentaiHandler(anonymous(), 42)..pageNum = 0).makeURL(''), '$api/latest/?page=0&take=42');
      expect(h.makeURL('id:73480'), '$api/album/73480');
      expect(h.makePostURL('73480'), 'https://eahentai.com/a/73480');
      expect(EaHentaiQuery.parse('sort:bogus', page: 1).error, isNotNull);
      final h2 = EaHentaiHandler(anonymous(), 42)..pageNum = 1;
      expect(h2.makeURL('sort:bogus'), '');
      expect(h2.errorString, contains('sort:'));
    });
  });

  group('the JSON listing', () {
    test('a search answer becomes finished items with their tags, cover, first page, kind and date', () {
      final h = EaHentaiHandler(anonymous(), 42);
      final List<BooruItem> items = h.itemsFromApi(json('eahentai_api_search.json'));
      expect(items, hasLength(3));
      final BooruItem first = items.first;
      expect(first.serverId, '74609');
      expect(first.postURL, 'https://eahentai.com/a/74609');
      expect(first.thumbnailURL, 'https://i.eahentai.com/file/ea-gallery/galleries/aaca9c54974d4221bb9f31de04c57c4b/thumbnail/image1t.jpg');
      // The 450-px cover is the whole card image: a feed in sample quality
      // must not download a full first page per card (review finding).
      expect(first.sampleURL, first.thumbnailURL);
      expect(first.fileURL, first.thumbnailURL);
      expect(first.description, startsWith('[OVing (Obui)] Paihame Nakayoshi'));
      // Names are stored bare; the namespace is the handler's to answer.
      final List<String> tags = first.tagsList.map((t) => t.fullString).toList();
      expect(tags, containsAll(['glasses', 'big_breasts', 'obui', 'oving', 'original', 'doujinshi', 'lolicon', 'english']));
      expect(h.tagNamespace('obui'), 'artist');
      expect(h.tagNamespace('original'), 'parody');
      expect(h.tagNamespace('doujinshi'), 'category');
      expect(h.tagNamespace('english'), 'language');
      expect(h.tagNamespace('lolicon'), isNull, reason: 'a kind that is not the category is a plain tag');
      expect(first.postDate, '2026-09-17T03:44:42.604');
      expect(first.postDateFormat, 'iso');
      expect(h.totalFromApi(json('eahentai_api_search.json')), 6292);
    });

    test('characters and a manga kind are read too', () {
      final h = EaHentaiHandler(anonymous(), 42);
      final BooruItem item = h.itemFromAlbum({
        'albumID': 5,
        'title': 'T',
        'thumbnailUri': 'galleries/x/thumbnail/01t.jpg',
        'imageUri': 'galleries/x/01.jpg',
        'tags': 'glasses|big breasts',
        'author': 'someone',
        'from': 'one piece',
        'characters': 'nami|nico robin',
        'albumType': 'Manga|Yaoi',
        'addDt': '2024-07-11T10:25:12.713',
      })!;
      final List<String> tags = item.tagsList.map((t) => t.fullString).toList();
      expect(tags, containsAll(['nami', 'nico_robin', 'one_piece', 'manga', 'yaoi', 'someone']));
      expect(h.tagNamespace('nami'), 'character');
      expect(h.tagNamespace('nico_robin'), 'character');
      expect(h.tagNamespace('one_piece'), 'parody');
      expect(h.tagNamespace('manga'), 'category');
      expect(h.tagNamespace('someone'), 'artist');
      expect(item.thumbnailURL, 'https://i.eahentai.com/file/ea-gallery/galleries/x/thumbnail/01t.jpg');
    });

    test('popular and random answer a bare array; a broken entry is skipped', () {
      final h = EaHentaiHandler(anonymous(), 42);
      expect(h.itemsFromApi(json('eahentai_api_popular.json')), hasLength(3));
      expect(h.itemsFromApi([{'title': 'no id'}, {'albumID': 9, 'title': 'ok', 'thumbnailUri': 'galleries/y/thumbnail/01t.jpg'}]), hasLength(1));
      expect(h.itemsFromApi('<html>not json</html>'), isEmpty);
      expect(h.totalFromApi(json('eahentai_api_popular.json')), isNull);
    });

    test('the handler parses a decoded answer and a text answer alike, and takes the total', () async {
      final h = EaHentaiHandler(anonymous(), 42);
      h.currentTags = 'glasses';
      final List decoded = await h.parseListFromResponse(_Resp(json('eahentai_api_search.json')));
      expect(decoded, hasLength(3));
      expect(h.totalCount.value, 6292);
      final List text = await h.parseListFromResponse(_Resp(fixture('eahentai_api_popular.json')));
      expect(text, hasLength(3));
    });

    test('the full first page is the detail cover, named like the reader page 1, without a request', () async {
      final h = EaHentaiHandler(anonymous(), 42);
      h.fetcher = (url, {postJson}) async => throw StateError('no request expected: $url');
      final BooruItem item = h.itemsFromApi(json('eahentai_api_search.json')).first;
      final BooruItem? cover = await h.detailCoverImage(item);
      expect(cover, isNotNull);
      expect(cover!.fileURL, 'https://i.eahentai.com/file/ea-gallery/galleries/aaca9c54974d4221bb9f31de04c57c4b/image1.webp');
      expect(cover.thumbnailURL, cover.fileURL);
      expect(cover.fileNameExtras, '74609_0001');

      SourceSettingsHandler.instance.settingsFor(anonymous()).detailCoverFromFirstPage = false;
      expect(await h.detailCoverImage(item), isNull);
    });

    test('an HTML listing still parses as the fallback', () {
      final h = EaHentaiHandler(anonymous(), 42);
      final List<BooruItem> items = h.itemsFromListing(fixture('eahentai_listing.html'));
      expect(items, isNotEmpty);
      expect(items.every((i) => RegExp(r'/a/\d+$').hasMatch(i.postURL)), isTrue);
      expect(items.every((i) => i.thumbnailURL.isNotEmpty && i.description!.isNotEmpty && i.description != 'Read Now'), isTrue);
      expect(items.firstWhere((e) => e.serverId == '73480').thumbnailURL, contains('/thumbnail/'));
    });
  });

  group('the reader from the album answer', () {
    test('an album lists its pages in order, each with its own thumbnail', () {
      final h = EaHentaiHandler(anonymous(), 42);
      final List<BooruItem> pages = h.pagesFromAlbum(json('eahentai_api_album.json'), postURL: 'https://eahentai.com/a/74609');
      expect(pages, hasLength(56));
      expect(pages.first.fileURL, 'https://i.eahentai.com/file/ea-gallery/galleries/aaca9c54974d4221bb9f31de04c57c4b/image1.webp');
      expect(pages.first.thumbnailURL, 'https://i.eahentai.com/file/ea-gallery/galleries/aaca9c54974d4221bb9f31de04c57c4b/thumbnail/image1t.jpg');
      expect(pages[9].fileURL, endsWith('/image10.webp'), reason: 'by sort, not by name');
      expect(pages.every((p) => p.postURL == 'https://eahentai.com/a/74609'), isTrue);
    });

    test('loadItem reads the album once and registers the book', () async {
      final h = EaHentaiHandler(anonymous(), 42);
      final List<String> asked = [];
      h.fetcher = (url, {postJson}) async {
        asked.add(url);
        return (status: 200, body: fixture('eahentai_api_album.json'), finalUrl: url);
      };
      final BooruItem item = BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://eahentai.com/a/74609', serverId: '74609');
      final res = await h.loadItem(item: item);
      expect(res.failed, isFalse, reason: res.error);
      expect(asked, ['https://eahentai.com/api/image/album/74609']);
      expect(ReaderHandler.instance.pagesFor(item), hasLength(56));
      expect(ReaderHandler.instance.pagesFor(item)!.first.fileNameExtras, '74609_0001', reason: 'the detail cover shares this name');
      expect(item.fileCountHint.value, 56);
      expect(item.tagsList.map((t) => t.fullString), contains('glasses'));
      expect(item.description, startsWith('[OVing (Obui)]'));
      expect(item.thumbnailURL, contains('/thumbnail/image1t.jpg'), reason: 'a bare item learns its cover');
    });

    test('when the album call fails the gallery and reader pages are scraped as before', () async {
      final h = EaHentaiHandler(anonymous(), 42);
      h.fetcher = (url, {postJson}) async {
        if (url.contains('/api/')) return (status: 500, body: '', finalUrl: url);
        if (url.endsWith('/0')) return (status: 200, body: fixture('eahentai_reader.html'), finalUrl: url);
        return (status: 200, body: fixture('eahentai_payload.html'), finalUrl: url);
      };
      final BooruItem item = BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://eahentai.com/a/73480', serverId: '73480');
      final res = await h.loadItem(item: item);
      expect(res.failed, isFalse, reason: res.error);
      expect(ReaderHandler.instance.pagesFor(item), hasLength(5));
      expect(item.tagsList.map((t) => t.fullString), contains('glasses'));
    });
  });

  group('login (r69)', () {
    test('the site login: one JSON call with login and password, a bearer token kept in its own file', () async {
      final h = EaHentaiHandler(ea(), 42);
      final List<({String url, String? body})> calls = [];
      h.fetcher = (url, {postJson}) async {
        calls.add((url: url, body: postJson));
        if (url.endsWith('/api/auth/login')) return (status: 200, body: '{"accessToken":"tok.en.123"}', finalUrl: url);
        if (url.endsWith('/api/auth/me')) return (status: 200, body: '{"username":"someone57"}', finalUrl: url);
        return (status: 404, body: '', finalUrl: url);
      };
      expect(await h.canSignIn(), isTrue);
      expect(await h.signIn(), isTrue);
      expect(calls.first.url, 'https://eahentai.com/api/auth/login');
      final Map<String, dynamic> body = jsonDecode(calls.first.body!) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'login', 'password'}, reason: 'the site wants login + password; username/email fields answer 400');
      expect(body['login'], 'someone57');
      expect(await h.isSignedIn(), isTrue);
      expect(EaHentaiSessionHandler.instance.token, 'tok.en.123');
      expect(EaHentaiSessionHandler.instance.username, 'someone57');
      expect(File('${tempDir.path}${Platform.pathSeparator}${EaHentaiSessionHandler.fileName}').existsSync(), isTrue);
      expect(h.getHeaders()['Authorization'], 'Bearer tok.en.123');
      expect(h.getMediaHeaders().containsKey('Authorization'), isFalse, reason: 'the CDN never sees the token');
      expect(h.loginMessage, contains('someone57'));
    });

    test('wrong credentials: the site message is kept, nothing is stored, and the pair is not sent again', () async {
      final h = EaHentaiHandler(ea(), 42);
      int posts = 0;
      h.fetcher = (url, {postJson}) async {
        posts++;
        return (status: 401, body: '{"error":"Invalid credentials."}', finalUrl: url);
      };
      expect(await h.signIn(), isFalse);
      expect(await h.isSignedIn(), isFalse);
      expect(h.loginMessage, contains('Invalid credentials.'));
      expect(h.getHeaders().containsKey('Authorization'), isFalse);
      // The base class asks searchSetup before every page; a refused pair
      // would be posted to a real auth endpoint per page.
      expect(await h.canSignIn(), isFalse);
      expect(await h.searchSetup(), isTrue);
      expect(await h.searchSetup(), isTrue);
      expect(posts, 1);
      EaHentaiHandler.forgetFailedLoginsForTests();
      expect(await h.canSignIn(), isTrue);
    });

    test('a 401 from /auth/me does not undo the login that just succeeded', () async {
      final h = EaHentaiHandler(ea(), 42);
      h.fetcher = (url, {postJson}) async {
        if (url.endsWith('/api/auth/login')) return (status: 200, body: '{"accessToken":"tok"}', finalUrl: url);
        return (status: 401, body: '', finalUrl: url);
      };
      expect(await h.signIn(), isTrue);
      expect(await h.isSignedIn(), isTrue);
      expect(EaHentaiSessionHandler.instance.token, 'tok');
    });

    test('a 401 on a listing call with a token drops it, so the next search logs in again', () async {
      final h = EaHentaiHandler(ea(), 42);
      EaHentaiSessionHandler.instance.store(token: 'stale', loginName: 'someone57');
      h.fetcher = (url, {postJson}) async => (status: 401, body: '', finalUrl: url);
      final r = await h.getTagSuggestions('glas');
      expect(r.isLeft(), isTrue);
      expect(EaHentaiSessionHandler.instance.isLoggedIn, isFalse);
    });

    test('changed credentials are a new login, not the old account', () async {
      final h = EaHentaiHandler(ea(), 42);
      h.fetcher = (url, {postJson}) async {
        if (url.endsWith('/api/auth/login')) return (status: 200, body: '{"accessToken":"tok"}', finalUrl: url);
        return (status: 200, body: '{"username":"someone57"}', finalUrl: url);
      };
      expect(await h.signIn(), isTrue);
      expect(await h.isSignedIn(), isTrue);
      h.booru.userID = 'someone-else';
      expect(await h.isSignedIn(), isFalse, reason: 'the token belongs to someone57');
    });

    test('a validation answer is read too', () async {
      final h = EaHentaiHandler(ea(), 42);
      h.fetcher = (url, {postJson}) async => (status: 400, body: '{"title":"One or more validation errors occurred.","errors":{"Login":["The Login field is required."]}}', finalUrl: url);
      expect(await h.signIn(), isFalse);
      expect(h.loginMessage, contains('The Login field is required.'));
    });

    test('a held token is not asked for again on every search; logout forgets it', () async {
      final h = EaHentaiHandler(ea(), 42);
      int logins = 0;
      h.fetcher = (url, {postJson}) async {
        if (url.endsWith('/api/auth/login')) {
          logins++;
          return (status: 200, body: '{"accessToken":"tok"}', finalUrl: url);
        }
        return (status: 200, body: '{"username":"someone57"}', finalUrl: url);
      };
      expect(await h.searchSetup(), isTrue);
      expect(await h.searchSetup(), isTrue);
      expect(logins, 1);
      await h.signOut();
      expect(await h.isSignedIn(), isFalse);
      expect(EaHentaiSessionHandler.instance.isLoggedIn, isFalse);
      expect(File('${tempDir.path}${Platform.pathSeparator}${EaHentaiSessionHandler.fileName}').existsSync(), isFalse);
    });

    test('no credentials: nothing is attempted', () async {
      final h = EaHentaiHandler(anonymous(), 42);
      h.fetcher = (url, {postJson}) async => throw StateError('no request expected: $url');
      expect(await h.canSignIn(), isFalse);
      expect(await h.searchSetup(), isTrue);
      expect(await h.isSignedIn(), isFalse);
    });
  });

  group('the search window', () {
    test('sort, scope and quick filters are offered', () {
      final DoujinFilterSpec spec = EaHentaiHandler(anonymous(), 42).doujinFilters;
      final DoujinFilterGroup sort = spec.group('sort')!;
      expect(sort.defaultValue, 'latest');
      expect(sort.options.map((o) => o.value), containsAll(['latest', 'today', 'weekly', 'monthly', 'alltime']));
      expect(spec.group('type')!.options.map((o) => o.value), containsAll(['artist', 'character', 'parody', 'tag']));
      final DoujinFilterGroup filter = spec.group('filter')!;
      expect(filter.multi, isTrue);
      expect(filter.options, hasLength(8));
    });

    test('suggestions come from the site, typed by namespace', () {
      final List<TagSuggestion> out = EaHentaiHandler.parseSuggestions(json('eahentai_api_suggestions.json'));
      expect(out.map((s) => s.tag), containsAll(['glasses', 'artist:glass_wall_garden', 'character:glastrier', 'glasses-blowjob']));
      final int liveCount = int.parse((json('eahentai_api_suggestions.json')['items'] as List).first['albumCount'].toString());
      expect(out.firstWhere((s) => s.tag == 'glasses').count, liveCount);
      expect(liveCount, greaterThan(1000));
    });
  });

  group('the HTML fallback parsers still read the site', () {
    test('the streamed hydration chunks decode, and pipe fields split', () {
      final String payload = EaHentaiHandler.decodeNextPayload(fixture('eahentai_payload.html'));
      expect(payload, contains('"tags"'));
      final List<String> tags = EaHentaiHandler.pipeField(payload, 'tags');
      expect(tags.length, greaterThan(3));
      expect(tags, contains('glasses'));
      expect(EaHentaiHandler.pipeField('', 'tags'), isEmpty);
      expect(EaHentaiHandler.decodeNextPayload('<html><body>nothing</body></html>'), isEmpty);
      final List<String> app = EaHentaiHandler(anonymous(), 42).tagsFromPayload(payload).map((t) => t.fullString).toList();
      expect(app, contains('big_breasts'));
      expect(app.every((t) => !t.contains(' ')), isTrue);
    });

    test('a reader page lists every full-size image in page order, thumbnails excluded', () {
      final List<String> urls = EaHentaiHandler.fullImageUrls(fixture('eahentai_reader.html'));
      expect(urls, hasLength(5));
      final numbers = [for (final u in urls) int.parse(RegExp(r'image(\d+)\.').firstMatch(u)!.group(1)!)];
      expect(numbers, [...numbers]..sort());
      expect(EaHentaiHandler.fullImageUrls('<img src="https://i.eahentai.com/file/ea-gallery/galleries/aaaa/thumbnail/image1t.jpg"/>'), isEmpty);
      expect(EaHentaiHandler.galleryHash(fixture('eahentai_reader.html')).length, greaterThanOrEqualTo(16));
    });
  });

  group('wiring', () {
    test('the factory builds the handler and it reads', () {
      final result = BooruHandlerFactory().getBooruHandler([anonymous()], 42);
      expect(result.booruHandler, isA<EaHentaiHandler>());
      expect(result.booruHandler.hasReader, isTrue);
      expect(result.booruHandler.hasSignInSupport, isTrue);
    });

    test('it is a doujin source, with item attribution by host', () {
      expect(DoujinDataHandler.isDoujinBooru(anonymous()), isTrue);
      final item = BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://eahentai.com/a/73480', serverId: '73480');
      expect(DoujinDataHandler.isDoujinItem(item), isTrue);
      expect(EaHentaiHandler(anonymous(), 42).relatedVersionsQuery(item), 'related:73480');
    });
  });
}

class _Resp {
  _Resp(this.data);
  final dynamic data;
  final int statusCode = 200;
}
