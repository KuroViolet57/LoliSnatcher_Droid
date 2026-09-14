import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// r37: browse filters on the doujin sources — sort, category, language as
/// checkmarks in the search window, carried in the query as the sources'
/// own terms (`sort:popular`, `category:manga`, `language:english`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru hdoujin = Booru('hdoujin', BooruType.HDoujin, '', 'https://hdoujin.org', '');
  final Booru ehentai = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  final Booru hitomi = Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_filters');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the grammar', () {
    test("selected reads a key's terms, ignoring exclusions; apply replaces them and keeps everything else in place", () {
      expect(DoujinFilters.selected('hu_tao sort:popular language:english -category:manga', 'sort'), ['popular']);
      expect(DoujinFilters.selected('hu_tao category:manga category:doujinshi', 'category'), ['manga', 'doujinshi']);
      expect(DoujinFilters.selected('hu_tao -category:manga', 'category'), isEmpty);
      expect(DoujinFilters.apply('hu_tao sort:popular language:english', 'sort', ['date']), 'hu_tao language:english sort:date');
      expect(DoujinFilters.apply('hu_tao sort:popular', 'sort', []), 'hu_tao');
      expect(DoujinFilters.apply('', 'category', ['manga', 'doujinshi']), 'category:manga category:doujinshi');
      expect(DoujinFilters.apply('SORT:Popular x', 'sort', ['date']), 'x sort:date', reason: 'case does not matter');
    });
  });

  group('what each source offers', () {
    test("hdoujin: Latest and Popular are the two shelves the API has; the per-source default sort picks the empty query's shelf", () {
      final SchaleHandler h = SchaleHandler(hdoujin, 20);
      final DoujinFilterSpec spec = h.doujinFilters;
      expect(spec.group('sort')!.options.map((o) => o.value), ['latest', 'popular']);
      expect(spec.group('sort')!.defaultValue, 'popular', reason: "the site's own default for an empty query");
      expect(spec.group('language'), isNotNull);
      expect(h.makeURL(''), 'https://api.hdoujin.org/books/popular?page=1');
      expect(h.makeURL('sort:latest'), 'https://api.hdoujin.org/books?page=1');
      expect(h.makeURL('sort:popular'), 'https://api.hdoujin.org/books/popular?page=1');
      expect(h.makeURL('language:english sort:latest'), 'https://api.hdoujin.org/books?s=language%3Aenglish&page=1', reason: 'the sort term never reaches the site');
      expect(h.makeURL('language:english sort:popular'), 'https://api.hdoujin.org/books?s=language%3Aenglish&page=1', reason: 'the popular shelf has no search: the search wins');
      SourceSettingsHandler.instance.update(hdoujin, (s) => s.defaultSort = 'latest');
      expect(h.makeURL(''), 'https://api.hdoujin.org/books?page=1');
      expect(h.doujinFilters.group('sort')!.defaultValue, 'latest');
    });

    test("e-hentai: categories are a multiple choice, Popular is the site's own page, languages are tags", () {
      final EHentaiHandler h = EHentaiHandler(ehentai, 20);
      final DoujinFilterSpec spec = h.doujinFilters;
      expect(spec.group('category')!.multi, isTrue);
      expect(spec.group('category')!.options.map((o) => o.value), contains('doujinshi'));
      expect(spec.group('sort')!.options.map((o) => o.value), ['latest', 'popular']);
      expect(h.makeURL('sort:popular'), 'https://e-hentai.org/popular');
      expect(h.makeURL('sort:latest'), 'https://e-hentai.org/?inline_set=dm_e');
      expect(h.makeURL('genshin sort:popular'), contains('f_search=genshin'), reason: 'popular has no search: the search wins, the term is not sent');
      expect(h.makeURL('genshin sort:popular'), isNot(contains('sort')));
    });

    test('hitomi: Latest is the plain index, Popular has its periods, type and language are single choices', () {
      final HitomiHandler h = HitomiHandler(hitomi, 20);
      final DoujinFilterSpec spec = h.doujinFilters;
      final DoujinFilterGroup sort = spec.group('popular')!;
      expect(sort.options.first.value, '', reason: 'Latest = no term');
      expect(sort.options.map((o) => o.value), containsAll(['today', 'week', 'month', 'year']));
      expect(spec.group('type')!.options.map((o) => o.value), containsAll(['doujinshi', 'manga', 'artistcg']));
      expect(HitomiHandler.nozomiTargetFor('popular:week'), (area: 'popular', tag: 'week', language: 'all'));
    });

    test('nhentai keeps its sorts, categories and languages; asmhentai and hentaipaw offer their languages', () {
      final NHentaiHandler n = NHentaiHandler(nhentai, 20);
      expect(n.doujinFilters.group('sort')!.options.map((o) => o.value), contains('popular-week'));
      expect(n.doujinFilters.group('category')!.multi, isFalse, reason: 'nhentai ANDs tags');
      expect(n.doujinFilters.group('language')!.options.map((o) => o.value), contains('english'));
      expect(AsmHentaiHandler(Booru('asm', BooruType.AsmHentai, '', 'https://asmhentai.com', ''), 20).doujinFilters.group('language'), isNotNull);
      expect(HentaiPawHandler(Booru('paw', BooruType.HentaiPaw, '', 'https://hentaipaw.com', ''), 20).doujinFilters.group('language'), isNotNull);
    });
  });

  group('the Filters card', () {
    testWidgets('checkmarks write the terms into the query: a single choice replaces, a multiple choice toggles, the default reads as checked', (tester) async {
      String query = 'hu_tao';
      final SchaleHandler h = SchaleHandler(hdoujin, 20);
      final EHentaiHandler e = EHentaiHandler(ehentai, 20);
      DoujinFilterSpec spec = h.doujinFilters;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return SingleChildScrollView(
                  child: DoujinFiltersBlock(
                    spec: spec,
                    query: query,
                    onQueryChanged: (String q) => setState(() => query = q),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Filters'), findsOneWidget);
      final Finder popular = find.byKey(const ValueKey('doujin-filter-sort-popular'));
      final Finder latest = find.byKey(const ValueKey('doujin-filter-sort-latest'));
      expect(tester.widget<FilterChip>(popular).selected, isTrue, reason: 'the site default, shown checked');
      await tester.tap(latest);
      await tester.pump();
      expect(query, 'hu_tao sort:latest');
      expect(tester.widget<FilterChip>(latest).selected, isTrue);
      expect(tester.widget<FilterChip>(popular).selected, isFalse);
      await tester.tap(find.byKey(const ValueKey('doujin-filter-language-english')));
      await tester.pump();
      expect(query, 'hu_tao sort:latest language:english');
      await tester.tap(find.byKey(const ValueKey('doujin-filter-language-english')));
      await tester.pump();
      expect(query, 'hu_tao sort:latest', reason: 'a single choice tapped again clears it');
      // A multiple choice: e-hentai categories.
      spec = e.doujinFilters;
      query = '';
      refresh(() {});
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doujin-filter-category-manga')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doujin-filter-category-doujinshi')));
      await tester.pump();
      expect(query, 'category:manga category:doujinshi');
      await tester.tap(find.byKey(const ValueKey('doujin-filter-category-manga')));
      await tester.pump();
      expect(query, 'category:doujinshi');
    });
  });
}
