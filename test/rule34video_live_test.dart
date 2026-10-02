@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/rule34video_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// rule34video.com from the LIVE site through the app's own client — a
/// report run, not part of the offline suite (see dart_test.yaml). A red
/// row can mean DDoS-Guard challenged this machine rather than a broken
/// handler; read the printed lines.
///
///   flutter test test/rule34video_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every HTTP request with an empty 400 unless the
  // mock overrides are removed; this file wants the real site.
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 24
    ..alice = Alice();
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();

  final Booru booru = Booru('rule34video', BooruType.Rule34Video, '', 'https://rule34video.com', '');
  Rule34VideoHandler handler() => Rule34VideoHandler(booru, Rule34VideoHandler.pageSize);
  bool typed(BooruItem i, String tag) => i.tagsList.any((t) => t.fullString == tag);

  test('newest: a page of cards, the site total, every card a video to load', () async {
    final h = handler();
    final List<BooruItem> items = List<BooruItem>.from(await h.search('', null));
    debugPrint('latest: ${items.length} items, total ${h.totalCount.value}, error "${h.errorString}", first ${items.firstOrNull?.postURL}');
    expect(h.errorString, isEmpty);
    expect(items.length, greaterThanOrEqualTo(20));
    expect(h.totalCount.value, greaterThan(300000));
    expect(items.every((i) => i.mediaType.value == MediaType.needToLoadItem), isTrue);
  });

  test('type:futa: the site filters the newest list (flag1)', () async {
    final h = handler();
    final List<BooruItem> items = List<BooruItem>.from(await h.search('type:futa', null));
    debugPrint('futa: ${items.length} items, badged ${items.where((i) => typed(i, 'type:futa')).length}');
    expect(items.length, greaterThanOrEqualTo(20));
    expect(items.every((i) => typed(i, 'type:futa')), isTrue, reason: 'flag1=15 honoured by the site');
  });

  test('text search: page 2 differs from page 1; a typed search is filtered on the phone', () async {
    final h1 = handler();
    final List<BooruItem> p1 = List<BooruItem>.from(await h1.search('genshin', null));
    final h2 = handler();
    final List<BooruItem> p2 = List<BooruItem>.from(await h2.search('genshin', 1));
    final Set<String?> overlap = p1.map((i) => i.serverId).toSet().intersection(p2.map((i) => i.serverId).toSet());
    debugPrint('genshin p1 ${p1.length} (total ${h1.totalCount.value}), p2 ${p2.length}, overlap ${overlap.length}');
    expect(p1.length, greaterThanOrEqualTo(20));
    expect(p2, isNotEmpty);
    expect(overlap, isEmpty);
    final h3 = handler();
    final List<BooruItem> futa = List<BooruItem>.from(await h3.search('genshin type:futa', null));
    debugPrint('genshin type:futa: ${futa.length} items after the phone filter, handler page now ${h3.page}');
    expect(futa.every((i) => typed(i, 'type:futa')), isTrue);
  });

  test('a video page resolves to an mp4 the CDN redirects without cookies', () async {
    final h = handler();
    final List<BooruItem> items = List<BooruItem>.from(await h.search('', null));
    final result = await h.loadItem(item: items.first);
    final String shown = (result.item?.fileURL ?? '').replaceAll(RegExp('v-acctoken=[^&]+'), 'v-acctoken=…');
    debugPrint(
      'loadItem: failed=${result.failed} error=${result.error} file=$shown '
      'tags=${result.item?.tagsList.map((t) => t.fullString).take(10).join(' ')} desc=${result.item?.description?.replaceAll('\n', ' | ')}',
    );
    expect(result.failed, isFalse);
    expect(result.item!.fileURL, contains('/get_file/'));
    expect(result.item!.fileURL, contains('.mp4'));
    expect(result.item!.mediaType.value, MediaType.video);
    expect(result.item!.tagsList, isNotEmpty);

    // The mp4 link redirects to the signed CDN URL; no cookies or referer.
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(Uri.parse(result.item!.fileURL));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, Tools.browserUserAgent);
    final HttpClientResponse response = await request.close();
    final int status = response.statusCode;
    final String? location = response.headers.value('location');
    client.close(force: true);
    debugPrint('mp4 link: $status -> ${location?.split('?').first}');
    expect(status, anyOf(200, 301, 302, 303, 307));
  });

  test('the three tag-builder indexes answer their first fragment', () async {
    final catalog = handler().tagCatalog!;
    final tags = await catalog.shardAt('tag', 0) ?? const [];
    final artists = await catalog.shardAt('artist', 0) ?? const [];
    final categories = await catalog.shardAt('category', 0) ?? const [];
    debugPrint(
      'tags ${tags.length} (${tags.take(2).map((e) => '${e.name}#${e.sourceId}(${e.count})').join(' ')}), '
      'artists ${artists.length} (${artists.take(2).map((e) => '${e.name}#${e.sourceId}').join(' ')}), '
      'categories ${categories.length} (${categories.take(2).map((e) => '${e.name}#${e.sourceId}').join(' ')})',
    );
    expect(tags.length, greaterThanOrEqualTo(100));
    expect(artists.length, greaterThanOrEqualTo(10));
    expect(categories.length, greaterThanOrEqualTo(30));
    expect(tags.every((e) => e.sourceId != null), isTrue);
  });
}
