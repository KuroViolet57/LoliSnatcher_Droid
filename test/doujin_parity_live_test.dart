@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r70 parity sweep against the LIVE sites, anonymous - a report run, not
/// part of the offline suite. No account: e-hentai's watched/favourites and
/// eahentai's bookmarks/lists are not reached here.
///
///   flutter test test/doujin_parity_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 25;
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();

  Booru of(BooruType type, String url) => Booru(type.name, type, '', url, '');

  test('e-hentai: the toplist of yesterday parses (compact rows), and tagsuggest answers', () async {
    final EHentaiHandler h = EHentaiHandler(of(BooruType.EHentai, 'https://e-hentai.org'), 25);
    final List<BooruItem> top = List<BooruItem>.from(await h.search('sort:toplist_yesterday', null));
    debugPrint('e-hentai toplist yesterday: ${top.length} items, error "${h.errorString}", first ${top.firstOrNull?.postURL} tags=${top.firstOrNull?.tagsList.length} pages=${top.firstOrNull?.fileCountHint.value}');
    expect(top.length, greaterThanOrEqualTo(40));
    expect(top.first.tagsList, isNotEmpty);
    final suggestions = await h.getTagSuggestions('big b');
    suggestions.fold(
      (e) => fail('tagsuggest failed: ${e.message}'),
      (list) {
        debugPrint('e-hentai tagsuggest: ${list.map((s) => s.tag).join(', ')}');
        expect(list, isNotEmpty);
      },
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('eahentai: one letter of artists and of tags from the index pages', () async {
    final EaHentaiHandler h = EaHentaiHandler(of(BooruType.EaHentai, 'https://eahentai.com'), 42);
    final List<BooruTagEntry>? artists = await h.tagCatalog!.shardAt('artist', 24);
    debugPrint('eahentai artists W: ${artists?.length} rows, first ${artists?.firstOrNull?.name} (${artists?.firstOrNull?.count})');
    expect(artists, isNotNull);
    expect(artists!.length, greaterThan(20));
    final List<BooruTagEntry>? tags = await h.tagCatalog!.shardAt('tag', 2);
    debugPrint('eahentai tags B: ${tags?.length} rows');
    expect(tags!.length, greaterThan(20));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('hentalk: the taxonomy in one request; a sorted search', () async {
    final FaccinaHandler h = FaccinaHandler(of(BooruType.Faccina, 'https://hentalk.pw'), 24);
    final List<BooruTagEntry>? rows = await h.tagCatalog!.shardAt('', 0);
    debugPrint('hentalk tagList: ${rows?.length} rows');
    expect(rows!.length, greaterThan(4000));
    final List<BooruItem> byTitle = List<BooruItem>.from(await h.search('sort:title order:asc', null));
    debugPrint('hentalk by title asc: ${byTitle.length}, first "${byTitle.firstOrNull?.description}", error "${h.errorString}"');
    expect(byTitle, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('niyaniya: the doujinshi category browses the site\'s own list', () async {
    final SchaleHandler h = SchaleHandler(of(BooruType.NiyaNiya, 'https://niyaniya.moe'), 25);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('category:doujinshi', null));
    debugPrint('niyaniya cat=4: ${items.length} items, error "${h.errorString}", first ${items.firstOrNull?.description}');
    expect(items, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('hentaipaw: the daily ranking', () async {
    final HentaiPawHandler h = HentaiPawHandler(of(BooruType.HentaiPaw, 'https://hentaipaw.com'), 25);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('sort:rank', null));
    debugPrint('hentaipaw rank: ${items.length} items, error "${h.errorString}", first ${items.firstOrNull?.description}');
    expect(items, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
