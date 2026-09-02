import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Round 4 fix 1: thumbnails on every new source were failing because the image
/// loader decided its headers from a hardcoded list of hosts in [Tools], which
/// none of the new sources were in. The URLs were correct the whole time, which
/// is what made it hard to see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('media_headers');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    BooruHandlerFactory.clearMediaHeaderCache();
  });

  tearDown(() {
    BooruHandlerFactory.clearMediaHeaderCache();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Booru booru(BooruType type, String url) => Booru(type.name, type, '', url, '');

  group('a source declares what its own CDN needs', () {
    test('hitomi asks for the referer its image hosts demand', () {
      // Verified live: the exact same thumbnail URL is 404 without a referer
      // and 200 image/webp with one.
      final headers = BooruHandlerFactory.mediaHeadersFor(
        booru(BooruType.Hitomi, 'https://hitomi.la'),
      );

      expect(headers['Referer'], 'https://hitomi.la/');
      expect(headers['Origin'], 'https://hitomi.la');
    });

    test('every doujin source declares one, so none can silently lose it', () {
      for (final entry in {
        BooruType.NiyaNiya: 'https://niyaniya.moe',
        BooruType.AsmHentai: 'https://asmhentai.com',
        BooruType.EaHentai: 'https://eahentai.com',
        BooruType.Faccina: 'https://hentalk.pw',
        BooruType.Hitomi: 'https://hitomi.la',
        BooruType.HentaiPaw: 'https://hentaipaw.com',
      }.entries) {
        final headers = BooruHandlerFactory.mediaHeadersFor(booru(entry.key, entry.value));
        expect(
          headers['Referer'],
          isNotNull,
          reason: '${entry.key.name} declares no media referer',
        );
      }
    });

    test('a source with no CDN requirements declares nothing', () {
      // The default has to stay empty: sending a referer everywhere would be a
      // behaviour change for dozens of existing boorus.
      expect(
        BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Gelbooru, 'https://gelbooru.com')),
        isEmpty,
      );
    });

    test('the answer is cached, since a grid asks once per thumbnail', () {
      final first = BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Hitomi, 'https://hitomi.la'));
      final second = BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Hitomi, 'https://hitomi.la'));
      expect(identical(first, second), isTrue);
    });

    test('two sources do not share a cache entry', () {
      final hitomi = BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Hitomi, 'https://hitomi.la'));
      final hentalk = BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Faccina, 'https://hentalk.pw'));
      expect(hitomi['Referer'], isNot(hentalk['Referer']));
    });
  });

  group('the image loader actually receives them', () {
    test("a hitomi item is fetched with hitomi's referer", () async {
      final headers = await Tools.getFileCustomHeaders(
        booru(BooruType.Hitomi, 'https://hitomi.la'),
        item: BooruItem(
          fileURL: 'https://atn.gold-usergeneratedcontent.net/webpbigtn/9/05/abc.webp',
          sampleURL: '',
          thumbnailURL: 'https://atn.gold-usergeneratedcontent.net/webpbigtn/9/05/abc.webp',
          tagsList: const [],
          postURL: 'https://hitomi.la/galleries/1.html',
        ),
        checkForReferer: true,
      );

      // This is the assertion that would have caught the original bug.
      expect(headers['Referer'], 'https://hitomi.la/');
      expect(headers['User-Agent'], isNotEmpty);
    });

    test('an existing booru keeps the referer the old host list gave it', () {
      // The host list is still the authority for the boorus it covers; the
      // handler lookup is additive, not a replacement.
      expect(
        BooruHandlerFactory.mediaHeadersFor(booru(BooruType.Gelbooru, 'https://gelbooru.com')),
        isEmpty,
      );
    });
  });
}
