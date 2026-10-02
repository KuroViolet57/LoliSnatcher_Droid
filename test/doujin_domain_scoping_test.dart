import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';

/// Round 4, item 3: source switching stays inside one domain. Previewing a
/// tag from a doujin source must offer only doujin sources, and from a booru
/// only boorus — the same rule the tag hub's strips and the find-elsewhere
/// candidates follow.
void main() {
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  test('a doujin origin only ever matches doujin sources', () {
    expect(DoujinDataHandler.sameDomain(nhentai, nhentai), isTrue);
    expect(DoujinDataHandler.sameDomain(gelbooru, nhentai), isFalse);
    expect(DoujinDataHandler.sameDomain(e621, nhentai), isFalse);
  });

  test('a booru origin only ever matches boorus', () {
    expect(DoujinDataHandler.sameDomain(gelbooru, e621), isTrue);
    expect(DoujinDataHandler.sameDomain(nhentai, gelbooru), isFalse);
  });

  test('filtering a mixed source list keeps only the origin domain', () {
    final List<Booru> all = [gelbooru, nhentai, e621];

    final doujinSide = all.where((b) => DoujinDataHandler.sameDomain(b, nhentai)).toList();
    expect(doujinSide, [nhentai]);

    final booruSide = all.where((b) => DoujinDataHandler.sameDomain(b, gelbooru)).toList();
    expect(booruSide, [gelbooru, e621]);
  });

  test('the relation is symmetric and reflexive', () {
    for (final a in [nhentai, gelbooru, e621]) {
      expect(DoujinDataHandler.sameDomain(a, a), isTrue);
      for (final b in [nhentai, gelbooru, e621]) {
        expect(DoujinDataHandler.sameDomain(a, b), DoujinDataHandler.sameDomain(b, a));
      }
    }
  });
}
