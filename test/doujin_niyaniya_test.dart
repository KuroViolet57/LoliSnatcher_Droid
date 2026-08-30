import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
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

  group('tag namespaces', () {
    // schale marks every tag with a numeric namespace. Each code below was
    // confirmed against the live API: search a namespaced query, then read
    // back which code the matching tag came home with.
    Tag? tag(int? namespace, String name) => SchaleHandler.tagFromEntry({
      'name': name,
      'namespace': ?namespace,
      'count': 7,
    });

    test("the confirmed codes become the app's namespaces", () {
      expect(tag(1, 'shindol')?.fullString, 'artist:shindol');
      expect(tag(2, 'karomix')?.fullString, 'circle:karomix');
      expect(tag(3, 'expelled from paradise')?.fullString, 'parody:expelled_from_paradise');
      expect(tag(4, 'comic bavel 2026-09')?.fullString, 'magazine:comic_bavel_2026-09');
      expect(tag(8, 'yaoi')?.fullString, 'male:yaoi');
      expect(tag(9, 'busty')?.fullString, 'female:busty');
      expect(tag(10, 'group')?.fullString, 'mixed:group');
      expect(tag(11, 'english')?.fullString, 'language:english');
      expect(tag(12, 'uncensored')?.fullString, 'other:uncensored');
    });

    test('a tag with no namespace stays bare', () {
      expect(tag(null, 'ahegao')?.fullString, 'ahegao');
      expect(tag(0, 'big penis')?.fullString, 'big_penis');
    });

    test('an unobserved code is left bare rather than guessed at', () {
      // Codes 5-7 were never seen and character:/event:/publisher: queries are
      // rejected by the API. Guessing would file the tag under the wrong hub
      // section and stop the blacklist matching it.
      expect(tag(6, 'mystery')?.fullString, 'mystery');
    });

    test('artists and series get the tag types the UI colours by', () {
      expect(tag(1, 'shindol')?.tagType, TagType.artist);
      expect(tag(2, 'karomix')?.tagType, TagType.artist);
      expect(tag(3, 'blue archive')?.tagType, TagType.copyright);
      expect(tag(9, 'busty')?.tagType, TagType.none);
    });

    test('a detail payload is flattened without duplicates', () {
      final tags = SchaleHandler.tagsFromDetail({
        'tags': [
          {'name': 'ahegao', 'count': 1},
          {'name': 'ahegao', 'count': 1},
          {'name': 'shindol', 'namespace': 1},
          {'name': '', 'namespace': 1},
        ],
      }).map((t) => t.fullString).toList();

      expect(tags, ['ahegao', 'artist:shindol']);
    });
  });

  group('query translation', () {
    test('underscores become spaces, which is what schale actually stores', () {
      expect(SchaleHandler.translateQuery('artist:asami_asami'), 'artist:asami asami');
      expect(SchaleHandler.translateQuery('big_breasts'), 'big breasts');
    });

    test('namespaces and negation survive', () {
      expect(
        SchaleHandler.translateQuery('parody:blue_archive -female:ahegao'),
        'parody:blue archive -female:ahegao',
      );
    });

    test('an already-quoted term is left alone', () {
      expect(SchaleHandler.translateQuery('"comic bavel"'), '"comic bavel"');
    });

    test('an empty query stays empty, so browse means browse', () {
      expect(SchaleHandler.translateQuery('   '), '');
    });
  });
}
