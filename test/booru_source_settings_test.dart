import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_site_filters.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/settings/source_settings_page.dart';

/// r43: every booru source gets its own settings — its site's sort/order and
/// rating filters (from the metatags its handler already declares, so each
/// site keeps its own words), default filters and "always add" terms applied
/// to every search on it, its hidden tags, its account, and notes about the
/// site. Reached from the left sidebar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru danbooru = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '');
  final Booru gelbooru = Booru('tbib', BooruType.Gelbooru, '', 'https://tbib.org', '');
  final Booru derpi = Booru('DerpiBooru', BooruType.Philomena, '', 'https://derpibooru.org', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('booru_source_settings');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.modularUi.clear();
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('site filters from the metatags a handler declares', () {
    test('danbooru: rating and order, each with the site default first; no ascending or technical orders', () {
      final DoujinFilterSpec spec = BooruSiteFilters.fromMetaTags(DanbooruHandler(danbooru, 20).availableMetaTags())!;
      final DoujinFilterGroup order = spec.group('order')!;
      final DoujinFilterGroup rating = spec.group('rating')!;
      expect(order.options.first.value, '');
      expect(order.options.first.label, 'Site default');
      expect(order.defaultValue, '');
      expect(order.options.map((o) => o.value), containsAll(['score', 'rank', 'favcount']));
      expect(order.options.map((o) => o.value), isNot(contains('score_asc')));
      expect(order.options.map((o) => o.value), isNot(contains('md5')));
      expect(rating.options.map((o) => o.value), containsAll(['general', 'sensitive', 'questionable', 'explicit']));
      expect(order.multi, isFalse);
    });

    test('the gelbooru engine: rating and sort, in its own words', () {
      final DoujinFilterSpec spec = BooruSiteFilters.fromMetaTags(GelbooruHandler(gelbooru, 20).availableMetaTags())!;
      expect(spec.group('sort')!.options.map((o) => o.value), contains('score'));
      expect(spec.group('sort')!.options.map((o) => o.value), isNot(contains('score:asc')));
      expect(spec.group('rating'), isNotNull);
    });

    test('a source with its own filters keeps them; local and doujin-only views get none of these', () {
      expect(FurAffinityHandler(fa, 48).siteFilters!.group('animated'), isNotNull);
      expect(NHentaiHandler(nhentai, 25).siteFilters, isNotNull, reason: 'its own filters');
      final Booru favourites = Booru('Favourites', BooruType.Favourites, '', '', '');
      expect(DanbooruHandler(favourites, 20).siteFilters, isNull);
      expect(DanbooruHandler(danbooru, 20).siteFilters!.group('order'), isNotNull);
    });
  });

  group('what a source searches', () {
    DoujinFilterSpec spec() => BooruSiteFilters.fromMetaTags(DanbooruHandler(danbooru, 20).availableMetaTags())!;

    test('default filters fill the groups the query leaves unset; always-add terms go last, never twice', () {
      expect(
        SourceSettingsHandler.composeQuery(query: 'cat', spec: spec(), defaultFilters: 'rating:general order:score', alwaysAdd: '-ai_generated'),
        'cat rating:general order:score -ai_generated',
      );
      expect(
        SourceSettingsHandler.composeQuery(query: 'cat order:rank', spec: spec(), defaultFilters: 'rating:general order:score', alwaysAdd: '-ai_generated'),
        'cat order:rank rating:general -ai_generated',
        reason: 'the query chose an order: the default order stays out',
      );
      expect(SourceSettingsHandler.composeQuery(query: 'cat -ai_generated', spec: spec(), alwaysAdd: '-ai_generated'), 'cat -ai_generated');
      expect(
        SourceSettingsHandler.composeQuery(query: 'cat', spec: spec(), defaultFilters: 'order:bogus'),
        'cat',
        reason: 'not an option of the site',
      );
      expect(SourceSettingsHandler.composeQuery(query: '', spec: null, alwaysAdd: '  '), '');
    });

    test('the handler searches with its source settings; a doujin source is left alone', () {
      SourceSettingsHandler.instance.update(danbooru, (s) {
        s.alwaysAdd = '-ai_generated';
        s.defaultFilters = 'rating:general';
      });
      expect(DanbooruHandler(danbooru, 20).sourceQuery('cat'), 'cat rating:general -ai_generated');
      SourceSettingsHandler.instance.update(nhentai, (s) => s.alwaysAdd = 'english');
      expect(NHentaiHandler(nhentai, 25).sourceQuery('cat'), 'cat');
    });

    test('the saved defaults show as the checked chips in the search window', () {
      final DoujinFilterSpec shown = SourceSettingsHandler.withDefaults(spec(), 'rating:explicit');
      expect(shown.group('rating')!.defaultValue, 'explicit');
      expect(shown.group('order')!.defaultValue, '');
    });

    test('the new settings are kept', () {
      final Map<String, dynamic> json = SourceSettings(alwaysAdd: '-ai_generated', defaultFilters: 'rating:general').toJson();
      expect(json, {'alwaysAdd': '-ai_generated', 'defaultFilters': 'rating:general'});
      final SourceSettings back = SourceSettings.fromJson(json);
      expect((back.alwaysAdd, back.defaultFilters), ('-ai_generated', 'rating:general'));
    });
  });

  group('derpibooru: the site filter and the sort are URL parameters', () {
    test('filter, sort field and direction go to the URL, not the query; Everything stays the default', () {
      final PhilomenaHandler h = PhilomenaHandler(derpi, 20)..pageNum = 1;
      final Uri plain = Uri.parse(h.makeURL('pony'));
      expect(plain.queryParameters['filter_id'], '56027');
      final Uri chosen = Uri.parse(h.makeURL('pony filter:default sf:score sd:asc'));
      expect(chosen.queryParameters['filter_id'], '100073');
      expect(chosen.queryParameters['sf'], 'score');
      expect(chosen.queryParameters['sd'], 'asc');
      expect(chosen.queryParameters['q'], 'pony');
      final DoujinFilterSpec spec = h.siteFilters!;
      expect(spec.group('filter')!.options.map((o) => o.value), containsAll(['everything', 'default', 'r34', 'dark', 'legacy', 'spoilers']));
      expect(spec.group('sf')!.options.map((o) => o.value), containsAll(['score', 'wilson_score', 'first_seen_at', 'random']));
      expect(spec.group('sd'), isNotNull);
    });
  });

  test('Modular UI: the booru filters card and the sidebar settings button are switches, on by default', () {
    expect(ModularUi.all, containsAll([ModularUi.searchSiteFilters, ModularUi.sidebarSourceSettings]));
    expect(ModularUi.isOn(ModularUi.searchSiteFilters), isTrue);
    expect(ModularUi.isOn(ModularUi.sidebarSourceSettings), isTrue);
  });

  testWidgets('a booru source settings page: search defaults, hidden tags, the site; no doujin reader rows', (tester) async {
    SettingsHandler.instance.booruList.add(danbooru);
    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: SourceSettingsPage(booru: danbooru)),
      ),
    );
    await tester.pump();
    expect(find.text('Always add to searches'), findsOneWidget);
    expect(find.text('Default filters'), findsOneWidget);
    expect(find.text('Hidden tags'), findsOneWidget);
    expect(find.text('About this site'), findsOneWidget);
    expect(find.text('Reading direction'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('doujin-filter-order-score')));
    await tester.pump();
    expect(SourceSettingsHandler.instance.settingsFor(danbooru).defaultFilters, 'order:score');
    await tester.enterText(find.byKey(const ValueKey('source-always-add')), '-ai_generated');
    await tester.pump();
    expect(SourceSettingsHandler.instance.settingsFor(danbooru).alwaysAdd, '-ai_generated');
  });

  /// r69: eahentai logs in through its API and says so on its page; e-hentai
  /// offers the first-page detail cover.
  testWidgets('eahentai: an ACCOUNT row with the login state and a Log in button', (tester) async {
    final Booru eahentai = Booru('eahentai', BooruType.EaHentai, '', 'https://eahentai.com', '');
    SettingsHandler.instance.booruList.add(eahentai);
    tester.view.physicalSize = const Size(420, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TranslationProvider(child: MaterialApp(home: SourceSettingsPage(booru: eahentai))));
    await tester.pump();
    expect(find.text('Not logged in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Detail cover from the first page'), findsOneWidget, reason: 'eahentai offers its full first page as the detail cover too');
  });

  testWidgets('e-hentai: the first-page detail cover is a switch on its page', (tester) async {
    final Booru eh = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
    SettingsHandler.instance.booruList.add(eh);
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TranslationProvider(child: MaterialApp(home: SourceSettingsPage(booru: eh))));
    await tester.pump();
    expect(find.text('Detail cover from the first page'), findsOneWidget);
  });
}
