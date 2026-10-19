import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';

/// 1.0: startup fills the tag map (128k rows on the user's phone) without an
/// await per row. The bulk fill must leave exactly the map the old per-row
/// `putTag(tag, useDB: false)` loop left.
void main() {
  List<Tag> rows() => [
    Tag('Artist_Name', tagType: TagType.artist, updatedAt: 5),
    Tag('  spaced  ', tagType: TagType.character, updatedAt: 6),
    Tag('', tagType: TagType.meta, updatedAt: 8),
    Tag('   ', tagType: TagType.meta, updatedAt: 9),
    Tag('dupe', tagType: TagType.none, updatedAt: 1),
    Tag('DUPE', tagType: TagType.copyright, updatedAt: 2),
    Tag('plain', updatedAt: 7),
  ];

  Map<String, (TagType, int)> snapshot(TagHandler h) => {
    for (final MapEntry<String, Tag> e in h.tagMap.entries) e.key: (e.value.tagType, e.value.updatedAt),
  };

  test('the bulk fill equals the old per-row loop', () async {
    final TagHandler oldWay = TagHandler();
    for (final Tag t in rows()) {
      await oldWay.putTag(t, useDB: false, dbEnabled: true);
    }

    final TagHandler newWay = TagHandler()..putTagsInMemory(rows());

    expect(snapshot(newWay), snapshot(oldWay));
    expect(newWay.tagMap.keys, containsAll(['artist_name', 'spaced', 'dupe', 'plain']));
    expect(newWay.tagMap.containsKey(''), isFalse);
    // the later row wins, as before
    expect(newWay.getTag('dupe').tagType, TagType.copyright);
  });

  test('names are trimmed and lower-cased on the tag objects themselves, as before', () {
    final List<Tag> list = rows();
    TagHandler().putTagsInMemory(list);
    expect(list[0].fullString, 'artist_name');
    expect(list[1].fullString, 'spaced');
  });
}
