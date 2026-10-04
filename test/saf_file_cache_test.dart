import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/saf_file_cache.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';

/// The list of file names in the picked download folder, read once and kept:
/// the Downloads check (DownloadsReconciler) and the "downloaded" badges
/// look names up in it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SettingsHandler.register();
    SAFFileCache.instance.invalidate();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ServiceHandler.platform, null);
    SAFFileCache.instance.invalidate();
    SettingsHandler.instance.extPathOverride = '';
  });

  test('1.0: a listing of the folder used before never fills the cache after the folder changed', () async {
    final Completer<List<String>> oldListing = Completer<List<String>>();
    final Completer<void> oldAsked = Completer<void>();
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (MethodCall call) async {
      switch (call.method) {
        case 'testSAF':
          return 'ok';
        case 'listFileNames':
          final String uri = (call.arguments as Map)['uri'] as String;
          if (uri == 'content://tree/old') {
            if (!oldAsked.isCompleted) oldAsked.complete();
            return oldListing.future;
          }
          return <String>['new.jpg'];
      }
      return null;
    });
    final SAFFileCache cache = SAFFileCache.instance;

    // The start of the app lists a big folder...
    SettingsHandler.instance.extPathOverride = 'content://tree/old';
    final Future<void> startup = cache.populate('content://tree/old');
    await oldAsked.future.timeout(const Duration(seconds: 5));

    // ...and the folder is changed before it is done (DownloadFolders.change).
    SettingsHandler.instance.extPathOverride = 'content://tree/new';
    cache.invalidate();
    final Future<void> afterChange = cache.populate('content://tree/new');

    oldListing.complete(['old.jpg']);
    await Future.wait([startup, afterChange]).timeout(const Duration(seconds: 5));

    expect(
      cache.isPopulated && cache.fileNames.contains('old.jpg'),
      isFalse,
      reason: "the Downloads check would judge the new folder's downloads by the old folder's files",
    );

    // Asked again (the Downloads check does when the cache is empty), the new
    // folder is listed.
    if (!cache.isPopulated) await cache.populate('content://tree/new');
    expect(cache.isPopulated, isTrue);
    expect(cache.fileNames, {'new.jpg'});
  });

  test('a listing that finishes for the folder still in use fills the cache', () async {
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (MethodCall call) async {
      if (call.method == 'testSAF') return 'ok';
      if (call.method == 'listFileNames') return <String>['a.jpg', 'b.mp4'];
      return null;
    });
    SettingsHandler.instance.extPathOverride = 'content://tree/only';
    await SAFFileCache.instance.populate('content://tree/only');
    expect(SAFFileCache.instance.isPopulated, isTrue);
    expect(SAFFileCache.instance.fileNames, {'a.jpg', 'b.mp4'});
    expect(await SAFFileCache.instance.existsFile('content://tree/only', 'a.jpg'), isTrue);
  });
}
