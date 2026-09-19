import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/downloads_reconciler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';

/// The media Downloads list: rows resolve back to the file the writer made,
/// generic file names no longer collide, and doujin rows stay out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('dl_reconcile');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final Booru r34h = Booru('rule34hentai', BooruType.R34Hentai, '', 'https://rule34hentai.net', '');
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  BooruItem video(String hash) => BooruItem(
    fileURL: 'https://rule34hentai.net/_images/$hash/thumb.webm',
    sampleURL: '',
    thumbnailURL: 'https://rule34hentai.net/_thumbs/$hash/thumb.jpg',
    tagsList: const [],
    postURL: 'https://rule34hentai.net/post/view/1',
    md5String: hash,
  );

  group('file names', () {
    test('two rule34hentai videos no longer share one file name', () {
      // From the device log: every video's URL ends in thumb.webm; the second
      // "already existed" and was never written.
      final writer = ImageWriter();
      final a = writer.getFilename(video('a90d0d9c80838e5feb12fa0af9aec5fa'), r34h);
      final b = writer.getFilename(video('0123456789abcdef0123456789abcdef'), r34h);
      expect(a, isNot(b));
      expect(a, startsWith('rule34hentai_a90d0d9c80838e5feb12fa0af9aec5fa_'));
      expect(a, endsWith('thumb.webm'));
    });

    test('an identifying name is kept exactly, so existing downloads still match', () {
      expect(
        ImageWriter.snatchTail('1d01c636af3b9656.jpg', urlWithoutQuery: 'https://x/images/1d01c636af3b9656.jpg', md5: 'zzz'),
        '1d01c636af3b9656.jpg',
      );
      expect(ImageWriter.snatchTail('123456789.png', urlWithoutQuery: 'https://x/123456789.png'), '123456789.png');
    });

    test('a generic name without an md5 takes the directory hash', () {
      final String t = ImageWriter.snatchTail('list-sm.jpg', urlWithoutQuery: 'https://tik.porn/video/1753/1753144/list-sm.jpg');
      expect(t, endsWith('_list-sm.jpg'));
      expect(t.length, greaterThan('list-sm.jpg'.length));
    });
  });

  group('resolving a row to its booru', () {
    test('by post host, then by file host', () {
      final List<Booru> boorus = [gelbooru, r34h, nhentai];
      expect(DownloadsReconciler.booruFor(video('h'), boorus), r34h);
      final BooruItem cdnOnly = BooruItem(
        fileURL: 'https://gelbooru.com/images/x/y.jpg',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://other.example/post/1',
      );
      expect(DownloadsReconciler.booruFor(cdnOnly, boorus), gelbooru);
    });

    test('a doujin row is never resolved to a media booru', () {
      final BooruItem d = BooruItem(
        fileURL: 'https://i.nhentai.net/galleries/1/1.webp',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: const [],
        postURL: 'https://nhentai.net/g/1/',
      );
      expect(DownloadsReconciler.booruFor(d, [gelbooru, nhentai]), isNull);
    });
  });

  group('the media list excludes doujin galleries', () {
    test('by post URL host, for every known doujin host', () {
      final conditions = DownloadsHandler.doujinExclusionConditions();
      expect(conditions, contains("bi.postURL NOT LIKE '%://nhentai.net/%'"));
      expect(conditions, contains("bi.postURL NOT LIKE '%://asmhentai.com/%'"));
      expect(conditions, contains("bi.postURL NOT LIKE '%://shupogaki.moe/%'"));
      expect(conditions.any((c) => c.contains('gelbooru')), isFalse);
    });
  });
}
