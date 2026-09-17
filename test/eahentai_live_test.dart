@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// eahentai.com through its JSON API, from the LIVE site with the app's own
/// client — a report run, not part of the offline suite. No account: the
/// login is not exercised here.
///
///   flutter test test/eahentai_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 42;
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();

  final Booru ea = Booru('ea', BooruType.EaHentai, '', 'https://eahentai.com', '');
  EaHentaiHandler h() => EaHentaiHandler(ea, 42);

  test('latest: a page of galleries, each with tags, then a different second page', () async {
    final handler = h();
    final List<BooruItem> p1 = List<BooruItem>.from(await handler.search('', null));
    debugPrint('eahentai latest p1: ${p1.length} items, total ${handler.totalCount.value}, error "${handler.errorString}"');
    expect(p1.length, greaterThanOrEqualTo(30));
    expect(p1.where((i) => i.tagsList.isNotEmpty).length, greaterThan(p1.length ~/ 2), reason: 'tags come with the listing now');
    // search() answers the accumulated list; a page that repeated page 1 would
    // be dropped by the duplicate guard and the list would not grow.
    final List<BooruItem> all = List<BooruItem>.from(await handler.search('', 2));
    expect(all.length, greaterThan(p1.length), reason: 'a further page must add galleries');
    final Set<String> added = all.skip(p1.length).map((i) => i.postURL).toSet();
    expect(added.intersection(p1.map((i) => i.postURL).toSet()), isEmpty, reason: 'the added page must differ from page 1');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a typed search and a sorted search answer', () async {
    final handler = h();
    final List<BooruItem> artist = List<BooruItem>.from(await handler.search('artist:santa', null));
    debugPrint('eahentai artist:santa: ${artist.length}, total ${handler.totalCount.value}, error "${handler.errorString}"');
    expect(artist, isNotEmpty);
    final handler2 = h();
    final List<BooruItem> weekly = List<BooruItem>.from(await handler2.search('sort:weekly', null));
    debugPrint('eahentai popular weekly: ${weekly.length}, error "${handler2.errorString}"');
    expect(weekly, isNotEmpty);
    final handler3 = h();
    final List<BooruItem> filtered = List<BooruItem>.from(await handler3.search('glasses filter:full_color sort:alltime', null));
    debugPrint('eahentai glasses + full color, all time: ${filtered.length}, total ${handler3.totalCount.value}');
    expect(filtered, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a gallery opens from the album answer and its pages are listed', () async {
    final handler = h();
    final List<BooruItem> p1 = List<BooruItem>.from(await handler.search('', null));
    final BooruItem item = p1.first;
    final res = await handler.loadItem(item: item);
    expect(res.failed, isFalse, reason: res.error);
    final List<BooruItem> pages = ReaderHandler.instance.pagesFor(item)!;
    debugPrint('eahentai ${item.postURL}: ${pages.length} pages, first ${pages.first.fileURL}');
    expect(pages, isNotEmpty);
    expect(pages.first.fileURL, contains('i.eahentai.com'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('suggestions answer for a prefix', () async {
    final result = await h().getTagSuggestions('glas');
    result.fold(
      (error) => fail('suggestions failed: ${error.message}'),
      (list) {
        debugPrint('eahentai suggestions: ${list.map((s) => '${s.tag}(${s.count})').join(', ')}');
        expect(list, isNotEmpty);
      },
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}
