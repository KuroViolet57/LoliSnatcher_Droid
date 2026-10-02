@Tags(['live'])
library;

import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/foryou_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r75, live: "Recommend more like this" seeds the For You feed with a
/// post's character / artist / series tags. Against two real sources the
/// seeded feed must come back with posts, and say so when it does not.
///
///   flutter test test/foryou_seed_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory tempDir;

  setUp(() {
    final SettingsHandler settings = SettingsHandler.register();
    ViewerHandler.register();
    NavigationHandler.register();
    TagHandler.register();
    SearchHandler.register();
    InterestsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('foryou_seed_live');
    settings
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice()
      ..dbEnabled = false;
    settings.booruList.value = [
      Booru('Gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', ''),
      Booru('yande.re', BooruType.Moebooru, '', 'https://yande.re', ''),
    ];
    ForYouHandler.resetForTests();
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a feed seeded with a well-known character comes back with posts from the real sources', () async {
    final ForYouHandler h = ForYouHandler(Booru('For You', BooruType.ForYou, '', '', ''), 20);
    final List items = await h.search('seed:hatsune_miku seed:vocaloid', null) as List;
    // ignore: avoid_print
    print('seeded feed: ${items.length} posts, error "${h.errorString}", locked ${h.locked}');
    expect(items, isNotEmpty, reason: h.errorString);
    expect(items.first, isA<BooruItem>());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a feed seeded with a tag no site knows says which seed went unanswered', () async {
    final ForYouHandler h = ForYouHandler(Booru('For You', BooruType.ForYou, '', '', ''), 20);
    final List items = await h.search('seed:zzqqxxyy_nobody_has_this', null) as List;
    expect(items, isEmpty);
    expect(h.errorString, contains('zzqqxxyy_nobody_has_this'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
