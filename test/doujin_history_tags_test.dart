import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r33: doujin history remembers a gallery's tags (namespaced), so the doujin
/// For You can build queries from what was read without refetching, and old
/// files without tags still load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_history_tags');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    DoujinDataHandler.instance.resetForTests();
  });

  tearDown(() {
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem gallery({List<Tag>? tags}) => BooruItem(
    fileURL: 'https://nhentai.net/g/1/',
    sampleURL: '',
    thumbnailURL: 'https://t.nhentai.net/1/cover.jpg',
    tagsList: tags ?? const [],
    postURL: 'https://nhentai.net/g/123456/',
    serverId: '123456',
    description: 'Tales of Hu Tao',
  )..fileCountHint.value = 40;

  final List<Tag> tags = [
    Tag('genshin_impact', tagType: TagType.copyright),
    Tag('hu_tao', tagType: TagType.character),
    Tag('wakahi', tagType: TagType.artist),
    Tag('big_breasts'),
    Tag('english', tagType: TagType.meta),
  ];

  test('an entry keeps namespaced tags and its page count, and reads back from JSON — with or without them', () {
    final DoujinEntry entry = DoujinEntry.fromItem(
      gallery(tags: tags),
      nhentai,
      tags: DoujinDataHandler.namespacedTagsOf(gallery(tags: tags), namespaces: const {'english': 'language', 'big_breasts': 'female'}),
    );
    expect(entry.tags, ['parody:genshin_impact', 'character:hu_tao', 'artist:wakahi', 'female:big_breasts', 'language:english']);
    expect(entry.pages, 40);
    final DoujinEntry back = DoujinEntry.fromJson(entry.toJson());
    expect(back.tags, entry.tags);
    expect(back.pages, 40);
    final DoujinEntry old = DoujinEntry.fromJson({'postURL': 'https://nhentai.net/g/1/', 'serverId': '1', 'thumbnailURL': '', 'title': 'x', 'booruHost': 'nhentai.net', 'addedAt': 1});
    expect(old.tags, isEmpty, reason: 'a file from before r33');
    expect(old.pages, isNull);
  });

  test('without a namespace map, the tag types name the namespaces and plain tags stay bare', () {
    expect(
      DoujinDataHandler.namespacedTagsOf(gallery(tags: tags)),
      ['parody:genshin_impact', 'character:hu_tao', 'artist:wakahi', 'big_breasts', 'english'],
    );
  });

  test('history captures tags on open, and learns them later when the listing carried none', () {
    final DoujinDataHandler data = DoujinDataHandler.instance;
    final BooruItem bare = gallery();
    data.addHistory(bare, nhentai);
    expect(data.history.single.tags, isEmpty);
    // The detail page loads the gallery: tags arrive, the entry learns them in place.
    bare.tagsList = tags;
    data.updateHistoryTags(bare, nhentai);
    expect(data.history, hasLength(1));
    expect(data.history.single.tags, contains('parody:genshin_impact'));
    expect(data.history.single.tags, contains('artist:wakahi'));
    // A later open of a tagged item stores them straight away.
    data.addHistory(gallery(tags: tags)..postURL = 'https://nhentai.net/g/7/', nhentai);
    expect(data.history.first.tags, contains('character:hu_tao'));
    // And it survives the file.
    data.save();
    data.reloadFromDisk();
    expect(data.history.first.tags, contains('character:hu_tao'));
    expect(data.history.last.tags, contains('parody:genshin_impact'));
  });

  test('updating tags of a gallery that is not in history adds nothing', () {
    final DoujinDataHandler data = DoujinDataHandler.instance;
    data.updateHistoryTags(gallery(tags: tags), nhentai);
    expect(data.history, isEmpty);
  });

  test('opening a gallery does not rewrite the whole file on the spot: history writes are gathered, then flushed (review)', () async {
    final DoujinDataHandler data = DoujinDataHandler.instance;
    final File file = File('${SettingsHandler.instance.path}doujinData.json');
    data.addHistory(gallery(tags: tags), nhentai);
    expect(file.existsSync(), isFalse, reason: 'nothing written yet');
    data.updateHistoryTags(gallery(tags: tags), nhentai);
    expect(data.pendingSave, isTrue);
    data.flushPendingSave();
    expect(data.pendingSave, isFalse);
    expect(file.readAsStringSync(), contains('character:hu_tao'));
    // Tags that did not change do not even ask for a write.
    data.updateHistoryTags(gallery(tags: tags), nhentai);
    expect(data.pendingSave, isFalse);
    // Left alone, the timer writes.
    data.addHistory(gallery(tags: tags)..postURL = 'https://nhentai.net/g/8/', nhentai);
    await Future<void>.delayed(DoujinDataHandler.historySaveDelay + const Duration(milliseconds: 150));
    expect(file.readAsStringSync(), contains('/g/8/'));
    expect(data.pendingSave, isFalse);
  });
}
