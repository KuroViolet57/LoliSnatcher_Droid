import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/pages/flash_player_page.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// r40: FurAffinity, read from its pages. Fixtures captured live on
/// 2026-09-15: browse, search pages 1 and 2, ryan-the-fox's gallery,
/// favorites and profile, an image submission, a GIF submission, the search
/// form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('furaffinity');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    FurAffinitySessionHandler.instance.resetForTests();
  });

  tearDown(() {
    FurAffinitySessionHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('listings', () {
    test('every figure of a browse page is a card: its page, a sharper thumbnail, artist, rating, type, and the tags the site files it under', () {
      final String html = fixture('furaffinity_browse.html');
      final List<BooruItem> items = FurAffinityParser.listing(html);
      expect(items, hasLength(48));
      final RegExpMatch first = RegExp(r'<figure id="sid-(\d+)"[^>]*>.*?data-tags="([^"]*)".*?src="([^"]+)".*?<figcaption>.*?title="([^"]*)".*?href="/user/([^/]+)/"', dotAll: true).firstMatch(html)!;
      final BooruItem item = items.first;
      expect(item.serverId, first.group(1));
      expect(item.postURL, 'https://www.furaffinity.net/view/${first.group(1)}/');
      expect(item.thumbnailURL, 'https:${first.group(3)}');
      expect(item.sampleURL, contains('@600-'), reason: 'the listing thumbnail is 200 px; the card asks for 600');
      expect(item.description, first.group(4));
      final List<String> tags = item.tagsList.map((t) => t.fullString).toList();
      expect(tags, contains('artist:${first.group(5)}'));
      expect(tags, contains('rating:general'));
      expect(tags, contains('type:image'));
      final List<String> siteTags = first.group(2)!.split(' ');
      for (final String t in siteTags.where((t) => t.startsWith('c_') && t != 'c_all')) {
        expect(tags, contains('category:${t.substring(2)}'));
      }
      for (final String t in siteTags.where((t) => !t.contains('_') || (!t.startsWith('u_') && !t.startsWith('c_') && !t.startsWith('t_') && !t.startsWith('s_')))) {
        expect(tags, contains(t), reason: 'keyword $t');
      }
      expect(tags.any((t) => t.startsWith('u_')), isFalse, reason: 'the site\'s internal user tag is the artist tag instead');
      expect(item.mediaType.value, MediaType.needToLoadItem, reason: 'the full file is on the submission page');
      expect(items.map((i) => i.serverId).toSet(), hasLength(48));
    });

    test('search pages 1 and 2 are different cards', () {
      final Set<String?> a = FurAffinityParser.listing(fixture('furaffinity_search.html')).map((i) => i.serverId).toSet();
      final Set<String?> b = FurAffinityParser.listing(fixture('furaffinity_search_page2.html')).map((i) => i.serverId).toSet();
      expect(a, hasLength(48));
      expect(b, hasLength(48));
      expect(a.intersection(b), isEmpty);
    });

    test("a gallery says when there is a next page; favorites hand over their cursor", () {
      expect(FurAffinityParser.galleryHasNext(fixture('furaffinity_gallery.html')), isTrue);
      expect(FurAffinityParser.galleryHasNext(fixture('furaffinity_view_image.html')), isFalse);
      expect(FurAffinityParser.favoritesCursor(fixture('furaffinity_favorites.html')), '1996020605');
      expect(FurAffinityParser.listing(fixture('furaffinity_favorites.html')), hasLength(48));
    });
  });

  group('a submission', () {
    test('an image: its file, title, artist, avatar, keywords, category, theme, species, size, stats, rating and date', () {
      final FurAffinitySubmission s = FurAffinityParser.submission(fixture('furaffinity_view_image.html'))!;
      expect(s.fileUrl, 'https://d.furaffinity.net/art/redbow/1789436510/1789436510.redbow_masseffect3streampromo.png');
      expect(s.title, 'Mass Effect 3 Stream');
      expect(s.artist, 'redbow');
      expect(s.artistName, 'Diamond the Card Wyvern');
      expect(s.avatarUrl, 'https://a.furaffinity.net/1786568777/redbow.gif');
      expect(s.keywords, containsAll(['stream', 'streaming', 'redbow']));
      expect(s.category, 'All');
      expect(s.theme, 'All');
      expect(s.species, 'Unspecified / Any');
      expect(s.resolution, '1000 x 1000');
      expect(s.views, 31);
      expect(s.commentCount, 0);
      expect(s.favorites, 1);
      expect(s.rating, 'general');
      expect(s.postedAt, 1789436510);
    });

    test('a GIF is a GIF: the item becomes an animation with the play icon', () {
      final FurAffinitySubmission s = FurAffinityParser.submission(fixture('furaffinity_view_gif.html'))!;
      expect(s.fileUrl, endsWith('.gif'));
      expect(s.title, startsWith('YCH PIXEL PLUSH CLAW ARCADE MACHINE'));
      final FurAffinityHandler h = FurAffinityHandler(fa, 48);
      final BooruItem item = FurAffinityParser.listing(fixture('furaffinity_browse.html')).first;
      h.applySubmission(item, s);
      expect(item.fileURL, s.fileUrl);
      expect(item.fileExt, 'gif');
      expect(item.mediaType.value, MediaType.animation);
      expect(h.mediaIconFor(item), CupertinoIcons.play_fill);
    });

    test('an image keeps its tags and gains the keywords; its icon is the image icon', () {
      final FurAffinityHandler h = FurAffinityHandler(fa, 48);
      final BooruItem item = FurAffinityParser.listing(fixture('furaffinity_browse.html')).first;
      h.applySubmission(item, FurAffinityParser.submission(fixture('furaffinity_view_image.html'))!);
      expect(item.mediaType.value, MediaType.image);
      expect(item.tagsList.map((t) => t.fullString), containsAll(['stream', 'streaming', 'rating:general']));
      expect(h.mediaIconFor(item), Symbols.image_rounded);
    });
  });

  test('icons by what the site says the submission is: music, story, flash', () {
    final FurAffinityHandler h = FurAffinityHandler(fa, 48);
    BooruItem typed(String type) => FurAffinityParser.listing(fixture('furaffinity_browse.html')).first
      ..tagsList.removeWhere((t) => t.fullString.startsWith('type:'))
      ..tagsList.add(FurAffinityParser.typeTag(type));
    expect(h.mediaIconFor(typed('music')), Symbols.music_note_rounded);
    expect(h.mediaIconFor(typed('text')), Symbols.article_rounded);
    expect(h.mediaIconFor(typed('flash')), Symbols.extension_rounded);
    expect(h.mediaIconFor(typed('image')), Symbols.image_rounded);
  });

  test("an artist's profile: name, display name, avatar and counts", () {
    final FurAffinityUser u = FurAffinityParser.user(fixture('furaffinity_user.html'))!;
    expect(u.username, 'ryan-the-fox');
    expect(u.displayName, 'Ryan-the-fox');
    expect(u.avatarUrl, 'https://a.furaffinity.net/1592797951/ryan-the-fox.gif');
    expect(u.submissions, 1223);
    expect(u.favorites, 49116);
    expect(u.views, 121961);
  });

  group('the account', () {
    test('the session rides only on the site itself, never on its image hosts', () {
      final FurAffinityHandler h = FurAffinityHandler(fa, 48);
      expect(h.getHeaders().containsKey('Cookie'), isFalse, reason: 'logged out');
      FurAffinitySessionHandler.instance.store(a: 'AAA', b: 'BBB');
      expect(FurAffinitySessionHandler.instance.isLoggedIn, isTrue);
      expect(h.getHeaders()['Cookie'], allOf(contains('a=AAA'), contains('b=BBB')));
      expect(h.getMediaHeaders().containsKey('Cookie'), isFalse);
      expect(h.sendsJarCookiesToMedia, isFalse);
      expect(FurAffinitySessionHandler.sendsTo(Uri.parse('https://www.furaffinity.net/browse/')), isTrue);
      expect(FurAffinitySessionHandler.sendsTo(Uri.parse('https://d.furaffinity.net/art/x.png')), isFalse);
      expect(FurAffinitySessionHandler.sendsTo(Uri.parse('https://t.furaffinity.net/1@600-2.jpg')), isFalse);
      FurAffinitySessionHandler.instance.reloadForTests();
      expect(FurAffinitySessionHandler.instance.isLoggedIn, isTrue, reason: 'kept in its own file');
      FurAffinitySessionHandler.instance.logout();
      expect(FurAffinitySessionHandler.instance.isLoggedIn, isFalse);
      expect(FurAffinitySessionHandler.fromCookiePairs({'a': 'x', 'b': 'y', 'sz': '1'}), (a: 'x', b: 'y'));
      expect(FurAffinitySessionHandler.fromCookiePairs({'a': 'x'}).b, isNull);
    });
  });

  group('filters and the tag builder', () {
    test("the filters are the site's own: sort, types (art and photo by default), ratings (all), range", () {
      final DoujinFilterSpec spec = FurAffinityHandler(fa, 48).doujinFilters;
      expect(spec.group('sort')!.defaultValue, 'relevancy');
      final DoujinFilterGroup type = spec.group('type')!;
      expect(type.multi, isTrue);
      expect(type.defaultValues, ['art', 'photo']);
      expect(type.options.map((o) => o.value), containsAll(['art', 'photo', 'music', 'story', 'poetry', 'flash']));
      final DoujinFilterGroup rating = spec.group('rating')!;
      expect(rating.multi, isTrue);
      expect(rating.defaultValues, ['general', 'mature', 'adult']);
      expect(spec.group('range')!.defaultValue, 'all');
    });

    testWidgets('tapping one type when none was chosen starts from the defaults, not from nothing', (tester) async {
      String query = 'fox';
      final DoujinFilterSpec spec = FurAffinityHandler(fa, 48).doujinFilters;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: DoujinFiltersBlock(spec: spec, query: query, onQueryChanged: (q) => setState(() => query = q)),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('doujin-filter-type-art'))).selected, isTrue);
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('doujin-filter-type-photo'))).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('doujin-filter-type-music')));
      await tester.pump();
      expect(query, 'fox type:art type:photo type:music');
      await tester.tap(find.byKey(const ValueKey('doujin-filter-type-art')));
      await tester.pump();
      expect(query, 'fox type:photo type:music');
    });

    test('the tag builder lists categories, themes and species from the search form, and inserts them by id', () {
      final String html = fixture('furaffinity_search_form.html');
      final categories = FurAffinityTagCatalog.parseSelect(html, 'category', FurAffinityTagCatalog.categoryKey);
      final themes = FurAffinityTagCatalog.parseSelect(html, 'arttype', FurAffinityTagCatalog.themeKey);
      final species = FurAffinityTagCatalog.parseSelect(html, 'species', FurAffinityTagCatalog.speciesKey);
      expect(categories, hasLength(38), reason: '39 options without "All"');
      expect(themes, hasLength(51));
      expect(species, hasLength(397), reason: 'without "Unspecified / Any"');
      final catalog = FurAffinityHandler(fa, 48).tagCatalog! as FurAffinityTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), [FurAffinityTagCatalog.categoryKey, FurAffinityTagCatalog.themeKey, FurAffinityTagCatalog.speciesKey]);
      final canine = species.firstWhere((e) => e.sourceId == '6017');
      expect(canine.name, 'canine_(other)');
      expect(catalog.searchTerm(canine), 'species:6017');
      expect(catalog.searchTerm(categories.firstWhere((e) => e.sourceId == '2')), 'category:2');
      expect(catalog.searchTerm(themes.firstWhere((e) => e.sourceId == '4')), 'theme:4');
    });
  });

  group('r41: the account survives a webview, and the filters are all the site has', () {
    test('after a webview: newer account cookies are taken, a guest visit never replaces the account', () {
      final FurAffinitySessionHandler s = FurAffinitySessionHandler.instance;
      s.store(a: 'AAA', b: 'BBB');
      expect(s.afterWebView({'a': 'A2', 'b': 'B2', 'sz': '1'}), FurAffinityJarAction.none);
      expect(s.cookieHeader(), 'a=A2; b=B2', reason: 'the site rotated the session inside the webview');
      expect(s.afterWebView({'b': 'guest', 'sz': '1'}), FurAffinityJarAction.reseed, reason: 'the jar lost the account: it goes back');
      expect(s.cookieHeader(), 'a=A2; b=B2', reason: 'a guest cookie never replaces the account');
      s.logout();
      expect(s.afterWebView(const {}), FurAffinityJarAction.none);
      expect(s.afterWebView({'a': 'A3', 'b': 'B3'}), FurAffinityJarAction.none);
      expect(s.isLoggedIn, isTrue, reason: 'logging in inside any FurAffinity webview counts');
    });

    test('a FurAffinity webview gets the session before it loads; other sites do not', () {
      final FurAffinitySessionHandler s = FurAffinitySessionHandler.instance;
      expect(s.webViewNeedsSession('https://www.furaffinity.net/view/1/'), isFalse, reason: 'logged out');
      s.store(a: 'AAA', b: 'BBB');
      expect(s.webViewNeedsSession('https://www.furaffinity.net/view/1/'), isTrue);
      expect(s.webViewNeedsSession('https://furaffinity.net/'), isTrue);
      expect(s.webViewNeedsSession('https://gelbooru.com/'), isFalse);
      expect(s.webViewNeedsSession('gelbooru.com'), isFalse);
    });

    test('the filters add gender, match and results per page', () {
      final DoujinFilterSpec spec = FurAffinityHandler(fa, 48).doujinFilters;
      final DoujinFilterGroup gender = spec.group('gender')!;
      expect(gender.multi, isTrue);
      expect(gender.defaultValues, isEmpty);
      expect(gender.options.map((o) => o.value), ['male', 'female', 'trans_male', 'trans_female', 'intersex', 'non_binary']);
      expect(spec.group('mode')!.defaultValue, 'extended');
      expect(spec.group('mode')!.options.map((o) => o.value), containsAll(['extended', 'all', 'any']));
      expect(spec.group('perpage')!.options.map((o) => o.value), ['24', '48', '72']);
      expect(spec.group('perpage')!.defaultValue, '48');
    });
  });


  group('r42: the blocklist hides, the post page has everything, the account works', () {
    const String avatar = '<img class="loggedin_user_avatar avatar" src="//a.furaffinity.net/1/kuroviolet.gif" alt="KuroViolet">';

    String loggedInBrowse({required String tags, String users = '', String hideTagless = '0'}) => fixture('furaffinity_browse.html').replaceFirst(
      RegExp(r'<body[^>]*>'),
      '<body class="c-bodyColor" data-user-logged-in="1" data-tag-blocklist="$tags" data-user-blocklist="$users" data-tag-blocklist-hide-tagless="$hideTagless" data-tag-blocklist-nonce="n1">$avatar',
    );

    test('submissions with a tag or an artist on your FurAffinity blocklist are not there at all', () {
      final String html = fixture('furaffinity_browse.html');
      final List<BooruItem> all = FurAffinityParser.listing(html);
      final String keyword = all[0].tagsList.map((t) => t.fullString).firstWhere((t) => !t.contains(':'));
      final String artist = all[1].tagsList.map((t) => t.fullString).firstWhere((t) => t.startsWith('artist:')).substring(7);
      final FurAffinityBlocklist none = FurAffinityParser.blocklist(html);
      expect(none.isEmpty, isTrue, reason: 'logged out: no blocklist');
      final String blocked = loggedInBrowse(tags: keyword, users: 'u_$artist');
      final FurAffinityBlocklist list = FurAffinityParser.blocklist(blocked);
      expect(list.tags, contains(keyword));
      expect(list.users, contains('u_$artist'));
      final List<String> kept = FurAffinityParser.listing(blocked).map((i) => i.serverId!).toList();
      expect(kept, isNot(contains(all[0].serverId)));
      expect(kept, isNot(contains(all[1].serverId)));
      expect(kept.length, lessThan(all.length));
      for (final BooruItem i in FurAffinityParser.listing(blocked)) {
        expect(i.tagsList.map((t) => t.fullString), isNot(contains(keyword)));
      }
    });

    test('hide untagged content: a submission without tags goes too', () {
      String html = loggedInBrowse(tags: 'zzzznothing', hideTagless: '1');
      final RegExpMatch first = RegExp(r'data-tags="([^"]*)"').firstMatch(html)!;
      html = html.replaceFirst(first.group(0)!, 'data-tags=""');
      expect(FurAffinityParser.listing(html).length, FurAffinityParser.listing(fixture('furaffinity_browse.html')).length - 1);
    });

    test('a submission page: folders, description, comments, the neighbour in the gallery, the mini gallery', () {
      final FurAffinitySubmission s = FurAffinityParser.submission(fixture('furaffinity_view_folders.html'))!;
      expect(s.title, 'Happy 8/8!');
      expect(s.folders, hasLength(3));
      final FurAffinityFolder f = s.folders.first;
      expect((f.user, f.id, f.slug, f.name, f.group, f.count), ('ryan-the-fox', '464222', 'Ryan-McCloud', 'Ryan McCloud', "My fursona's", 116));
      expect(f.term, 'folder:ryan-the-fox/464222/Ryan-McCloud');
      expect(s.descriptionHtml, contains('Happy 8/8!'));
      expect(s.descriptionHtml, contains('https://www.furaffinity.net/view/61869875/'));
      expect(s.comments, hasLength(5));
      final FurAffinityComment c = s.comments.first;
      expect((c.id, c.username, c.displayName, c.text, c.postedAt), ('193012193', 'jonhankercheif', 'JonHankercheif', 'Happy late vore day fluffer', 1786278268));
      expect(c.avatarUrl, 'https://a.furaffinity.net/1775616396/jonhankercheif.gif');
      expect(s.olderId, '62753223');
      expect(s.newerId, isNull);
      expect(s.gallery.map((i) => i.serverId), contains('62753223'), reason: 'mini gallery figures use sid_');
      expect(FurAffinityParser.submission(fixture('furaffinity_view_image.html'))!.olderId, '66348089');
    });

    test("an artist's folders, grouped as the gallery page groups them", () {
      final List<FurAffinityFolder> folders = FurAffinityParser.userFolders(fixture('furaffinity_gallery.html'));
      expect(folders, hasLength(50));
      final FurAffinityFolder f = folders.first;
      expect((f.user, f.id, f.slug, f.name, f.group, f.count), ('ryan-the-fox', '464222', 'Ryan-McCloud', 'Ryan McCloud', "My fursona's", 116));
    });

    test('watch, favourite, who is logged in, the watch list, the inbox cursor', () {
      final String user = fixture('furaffinity_user.html');
      expect(FurAffinityParser.watchLink(user), isNull, reason: 'logged out: the link has no key');
      final watch = FurAffinityParser.watchLink(user.replaceFirst('/watch/ryan-the-fox/?key=', '/watch/ryan-the-fox/?key=abc'))!;
      expect((watch.path, watch.watching), ('/watch/ryan-the-fox/?key=abc', false));
      final unwatch = FurAffinityParser.watchLink('<a class="button" id="watch-button" href="/unwatch/ryan-the-fox/?key=abc">Unwatch</a>')!;
      expect(unwatch.watching, isTrue);
      expect(FurAffinityParser.favLink('<a class="button" href="/fav/66369202/?key=k1">+Fav</a>'), (path: '/fav/66369202/?key=k1', faved: false));
      expect(FurAffinityParser.favLink('<a class="button" href="/unfav/66369202/?key=k1">-Fav</a>')!.faved, isTrue);
      expect(FurAffinityParser.favLink(fixture('furaffinity_view_image.html')), isNull);
      expect(FurAffinityParser.loggedInUser(avatar), 'kuroviolet');
      expect(FurAffinityParser.loggedInUser(fixture('furaffinity_browse.html')), isNull);
      final watched = FurAffinityParser.watchlist(fixture('furaffinity_watchlist.html'));
      expect(watched.users, hasLength(200));
      expect((watched.users.first.username, watched.users.first.displayName), ('-fluffy-', '-Fluffy-'));
      expect(watched.hasNext, isTrue);
      expect(FurAffinityParser.inboxCursor('<a class="button standard more" href="/msg/submissions/new~66370000@72/">Next 72</a>'), 'new~66370000@72');
      expect(FurAffinityParser.inboxCursor(fixture('furaffinity_browse.html')), isNull);
    });

    test('the handler learns the account name and blocklist from pages, and pages the inbox by its cursor', () {
      final FurAffinitySessionHandler session = FurAffinitySessionHandler.instance;
      final FurAffinityHandler h = FurAffinityHandler(fa, 48);
      expect(h.hasSiteFavourites, isFalse);
      session.store(a: 'AAA', b: 'BBB');
      expect(h.hasSiteFavourites, isTrue);
      final String keyword = FurAffinityParser.listing(fixture('furaffinity_browse.html'))[0].tagsList.map((t) => t.fullString).firstWhere((t) => !t.contains(':'));
      h.currentTags = 'inbox:';
      final List parsed = h.parseListFromResponse(_Response(loggedInBrowse(tags: keyword) + '<a class="button standard more" href="/msg/submissions/new~66370000@72/">Next 72</a>')) as List;
      expect(parsed, isNotEmpty);
      expect(session.username, 'kuroviolet');
      expect(session.siteBlocklist!.tags, contains(keyword));
      h.pageNum = 1;
      expect(h.makeURL('inbox:'), 'https://www.furaffinity.net/msg/submissions/new~66370000@72/');
      session.reloadForTests();
      expect(session.username, 'kuroviolet', reason: 'kept with the session');
      session.logout();
      expect(session.username, isNull);
    });

    test('the Animated filter: all, or real GIF files only', () {
      final DoujinFilterGroup g = FurAffinityHandler(fa, 48).doujinFilters.group('animated')!;
      expect(g.defaultValue, 'all');
      expect(g.options.map((o) => o.value), ['all', 'gif']);
    });
  });


  group('r42b: Flash plays through Ruffle, the emulator the site itself uses', () {
    test('a Flash submission page gives its SWF and the Ruffle the site loads; the item is Flash', () {
      final String html = fixture('furaffinity_view_flash.html');
      final FurAffinitySubmission s = FurAffinityParser.submission(html)!;
      expect(s.fileUrl, 'https://d.furaffinity.net/art/alsnapz/1590186628/1439336748.alsnapz_panftr_v1_2015_08_11z_release.swf');
      expect(s.title, 'Panftr Player! -Vore Game-');
      expect(FurAffinityParser.ruffleScript(html), 'https://d.furaffinity.net/media/ruffle-0.2.0/ruffle.js');
      final BooruItem item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: [FurAffinityParser.typeTag('flash')],
        postURL: 'https://www.furaffinity.net/view/17371095/',
        serverId: '17371095',
      );
      expect(FlashPlayerPage.isFlash(item), isTrue, reason: 'the listing already says flash');
      FurAffinityHandler(fa, 48).applySubmission(item, s);
      expect(item.fileExt, 'swf');
      expect(FlashPlayerPage.isFlashUrl(item.fileURL), isTrue);
      expect(FlashPlayerPage.isFlash(FurAffinityParser.listing(fixture('furaffinity_browse.html')).first), isFalse);
    });

    test('the player page loads Ruffle, then the movie, filling the screen; the address is escaped', () {
      final String page = FlashPlayerPage.html(swfUrl: 'https://d.furaffinity.net/art/x/1/y.swf', ruffleUrl: FlashPlayerPage.defaultRuffle);
      expect(page, contains('<script src="https://d.furaffinity.net/media/ruffle-0.2.0/ruffle.js"></script>'));
      expect(page, contains('"https://d.furaffinity.net/art/x/1/y.swf"'));
      expect(page, contains('RufflePlayer.newest()'));
      expect(FlashPlayerPage.html(swfUrl: 'https://x/"</script>.swf', ruffleUrl: FlashPlayerPage.defaultRuffle), isNot(contains('"</script>')));
    });
  });

}

class _Response {
  _Response(this.data);

  final String data;
}
