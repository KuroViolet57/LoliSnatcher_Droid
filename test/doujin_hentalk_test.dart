import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: hentalk.pw, which runs faccina — an open-source gallery server
/// with a real REST API, so nothing here parses page markup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru hentalk() => Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('faccina_test');
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

  group('query translation into faccina syntax', () {
    test('a namespaced tag becomes a quoted namespaced term', () {
      // The app writes underscores; faccina reads them literally, so they go
      // back to spaces and the value is quoted.
      expect(FaccinaHandler.translateQuery('artist:asami_asami'), 'artist:"asami asami"');
    });

    test('a single-word value needs no quoting', () {
      expect(FaccinaHandler.translateQuery('artist:wakahi'), 'artist:wakahi');
      expect(FaccinaHandler.translateQuery('glasses'), 'glasses');
    });

    test('a bare multi-word tag is quoted too', () {
      expect(FaccinaHandler.translateQuery('big_breasts'), '"big breasts"');
    });

    test('exclusions and OR markers survive translation', () {
      expect(FaccinaHandler.translateQuery('-artist:asami_asami'), '-artist:"asami asami"');
      expect(FaccinaHandler.translateQuery('-glasses'), '-glasses');
      expect(FaccinaHandler.translateQuery('~big_breasts'), '~"big breasts"');
    });

    test('several terms are translated independently', () {
      expect(
        FaccinaHandler.translateQuery('glasses artist:asami_asami -netorare'),
        'glasses artist:"asami asami" -netorare',
      );
    });

    test('an already-quoted term is left alone', () {
      expect(FaccinaHandler.translateQuery('artist:"asami asami"'), 'artist:"asami asami"');
    });

    test('empty input stays empty', () {
      expect(FaccinaHandler.translateQuery('   '), '');
    });
  });

  group('URLs', () {
    test('browse uses the API, not the page', () {
      final h = FaccinaHandler(hentalk(), 20)..pageNum = 4;
      expect(h.makeURL(''), 'https://hentalk.pw/api/library?page=4');
    });

    test('search uses q= — the parameter that actually filters', () {
      final h = FaccinaHandler(hentalk(), 20)..pageNum = 1;
      // `search=` is accepted by this API and silently ignored, returning the
      // whole library, so the parameter name is pinned here.
      final String url = h.makeURL('artist:asami_asami');
      expect(url, startsWith('https://hentalk.pw/api/library?q='));
      expect(url, contains('page=1'));
      expect(Uri.parse(url).queryParameters['q'], 'artist:"asami asami"');
    });

    test('an id: query hits the single-gallery endpoint', () {
      final h = FaccinaHandler(hentalk(), 20);
      expect(h.makeURL('id:18792'), 'https://hentalk.pw/api/g/18792');
      expect(h.makePostURL('18792'), 'https://hentalk.pw/g/18792');
    });

    test('the host comes from the config, since faccina is self-hosted', () {
      final other = Booru('mine', BooruType.Faccina, '', 'https://gallery.example.org/', '');
      final h = FaccinaHandler(other, 20)..pageNum = 1;
      expect(h.makeURL(''), 'https://gallery.example.org/api/library?page=1');
    });
  });

  group('archive parsing', () {
    final Map<String, dynamic> archive = {
      'id': 18792,
      'hash': '6b85eee17ccee0ec',
      'title': 'A Work',
      'pages': 22,
      // NB: this is a PAGE NUMBER used as the cover, not a URL.
      'thumbnail': 3,
      'tags': [
        {'id': 1, 'namespace': 'artist', 'name': 'Wakahi-Chan'},
        {'id': 2, 'namespace': 'magazine', 'name': 'Comic Something 2026-08'},
        {'id': 3, 'namespace': '', 'name': 'big breasts'},
      ],
    };

    test('tag names are bare, with the namespace kept beside them', () {
      final h = FaccinaHandler(hentalk(), 20);
      final tags = h.tagsFromArchive(archive).map((t) => t.fullString).toList();

      // The screenshots showed `artist:wakahi-chan` on a chip; the name is the
      // bare part and the namespace lives on the handler.
      expect(tags, contains('wakahi-chan'));
      expect(h.tagNamespace('wakahi-chan'), 'artist');
      expect(tags, contains('comic_something_2026-08'));
      expect(h.tagNamespace('comic_something_2026-08'), 'magazine');
      // An empty namespace means a plain tag, with no namespace at all.
      expect(tags, contains('big_breasts'));
      expect(h.tagNamespace('big_breasts'), isNull);
      expect(tags.any((t) => t.contains(':')), isFalse);
    });

    test('a bare tag is put back into its namespaced form for searching', () {
      // faccina matches on `artist:"wakahi chan"`, so a chip that displays bare
      // still has to round-trip to the qualified form.
      final h = FaccinaHandler(hentalk(), 20);
      h.tagsFromArchive(archive);
      expect(h.qualifyTag('wakahi-chan'), 'artist:wakahi-chan');
      expect(h.qualifyTag('big_breasts'), 'big_breasts');
    });

    test('the cover is built from the thumbnail PAGE, not treated as a URL', () {
      final h = FaccinaHandler(hentalk(), 20);
      final item = h.itemFromArchive(archive)!;
      expect(item.thumbnailURL, 'https://hentalk.pw/image/6b85eee17ccee0ec/3');
      expect(item.serverId, '18792');
      expect(item.postURL, 'https://hentalk.pw/g/18792');
      expect(item.description, 'A Work');
    });

    test('an archive missing its hash is skipped rather than half-built', () {
      final h = FaccinaHandler(hentalk(), 20);
      expect(h.itemFromArchive({'id': 1, 'title': 'x'}), isNull);
      expect(h.itemFromArchive('not a map'), isNull);
    });
  });

  group('wiring', () {
    test('the factory builds the handler and it reads', () {
      final result = BooruHandlerFactory().getBooruHandler([hentalk()], 20);
      expect(result.booruHandler, isA<FaccinaHandler>());
      expect(result.booruHandler.hasReader, isTrue);
    });

    test('login is offered and gated on credentials', () async {
      final h = FaccinaHandler(hentalk(), 20);
      expect(h.hasSignInSupport, isTrue);
      expect(await h.canSignIn(), isFalse);
    });

    test('it is a doujin source, with item attribution by host', () {
      expect(DoujinDataHandler.isDoujinBooru(hentalk()), isTrue);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://hentalk.pw/g/18792',
        serverId: '18792',
      );
      expect(DoujinDataHandler.isDoujinItem(item), isTrue);
    });

    test('Related is offered', () {
      final h = FaccinaHandler(hentalk(), 20);
      final item = BooruItem(
        fileURL: '',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://hentalk.pw/g/18792',
        serverId: '18792',
      );
      expect(h.relatedVersionsQuery(item), 'related:18792');
    });
  });
}
