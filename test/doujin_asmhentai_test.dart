import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: asmhentai.com. The parser tests run against markup captured from
/// the live site (titles swapped for placeholders, structure untouched), so
/// they fail if the site's actual shape changes rather than only if my
/// hand-written sample does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru asm() => Booru('asmhentai', BooruType.AsmHentai, '', 'https://asmhentai.com', '');

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('asm_test');
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
    test('browse and search', () {
      final h = AsmHentaiHandler(asm(), 20)..pageNum = 3;
      expect(h.makeURL(''), 'https://asmhentai.com/?page=3');
      expect(h.makeURL('glasses'), 'https://asmhentai.com/search/?q=glasses&page=3');
    });

    test('an id: query goes straight to the gallery page', () {
      final h = AsmHentaiHandler(asm(), 20)..pageNum = 1;
      expect(h.makeURL('id:676997'), 'https://asmhentai.com/g/676997/');
      expect(h.makePostURL('676997'), 'https://asmhentai.com/g/676997/');
    });
  });

  group('listing parser, against real markup', () {
    test('reads every card: id, title and cover', () {
      final h = AsmHentaiHandler(asm(), 20);
      final items = h.itemsFromListingForTests(fixture('asmhentai_listing.html'));

      expect(items.length, 2);
      expect(items.first.serverId, isNotEmpty);
      expect(items.first.postURL, startsWith('https://asmhentai.com/g/'));
      // The caption is the title, not the img alt.
      expect(items.first.description, contains('Placeholder Work'));
      // Protocol-relative cover URLs are made absolute.
      expect(items.first.thumbnailURL, startsWith('https://images.asmhentai.com/'));
    });

    test('the lazy-load placeholder is never mistaken for a cover', () {
      final h = AsmHentaiHandler(asm(), 20);
      final items = h.itemsFromListingForTests(fixture('asmhentai_listing.html'));
      for (final item in items) {
        expect(item.thumbnailURL, isNot(startsWith('data:')));
      }
    });

    test('the same gallery is never returned twice', () {
      final h = AsmHentaiHandler(asm(), 20);
      final items = h.itemsFromListingForTests(fixture('asmhentai_listing.html'));
      expect(items.map((e) => e.serverId).toSet().length, items.length);
    });
  });

  group('gallery parser, against real markup', () {
    test('tags carry the namespace from their link path', () {
      final h = AsmHentaiHandler(asm(), 20);
      final tags = h.tagsFromHtmlForTests(fixture('asmhentai_gallery.html'))
          .map((t) => t.fullString)
          .toList();

      // Tag NAMES are bare — the namespace is kept beside them, so a chip
      // never shows a raw `artist:` prefix.
      expect(tags, contains('sleeping'));
      expect(tags.any((t) => t.contains(':')), isFalse);
      expect(h.namespacesByTag.values, contains('parody'));
      expect(h.namespacesByTag.values, contains('artist'));
      expect(h.namespacesByTag.values, contains('character'));
    });

    test('the namespace round-trips through tagNamespace', () {
      final h = AsmHentaiHandler(asm(), 20);
      h.tagsFromHtmlForTests(fixture('asmhentai_gallery.html'));

      // A general tag has no namespace at all, which is what puts it in the
      // ordinary section rather than a named one.
      expect(h.tagNamespace('sleeping'), isNull);
      // Anything the site filed under a namespace answers with it.
      final String artist = h.namespacesByTag.entries.firstWhere((e) => e.value == 'artist').key;
      expect(h.tagNamespace(artist), 'artist');
      // A tag saved by an older build still carries its prefix inline; reading
      // it keeps those favourites and blacklists grouping correctly.
      expect(h.tagNamespace('artist:yurimo'), 'artist');
    });

    test('the page count comes off the page', () {
      expect(AsmHentaiHandler.pageCountForTests(fixture('asmhentai_gallery.html')), 20);
    });
  });

  group('wiring', () {
    test('the factory builds the handler and it reads', () {
      final result = BooruHandlerFactory().getBooruHandler([asm()], 20);
      expect(result.booruHandler, isA<AsmHentaiHandler>());
      expect(result.booruHandler.hasReader, isTrue);
    });

    test('login is offered, and only usable once credentials exist', () async {
      final h = AsmHentaiHandler(asm(), 20);
      expect(h.hasSignInSupport, isTrue);
      expect(await h.canSignIn(), isFalse);

      final withCreds = AsmHentaiHandler(
        Booru('asmhentai', BooruType.AsmHentai, '', 'https://asmhentai.com', '')
          ..userID = 'someone'
          ..apiKey = 'secret',
        20,
      );
      expect(await withCreds.canSignIn(), isTrue);
      // Not signed in until signIn() actually captures a session.
      expect(await withCreds.isSignedIn(), isFalse);
    });

    test('it is a doujin source and inherits the doujin system', () {
      expect(DoujinDataHandler.isDoujinBooru(asm()), isTrue);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://asmhentai.com/g/676997/',
        serverId: '676997',
      );
      expect(DoujinDataHandler.isDoujinItem(item), isTrue);
    });

    test('Related is offered even though the site publishes none', () {
      final h = AsmHentaiHandler(asm(), 20);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://asmhentai.com/g/676997/',
        serverId: '676997',
      );
      expect(h.relatedVersionsQuery(item), 'related:676997');
    });
  });
}
