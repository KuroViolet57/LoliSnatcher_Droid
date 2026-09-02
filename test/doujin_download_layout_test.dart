import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_download_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';

/// How a doujin download is laid out on disk and read back as ONE entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_dl');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final Booru asm = Booru('asmhentai', BooruType.AsmHentai, '', 'https://asmhentai.com', '');

  BooruItem page(int n, {String ext = 'jpg'}) => BooruItem(
    fileURL: 'https://images.asmhentai.com/018/678076/$n.$ext',
    sampleURL: '',
    thumbnailURL: 'https://images.asmhentai.com/018/678076/${n}t.jpg',
    tagsList: const [],
    postURL: 'https://asmhentai.com/g/678076/',
  );

  final BooruItem gallery = BooruItem(
    fileURL: 'https://images.asmhentai.com/018/678076/cover.jpg',
    sampleURL: '',
    thumbnailURL: 'https://images.asmhentai.com/018/678076/cover.jpg',
    tagsList: const [],
    postURL: 'https://asmhentai.com/g/678076/',
    serverId: '678076',
    description: 'A Title\nSecond line',
  );

  group('the write side', () {
    test('a book gets a folder named host_id and pages numbered by their place in the book', () {
      final pages = [for (int n = 1; n <= 12; n++) page(n)];
      final info = DoujinDownloadInfo.fromGallery(gallery, asm, pages);
      expect(info.folderName, 'asmhentai.com_678076');
      expect(info.title, 'A Title');
      expect(DoujinDownloadHandler.pageFileName(info, pages[0], 0), '001.jpg');
      expect(DoujinDownloadHandler.pageFileName(info, pages[11], 11), '012.jpg');
      // A SINGLE page saved from the reader is queue index 0 but book page 7.
      expect(DoujinDownloadHandler.pageFileName(info, pages[6], 0), '007.jpg');
    });

    test('the manifest carries what the list shows', () {
      final pages = [page(1), page(2, ext: 'webp')];
      final info = DoujinDownloadInfo.fromGallery(gallery, asm, pages);
      final m = DoujinDownloadHandler.instance.manifestFor(info);
      expect(m['host'], 'asmhentai.com');
      expect(m['serverId'], '678076');
      expect(m['title'], 'A Title');
      expect(m['sourceName'], 'asmhentai');
      expect(m['pageCount'], 2);
      expect(m['pages'], ['001.jpg', '002.webp']);
      expect(m['postURL'], 'https://asmhentai.com/g/678076/');
    });

    test('a book opened in the reader (no gallery item) is described from its pages', () {
      final pages = [page(1), page(2)];
      final info = DoujinDownloadInfo.fromPages(pages, asm, galleryId: '678076', title: 'From reader');
      expect(info.folderName, 'asmhentai.com_678076');
      expect(info.postURL, 'https://asmhentai.com/g/678076/');
      expect(info.coverURL, pages.first.thumbnailURL);
    });

    test('a loose page name no longer collides across books (the old layout did)', () {
      // Before: both were `asmhentai_1.jpg`, so the second book's page 1
      // "already existed". Folders fix this for books; the writer's generic
      // naming now disambiguates too, for anything that still lands loose.
      final writer = ImageWriter();
      final BooruItem other = BooruItem(
        fileURL: 'https://images.asmhentai.com/019/999/1.jpg',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://asmhentai.com/g/999/',
      );
      final String a = writer.getFilename(page(1), asm);
      final String b = writer.getFilename(other, asm);
      expect(a, isNot(b));
      expect(a, startsWith('asmhentai_'));
      expect(a, endsWith('_1.jpg'));
    });
  });

  group('the read side', () {
    test('a folder with a manifest lists as one entry, pages in manifest order', () {
      final entry = DoujinDownloadHandler.entryFromFolder(
        folderName: 'asmhentai.com_678076',
        filesByName: {
          '002.jpg': 'file:///dl/Doujin/asmhentai.com_678076/002.jpg',
          '001.jpg': 'file:///dl/Doujin/asmhentai.com_678076/001.jpg',
          'doujin.json': 'file:///dl/Doujin/asmhentai.com_678076/doujin.json',
        },
        manifest: {
          'host': 'asmhentai.com',
          'serverId': '678076',
          'title': 'A Title',
          'sourceName': 'asmhentai',
          'postURL': 'https://asmhentai.com/g/678076/',
          'pages': ['001.jpg', '002.jpg', '003.jpg'],
          'savedAt': 5,
        },
        location: '/dl/Doujin/asmhentai.com_678076/',
        isSaf: false,
        savedAt: 1,
      )!;
      expect(entry.title, 'A Title');
      expect(entry.pageCount, 2, reason: 'a page listed in the manifest but missing on disk is not shown');
      expect(entry.pages.first, endsWith('001.jpg'));
      expect(entry.cover, endsWith('001.jpg'));
      expect(entry.sourceName, 'asmhentai');
      expect(entry.savedAt, 5);
      final items = entry.toPageItems();
      expect(items.length, 2);
      expect(items.first.fileURL, startsWith('file://'));
      expect(items.first.postURL, 'https://asmhentai.com/g/678076/');
    });

    test('a folder WITHOUT a manifest is listed from its images in natural order', () {
      final entry = DoujinDownloadHandler.entryFromFolder(
        folderName: 'nhentai.net_123',
        filesByName: {
          '10.webp': 'u10',
          '2.webp': 'u2',
          '1.webp': 'u1',
          'notes.txt': 'ut',
        },
        manifest: null,
        location: '/dl/Doujin/nhentai.net_123/',
        isSaf: false,
        savedAt: 9,
      )!;
      expect(entry.pages, ['u1', 'u2', 'u10']);
      expect(entry.host, 'nhentai.net');
      expect(entry.serverId, '123');
      expect(entry.title, 'nhentai.net_123');
      expect(entry.savedAt, 9);
    });

    test('an empty folder is not an entry', () {
      expect(
        DoujinDownloadHandler.entryFromFolder(
          folderName: 'x_1',
          filesByName: {'doujin.json': 'm'},
          manifest: {'pages': <String>[]},
          location: '/x/',
          isSaf: false,
          savedAt: 0,
        ),
        isNull,
      );
    });

    test('loose pages from before folders group per source, numerically', () {
      final groups = DoujinDownloadHandler.looseGroups(
        {
          'asmhentai_10.jpg': 'a10',
          'asmhentai_2.jpg': 'a2',
          'asmhentai_1.jpg': 'a1',
          'nhentai_1.webp': 'n1',
          'gelbooru_abc123def456.png': 'g', // a booru download: not a doujin page
          'asmhentai_cover.jpg': 'c', // no number: not a page
        },
        location: '/dl/',
        isSaf: false,
      );
      expect(groups.map((g) => g.sourceName), unorderedEquals(['asmhentai', 'nhentai']));
      final asmGroup = groups.firstWhere((g) => g.sourceName == 'asmhentai');
      expect(asmGroup.pages, ['a1', 'a2', 'a10']);
      expect(asmGroup.isLoose, isTrue);
      expect(asmGroup.title, contains('loose'));
    });

    test('natural order', () {
      expect(['10.jpg', '9.jpg', '100.jpg', '1.jpg']..sort(DoujinDownloadHandler.naturalCompare), ['1.jpg', '9.jpg', '10.jpg', '100.jpg']);
    });
  });
}
