import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/widgets/booru/booru_switcher_sheet.dart';

/// The right-sidebar source switcher offers only the current tab's world.
void main() {
  final Booru nhentai = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final Booru niyaniya = Booru('niyaniya', BooruType.NiyaNiya, '', 'https://niyaniya.moe', '');
  final Booru hitomi = Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', '');
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  final Booru downloads = Booru('Downloads', BooruType.Downloads, '', '', '');
  final Booru favourites = Booru('Favourites', BooruType.Favourites, '', '', '');
  final List<Booru> all = [gelbooru, nhentai, e621, niyaniya, downloads, hitomi, favourites];

  test('on a doujin tab only doujin sources are listed', () {
    expect(switchableBoorus(all, nhentai), [nhentai, niyaniya, hitomi]);
  });

  test('on a booru tab the boorus and the local feeds are listed, no doujin', () {
    expect(switchableBoorus(all, gelbooru), [gelbooru, e621, downloads, favourites]);
  });

  test('a local feed counts as the booru side', () {
    expect(switchableBoorus(all, downloads), isNot(contains(nhentai)));
    expect(switchableBoorus(all, downloads), contains(gelbooru));
  });

  test('the current source is always in its own list', () {
    for (final b in all) {
      expect(switchableBoorus(all, b), contains(b));
    }
  });
}
