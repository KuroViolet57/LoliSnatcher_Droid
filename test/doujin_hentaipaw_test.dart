import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/origin_page_client.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// hentaipaw.com, parsed against the pages the source-capture tool recorded on
/// the phone (2026-09-02): the home listing, a gallery, its viewer, a search
/// and a tag page. The site is server-rendered; there is no JSON API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru paw() => Booru('hentaipaw', BooruType.HentaiPaw, '', 'https://hentaipaw.com', '');
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('paw_test');
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
    test('browse, search, id', () {
      final h = HentaiPawHandler(paw(), 20)..pageNum = 3;
      expect(h.makeURL(''), 'https://hentaipaw.com/?page=3');
      expect(h.makeURL('milf'), 'https://hentaipaw.com/articles/search?keyword=milf&page=3');
      expect(h.makeURL('id:4133420'), 'https://hentaipaw.com/articles/4133420');
    });

    test('a namespaced chip searches by its bare name', () {
      expect(HentaiPawHandler.keywordFor('artist:neromashin'), 'neromashin');
      expect(HentaiPawHandler.keywordFor('tag:big_areolae'), 'big areolae');
      expect(HentaiPawHandler.keywordFor('plain words'), 'plain words');
    });
  });

  group('the listing, from captured markup', () {
    test('reads every card: id, cover, clean title, language flag', () {
      final items = HentaiPawHandler(paw(), 20).itemsFromListingForTests(fixture('hentaipaw_home.html'));
      expect(items.length, greaterThan(10));
      final first = items.first;
      expect(first.serverId, '3410192');
      expect(first.postURL, 'https://hentaipaw.com/articles/3410192');
      expect(first.thumbnailURL, 'https://cdn.imagedeliveries.com/3410192/thumbnails/cover.webp');
      expect(first.description, 'My Landlady Noona (decensored)');
      expect(first.tagsList.map((t) => t.fullString), contains('english'));
      final korean = items.firstWhere((i) => i.serverId == '4133420');
      expect(korean.tagsList.map((t) => t.fullString), contains('korean'));
    });

    test('search and tag pages use the same cards', () {
      final h = HentaiPawHandler(paw(), 20);
      expect(h.itemsFromListingForTests(fixture('hentaipaw_search.html')).length, greaterThan(5));
      expect(h.itemsFromListingForTests(fixture('hentaipaw_tag.html')).length, greaterThan(5));
    });

    test('no card is counted twice', () {
      final items = HentaiPawHandler(paw(), 20).itemsFromListingForTests(fixture('hentaipaw_home.html'));
      expect(items.map((i) => i.serverId).toSet().length, items.length);
    });
  });

  group('a gallery page', () {
    test('title, namespaced tags, page count', () {
      final h = HentaiPawHandler(paw(), 20);
      final item = h.itemFromArticleForTests('4133420', fixture('hentaipaw_article.html'))!;
      expect(item.description, startsWith('Omae no Kaa-chan'));
      final names = item.tagsList.map((t) => t.fullString).toList();
      expect(names, contains('neromashin'));
      expect(h.tagNamespace('neromashin'), 'artist');
      expect(names, contains('aodouhu'));
      expect(h.tagNamespace('aodouhu'), 'group');
      expect(names, contains('ahegao'));
      expect(names, contains('doujinshi'));
      expect(h.tagNamespace('doujinshi'), 'category');
      expect(names, isNot(contains('n/a')));
      expect(item.fileCountHint.value, 219);
    });

    test('the page count is the number of distinct viewer links', () {
      expect(HentaiPawHandler.pageCountFrom('4133420', parse(fixture('hentaipaw_article.html'))), 219);
    });
  });

  group('the viewer', () {
    test('one document lists every page, in order, each under its own hash', () {
      final urls = HentaiPawHandler.pageUrlsForTests('4133420', fixture('hentaipaw_viewer.html'));
      expect(urls.length, greaterThan(200));
      expect(urls.first, matches(RegExp(r'^https://cdn\.imagedeliveries\.com/4133420/[a-f0-9]+/1\.webp$')));
      expect(urls[1], endsWith('/2.webp'));
      expect(urls.last, endsWith('/${urls.length}.webp'));
      expect(urls.toSet().length, urls.length);
    });

    test('a page from another gallery is never picked up', () {
      expect(HentaiPawHandler.pageUrlsForTests('999', fixture('hentaipaw_viewer.html')), isEmpty);
    });
  });

  group('capabilities', () {
    test('no account, one page size, media referer declared', () {
      final h = HentaiPawHandler(paw(), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.readerImageQualities, isEmpty);
      expect(h.getMediaHeaders()['Referer'], 'https://hentaipaw.com/');
      expect(DoujinDataHandler.isDoujinBooru(paw()), isTrue);
    });
  });

  group('pages are fetched from the WebView on the site origin', () {
    test('the in-page fetch is same-origin and never leaves the site', () async {
      expect(OriginPageClient.fetchScript, contains("credentials: 'same-origin'"));
      final client = OriginPageClient('https://hentaipaw.com');
      expect(await client.fetch('https://evil.example/x'), isNull);
      // No WebView in a unit test: null, so the handler falls back to HTTP.
      expect(await client.fetch('https://hentaipaw.com/?page=1'), isNull);
    });
  });
}
