import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';

/// r40: FurAffinity has no content API; the source reads its pages. The query
/// language maps what the app types onto those pages: browse, search (with the
/// site's own filters), an artist's gallery, scraps and favorites, one
/// submission.
void main() {
  const String site = 'https://www.furaffinity.net';
  String form() => File('test/fixtures/furaffinity_search_form.html').readAsStringSync();

  group('routes', () {
    test('an empty query is the browse page; page 2 has its own path', () {
      final FurAffinityQuery q = FurAffinityQuery.parse('');
      expect(q.kind, FurAffinityRoute.browse);
      expect(q.url(page: 1), '$site/browse/');
      expect(q.url(page: 2), '$site/browse/2/');
    });

    test('an artist: user: and gallery: are the gallery, scraps: and favorites: their own pages, names lowercased', () {
      expect(FurAffinityQuery.parse('user:Ryan-The-Fox').url(page: 1), '$site/gallery/ryan-the-fox/');
      expect(FurAffinityQuery.parse('gallery:ryan-the-fox').url(page: 3), '$site/gallery/ryan-the-fox/3/');
      expect(FurAffinityQuery.parse('scraps:ryan-the-fox').url(page: 2), '$site/scraps/ryan-the-fox/2/');
      final FurAffinityQuery fav = FurAffinityQuery.parse('favorites:ryan-the-fox');
      expect(fav.kind, FurAffinityRoute.favorites);
      expect(fav.user, 'ryan-the-fox');
      expect(fav.url(page: 1), '$site/favorites/ryan-the-fox/');
      expect(fav.url(page: 2, cursor: '1996020605'), '$site/favorites/ryan-the-fox/1996020605/next');
      expect(fav.url(page: 2), '', reason: 'favorites page by the cursor the previous page gave; without it there is no next page');
    });

    test('id: is one submission', () {
      final FurAffinityQuery q = FurAffinityQuery.parse('id:66369202');
      expect(q.kind, FurAffinityRoute.view);
      expect(q.url(page: 1), '$site/view/66369202/');
    });

    test('words go to the search, with the operators left as the site reads them', () {
      final FurAffinityQuery q = FurAffinityQuery.parse('fox | wolf -dragon "red panda"');
      expect(q.kind, FurAffinityRoute.search);
      final Uri u = Uri.parse(q.url(page: 2));
      expect(u.path, '/search/');
      expect(u.queryParameters['q'], 'fox | wolf -dragon "red panda"');
      expect(u.queryParameters['page'], '2');
      expect(u.queryParameters['mode'], 'extended');
    });
  });

  group('filters', () {
    test('defaults: art and photo, every rating (the account decides what it may see), relevancy, newest first, all time', () {
      final Uri u = Uri.parse(FurAffinityQuery.parse('fox').url(page: 1));
      expect(u.queryParameters['type-art'], '1');
      expect(u.queryParameters['type-photo'], '1');
      for (final String t in ['type-music', 'type-story', 'type-poetry', 'type-flash']) {
        expect(u.queryParameters.containsKey(t), isFalse, reason: t);
      }
      for (final String r in ['rating-general', 'rating-mature', 'rating-adult']) {
        expect(u.queryParameters[r], '1', reason: r);
      }
      expect(u.queryParameters['order-by'], 'relevancy');
      expect(u.queryParameters['order-direction'], 'desc');
      expect(u.queryParameters['range'], 'all');
    });

    test('filter terms replace the defaults and never reach the search text', () {
      final FurAffinityQuery q = FurAffinityQuery.parse('fox type:music type:story rating:general sort:date order:asc range:30days');
      final Uri u = Uri.parse(q.url(page: 1));
      expect(u.queryParameters['q'], 'fox');
      expect(u.queryParameters['type-music'], '1');
      expect(u.queryParameters['type-story'], '1');
      expect(u.queryParameters.containsKey('type-art'), isFalse);
      expect(u.queryParameters['rating-general'], '1');
      expect(u.queryParameters.containsKey('rating-adult'), isFalse);
      expect(u.queryParameters['order-by'], 'date');
      expect(u.queryParameters['order-direction'], 'asc');
      expect(u.queryParameters['range'], '30days');
    });

    test('category, theme and species go by the site ids, and a filter alone still searches', () {
      final Uri u = Uri.parse(FurAffinityQuery.parse('category:2 theme:4 species:6017').url(page: 1));
      expect(u.path, '/search/');
      expect(u.queryParameters['category'], '2');
      expect(u.queryParameters['arttype'], '4');
      expect(u.queryParameters['species'], '6017');
    });

    test('every parameter and value the source sends is one the site\'s own search form has', () {
      final String html = form();
      bool hasField(String name) => html.contains('name="$name"');
      bool hasOption(String name, String value) {
        final RegExpMatch? m = RegExp('<select[^>]*name="$name"[^>]*>(.*?)</select>', dotAll: true).firstMatch(html);
        return m != null && m.group(1)!.contains('value="$value"');
      }
      for (final String f in ['q', 'page', 'mode', 'order-by', 'order-direction', 'range', 'category', 'arttype', 'species',
          'rating-general', 'rating-mature', 'rating-adult', 'type-art', 'type-photo', 'type-music', 'type-story', 'type-poetry', 'type-flash']) {
        expect(hasField(f), isTrue, reason: f);
      }
      for (final String v in FurAffinityQuery.sorts) {
        expect(html.contains('value="$v"'), isTrue, reason: 'order-by $v');
      }
      for (final String v in FurAffinityQuery.ranges) {
        expect(html.contains('value="$v"'), isTrue, reason: 'range $v');
      }
      expect(hasOption('category', '2'), isTrue);
      expect(hasOption('arttype', '4'), isTrue);
      expect(hasOption('species', '6017'), isTrue);
    });
  });

  group('r41: the feed follows the filters, and the rest of the search form', () {
    Map<String, String> params(String query, {int page = 1}) => Uri.parse(FurAffinityQuery.parse(query).url(page: page)).queryParameters;

    test('an empty query with filter terms is a search with no words, so the main feed follows the filters', () {
      final FurAffinityQuery q = FurAffinityQuery.parse('rating:adult sort:popularity');
      expect(q.kind, FurAffinityRoute.search);
      expect(Uri.parse(q.url(page: 1)).path, '/search/');
      final Map<String, String> p = params('rating:adult sort:popularity');
      expect(p['q'], '');
      expect(p['rating-adult'], '1');
      expect(p.containsKey('rating-general'), isFalse);
      expect(p['order-by'], 'popularity');
      expect(params('range:7days', page: 2)['page'], '2');
      expect(FurAffinityQuery.parse('').kind, FurAffinityRoute.browse, reason: 'no filters: still the browse page');
      expect(FurAffinityQuery.parse('   ').kind, FurAffinityRoute.browse);
    });

    test('gender, match and results per page', () {
      final Map<String, String> p = params('fox gender:male gender:trans_female gender:robot mode:any perpage:72');
      expect(p['q'], 'fox', reason: 'a filter term with an unknown value is dropped, not searched for');
      expect(p['gender-male'], '1');
      expect(p['gender-trans_female'], '1');
      expect(p.keys.where((k) => k.startsWith('gender-')), hasLength(2));
      expect(p['mode'], 'any');
      expect(p['perpage'], '72');
      expect(params('fox')['mode'], 'extended');
      expect(params('fox').containsKey('perpage'), isFalse, reason: "the site's own default");
      expect(params('fox perpage:50').containsKey('perpage'), isFalse);
    });

    test('a manual date range', () {
      final Map<String, String> p = params('fox from:2024-01-01 to:2024-06-30');
      expect(p['range'], 'manual');
      expect(p['range_from'], '2024-01-01');
      expect(p['range_to'], '2024-06-30');
      expect(p['q'], 'fox');
      expect(params('fox from:yesterday')['range'], 'all', reason: 'not a date: ignored');
      expect(FurAffinityQuery.parse('from:2024-01-01').kind, FurAffinityRoute.search);
    });
  });

}
