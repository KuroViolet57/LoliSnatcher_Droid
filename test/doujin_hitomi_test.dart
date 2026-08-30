import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: hitomi.la.
///
/// hitomi has no API at all, so every one of these tests runs against the real
/// artefacts the site serves — the live `gg.js` script and a real galleryinfo
/// payload, both captured into `test/fixtures/` with only the title replaced.
/// The expected URLs below were verified against the CDN (HTTP 206,
/// `image/webp`) at the time the fixture was taken.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru hitomi() => Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', '');

  final String ggSource = File('test/fixtures/hitomi_gg.js').readAsStringSync();
  final String galleryInfoSource = File('test/fixtures/hitomi_galleryinfo.js').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('hitomi_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('gg.js — the rotating image-URL script', () {
    test('parses the real 22KB script into a prefix and a mirror table', () {
      final gg = HitomiGg.parse(ggSource);

      expect(gg.b, matches(RegExp(r'^\d+/$')));
      expect(gg.defaultM, 1);
      // The live script routes a couple of thousand keys to the other mirror.
      expect(gg.overrides.length, greaterThan(1000));
      expect(gg.overrides.values.toSet(), {0});
    });

    test('every accumulated case run gets the value that follows it', () {
      final gg = HitomiGg.parse('''
gg = { m: function(g) {
var o = 1;
switch (g) {
case 10:
case 11:
o = 0; break;
case 20:
o = 3; break;
}
return o;
},
b: '123/' };
''');

      expect(gg.m(10), 0);
      expect(gg.m(11), 0);
      expect(gg.m(20), 3);
      // Anything not listed falls through to the default.
      expect(gg.m(999), 1);
    });

    test('a script with no path prefix fails loudly instead of guessing', () {
      expect(
        () => HitomiGg.parse('gg = { m: function(g) { var o = 1; switch (g) { case 1: o = 0; break; } return o; } };'),
        throwsA(
          isA<HitomiFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('changed how it derives image URLs'), contains('"b"')),
          ),
        ),
      );
    });

    test('a script with no mirror table fails loudly instead of guessing', () {
      expect(
        () => HitomiGg.parse("gg = { m: function(g) { var o = 1; return o; }, b: '123/' };"),
        throwsA(
          isA<HitomiFormatException>().having(
            (e) => e.message,
            'message',
            contains('no longer contains a mirror table'),
          ),
        ),
      );
    });

    test('a prefix missing its slash is tolerated rather than producing a broken path', () {
      expect(HitomiGg.parse("gg = { m: function(g) { var o = 1; switch(g){case 1: o = 0; break;} return o; }, b: '77' };").b, '77/');
    });
  });

  group('gg.s — hash to mirror key', () {
    // JS: /(..)(.)$/.exec(h) then parseInt(m[2] + m[1], 16). The LAST character
    // leads. Reversing this yields a valid-looking number and a dead URL, which
    // is exactly the silent failure this test exists to prevent.
    test('reads the last character of the hash first', () {
      // ...905 -> "9" + "05" -> 0x905 = 2309
      const String hash = 'e7c087fc7648817da9d5bb88b6a790f3662694de4b32f486765f068de9a93059';
      expect(HitomiGg.subdomainKey(hash), 0x905);
      expect(HitomiGg.subdomainKey(hash), isNot(0x059));
    });

    test('rejects a hash that is not hexadecimal', () {
      expect(
        () => HitomiGg.subdomainKey('zzzz'),
        throwsA(isA<HitomiFormatException>()),
      );
    });
  });

  group('image URL derivation', () {
    const String hash = 'e7c087fc7648817da9d5bb88b6a790f3662694de4b32f486765f068de9a93059';
    const HitomiGg gg = HitomiGg(b: '1788094801/', defaultM: 1, overrides: {0x905: 0});

    test('builds the full-size URL hitomi itself would build', () {
      // Verified live: 206 image/webp.
      expect(
        HitomiHandler.imageUrlFor(gg, hash),
        'https://w1.gold-usergeneratedcontent.net/1788094801/2309/$hash.webp',
      );
    });

    test('thumbnails use the completely different webpbigtn path shape', () {
      // Verified live: 206 image/webp. Note <last>/<two before>/<hash>.
      expect(
        HitomiHandler.thumbnailUrlFor(gg, hash),
        'https://atn.gold-usergeneratedcontent.net/webpbigtn/9/05/$hash.webp',
      );
    });

    test('the mirror index shifts both hosts together', () {
      const HitomiGg other = HitomiGg(b: '1788094801/', defaultM: 1, overrides: {});
      expect(HitomiHandler.imageUrlFor(other, hash), startsWith('https://w2.'));
      expect(HitomiHandler.thumbnailUrlFor(other, hash), startsWith('https://btn.'));
    });

    test('a short hash cannot silently produce a wrong thumbnail path', () {
      expect(
        () => HitomiHandler.thumbnailUrlFor(gg, 'abc'),
        throwsA(isA<HitomiFormatException>()),
      );
    });
  });

  group('nozomi id lists', () {
    test('decodes packed big-endian int32 ids', () {
      final Uint8List bytes = Uint8List(12);
      final ByteData view = ByteData.sublistView(bytes);
      view.setInt32(0, 4157254, Endian.big);
      view.setInt32(4, 4157247, Endian.big);
      view.setInt32(8, 4157242, Endian.big);

      expect(HitomiHandler.decodeNozomi(bytes), [4157254, 4157247, 4157242]);
    });

    test('a length that is not a whole number of entries is refused, not truncated', () {
      expect(
        () => HitomiHandler.decodeNozomi([0, 0, 0, 1, 0]),
        throwsA(
          isA<HitomiFormatException>().having(
            (e) => e.message,
            'message',
            contains('search index format changed'),
          ),
        ),
      );
    });

    test('an empty range (past the end of an index) is simply no results', () {
      expect(HitomiHandler.decodeNozomi(const []), isEmpty);
    });
  });

  group('query routing into hitomi namespaces', () {
    ({String? area, String tag, String language})? target(String term) =>
        HitomiHandler.nozomiTargetFor(term);

    test('gendered tags live under tag/ with the gender kept in the name', () {
      expect(target('female:ahegao'), (area: 'tag', tag: 'female:ahegao', language: 'all'));
      expect(target('male:sole_male'), (area: 'tag', tag: 'male:sole male', language: 'all'));
    });

    test('language selects the whole-site index for that language', () {
      expect(target('language:japanese'), (area: null, tag: 'index', language: 'japanese'));
    });

    test("the app's parody/circle spellings map onto hitomi's series/group", () {
      expect(target('parody:blue_archive'), (area: 'series', tag: 'blue archive', language: 'all'));
      expect(target('circle:remora_field'), (area: 'group', tag: 'remora field', language: 'all'));
    });

    test('free text has no nozomi bucket and falls through to the search index', () {
      expect(target('sample gallery'), isNull);
      expect(target(''), isNull);
    });

    test('an unrecognised namespace is not flattened into an unrelated bucket', () {
      // Guessing here would answer with real results for the wrong thing.
      expect(target('rating:safe'), isNull);
    });

    test('builds the URLs the CDN actually serves', () {
      expect(
        HitomiHandler.nozomiUrlFor(target('female:ahegao')!),
        'https://ltn.gold-usergeneratedcontent.net/n/tag/female:ahegao-all.nozomi',
      );
      expect(
        HitomiHandler.nozomiUrlFor(target('artist:asami_asami')!),
        'https://ltn.gold-usergeneratedcontent.net/n/artist/asami%20asami-all.nozomi',
      );
      expect(
        HitomiHandler.nozomiUrlFor(target('language:japanese')!),
        'https://ltn.gold-usergeneratedcontent.net/n/index-japanese.nozomi',
      );
    });
  });

  group('query planning', () {
    test('splits positive and negative terms', () {
      final parsed = HitomiHandler.parseQuery('artist:remora  -female:ahegao  "blue archive"');
      expect(parsed.positive, ['artist:remora', 'blue archive']);
      expect(parsed.negative, ['female:ahegao']);
    });

    test('an empty query plans nothing rather than a bare minus', () {
      expect(HitomiHandler.parseQuery('  -  ').positive, isEmpty);
      expect(HitomiHandler.parseQuery('  -  ').negative, isEmpty);
    });
  });

  group('the free-text B-tree index', () {
    /// The node layout hitomi writes: int32 key count, (int32 length, bytes)*,
    /// int32 data count, (int64 offset, int32 length)*, int64 subnode[B+1].
    Uint8List buildNode({
      required List<List<int>> keys,
      required List<({int offset, int length})> datas,
      required List<int> subnodes,
    }) {
      final BytesBuilder builder = BytesBuilder();
      void int32(int value) {
        final ByteData d = ByteData(4)..setInt32(0, value, Endian.big);
        builder.add(d.buffer.asUint8List());
      }

      void int64(int value) {
        final ByteData d = ByteData(8)..setInt64(0, value, Endian.big);
        builder.add(d.buffer.asUint8List());
      }

      int32(keys.length);
      for (final key in keys) {
        int32(key.length);
        builder.add(key);
      }
      int32(datas.length);
      for (final data in datas) {
        int64(data.offset);
        int32(data.length);
      }
      for (int i = 0; i < 17; i++) {
        int64(i < subnodes.length ? subnodes[i] : 0);
      }
      return builder.toBytes();
    }

    test('decodes a node the way hitomi writes one', () {
      final node = HitomiHandler.decodeNode(
        buildNode(
          keys: [
            [0x12, 0xb9, 0x77, 0x54],
            [0x26, 0x89, 0x26, 0xe1],
          ],
          datas: [(offset: 77221604, length: 12), (offset: 113455600, length: 40)],
          subnodes: [0, 0, 0],
        ),
      );

      expect(node.keys.length, 2);
      expect(node.keys.first, [0x12, 0xb9, 0x77, 0x54]);
      expect(node.datas[1], (offset: 113455600, length: 40));
      expect(node.isLeaf, isTrue);
    });

    test('a node with a live subnode address is not a leaf', () {
      final node = HitomiHandler.decodeNode(
        buildNode(keys: [[1, 2, 3, 4]], datas: [(offset: 1, length: 1)], subnodes: [0, 464]),
      );
      expect(node.isLeaf, isFalse);
    });

    test('a truncated node is refused rather than read as zeroes', () {
      final Uint8List full = buildNode(
        keys: [[1, 2, 3, 4]],
        datas: [(offset: 1, length: 1)],
        subnodes: [0],
      );
      expect(
        () => HitomiHandler.decodeNode(full.sublist(0, full.length - 20)),
        throwsA(
          isA<HitomiFormatException>().having(
            (e) => e.message,
            'message',
            contains('search index format changed'),
          ),
        ),
      );
    });

    test('an impossible key count is refused', () {
      final ByteData header = ByteData(4)..setInt32(0, 9999, Endian.big);
      expect(
        () => HitomiHandler.decodeNode(header.buffer.asUint8List()),
        throwsA(isA<HitomiFormatException>()),
      );
    });

    test('locateKey finds an exact key and otherwise picks the descent slot', () {
      final node = HitomiHandler.decodeNode(
        buildNode(
          keys: [
            [0x10, 0, 0, 0],
            [0x30, 0, 0, 0],
            [0x50, 0, 0, 0],
          ],
          datas: [
            (offset: 1, length: 1),
            (offset: 2, length: 1),
            (offset: 3, length: 1),
          ],
          subnodes: [1, 2, 3, 4],
        ),
      );

      expect(HitomiHandler.locateKey(Uint8List.fromList([0x30, 0, 0, 0]), node), (found: true, index: 1));
      // Between the first and second key: descend through slot 1.
      expect(HitomiHandler.locateKey(Uint8List.fromList([0x20, 0, 0, 0]), node), (found: false, index: 1));
      // Past every key: descend through the last slot.
      expect(HitomiHandler.locateKey(Uint8List.fromList([0x99, 0, 0, 0]), node), (found: false, index: 3));
    });

    test('hashTerm is the first four bytes of the SHA-256 of the term', () {
      final expected = sha256.convert(utf8.encode('blue archive')).bytes.sublist(0, 4);
      expect(HitomiHandler.hashTerm('blue archive'), expected);
      expect(HitomiHandler.hashTerm('blue archive').length, 4);
    });
  });

  group('galleryinfo', () {
    test('reads the var-assignment wrapper around the JSON', () {
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource);
      expect(gallery['id'], '4157254');
      expect((gallery['files'] as List).length, 25);
    });

    test('a body that is not an assignment fails loudly', () {
      expect(
        () => HitomiHandler.parseGalleryInfo('404 Not Found'),
        throwsA(isA<HitomiFormatException>()),
      );
    });

    test("flattens hitomi's six separate tag keys into namespaced tags", () {
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource);
      final tags = HitomiHandler.tagsFromGallery(gallery).map((t) => t.fullString).toList();

      expect(tags, contains('artist:remora'));
      expect(tags, contains('circle:remora_field'));
      expect(tags, contains('parody:blue_archive'));
      expect(tags, contains('character:kei_tendou'));
      expect(tags, contains('type:doujinshi'));
      expect(tags, contains('language:japanese'));
    });

    test('gendered flags become the namespace, ungendered tags stay bare', () {
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource);
      final tags = HitomiHandler.tagsFromGallery(gallery).map((t) => t.fullString).toList();

      expect(tags, contains('female:bikini'));
      // `digital` carries neither flag on the real payload.
      expect(tags, contains('digital'));
      expect(tags, isNot(contains('female:digital')));
    });

    test('does not emit the same tag twice', () {
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource);
      final tags = HitomiHandler.tagsFromGallery(gallery).map((t) => t.fullString).toList();
      expect(tags.length, tags.toSet().length);
    });
  });

  group('doujin-domain membership', () {
    test('the factory builds a hitomi handler with a reader', () {
      final handler = BooruHandlerFactory().getBooruHandler([hitomi()], 20).booruHandler;
      expect(handler, isA<HitomiHandler>());
      expect(handler.hasReader, isTrue);
      expect(handler.hasLoadItemSupport, isTrue);
    });

    test('hitomi is part of the doujin domain, so it inherits the whole system', () {
      // Membership is the parity mechanism: favourites, collections, history,
      // follows, saved searches, per-source blacklist and settings, backup,
      // doujin tabs and tag stars all key off these two.
      expect(DoujinDataHandler.doujinTypes, contains(BooruType.Hitomi));
      expect(DoujinDataHandler.knownDoujinHosts, contains('hitomi.la'));
    });

    test('post URLs are recognised as doujin items', () {
      final handler = HitomiHandler(hitomi(), 20);
      expect(handler.makePostURL('4157254'), 'https://hitomi.la/galleries/4157254.html');
    });

    test('a gallery becomes a fully populated doujin item', () async {
      final handler = HitomiHandler(hitomi(), 20)..ggForTests = HitomiGg.parse(ggSource);
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource);

      final List items = await handler.parseListFromResponse(_FakeResponse([gallery]));
      expect(items, hasLength(1));

      final BooruItem item = items.first as BooruItem;
      expect(item.serverId, '4157254');
      expect(item.postURL, 'https://hitomi.la/galleries/4157254.html');
      expect(item.fileCountHint.value, 25);
      expect(item.description, contains('Sample Gallery Title'));
      expect(item.tagsList.map((t) => t.fullString), contains('artist:remora'));
      // The cover is a thumbnail, not a full-size page.
      expect(item.thumbnailURL, contains('/webpbigtn/'));
      // Related is offered because hitomi publishes its own related list.
      expect(handler.relatedVersionsQuery(item), 'related:4157254');
    });

    test('a gallery with no files is skipped rather than yielding a broken card', () async {
      final handler = HitomiHandler(hitomi(), 20)..ggForTests = HitomiGg.parse(ggSource);
      final gallery = HitomiHandler.parseGalleryInfo(galleryInfoSource)..['files'] = <dynamic>[];

      expect(await handler.parseListFromResponse(_FakeResponse([gallery])), isEmpty);
    });
  });
}

/// `fetchSearch` is overridden for hitomi and hands `parseListFromResponse` a
/// plain list of galleryinfo maps, so a stand-in response is all the parser
/// needs.
class _FakeResponse {
  _FakeResponse(this.data);

  final dynamic data;
}
