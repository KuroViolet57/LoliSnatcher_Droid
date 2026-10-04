import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/saf_file_cache.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/download_folders.dart';
import 'package:lolisnatcher/features/downloads/logic/downloads_reconciler.dart';
import 'package:lolisnatcher/features/downloads/logic/image_writer.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';

/// The Downloads check (Downloads drawer -> check against the folder) with a
/// folder picked in Settings -> Save & cache: Android's folder access lists
/// its file names, and a listing that failed comes back as no names at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const String picked = 'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FLoli';
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  late Directory tempDir;
  late List<String> log;

  BooruItem post(String id) => BooruItem(
    fileURL: 'https://img3.gelbooru.com/images/aa/bb/$id.jpg',
    sampleURL: '',
    thumbnailURL: 'https://img3.gelbooru.com/thumbnails/aa/bb/thumbnail_$id.jpg',
    tagsList: const [],
    postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$id',
    md5String: id,
  );

  /// The folder answers every listing with [names] (an empty list is also
  /// what a failed listing looks like).
  void folderLists(List<String> names) {
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (MethodCall call) async {
      switch (call.method) {
        case 'testSAF':
          return 'ok';
        case 'hasSafAccess': // 1.0: the cache warm-up asks for the grant only
          return true;
        case 'listFileNames':
          return names;
      }
      return null;
    });
  }

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('saf_listing');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..extPathOverride = picked
      ..booruList.clear()
      ..booruList.add(gelbooru);
    SettingsHandler.instance.earlierDownloadFolders.clear();
    log = [];
    DownloadsReconciler.instance
      ..resetForTests()
      ..isAndroid = (() => true)
      ..logLine = log.add
      ..storageProblem = null;
    DownloadFolders.forgetListings();
    SAFFileCache.instance.invalidate();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ServiceHandler.platform, null);
    DownloadsReconciler.instance
      ..resetForTests()
      ..storageProblem = null;
    DownloadFolders.resetForTests();
    SAFFileCache.instance.invalidate();
    SettingsHandler.instance
      ..extPathOverride = ''
      ..booruList.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('1.0: a listing that failed is not an empty folder: nothing is called missing, so Forget is not offered', () async {
    folderLists(const []);
    // Asked directly, the folder does not answer.
    DownloadFolders.probe = (String folder) async =>
        const FolderProbe(files: 0, dirs: 0, access: true, error: 'IllegalStateException: provider died');

    final r = await DownloadsReconciler.instance.check([post('1'), post('2')]);

    expect(r.missing, isEmpty);
    expect(DownloadsReconciler.instance.storageProblem, isNotNull);
    expect(SAFFileCache.instance.isPopulated, isFalse, reason: 'listed again next time, not trusted as empty');
  });

  test('1.0: files the folder holds while its listing came back empty: nothing is called missing', () async {
    folderLists(const []);
    DownloadFolders.probe = (String folder) async => const FolderProbe(files: 2, dirs: 0, access: true, sampleFiles: ['a.jpg', 'b.jpg']);

    final r = await DownloadsReconciler.instance.check([post('1')]);

    expect(r.missing, isEmpty);
    expect(DownloadsReconciler.instance.storageProblem, isNotNull);
  });

  test('a folder that really is empty still shows its downloads as missing', () async {
    folderLists(const []);
    DownloadFolders.probe = (String folder) async => const FolderProbe(files: 0, dirs: 0, access: true);

    final r = await DownloadsReconciler.instance.check([post('1'), post('2')]);

    expect(r.missing, hasLength(2));
    expect(DownloadsReconciler.instance.storageProblem, isNull);
  });

  test('a listing with names is used as it is', () async {
    DownloadFolders.probe = (String folder) async => const FolderProbe(files: 1, dirs: 0, access: true);
    final BooruItem here = post('1');
    final BooruItem gone = post('2');
    // The writer's own name for the post that is in the folder.
    final String name = ImageWriter().getFilename(here, gelbooru);
    folderLists([name]);

    final r = await DownloadsReconciler.instance.check([here, gone]);

    expect(r.missing, [gone]);
    expect(DownloadsReconciler.instance.storageProblem, isNull);
  });
}
