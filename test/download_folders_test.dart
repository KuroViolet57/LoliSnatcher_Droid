import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_download_handler.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/download_folders.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';

/// r82: a download folder you move away from is remembered, and the
/// Downloads list, the "downloaded" badge and the doujin downloads look for
/// their files there too. New downloads still go only to the current folder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<String> refreshed;
  int saves = 0;

  String dir(String name) {
    final Directory d = Directory('${tempDir.path}${Platform.pathSeparator}$name${Platform.pathSeparator}')..createSync(recursive: true);
    return d.path;
  }

  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  BooruItem post(String id) => BooruItem(
    fileURL: 'https://img3.gelbooru.com/images/aa/bb/$id.jpg',
    sampleURL: '',
    thumbnailURL: 'https://img3.gelbooru.com/thumbnails/aa/bb/thumbnail_$id.jpg',
    tagsList: const [],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$id',
    md5String: id,
  );

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('download_folders');
    SettingsHandler.instance
      ..path = dir('config')
      ..extPathOverride = ''
      ..booruList.clear()
      ..booruList.add(gelbooru);
    SettingsHandler.instance.earlierDownloadFolders.clear();
    refreshed = [];
    saves = 0;
    DownloadFolders.defaultFolder = () async => dir('Pictures');
    DownloadFolders.onChanged = refreshed.add;
    DownloadFolders.save = () async => saves++;
    DownloadFolders.forgetListings();
  });

  tearDown(() {
    DownloadFolders.resetForTests();
    DownloadFolders.forgetListings();
    SettingsHandler.instance
      ..extPathOverride = ''
      ..booruList.clear();
    SettingsHandler.instance.earlierDownloadFolders.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the folders', () {
    test('changing the download folder remembers the one you leave; going back to it takes it off the list', () async {
      final String a = dir('a');
      final String b = dir('b');
      await DownloadFolders.change(a);
      expect(SettingsHandler.instance.extPathOverride, a);
      expect(DownloadFolders.earlier, [dir('Pictures')], reason: 'the default folder was the one in use');
      await DownloadFolders.change(b);
      expect(DownloadFolders.earlier, [a, dir('Pictures')], reason: 'newest first');
      await DownloadFolders.change(a);
      expect(DownloadFolders.earlier, [b, dir('Pictures')], reason: 'a is current again; b is the one left');
      await DownloadFolders.change(a);
      expect(DownloadFolders.earlier, [b, dir('Pictures')], reason: 'the same folder is no change');
      expect(saves, 3);
    });

    test("the new folder's file list is refreshed at once, not after a restart", () async {
      await DownloadFolders.change(dir('a'));
      expect(refreshed, [dir('a')]);
      await DownloadFolders.change('');
      expect(refreshed, [dir('a'), ''], reason: 'back to the default folder');
    });

    test('a folder is added and removed by hand; the current one and a repeat are refused', () async {
      SettingsHandler.instance.extPathOverride = dir('now');
      expect(await DownloadFolders.addEarlier(dir('old')), isTrue);
      expect(await DownloadFolders.addEarlier(dir('old')), isFalse, reason: 'already there');
      expect(await DownloadFolders.addEarlier(dir('now')), isFalse, reason: 'the current folder');
      expect(await DownloadFolders.addEarlier(''), isFalse);
      expect(DownloadFolders.earlier, [dir('old')]);
      await DownloadFolders.removeEarlier(dir('old'));
      expect(DownloadFolders.earlier, isEmpty);
      expect(saves, 2);
    });

    test('the earlier folders survive a restart and stay on this phone', () async {
      SettingsHandler.instance.earlierDownloadFolders.addAll(['content://tree/old', dir('Pictures')]);
      final String saved = jsonEncode(SettingsHandler.instance.toJson());
      SettingsHandler.instance.earlierDownloadFolders.clear();
      await SettingsHandler.instance.loadFromJSON(saved, false);
      expect(SettingsHandler.instance.earlierDownloadFolders, ['content://tree/old', dir('Pictures')]);
      expect(SettingsHandler.instance.deviceSpecificSettings, contains('earlierDownloadFolders'));
      await SettingsHandler.instance.loadFromJSON(jsonEncode({'earlierDownloadFolders': ['x', 3, '', 'x']}), false);
      expect(SettingsHandler.instance.earlierDownloadFolders, ['x'], reason: 'only names, once each');
    });

    test('a folder is named plainly: the storage path of a picked folder, the path of a plain one', () {
      expect(DownloadFolders.describe('content://com.android.externalstorage.documents/tree/primary%3ADownload%2FLoli'), 'Download/Loli');
      expect(DownloadFolders.describe('content://com.android.externalstorage.documents/tree/1234-ABCD%3APictures'), '1234-ABCD: Pictures');
      expect(DownloadFolders.describe('/storage/emulated/0/Pictures/LoliSnatcher/'), '/storage/emulated/0/Pictures/LoliSnatcher/');
    });
  });

  group('looking in them', () {
    test('the Downloads list finds a file left in an earlier folder; one in no folder is missing', () async {
      final String now = dir('now');
      final String old = dir('old');
      SettingsHandler.instance.extPathOverride = now;
      SettingsHandler.instance.earlierDownloadFolders.add(old);
      final BooruItem moved = post('1');
      final BooruItem here = post('2');
      final BooruItem gone = post('3');
      final ImageWriter writer = ImageWriter();
      File('$old${writer.getFilename(moved, gelbooru)}').writeAsStringSync('x');
      File('$now${writer.getFilename(here, gelbooru)}').writeAsStringSync('x');

      final r = await DownloadsReconciler.instance.check([moved, here, gone]);
      expect(r.present.map((i) => i.postURL), [moved.postURL, here.postURL]);
      expect(r.missing.map((i) => i.postURL), [gone.postURL]);
      expect(await DownloadFolders.earlierFolderWith(writer.getFilename(moved, gelbooru)), old);
    });

    test('an earlier folder that cannot be read is skipped, not an error', () async {
      SettingsHandler.instance.extPathOverride = dir('now');
      SettingsHandler.instance.earlierDownloadFolders.add('${tempDir.path}${Platform.pathSeparator}gone${Platform.pathSeparator}');
      final r = await DownloadsReconciler.instance.check([post('4')]);
      expect(r.missing, hasLength(1));
    });

    test('the doujin downloads list includes books saved in an earlier folder', () async {
      final String now = dir('now');
      final String old = dir('old');
      SettingsHandler.instance.extPathOverride = now;
      SettingsHandler.instance.earlierDownloadFolders.add(old);
      final Directory book = Directory('$old${DoujinDownloadHandler.folderName}${Platform.pathSeparator}nhentai.net_123')..createSync(recursive: true);
      File('${book.path}${Platform.pathSeparator}001.jpg').writeAsBytesSync([1]);
      File('${book.path}${Platform.pathSeparator}${DoujinDownloadHandler.manifestName}').writeAsStringSync(
        jsonEncode({'host': 'nhentai.net', 'serverId': '123', 'title': 'Old book', 'pages': ['001.jpg']}),
      );
      final entries = await DoujinDownloadHandler.instance.scan();
      expect(entries.map((e) => e.title), contains('Old book'));
    });

    test('an empty Downloads tab says why instead of "No results"', () {
      expect(DownloadsHandler.missingNote(250, earlier: 0), contains('None of your 250 most recent downloads'));
      expect(DownloadsHandler.missingNote(250, earlier: 0), contains('Settings → Save & cache → Earlier download folders'));
      expect(DownloadsHandler.missingNote(3, earlier: 2), contains('or the 2 earlier folders'));
      expect(DownloadsHandler.missingNote(3, earlier: 1), contains('or the earlier folder'));
    });
  });
}
