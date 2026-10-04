import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/logging/log_redaction.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/booru_tag_store.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_tag.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/booru/hydrus_handler.dart';
import 'package:lolisnatcher/sources/booru/nozomi_handler.dart';
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

class _Stop implements Exception {}

/// Records what a search hands to the OR translation - the query after the
/// source settings were applied - and stops before any request.
class _NozomiProbe extends NozomiHandler {
  _NozomiProbe(super.booru, super.limit);

  String? asked;

  @override
  String translateOrSyntax(String tags) {
    asked = tags;
    throw _Stop();
  }
}

class _HydrusProbe extends HydrusHandler {
  _HydrusProbe(super.booru, super.limit);

  String? asked;

  @override
  String translateOrSyntax(String tags) {
    asked = tags;
    throw _Stop();
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

    test('two different posts with the same id from two sites are both shown; one site twice is a duplicate', () {
      final BooruHandler h = handlerFor(gelbooru);
      h.fetched.addAll([
        item('12345'),
        item('12345', host: 'danbooru.donmai.us'),
        item('777'),
        // The same gelbooru post again, its file on another server.
        BooruItem(
          fileURL: 'https://img2.gelbooru.com/images/777.png',
          sampleURL: 'https://img2.gelbooru.com/samples/777.png',
          thumbnailURL: 'https://img2.gelbooru.com/thumbs/777.png',
          tagsList: [Tag('solo')],
          postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=777',
          serverId: '777',
        ),
      ]);

      h.filterFetched();

      expect(h.filteredFetched.map((i) => Uri.parse(i.postURL).host), ['gelbooru.com', 'danbooru.donmai.us', 'gelbooru.com']);
      expect(h.filteredFetched.map((i) => i.serverId), ['12345', '12345', '777']);
    });

    test('merge: a post without an md5 is not taken for a copy of every other post without one', () {
      final MergebooruHandler merge = MergebooruHandler(Booru('Merge', BooruType.Merge, '', '', ''), 20);
      final List<BooruItem> pageOne = [item('1', host: 'nozomi.la')];

      expect(merge.hashInFetched(pageOne, null, 'https://img.redgifs.com/images/2.png'), isFalse);
      expect(merge.hashInFetched([item('1', md5: 'abc')], 'abc', 'https://img.other.com/images/9.png'), isTrue, reason: 'a real md5 match still is one');
    });
  });

  group('Set-Cookie into the jar', () {
    test('a value with "=" in it is kept whole (base64 padding)', () {
      expect(Tools.parseSetCookie('sess=abc==; Path=/; Secure').value, 'abc==');
      expect(Tools.parseSetCookie('token=a=b=c').value, 'a=b=c');
      expect(Tools.parseSetCookie('sess=abc==; Path=/').name, 'sess');
      expect(Tools.parseSetCookie('plain=value; path=/').value, 'value');
    });

    test('the attributes reach the jar: domain, path, expiry, secure, httponly', () {
      final int expiry = DateTime.utc(2037, 10, 21, 7, 28).millisecondsSinceEpoch;
      final full = Tools.parseSetCookie('sess=abc==; Path=/app; Domain=.site.example; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Secure; HttpOnly');
      expect(full.domain, '.site.example');
      expect(full.path, '/app');
      expect(full.expiresDate, expiry);
      expect(full.isSecure, isTrue);
      expect(full.isHttpOnly, isTrue);

      expect(Tools.parseSetCookie('a=1; expires=Wed, 21-Oct-2037 07:28:00 GMT').expiresDate, expiry, reason: 'the dashed date servers send');
      final int now = DateTime.now().millisecondsSinceEpoch;
      expect(
        Tools.parseSetCookie('a=1; Max-Age=3600; Expires=Wed, 21 Oct 2037 07:28:00 GMT').expiresDate,
        inInclusiveRange(now + 3600 * 1000 - 5000, now + 3600 * 1000 + 5000),
        reason: 'Max-Age wins over Expires',
      );

      final plain = Tools.parseSetCookie('plain=value');
      expect(plain.domain, isNull, reason: 'host-only');
      expect(plain.path, isNull, reason: 'saveCookies writes "/"');
      expect(plain.expiresDate, isNull, reason: 'a session cookie');
      expect(plain.isSecure, isFalse);
      expect(plain.isHttpOnly, isFalse);
    });
  });

  group('Source settings reach the handlers that search by themselves', () {
    test('Nozomi: always-add terms are searched', () async {
      final Booru nozomi = Booru('Nozomi', BooruType.Nozomi, '', 'https://nozomi.la', '');
      SourceSettingsHandler.instance.update(nozomi, (s) => s.alwaysAdd = 'sort:popular');
      final _NozomiProbe probe = _NozomiProbe(nozomi, 20);

      await expectLater(probe.search('cat', null), throwsA(isA<_Stop>()));

      expect(probe.asked, 'cat sort:popular');
    });

    test('Hydrus: always-add terms are searched', () async {
      final Booru hydrus = Booru('Hydrus', BooruType.Hydrus, '', 'http://127.0.0.1:45869', '');
      SourceSettingsHandler.instance.update(hydrus, (s) => s.alwaysAdd = 'system:inbox');
      final _HydrusProbe probe = _HydrusProbe(hydrus, 20);

      await expectLater(probe.search('cat', null), throwsA(isA<_Stop>()));

      expect(probe.asked, 'cat system:inbox');
    });
  });

  group('rule34video with Source settings', () {
    late bool dbReady;

    setUp(() async {
      dbReady = false;
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = SettingsHandler.instance.dbHandler;
        db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await db.updateTable();
        await db.createCriticalIndexes();
        SettingsHandler.instance.dbEnabled = true;
        dbReady = true;
      } catch (e) {
        // ignore: avoid_print
        print('sqlite unavailable on this test host: $e');
      }
    });

    tearDown(() async {
      try {
        await SettingsHandler.instance.dbHandler.db?.close();
      } catch (_) {}
      SettingsHandler.instance.dbHandler.db = null;
    });

    test('an always-add term keeps the slug the index stored for an artist', () async {
      if (!dbReady) return;
      final Booru booru = Booru('rule34video', BooruType.Rule34Video, '', 'https://rule34video.com', '');
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'paranoiddroid', tagType: TagType.artist, namespace: 'artist', sourceId: 'paranoid-droid'),
      ]);
      SourceSettingsHandler.instance.update(booru, (s) => s.alwaysAdd = 'type:futa');
      final List<String> asked = [];
      final Rule34VideoHandler h = Rule34VideoHandler(booru, Rule34VideoHandler.pageSize)
        ..listingFetch = (Uri uri) async {
          asked.add(uri.toString());
          return Response<dynamic>(requestOptions: RequestOptions(path: uri.toString()), statusCode: 200, data: '<html></html>');
        };

      await h.search('artist:paranoiddroid', null);

      expect(asked.first, 'https://rule34video.com/models/paranoid-droid/?flag1=15');
    });
  });
}
