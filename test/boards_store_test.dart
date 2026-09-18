import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r73: boards - saved "find me posts like this" queries: a description, a
/// reference image, must-have and excluded tags, the sources to ask. Kept in
/// `boards.json` beside the settings, with the SauceNAO key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final BoardsHandler store = BoardsHandler.instance;

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('boards_store');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    await store.resetForTests();
    store.directoryOverride = SettingsHandler.instance.path;
    await store.load();
  });
  tearDown(() async {
    await store.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a board round-trips through json; tags are parsed the booru way', () {
    final Board b = Board(
      id: 'b1',
      name: 'Beach girls',
      description: 'a blonde girl on a beach at sunset',
      mustTags: Board.parseTags('animated, Blonde_Hair  -solo'),
      excludeTags: Board.parseTags('male'),
      sourceNames: const ['Gelbooru', 'Danbooru'],
      imagePath: '/tmp/x.jpg',
      imageUrl: 'https://example.com/x.jpg',
    );
    expect(b.mustTags, ['animated', 'blonde_hair', 'solo'], reason: 'lowercase, a leading minus dropped');
    expect(b.hasImage, isTrue);
    final Board back = Board.fromJson(jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>);
    expect(back.id, 'b1');
    expect(back.name, 'Beach girls');
    expect(back.description, b.description);
    expect(back.mustTags, b.mustTags);
    expect(back.excludeTags, ['male']);
    expect(back.sourceNames, ['Gelbooru', 'Danbooru']);
    expect(back.imagePath, '/tmp/x.jpg');
    expect(back.imageUrl, 'https://example.com/x.jpg');
    expect(back.createdAt.millisecondsSinceEpoch, b.createdAt.millisecondsSinceEpoch);
    expect(Board.parseTags(''), isEmpty);
    expect(Board.fromJson(const {'id': 'x', 'name': 'n'}).mustTags, isEmpty, reason: 'missing fields default');
    // The image's source and the cached reverse-image matches travel too.
    final Board cached = b.copyWith(
      imageBooru: 'Gelbooru',
      matches: const [ReverseMatch(site: 'danbooru', postId: '1234', similarity: 93.5, tags: ['sakamata_chloe'], alsoOn: {'gelbooru': '99'})],
      matchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      matchedImage: 'file:/tmp/x.jpg',
    );
    expect(cached.imageKey, 'file:/tmp/x.jpg', reason: 'the copy wins over the address');
    expect(cached.hasFreshMatches, isTrue);
    expect(cached.copyWith(imagePath: '/tmp/y.jpg').hasFreshMatches, isFalse, reason: 'another image, stale matches');
    final Board cachedBack = Board.fromJson(jsonDecode(jsonEncode(cached.toJson())) as Map<String, dynamic>);
    expect(cachedBack.imageBooru, 'Gelbooru');
    expect(cachedBack.matches!.single.postId, '1234');
    expect(cachedBack.matches!.single.similarity, 93.5);
    expect(cachedBack.matches!.single.tags, ['sakamata_chloe']);
    expect(cachedBack.matches!.single.alsoOn, {'gelbooru': '99'});
    expect(cachedBack.matchedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(cachedBack.matchedImage, 'file:/tmp/x.jpg');
    expect(cachedBack.copyWith(clearMatches: true).matches, isNull);
    expect(cachedBack.copyWith(clearMatches: true).matchedImage, isEmpty);
    expect(Board.fromJson(const {'id': 'x', 'name': 'n'}).matches, isNull);
    // An empty answer is trusted for a day only (an index may have been down).
    expect(cached.copyWith(matches: const [], matchedAt: DateTime.now()).hasFreshMatches, isTrue);
    expect(cached.copyWith(matches: const [], matchedAt: DateTime.now().subtract(const Duration(days: 2))).hasFreshMatches, isFalse);
  });

  test('reloadFromDisk re-reads the file (a restore from backup)', () async {
    await store.save(Board(id: 'old', name: 'Old'));
    store.file.writeAsStringSync(jsonEncode({'version': 1, 'sauceNaoApiKey': 'restored', 'boards': [Board(id: 'new', name: 'Restored').toJson()]}));
    await store.reloadFromDisk();
    expect(store.boards.map((b) => b.name), ['Restored']);
    expect(store.sauceNaoApiKey, 'restored');
  });

  test('save, list, replace, delete; the file is written and read back on load', () async {
    expect(store.boards, isEmpty);
    final Board a = await store.save(Board(id: store.newId(), name: 'A', description: 'cats'));
    final Board b = await store.save(Board(id: store.newId(), name: 'B'));
    expect(a.id, isNot(b.id));
    expect(store.boards.map((x) => x.name), ['A', 'B']);
    final Board a2 = await store.save(a.copyWith(name: 'A2', mustTags: const ['cat']));
    expect(store.boards.map((x) => x.name), ['A2', 'B'], reason: 'replaced in place');
    expect(a2.updatedAt.isAfter(a.createdAt) || a2.updatedAt.isAtSameMomentAs(a.createdAt), isTrue);
    expect(store.byId(a.id)!.mustTags, ['cat']);
    expect(store.file.existsSync(), isTrue);
    await store.setSauceNaoApiKey('k123');
    // A fresh handler state reads the same file back.
    await store.resetForTests();
    store.directoryOverride = SettingsHandler.instance.path;
    await store.load();
    expect(store.boards.map((x) => x.name), ['A2', 'B']);
    expect(store.sauceNaoApiKey, 'k123');
    await store.delete(b.id);
    expect(store.boards.map((x) => x.name), ['A2']);
    expect(store.byId(b.id), isNull);
  });

  test('a reference image is copied under boards/ and removed with its board', () async {
    final Board b = await store.save(Board(id: store.newId(), name: 'pic'));
    final String path = await store.importImageBytes([0x89, 0x50, 0x4E, 0x47, 1, 2, 3], b.id, ext: 'png');
    expect(path, startsWith('${SettingsHandler.instance.path}boards${Platform.pathSeparator}'));
    expect(File(path).existsSync(), isTrue);
    expect(File(path).lengthSync(), 7);
    final Board withImage = await store.save(b.copyWith(imagePath: path));
    expect(withImage.hasImage, isTrue);
    await store.delete(b.id);
    expect(File(path).existsSync(), isFalse, reason: 'the copy goes with the board');
  });

  test('a broken file loads as no boards, not a crash; the revision counter ticks on every change', () async {
    store.file.writeAsStringSync('{not json');
    await store.resetForTests();
    store.directoryOverride = SettingsHandler.instance.path;
    await store.load();
    expect(store.boards, isEmpty);
    final int before = store.revision.value;
    await store.save(Board(id: store.newId(), name: 'x'));
    expect(store.revision.value, greaterThan(before));
  });
}
