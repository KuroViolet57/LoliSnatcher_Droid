import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// The InterestsHandler guard: the booru taste profile refuses doujin
/// signals AT THE DOOR, whichever caller forgot to check. Every entry point
/// is tried with a doujin item/source and a booru one; only the booru one
/// may leave a pending signal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InterestsHandler interests;

  BooruItem itemOn(String postURL) => BooruItem(
    fileURL: 'https://cdn.example/x.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [Tag('hakurei_reimu'), Tag('kirisame_marisa')],
    postURL: postURL,
  );

  final BooruItem doujinItem = itemOn('https://nhentai.net/g/123456/');
  final BooruItem mirrorItem = itemOn('https://shupogaki.moe/g/1/abc');
  final BooruItem booruItem = itemOn('https://gelbooru.com/index.php?page=post&s=view&id=1');

  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('interests_guard');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = true
      ..enableInterestTracking = true;
    InterestsHandler.register();
    interests = InterestsHandler.instance;
  });

  tearDown(() async {
    await interests.flushNow();
    InterestsHandler.unregister();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a viewed doujin leaves no signal; a viewed booru post does', () {
    interests.onItemViewed(doujinItem, const Duration(seconds: 20));
    expect(interests.pendingSignals, isEmpty);
    interests.onItemViewed(booruItem, const Duration(seconds: 20));
    expect(interests.pendingSignals, isNotEmpty);
  });

  test('a doujin on a mirror host is still a doujin', () {
    interests.onItemViewed(mirrorItem, const Duration(seconds: 20));
    expect(interests.pendingSignals, isEmpty);
  });

  test('favouriting', () {
    interests.onItemFavourited(doujinItem, nowFavourite: true);
    expect(interests.pendingSignals, isEmpty);
    interests.onItemFavourited(booruItem, nowFavourite: true);
    expect(interests.pendingSignals['hakurei_reimu'], 6);
  });

  test('snatching and collecting a mixed list keeps only the booru items', () {
    interests.onItemsSnatched([doujinItem, mirrorItem]);
    expect(interests.pendingSignals, isEmpty);
    interests.onItemsCollected([doujinItem]);
    expect(interests.pendingSignals, isEmpty);
    interests.onItemsSnatched([doujinItem, booruItem]);
    expect(interests.pendingSignals['hakurei_reimu'], 4);
  });

  test('a search on a doujin source is refused, on a booru recorded', () {
    interests.onSearch('touhou', booru: nhentai);
    expect(interests.pendingSignals, isEmpty);
    interests.onSearch('touhou', booru: gelbooru);
    expect(interests.pendingSignals['touhou'], 2);
  });

  test('a tag preview from a doujin source is refused', () {
    interests.onTagPreviewOpened('touhou', booru: nhentai);
    expect(interests.pendingSignals, isEmpty);
    interests.onTagPreviewOpened('touhou', booru: gelbooru);
    expect(interests.pendingSignals['touhou'], 1.5);
  });
}
