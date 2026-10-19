import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/models/booru_item.dart';

/// The batch snatcher (Snatcher page: tags + amount): pages through a source
/// until it has the amount asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  int serial = 0;
  BooruItem post({bool hidden = false}) {
    final int id = ++serial;
    return BooruItem(
      fileURL: 'https://img3.gelbooru.com/images/aa/bb/$id.jpg',
      sampleURL: 'https://img3.gelbooru.com/samples/aa/bb/$id.jpg',
      thumbnailURL: 'https://img3.gelbooru.com/thumbnails/aa/bb/$id.jpg',
      tagsList: const [],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=$id',
    )..hiddenInSource = hidden;
  }

  /// A source that adds [pageSize] posts per page; [failFrom] on, a request
  /// fails: the list stays as it was and the source is not locked (as
  /// BooruHandler.search does on a 5xx, a 403 or no network).
  ({Future<List<BooruItem>> Function() nextPage, bool Function() locked, int Function() asked}) source({
    int pageSize = 100,
    int pages = 1000,
    int? failFrom,
    bool hiddenEveryOther = false,
  }) {
    final List<BooruItem> fetched = [];
    bool locked = false;
    int asked = 0;
    return (
      nextPage: () async {
        asked++;
        if (asked > 50) throw StateError('still asking for pages after 50');
        if (failFrom != null && asked >= failFrom) return fetched;
        if (asked > pages) {
          locked = true;
          return fetched;
        }
        for (int i = 0; i < pageSize; i++) {
          fetched.add(post(hidden: hiddenEveryOther && i.isOdd));
        }
        return fetched;
      },
      locked: () => locked,
      asked: () => asked,
    );
  }

  test('1.0: a request that fails ends the batch instead of asking for pages for ever', () async {
    final s = source(failFrom: 1);
    final List<BooruItem> got = await SnatchHandler.pagesForSnatch(50, nextPage: s.nextPage, locked: s.locked);
    expect(got, isEmpty);
    expect(s.asked(), 1);
  });

  test('1.0: a failure on a later page queues what came before', () async {
    final s = source(failFrom: 2);
    final List<BooruItem> got = await SnatchHandler.pagesForSnatch(150, nextPage: s.nextPage, locked: s.locked);
    expect(got, hasLength(100));
    expect(s.asked(), 2);
  });

  test('1.0: 150 asked for is 150 queued, not two whole pages', () async {
    final s = source();
    final List<BooruItem> got = await SnatchHandler.pagesForSnatch(150, nextPage: s.nextPage, locked: s.locked);
    expect(got, hasLength(150));
    expect(s.asked(), 2);
  });

  test('hidden posts do not count, and the end of the source ends the batch', () async {
    final s = source(pages: 3, hiddenEveryOther: true);
    final List<BooruItem> got = await SnatchHandler.pagesForSnatch(1000, nextPage: s.nextPage, locked: s.locked);
    expect(got, hasLength(150), reason: 'three pages, half of each hidden');
    expect(got.any((p) => p.isHidden), isFalse);
  });
}
