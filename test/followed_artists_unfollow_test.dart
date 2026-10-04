import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/models/pinned_tag.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/tags/logic/followed_artists_handler.dart';

/// 1.0 (M2): follows are global pins carrying the 'followed' label. Unfollow
/// deleted every global pin with the tag's name, so a plain pin on every
/// source for the same tag went with the follow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  bool dbReady = false;

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('followed_unfollow');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    dbReady = false;
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = SettingsHandler.instance.dbHandler;
      db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.updateTable();
      dbReady = true;
    } catch (e) {
      // ignore: avoid_print
      print('sqlite unavailable on this test host: $e');
    }
    SettingsHandler.instance.dbEnabled = true;
  });

  tearDown(() async {
    try {
      await SettingsHandler.instance.dbHandler.db?.close();
    } catch (_) {}
    SettingsHandler.instance.dbHandler.db = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('unfollow removes the follow only; a plain pin of the same tag on every source stays', () async {
    if (!dbReady) return;
    final db = SettingsHandler.instance.dbHandler;
    await FollowedArtistsHandler.follow('artist_x');
    // The pins editor: a pin for one source, then made global ("every source").
    await db.addPinnedTag('artist_x', booruType: 'Gelbooru', booruName: 'gelbooru');
    final PinnedTag plain = (await db.getAllPinnedTags()).firstWhere((p) => !p.isGlobal);
    await db.updatePinnedTag(plain.id, tagName: 'artist_x');
    expect((await db.getAllPinnedTags()).where((p) => p.isGlobal && p.tagName == 'artist_x').length, 2);

    await FollowedArtistsHandler.unfollow('artist_x');

    final List<PinnedTag> left = await db.getAllPinnedTags();
    expect(await FollowedArtistsHandler.isFollowed('artist_x'), isFalse);
    expect(left.map((p) => p.id), [plain.id], reason: 'the plain pin is not a follow');
    expect(FollowedArtistsHandler.isFollowPin(left.single), isFalse);
  });

  test('unfollow of a tag that is only followed removes it', () async {
    if (!dbReady) return;
    await FollowedArtistsHandler.follow('artist_y');
    expect(await FollowedArtistsHandler.isFollowed('artist_y'), isTrue);
    await FollowedArtistsHandler.unfollow('artist_y');
    expect(await FollowedArtistsHandler.isFollowed('artist_y'), isFalse);
    expect(await SettingsHandler.instance.dbHandler.getAllPinnedTags(), isEmpty);
  });
}
