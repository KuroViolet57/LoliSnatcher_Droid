@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin_foryou_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/recommender_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r33: the doujin For You against the LIVE sites (nhentai, e-hentai),
/// through the real handlers — a report run, not part of the offline suite.
///
///   flutter test test/doujin_foryou_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 20
    ..dbEnabled = false
    ..alice = Alice();
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  RecommenderHandler.register();
  Logger.Inst();

  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru ehentai = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
  settingsHandler.booruList
    ..clear()
    ..addAll([nhentai, ehentai]);

  DoujinEntry read(String id, List<String> tags) => DoujinEntry(
    postURL: 'https://nhentai.net/g/$id/',
    serverId: id,
    thumbnailURL: '',
    title: 'Book $id',
    booruHost: 'nhentai.net',
    addedAt: 1,
    tags: tags,
    pages: 30,
  );

  test('history mode: a page of galleries from more than one site, none of them already read', () async {
    DoujinDataHandler.instance
      ..resetForTests()
      ..history.addAll([
        read('1', ['parody:genshin_impact', 'character:hu_tao', 'artist:wakahi', 'female:big_breasts', 'female:nakadashi', 'language:english']),
        read('2', ['parody:blue_archive', 'character:hina', 'female:stockings', 'language:english']),
      ]);
    final DoujinForYouHandler h = DoujinForYouHandler(settingsHandler.ensureForYouDoujinBooru(), 20);
    final List<BooruItem> page = List<BooruItem>.from(await h.search('', null) as List);
    debugPrint('doujin For You (history): ${page.length} items, error "${h.errorString}", language "${h.language}", hosts ${page.map((i) => Uri.parse(i.postURL).host).toSet()}');
    for (final r in h.lastRequests) {
      debugPrint('  ask ${r.source}: "${r.query}" -> got ${r.got}, kept ${r.kept}${r.error.isEmpty ? '' : ', error: ${r.error}'}');
    }
    for (final BooruItem i in page.take(5)) {
      debugPrint('  ${i.postURL}  ${i.tagsList.take(6).map((t) => t.fullString).join(' ')}');
    }
    expect(h.errorString, isEmpty);
    expect(page, isNotEmpty);
    expect(page.every(DoujinDataHandler.isDoujinItem), isTrue);
    expect(page.map((i) => i.postURL), isNot(contains('https://nhentai.net/g/1/')));
    expect(page.map((i) => i.postURL).toSet().length, page.length);
  });

  test('seed mode: a namespaced seed reaches every site in its own grammar', () async {
    DoujinDataHandler.instance.resetForTests();
    final DoujinForYouHandler h = DoujinForYouHandler(settingsHandler.ensureForYouDoujinBooru(), 20);
    final List<BooruItem> page = List<BooruItem>.from(await h.search('seed:parody:genshin_impact', null) as List);
    debugPrint('doujin For You (seed): ${page.length} items, error "${h.errorString}", hosts ${page.map((i) => Uri.parse(i.postURL).host).toSet()}');
    for (final r in h.lastRequests) {
      debugPrint('  ask ${r.source}: "${r.query}" -> got ${r.got}, kept ${r.kept}${r.error.isEmpty ? '' : ', error: ${r.error}'}');
    }
    expect(h.errorString, isEmpty);
    expect(page, isNotEmpty);
    expect(page.map((i) => Uri.parse(i.postURL).host).toSet().length, greaterThan(1), reason: 'both sites answered');
    // A card resolves through its own source.
    final BooruItem card = page.firstWhere((i) => i.postURL.contains('e-hentai.org'));
    expect(h.handlerForItem(card).booru.type, BooruType.EHentai);
    final res = await h.loadItem(item: card);
    debugPrint('card ${card.postURL}: failed=${res.failed} error=${res.error} tags=${card.tagsList.length}');
    expect(res.failed, isFalse, reason: res.error);
  });
}
