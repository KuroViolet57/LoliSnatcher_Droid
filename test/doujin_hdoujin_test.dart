import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_network.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/schale_clearance_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// hdoujin.org: the Schale software on its own hosts (api.hdoujin.org,
/// auth.hdoujin.org), probed 2026-09-09. Listing, popular and the GET detail
/// answer without a clearance; the reader's data needs one from
/// auth.hdoujin.org — a second clearance beside niyaniya's.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru hd = Booru('hdoujin', BooruType.HDoujin, '', 'https://hdoujin.org', '');
  final Booru niya = Booru('niyaniya', BooruType.NiyaNiya, '', 'https://niyaniya.moe', '');
  Response<dynamic> resp(String body) =>
      Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: jsonDecode(body));

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('hdoujin');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SchaleClearanceHandler.instance.resetForTests();
    SchaleHandler.resetDomainsForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SchaleClearanceHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('network table', () {
    test('hdoujin.org has its own API and auth hosts; every other base is the Schale network', () {
      final SchaleNetwork h = SchaleNetwork.forSite('https://hdoujin.org');
      expect(h.api, 'https://api.hdoujin.org');
      expect(h.auth, 'https://auth.hdoujin.org');
      expect(h.key, 'hdoujin');
      expect(SchaleNetwork.forSite('https://hdoujin.org/').key, 'hdoujin');
      final SchaleNetwork n = SchaleNetwork.forSite('https://niyaniya.moe');
      expect(n.api, 'https://api.schale.network');
      expect(n.auth, 'https://auth.schale.network');
      expect(n.key, 'schale');
      expect(SchaleNetwork.forSite('https://shupogaki.moe').key, 'schale');
      expect(SchaleNetwork.forSite('').key, 'schale');
    });

    test('the handler builds its URLs on the network of its base, and the tag catalog follows', () {
      final SchaleHandler h = SchaleHandler(hd, 20);
      expect(h.apiBase, 'https://api.hdoujin.org');
      expect(h.makeURL(''), 'https://api.hdoujin.org/books/popular?page=1', reason: 'the empty query is the popular shelf, as on niyaniya');
      expect(h.makeURL('genshin'), 'https://api.hdoujin.org/books?s=genshin&page=1');
      expect(h.getHeaders()['Referer'], 'https://hdoujin.org/');
      expect(h.getHeaders()['Origin'], 'https://hdoujin.org');
      expect(h.getMediaHeaders()['Referer'], 'https://hdoujin.org/');
      final SchaleTagCatalog catalog = h.tagCatalog as SchaleTagCatalog;
      expect(catalog.shardUrl(0), startsWith('https://api.hdoujin.org/books/tags'));
      final SchaleHandler n = SchaleHandler(niya, 20);
      expect(n.apiBase, 'https://api.schale.network');
      expect(n.makeURL(''), 'https://api.schale.network/books/popular?page=1');
      expect(SchaleHandler.defaultSiteFor(BooruType.HDoujin), 'https://hdoujin.org');
      expect(SchaleHandler.defaultSiteFor(BooruType.NiyaNiya), 'https://niyaniya.moe');
    });
  });

  group('parsing the same JSON', () {
    test('a search page and the popular shelf list books with pages and thumbnails', () async {
      final SchaleHandler h = SchaleHandler(hd, 20);
      h.currentTags = 'genshin';
      final List items = await h.parseListFromResponse(resp(fixture('hdoujin_search.json')));
      expect(items, isNotEmpty);
      final BooruItem first = items.first as BooruItem;
      expect(first.serverId, '225373');
      expect(first.postURL, 'https://hdoujin.org/g/225373/ada0292991b8');
      expect(first.thumbnailURL, startsWith('https://erocdn.net/books/thumb/'));
      expect(first.fileCountHint.value, 11);
      expect(first.description, contains('Genshin Impact'));
      h.currentTags = '';
      final List popular = await h.parseListFromResponse(resp(fixture('hdoujin_popular.json')));
      expect(popular, isNotEmpty);
    });

    test('a detail answer yields namespaced bare tags through the shared parser', () {
      final SchaleHandler h = SchaleHandler(hd, 20);
      final Map<String, dynamic> detail = jsonDecode(fixture('hdoujin_detail.json')) as Map<String, dynamic>;
      final tags = h.tagsFromDetail(detail);
      expect(tags.map((t) => t.fullString), containsAll(['chinese', 'translated']));
      expect(tags.every((t) => !t.fullString.contains(':')), isTrue);
      expect(h.tagNamespace('chinese'), 'language');
    });
  });

  group('one clearance per network', () {
    test('tokens are stored and invalidated per network, the legacy zero-argument calls mean the Schale network', () {
      final c = SchaleClearanceHandler.instance;
      c.store('schale-token');
      c.store('hd-token', siteUrl: 'https://hdoujin.org');
      expect(c.token, 'schale-token');
      expect(c.tokenFor('https://niyaniya.moe'), 'schale-token');
      expect(c.tokenFor('https://shupogaki.moe'), 'schale-token');
      expect(c.tokenFor('https://hdoujin.org'), 'hd-token');
      expect(c.hasTokenFor('https://hdoujin.org'), isTrue);
      c.invalidate(siteUrl: 'https://hdoujin.org');
      expect(c.tokenFor('https://hdoujin.org'), isNull);
      expect(c.rejectedTokenFor('https://hdoujin.org'), 'hd-token');
      expect(c.token, 'schale-token', reason: 'the other network keeps its token');
      c.invalidate();
      expect(c.token, isNull);
      expect(c.rejectedToken, 'schale-token');
    });

    test('the file keeps both networks, and a pre-r30 single-token file loads as the Schale network', () {
      final c = SchaleClearanceHandler.instance;
      c.store('A');
      c.store('B', siteUrl: 'https://hdoujin.org');
      final File file = File('${tempDir.path}${Platform.pathSeparator}${SchaleClearanceHandler.fileName}');
      final Map<String, dynamic> saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect((saved['sites'] as Map)['schale']['token'], 'A');
      expect((saved['sites'] as Map)['hdoujin']['token'], 'B');
      c.resetForTests();
      c.reloadForTests();
      expect(c.token, 'A');
      expect(c.tokenFor('https://hdoujin.org'), 'B');
      file.writeAsStringSync(jsonEncode({'token': 'legacy', 'trace': 't', 'at': 1}));
      c.resetForTests();
      c.reloadForTests();
      expect(c.token, 'legacy');
      expect(c.tokenFor('https://hdoujin.org'), isNull);
    });

    test('the solve message names no site', () {
      expect(SchaleClearanceHandler.needsSolveMessage, isNot(contains('niyaniya')));
      expect(SchaleClearanceHandler.needsSolveMessage, contains('Open the check'));
    });
  });

  group('wiring', () {
    test('a doujin source of its own type, built by the factory on the shared handler', () {
      expect(DoujinDataHandler.doujinTypes, contains(BooruType.HDoujin));
      expect(DoujinDataHandler.knownDoujinHosts, contains('hdoujin.org'));
      expect(BooruType.HDoujin.isDetectable, isFalse);
      expect(BooruType.HDoujin.isHDoujin, isTrue);
      expect(BooruType.HDoujin.alias, contains('HDoujin'));
      final h = BooruHandlerFactory().getBooruHandler([hd], null).booruHandler;
      expect(h, isA<SchaleHandler>());
      expect(h.hasReader, isTrue);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.readerImageQualities, isNotEmpty);
    });
  });
}
