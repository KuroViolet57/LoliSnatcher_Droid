import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

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
      expect(s.comments, 0);
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

}
