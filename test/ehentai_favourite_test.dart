import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/doujin/ehentai/ehentai_handler.dart';
import 'package:lolisnatcher/sources/doujin/ehentai/ehentai_session_handler.dart';

/// Account favourites on e-hentai / exhentai. The popup URL is the one in
/// test/fixtures/ehentai_listing.html, captured 2026-09-09. The form fields
/// are EhViewer's addFavorites (seven332, read 2026-10-07): favcat, favnote,
/// submit=Apply Changes, update=1. favdel removes. Category 0 is the first
/// folder. The note is whatever the popup form already shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru booru = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  EHentaiHandler handler() => EHentaiHandler(booru, 25);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('ehentai-fav');
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

  BooruItem gallery() => BooruItem(
    fileURL: '',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: const [],
    postURL: 'https://e-hentai.org/g/4178435/29ec786079/',
    serverId: '4178435',
  );

  test('the form is gallerypopups.php on the handler host, never the EA bookmark API', () {
    final EHentaiFavouriteForm? add = ehentaiFavouriteForm(
      site: EHentaiHandler.defaultSite,
      gid: '4178435',
      token: '29ec786079',
      wantFavourite: true,
      note: 'keep me',
    );
    expect(add, isNotNull);
    expect(add!.url, 'https://e-hentai.org/gallerypopups.php?gid=4178435&t=29ec786079&act=addfav');
    expect(add.url, isNot(contains('/api/bookmarks')));
    expect(add.fields, {'favcat': '0', 'favnote': 'keep me', 'submit': 'Apply Changes', 'update': '1'});

    final EHentaiFavouriteForm? remove = ehentaiFavouriteForm(
      site: EHentaiHandler.exSite,
      gid: '4178435',
      token: '29ec786079',
      wantFavourite: false,
    );
    expect(remove!.url, startsWith('https://exhentai.org/gallerypopups.php?'));
    expect(remove.fields['favcat'], 'favdel');
    expect(remove.fields['submit'], 'Apply Changes');
    expect(remove.fields['favnote'], '');

    expect(ehentaiFavouriteForm(site: 'https://e-hentai.org.evil.com', gid: '1', token: 'aaaaaaaaaa', wantFavourite: true), isNull);
    expect(ehentaiFavouriteForm(site: 'https://not-e-hentai.org', gid: '1', token: 'aaaaaaaaaa', wantFavourite: true), isNull);
    expect(ehentaiFavouriteForm(site: EHentaiHandler.defaultSite, gid: '4178435_3', token: '29ec786079', wantFavourite: true), isNull);
    expect(ehentaiFavouriteForm(site: EHentaiHandler.defaultSite, gid: '4178435', token: '../cookies', wantFavourite: true), isNull);
  });

  test('a gallery URL from the captured listing yields its gid and token; a lookalike host does not', () {
    final String html = File('test/fixtures/ehentai_listing.html').readAsStringSync();
    final List<BooruItem> items = handler().itemsFromListing(html);
    final ({String gid, String token})? id = ehentaiFavouriteIdentity(items.first.postURL);
    expect(id?.gid, '4178435');
    expect(id?.token, '29ec786079');
    expect(ehentaiFavouriteIdentity('https://e-hentai.org.evil.com/g/4178435/29ec786079/'), isNull);
    expect(ehentaiFavouriteIdentity('https://not-e-hentai.org/g/1/aaaaaaaaaa/'), isNull);

    final ({String gid, String token})? page = ehentaiFavouriteIdentity(
      'https://exhentai.org/s/deadbeef00/4178435-3',
      rememberedToken: EHentaiHandler.tokenFor('4178435'),
    );
    expect(page?.gid, '4178435');
    expect(page?.token, '29ec786079');
    EHentaiHandler.resetForTests();
    expect(ehentaiFavouriteIdentity('https://e-hentai.org/s/deadbeef00/4178435-3'), isNull);
  });

  test('the note is the popup textarea, and a login page has none', () {
    expect(ehentaiFavouriteNote('<form><textarea name="favnote">keep &amp; me</textarea></form>'), 'keep & me');
    expect(ehentaiFavouriteNote('<textarea name="favnote"></textarea>'), '');
    expect(ehentaiFavouriteNote('<title>E-Hentai.org Login</title><p>This page requires you to log on.</p>'), isNull);
  });

  test('a 200 page is accepted unless it is the login bounce, kokomade, a blank exhentai page, or the sad-panda gif', () {
    expect(ehentaiFavouriteAccepted(status: 200, body: '<html><body>done</body></html>'), isTrue);
    expect(
      ehentaiFavouriteAccepted(status: 200, body: '<title>E-Hentai.org Login</title>', finalUrl: 'https://e-hentai.org/bounce_login.php?b=ds'),
      isFalse,
    );
    expect(ehentaiFavouriteAccepted(status: 200, body: '<img src="https://exhentai.org/img/kokomade.jpg">'), isFalse);
    expect(ehentaiFavouriteAccepted(status: 200, body: '   '), isFalse);
    expect(ehentaiFavouriteAccepted(status: 200, body: '<html></html>', contentType: 'image/gif'), isFalse);
    expect(ehentaiFavouriteAccepted(status: 403, body: '<html></html>'), isFalse);
  });

  test('logged out, the heart does not call the site', () async {
    final EHentaiHandler h = handler();
    expect(h.hasSiteFavourites, isFalse);
    expect(h.siteFavouritesLoginHint, contains('Source settings'));
    var calls = 0;
    h.favouritePageFetcher = (String url) async {
      calls++;
      return (status: 200, body: '<textarea name="favnote"></textarea>', finalUrl: url);
    };
    h.favouriteWriter = (String url, Map<String, String> fields) async {
      calls++;
      return (status: 200, body: '<html></html>', finalUrl: url, contentType: 'text/html');
    };
    final (bool ok, String message) = await h.setSiteFavourite(gallery(), true);
    expect(ok, isFalse);
    expect(message.toLowerCase(), contains('log in'));
    expect(calls, 0);
  });

  test('logged in, the heart posts category 0 and sends the note the form already had', () async {
    EHentaiSessionHandler.instance.store(memberId: '1', passHash: 'h');
    final EHentaiHandler h = handler();
    expect(h.hasSiteFavourites, isTrue);
    final List<String> gets = [];
    final List<(String, Map<String, String>)> posts = [];
    h.favouritePageFetcher = (String url) async {
      gets.add(url);
      return (status: 200, body: '<form><textarea name="favnote">keep me</textarea></form>', finalUrl: url);
    };
    h.favouriteWriter = (String url, Map<String, String> fields) async {
      posts.add((url, fields));
      return (status: 200, body: '<html><body>ok</body></html>', finalUrl: url, contentType: 'text/html');
    };
    final (bool ok, String message) = await h.setSiteFavourite(gallery(), true);
    expect(ok, isTrue, reason: message);
    expect(message, contains('category 0'));
    expect(gets, ['https://e-hentai.org/gallerypopups.php?gid=4178435&t=29ec786079&act=addfav']);
    expect(posts.single.$1, gets.single);
    expect(posts.single.$2['favcat'], '0');
    expect(posts.single.$2['favnote'], 'keep me');
    expect(posts.single.$2['submit'], 'Apply Changes');
    expect(posts.single.$2['update'], '1');
    expect(posts.single.$1, isNot(contains('/api/bookmarks')));

    final (bool removed, _) = await h.setSiteFavourite(gallery(), false);
    expect(removed, isTrue);
    expect(posts.last.$2['favcat'], 'favdel');
    expect(posts.last.$2['favnote'], 'keep me');
  });

  test('a login bounce is not followed by a post, and kokomade is a failure', () async {
    EHentaiSessionHandler.instance.store(memberId: '1', passHash: 'h');
    final EHentaiHandler h = handler();
    var posts = 0;
    h.favouritePageFetcher = (String url) async => (
      status: 200,
      body: '<title>E-Hentai.org Login</title>',
      finalUrl: 'https://e-hentai.org/bounce_login.php?b=ds',
    );
    h.favouriteWriter = (String url, Map<String, String> fields) async {
      posts++;
      return (status: 200, body: '<html></html>', finalUrl: url, contentType: 'text/html');
    };
    final (bool ok, String message) = await h.setSiteFavourite(gallery(), true);
    expect(ok, isFalse);
    expect(message.toLowerCase(), contains('log in'));
    expect(posts, 0);

    h.favouritePageFetcher = (String url) async => (
      status: 200,
      body: '<textarea name="favnote"></textarea>',
      finalUrl: url,
    );
    h.favouriteWriter = (String url, Map<String, String> fields) async {
      posts++;
      return (status: 200, body: '<img src="https://exhentai.org/img/kokomade.jpg">', finalUrl: url, contentType: 'text/html');
    };
    final (bool banned, _) = await h.setSiteFavourite(gallery(), true);
    expect(banned, isFalse);
    expect(posts, 1);
  });

  test('exhentai posts to exhentai.org, and a page with no remembered token is not posted', () async {
    EHentaiSessionHandler.instance.store(memberId: '1', passHash: 'h', igneous: 'ok');
    SourceSettingsHandler.instance.update(booru, (s) => s.siteVariant = 'exhentai');
    final EHentaiHandler h = handler();
    expect(h.site, EHentaiHandler.exSite);
    String? posted;
    h.favouritePageFetcher = (String url) async => (status: 200, body: '<textarea name="favnote">n</textarea>', finalUrl: url);
    h.favouriteWriter = (String url, Map<String, String> fields) async {
      posted = url;
      return (status: 200, body: '<html>ok</html>', finalUrl: url, contentType: 'text/html');
    };
    final (bool ok, _) = await h.setSiteFavourite(gallery(), true);
    expect(ok, isTrue);
    expect(posted, startsWith('https://exhentai.org/gallerypopups.php?gid=4178435&t=29ec786079&act=addfav'));

    EHentaiHandler.resetForTests();
    posted = null;
    final BooruItem page = BooruItem(
      fileURL: '',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: const [],
      postURL: 'https://e-hentai.org/s/deadbeef00/4178435-3',
      serverId: '4178435_3',
    );
    final (bool pageOk, String pageMessage) = await h.setSiteFavourite(page, true);
    expect(pageOk, isFalse);
    expect(pageMessage.toLowerCase(), contains('token'));
    expect(posted, isNull);
  });
}
