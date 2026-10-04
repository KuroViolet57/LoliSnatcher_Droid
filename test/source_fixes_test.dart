import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/logging/log_redaction.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_handler.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_session_handler.dart';
import 'package:lolisnatcher/sources/local/mergebooru_handler.dart';
import 'package:lolisnatcher/sources/tube/rule34video_handler.dart';

/// The favourite/snatched lookup, held open until the test lets it answer.
class _GatedDb extends DBHandler {
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<List<bool>>> getMultipleTrackedValues(List<BooruItem> items) async {
    await gate.future;
    return [
      for (final _ in items) [true, true],
    ];
  }
}

/// m2 (1.0): source-side bugs from the subsystem map, each pinned by the
/// scenario that showed it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('Gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  BooruItem item(String id, {String host = 'gelbooru.com', String? md5}) => BooruItem(
    fileURL: 'https://img.$host/images/$id.png',
    sampleURL: 'https://img.$host/samples/$id.png',
    thumbnailURL: 'https://img.$host/thumbs/$id.png',
    tagsList: [Tag('solo')],
    postURL: 'https://$host/index.php?page=post&s=view&id=$id',
    serverId: id,
    md5String: md5,
  );

  BooruHandler handlerFor(Booru booru) => BooruHandlerFactory().getBooruHandler([booru], 20).booruHandler;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('source_fixes_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    FurAffinitySessionHandler.instance.resetForTests();
    Rule34VideoHandler.knownTagIds.clear();
    Rule34VideoHandler.knownUploaderIds.clear();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    FurAffinitySessionHandler.instance.resetForTests();
    Tools.resetCookieJarForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('credentials stay out of the log', () {
    test("FurAffinity's session cookies (a, b) are not written by getCookies; the request still carries them", () async {
      Tools.cookieJarReaderOverride = (String uri) async => const {};
      Logger.Inst();
      FurAffinitySessionHandler.instance.store(a: 'FASESSIONA0123456789', b: 'FASESSIONB0123456789');
      final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
      final int before = Logger.talker.history.length;

      final String? cookies = await FurAffinityHandler(fa, 48).getCookies();

      expect(cookies, allOf(contains('a=FASESSIONA0123456789'), contains('b=FASESSIONB0123456789')));
      final String logged = [for (final e in Logger.talker.history.skip(before)) e.generateTextMessage()].join('\n');
      expect(logged, contains('www.furaffinity.net'), reason: 'the line is still written, for diagnosis');
      expect(logged, isNot(contains('FASESSIONA0123456789')));
      expect(logged, isNot(contains('FASESSIONB0123456789')));
    });

    test("InkBunny's session id is redacted in a URL, a decoded answer and a raw JSON body", () {
      const String sid = 'SIDVALUE0123456789abc';
      expect(redactSecrets('https://inkbunny.net/api_search.php?output_mode=json&sid=$sid&text=cat'), isNot(contains(sid)));
      expect(redactSecrets('{sid: $sid, results_count_all: 3}'), isNot(contains(sid)));
      expect(redactSecrets('{"sid":"$sid","results_count_all":"3"}'), isNot(contains(sid)));
      expect(
        redactSecrets('https://inkbunny.net/api_search.php?output_mode=json&sid=$sid&text=cat'),
        contains('text=cat'),
        reason: 'only the value goes',
      );
    });
  });

  group('the feed', () {
    test('a refresh while the favourite/snatched lookup runs: the flags land on the posts they were read for', () async {
      final _GatedDb db = _GatedDb();
      sqfliteFfiInit();
      db.db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final DBHandler original = SettingsHandler.instance.dbHandler;
      SettingsHandler.instance.dbHandler = db;
      try {
        final BooruHandler h = handlerFor(gelbooru);
        final BooruItem a = item('1');
        final BooruItem b = item('2');
        final Future<void> page = h.afterParseResponse([a, b]);
        // The feed is reset and refilled by a new query meanwhile.
        h.fetched.value = [];
        final BooruItem c = item('3');
        h.fetched.add(c);
        db.gate.complete();

        await page;

        expect(a.isFavourite.value, isTrue);
        expect(b.isSnatched.value, isTrue);
        expect(c.isFavourite.value, isNot(isTrue), reason: "another query's post never gets these flags");
        expect(c.isSnatched.value, isNot(isTrue));
      } finally {
        SettingsHandler.instance.dbHandler = original;
        await db.db?.close();
      }
    });

    test('merge: a post without an md5 is not taken for a copy of every other post without one', () {
      final MergebooruHandler merge = MergebooruHandler(Booru('Merge', BooruType.Merge, '', '', ''), 20);
      final List<BooruItem> pageOne = [item('1', host: 'nozomi.la')];

      expect(merge.hashInFetched(pageOne, null, 'https://img.redgifs.com/images/2.png'), isFalse);
      expect(merge.hashInFetched([item('1', md5: 'abc')], 'abc', 'https://img.other.com/images/9.png'), isTrue, reason: 'a real md5 match still is one');
    });
  });
}
