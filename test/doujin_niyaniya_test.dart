import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: niyaniya.moe (Schale Network) as a doujin source.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru niyaniya() => Booru('niyaniya', BooruType.NiyaNiya, '', 'https://niyaniya.moe', '');
  Booru gelbooru() => Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('niyaniya_test');
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

  group('search URLs', () {
    test('an empty query browses the popular shelf', () {
      final h = SchaleHandler(niyaniya(), 20)..pageNum = 1;
      expect(h.makeURL(''), 'https://api.schale.network/books/popular?page=1');
    });

    test('a query uses ?s= — the parameter that actually filters', () {
      final h = SchaleHandler(niyaniya(), 20)..pageNum = 2;
      // ?search=, ?q=, ?tags= and friends are all silently ignored by the
      // API and return the unfiltered list, which is why this is pinned.
      expect(h.makeURL('glasses'), 'https://api.schale.network/books?s=glasses&page=2');
    });

    test('multi-word queries are encoded', () {
      final h = SchaleHandler(niyaniya(), 20)..pageNum = 1;
      // The API decodes '+' as a space (checked against the live endpoint:
      // 's=asami+asami' and 's=asami%20asami' return the same two results).
      expect(h.makeURL('asami asami'), contains('s=asami+asami'));
    });

    test('gallery URLs point at the site, not the API', () {
      final h = SchaleHandler(niyaniya(), 20);
      expect(h.makePostURL('27531'), 'https://niyaniya.moe/g/27531');
    });
  });

  group('the source is wired into the app', () {
    test('the factory builds a Schale handler for the type', () {
      final result = BooruHandlerFactory().getBooruHandler([niyaniya()], 20);
      expect(result.booruHandler, isA<SchaleHandler>());
      expect(result.booruHandler.hasReader, isTrue);
    });

    test('it is a DOUJIN source, so it inherits the whole doujin system', () {
      // Favourites, collections, history, follows, saved searches, pins, the
      // per-source blacklist and settings, backup coverage, doujin tabs and
      // the tag-star store all key off exactly this.
      expect(DoujinDataHandler.isDoujinBooru(niyaniya()), isTrue);
      expect(DoujinDataHandler.isDoujinBooru(gelbooru()), isFalse);
      expect(DoujinDataHandler.sameDomain(niyaniya(), gelbooru()), isFalse);
    });

    test('its items are attributed by host, so merge feeds stay separated', () {
      final item = BooruItem(
        fileURL: 'https://hikari.erocdn.net/x.jpg',
        sampleURL: 'https://hikari.erocdn.net/x.jpg',
        thumbnailURL: 'https://hikari.erocdn.net/x.jpg',
        tagsList: [Tag('vanilla')],
        postURL: 'https://niyaniya.moe/g/27531/b1a89d0bd191',
        serverId: '27531',
      );
      expect(DoujinDataHandler.isDoujinItem(item), isTrue);
    });

    test('doujin favourites for it land in the doujin store, not store.db', () {
      final booru = niyaniya();
      final item = BooruItem(
        fileURL: 'https://hikari.erocdn.net/x.jpg',
        sampleURL: 'https://hikari.erocdn.net/x.jpg',
        thumbnailURL: 'https://hikari.erocdn.net/x.jpg',
        tagsList: const [],
        postURL: 'https://niyaniya.moe/g/27531/b1a89d0bd191',
        serverId: '27531',
      )..description = 'A Work';

      DoujinDataHandler.instance.toggleFavourite(item, booru);
      expect(DoujinDataHandler.instance.favourites.length, 1);
      expect(
        DoujinDataHandler.instance.favourites.values.first.booruHost,
        'niyaniya.moe',
      );
    });

    test('its blacklist is the doujin one, per source', () {
      final booru = niyaniya();
      SourceSettingsHandler.instance.update(booru, (s) => s.tagBlacklist = 'guro');
      expect(SourceSettingsHandler.instance.tagBlacklist(booru), contains('guro'));
      // ...and it does not bleed onto another doujin source.
      final other = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
      expect(SourceSettingsHandler.instance.tagBlacklist(other), isNot(contains('guro')));
    });
  });

  group('Related / Recommended exist even though the site offers neither', () {
    test('the detail page asks for a generated related list', () {
      final h = SchaleHandler(niyaniya(), 20);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://niyaniya.moe/g/27531/b1a89d0bd191',
        serverId: '27531',
      );
      expect(h.relatedVersionsQuery(item), 'related:27531');
    });
  });
}
