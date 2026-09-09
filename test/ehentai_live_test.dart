@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/reader_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// e-hentai.org (anonymous) and hdoujin.org from the LIVE sites through the
/// app's own client — a report run, not part of the offline suite. No
/// account is used: exhentai and the clearance-gated hdoujin reader are not
/// reached here.
///
///   flutter test test/ehentai_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 25
    ..alice = Alice();
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();

  final Booru eh = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  EHentaiHandler ehHandler() => EHentaiHandler(eh, 25);

  test('e-hentai: the newest list, then the page the cursor leads to', () async {
    final h = ehHandler();
    final List<BooruItem> p1 = List<BooruItem>.from(await h.search('', null));
    debugPrint('e-hentai p1: ${p1.length} items, total ${h.totalCount.value}, error "${h.errorString}", first ${p1.firstOrNull?.postURL} tags=${p1.firstOrNull?.tagsList.length}');
    expect(h.errorString, isEmpty);
    expect(p1.length, greaterThanOrEqualTo(20));
    h.pageNum = 1;
    final List<BooruItem> all = List<BooruItem>.from(await h.search('', null));
    final List<BooruItem> p2 = all.skip(p1.length).toList();
    debugPrint('e-hentai p2: ${p2.length} items, overlap ${p1.map((i) => i.serverId).toSet().intersection(p2.map((i) => i.serverId).toSet()).length}');
    expect(p2.length, greaterThanOrEqualTo(20));
    expect(p1.map((i) => i.serverId).toSet().intersection(p2.map((i) => i.serverId).toSet()), isEmpty);
  });

  test('e-hentai: a tag search comes back tagged; a category chip narrows it', () async {
    final h = ehHandler();
    final List<BooruItem> items = List<BooruItem>.from(await h.search('parody:genshin_impact language:english', null));
    debugPrint('genshin/english: ${items.length} items, total ${h.totalCount.value}, first tags ${items.firstOrNull?.tagsList.map((t) => t.fullString).take(6).join(' ')}');
    expect(items, isNotEmpty);
    expect(items.every((i) => i.tagsList.any((t) => t.fullString == 'english')), isTrue);
    final h2 = ehHandler();
    final List<BooruItem> nonH = List<BooruItem>.from(await h2.search('category:non-h parody:genshin_impact', null));
    debugPrint('non-h genshin: ${nonH.length} items, total ${h2.totalCount.value}');
    expect(nonH.every((i) => i.tagsList.any((t) => t.fullString == 'non-h')), isTrue);
  });

  test('e-hentai: a gallery registers its pages; page 1 resolves through the page view, page 2 through showpage; the image serves without cookies', () async {
    final h = ehHandler();
    final List<BooruItem> items = List<BooruItem>.from(await h.search('language:english', null));
    final BooruItem gallery = items.firstWhere((i) => (i.fileCountHint.value ?? 0) >= 3);
    final res = await h.loadItem(item: gallery);
    debugPrint('gallery ${gallery.postURL}: failed=${res.failed} error=${res.error} pages=${ReaderHandler.instance.pagesFor(gallery)?.length} tags=${gallery.tagsList.length} desc=${gallery.description?.split('\n').first}');
    expect(res.failed, isFalse, reason: res.error);
    final List<BooruItem> pages = ReaderHandler.instance.pagesFor(gallery)!;
    expect(pages.length, gallery.fileCountHint.value);
    expect(pages.every((p) => p.mediaType.value == MediaType.needToLoadItem), isTrue);
    final r1 = await h.loadItem(item: pages[0]);
    debugPrint('page 1: failed=${r1.failed} error=${r1.error} url=${pages[0].fileURL.split('/').take(3).join('/')} ${pages[0].fileWidth}x${pages[0].fileHeight} ext=${pages[0].fileExt}');
    expect(r1.failed, isFalse, reason: r1.error);
    expect(pages[0].fileURL, contains('hath.network'));
    final r2 = await h.loadItem(item: pages[1]);
    debugPrint('page 2: failed=${r2.failed} error=${r2.error} url=${pages[1].fileURL.split('/').take(3).join('/')}');
    expect(r2.failed, isFalse, reason: r2.error);
    expect(pages[1].mediaType.value, MediaType.image);
    // The image itself, from the hath node, with no cookie and no referer.
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.headUrl(Uri.parse(pages[0].fileURL));
    request.headers.set(HttpHeaders.userAgentHeader, Tools.browserUserAgent);
    final HttpClientResponse response = await request.close();
    debugPrint('image HEAD: ${response.statusCode} ${response.headers.contentType}');
    client.close(force: true);
    expect(response.statusCode, 200);
    // Related: newer versions + parent through gdata (may be empty; must not error).
    final h3 = ehHandler();
    final List<BooruItem> related = List<BooruItem>.from(await h3.search('related:${gallery.serverId}', null));
    debugPrint('related: ${related.length} items, error "${h3.errorString}"');
    expect(h3.errorString, isEmpty);
  });

  test('hdoujin: the popular shelf and a search answer on the hdoujin network', () async {
    final Booru hd = Booru('hdoujin', BooruType.HDoujin, '', 'https://hdoujin.org', '');
    final SchaleHandler h = SchaleHandler(hd, 20);
    final List<BooruItem> popular = List<BooruItem>.from(await h.search('', null));
    debugPrint('hdoujin popular: ${popular.length} items, error "${h.errorString}", first ${popular.firstOrNull?.postURL} pages=${popular.firstOrNull?.fileCountHint.value}');
    expect(h.errorString, isEmpty);
    expect(popular, isNotEmpty);
    expect(popular.first.postURL, startsWith('https://hdoujin.org/g/'));
    final SchaleHandler h2 = SchaleHandler(hd, 20);
    final List<BooruItem> found = List<BooruItem>.from(await h2.search('genshin', null));
    debugPrint('hdoujin genshin: ${found.length} items, error "${h2.errorString}"');
    expect(found, isNotEmpty);
  });
}
