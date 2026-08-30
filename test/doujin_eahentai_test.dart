import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: eahentai.com. Its visible markup carries almost no metadata —
/// tags and the gallery's image hash live in the streamed Next.js hydration
/// payload — so the payload decoder is what these tests mostly exercise,
/// against slices captured from the live site.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru ea() => Booru('eahentai', BooruType.EaHentai, '', 'https://eahentai.com', '');

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('ea_test');
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

  group('URLs', () {
    test('browse, search and gallery', () {
      final h = EaHentaiHandler(ea(), 20)..pageNum = 2;
      expect(h.makeURL(''), 'https://eahentai.com/?page=2');
      expect(h.makeURL('glasses'), 'https://eahentai.com/search?q=glasses&page=2');
      expect(h.makeURL('id:73480'), 'https://eahentai.com/a/73480');
      expect(h.makePostURL('73480'), 'https://eahentai.com/a/73480');
    });
  });

  group('hydration payload', () {
    test('the streamed chunks decode back to readable text', () {
      final payload = EaHentaiHandler.decodeNextPayload(fixture('eahentai_payload.html'));
      expect(payload, isNotEmpty);
      // The chunks are JS string literals; the escaped quotes must come back
      // as real ones or no field can be matched.
      expect(payload, contains('"tags"'));
    });

    test('pipe-separated fields are split into individual tags', () {
      final payload = EaHentaiHandler.decodeNextPayload(fixture('eahentai_payload.html'));
      final tags = EaHentaiHandler.pipeField(payload, 'tags');

      expect(tags.length, greaterThan(3));
      expect(tags, contains('glasses'));
      // Split, not left as one blob.
      expect(tags.every((t) => !t.contains('|')), isTrue);
    });

    test('tags become normalised app tags, spaces to underscores', () {
      final payload = EaHentaiHandler.decodeNextPayload(fixture('eahentai_payload.html'));
      final tags = EaHentaiHandler.tagsFromPayload(payload).map((t) => t.fullString).toList();

      expect(tags, contains('big_breasts'));
      expect(tags, contains('glasses'));
      expect(tags.every((t) => !t.contains(' ')), isTrue);
    });

    test('a missing field yields nothing rather than throwing', () {
      expect(EaHentaiHandler.pipeField('', 'tags'), isEmpty);
      expect(EaHentaiHandler.pipeField('{"other":"x"}', 'tags'), isEmpty);
      expect(EaHentaiHandler.tagsFromPayload(''), isEmpty);
    });

    test('a page with no payload at all decodes to empty, not an exception', () {
      expect(EaHentaiHandler.decodeNextPayload('<html><body>nothing</body></html>'), isEmpty);
    });
  });

  group('reader pages', () {
    test('every full-size image is collected, in page order', () {
      final urls = EaHentaiHandler.fullImageUrls(fixture('eahentai_reader.html'));

      expect(urls.length, 5);
      // Sorted by page NUMBER, not lexically — image10 must not precede image2.
      final numbers = [
        for (final u in urls) int.parse(RegExp(r'image(\d+)\.').firstMatch(u)!.group(1)!),
      ];
      final sorted = [...numbers]..sort();
      expect(numbers, sorted);
    });

    test('thumbnails are not mistaken for full-size pages', () {
      const thumbOnly =
          '<img src="https://i.eahentai.com/file/ea-gallery/galleries/aaaa/thumbnail/image1t.jpg"/>';
      expect(EaHentaiHandler.fullImageUrls(thumbOnly), isEmpty);
    });

    test('the gallery hash is read off the page', () {
      final hash = EaHentaiHandler.galleryHash(fixture('eahentai_reader.html'));
      expect(hash, isNotEmpty);
      expect(hash.length, greaterThanOrEqualTo(16));
    });
  });

  group('listing', () {
    test('gallery cards are read, and reader routes are not', () {
      final h = EaHentaiHandler(ea(), 20);
      final items = h.itemsFromListing(fixture('eahentai_listing.html'));

      expect(items, isNotEmpty);
      for (final item in items) {
        // /a/{id} only — never /a/{id}/{n}, which is a single reader page.
        expect(RegExp(r'/a/\d+$').hasMatch(item.postURL), isTrue);
      }
      expect(items.map((e) => e.serverId).toSet().length, items.length);
    });
  });

  group('wiring', () {
    test('the factory builds the handler and it reads', () {
      final result = BooruHandlerFactory().getBooruHandler([ea()], 20);
      expect(result.booruHandler, isA<EaHentaiHandler>());
      expect(result.booruHandler.hasReader, isTrue);
    });

    test('login is offered and gated on credentials', () async {
      final h = EaHentaiHandler(ea(), 20);
      expect(h.hasSignInSupport, isTrue);
      expect(await h.canSignIn(), isFalse);
      expect(await h.isSignedIn(), isFalse);
    });

    test('it is a doujin source, with item attribution by host', () {
      expect(DoujinDataHandler.isDoujinBooru(ea()), isTrue);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://eahentai.com/a/73480',
        serverId: '73480',
      );
      expect(DoujinDataHandler.isDoujinItem(item), isTrue);
    });

    test('Related is offered although the site publishes none', () {
      final h = EaHentaiHandler(ea(), 20);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://eahentai.com/a/73480',
        serverId: '73480',
      );
      expect(h.relatedVersionsQuery(item), 'related:73480');
    });
  });
}
