import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/features/doujin/logic/doujin_download_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_queue_journal.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/tag.dart';

void main() {
  test('a queued snatch comes back without the booru key', () async {
    final Directory dir = Directory.systemTemp.createTempSync('snatch-journal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final SnatchQueueJournal journal = SnatchQueueJournal(File('${dir.path}/snatch-queue.json'));

    final Booru saved = Booru.withKey(
      'Gel',
      BooruType.Gelbooru,
      '',
      'https://gelbooru.com',
      '',
      'secret-key',
      'user-1',
    );
    final BooruItem item = BooruItem(
      fileURL: 'https://example.com/a.jpg',
      sampleURL: 'https://example.com/s.jpg',
      thumbnailURL: 'https://example.com/t.jpg',
      tagsList: [Tag('cat')],
      postURL: 'https://example.com/post/1',
      md5String: 'abc123',
      downloadFileName: 'named.jpg',
      serverId: '42',
    );
    journal.save([
      SnatchItem(
        [item],
        250,
        saved,
        true,
        doujin: DoujinDownloadInfo(
          host: 'e-hentai.org',
          serverId: '99',
          postURL: 'https://e-hentai.org/g/99',
          title: 'Book',
          coverURL: 'https://example.com/t.jpg',
          sourceName: 'Gel',
          pages: [item],
          missingPages: const [2],
        ),
      ),
    ]);
    await journal.flushed;

    final String raw = File('${dir.path}/snatch-queue.json').readAsStringSync();
    expect(raw.contains('secret-key'), isFalse);
    expect(raw.contains('user-1'), isFalse);
    expect(raw.contains('abc123'), isTrue);

    final Booru live = Booru.withKey(
      'Gel',
      BooruType.Gelbooru,
      '',
      'https://gelbooru.com',
      '',
      'secret-key',
      'user-1',
    );
    final List<SnatchItem> loaded = await journal.load(
      lookup: (String name, String baseUrl) => name == 'Gel' && baseUrl == 'https://gelbooru.com' ? live : null,
    );
    expect(loaded, hasLength(1));
    expect(identical(loaded.single.booru, live), isTrue);
    expect(loaded.single.cooldown, 250);
    expect(loaded.single.ignoreExists, isTrue);
    expect(loaded.single.booruItems.single.fileURL, 'https://example.com/a.jpg');
    expect(loaded.single.booruItems.single.md5String, 'abc123');
    expect(loaded.single.booruItems.single.downloadFileName, 'named.jpg');
    expect(loaded.single.booruItems.single.serverId, '42');
    expect(loaded.single.booruItems.single.tagsList.single.fullString, 'cat');
    expect(loaded.single.doujin?.serverId, '99');
    expect(loaded.single.doujin?.missingPages, [2]);
    expect(loaded.single.doujin?.pages.single.fileURL, 'https://example.com/a.jpg');
  });

  test('a broken file is an empty queue, and a leftover temp file still loads', () async {
    final Directory dir = Directory.systemTemp.createTempSync('snatch-journal-bad');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}/snatch-queue.json');
    final SnatchQueueJournal journal = SnatchQueueJournal(file);

    file.writeAsStringSync('{not json');
    expect(await journal.load(), isEmpty);

    final Booru booru = Booru('Gel', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    final BooruItem item = BooruItem(
      fileURL: 'https://example.com/b.jpg',
      sampleURL: 'https://example.com/b.jpg',
      thumbnailURL: 'https://example.com/b.jpg',
      tagsList: [Tag('dog')],
      postURL: 'https://example.com/post/2',
    );
    journal.save([SnatchItem([item], 100, booru, false)]);
    await journal.flushed;
    final String good = file.readAsStringSync();
    file.deleteSync();
    File('${file.path}.tmp').writeAsStringSync(good);
    final List<SnatchItem> loaded = await journal.load();
    expect(loaded.single.booruItems.single.fileURL, 'https://example.com/b.jpg');
  });

  test('the handler journals the queue and startup reads it back', () {
    final String snatch = File('lib/features/downloads/logic/snatch_handler.dart').readAsStringSync();
    expect(snatch.contains('restoreJournal'), isTrue);
    expect(snatch.contains('_rememberQueue'), isTrue);
    final String main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('restoreJournal'), isTrue);
  });
}
