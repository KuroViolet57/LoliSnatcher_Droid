import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4 fix 2: every new source was storing `artist:wakahi-chan` as the tag's
/// own name. That put a raw prefix on every chip, and quietly broke three other
/// things that all read the tag name — the language badge (which looks for a tag
/// called `english`, never `language:english`), the blacklist and the favourite
/// tags (which compare against a namespace-stripped form).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tag_ns');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group("how a namespace maps onto the app's tag types", () {
    test('the ones with an exact equivalent map to it', () {
      expect(doujinTagTypeFor('artist'), TagType.artist);
      expect(doujinTagTypeFor('character'), TagType.character);
      expect(doujinTagTypeFor('parody'), TagType.copyright);
      expect(doujinTagTypeFor('language'), TagType.meta);
    });

    test('a circle is treated as an artist, as nhentai treats its groups', () {
      expect(doujinTagTypeFor('circle'), TagType.artist);
      expect(doujinTagTypeFor('group'), TagType.artist);
    });

    test('series is the same concept as parody under another name', () {
      expect(doujinTagTypeFor('series'), doujinTagTypeFor('parody'));
    });

    test('edition metadata is meta, not general', () {
      // magazine and publisher describe the edition rather than its content,
      // which keeps them out of the general tag soup on a card.
      expect(doujinTagTypeFor('magazine'), TagType.meta);
      expect(doujinTagTypeFor('publisher'), TagType.meta);
      expect(doujinTagTypeFor('type'), TagType.meta);
      expect(doujinTagTypeFor('category'), TagType.meta);
    });

    test('gendered namespaces stay general, so the same tag looks the same everywhere', () {
      // female:busty on one source and busty on another are the same tag; giving
      // one of them a type would colour them differently for no reason.
      expect(doujinTagTypeFor('female'), TagType.none);
      expect(doujinTagTypeFor('male'), TagType.none);
      expect(doujinTagTypeFor('mixed'), TagType.none);
      expect(doujinTagTypeFor('other'), TagType.none);
      expect(doujinTagTypeFor(null), TagType.none);
    });
  });

  group('names are bare, namespaces live beside them', () {
    test('the namespace never ends up inside the tag name', () {
      final h = FaccinaHandler(
        Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', ''),
        20,
      );
      final tag = h.namespacedTag('Wakahi Chan', 'artist');

      expect(tag.fullString, 'wakahi_chan');
      expect(tag.tagType, TagType.artist);
      expect(h.tagNamespace('wakahi_chan'), 'artist');
    });

    test('a general tag records no namespace at all', () {
      final h = FaccinaHandler(
        Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', ''),
        20,
      );
      expect(h.namespacedTag('big breasts', null).fullString, 'big_breasts');
      expect(h.namespacedTag('sleeping', 'tag').fullString, 'sleeping');
      expect(h.tagNamespace('big_breasts'), isNull);
      expect(h.tagNamespace('sleeping'), isNull);
    });

    test('a tag saved by an older build still groups correctly', () {
      // Favourites and blacklists written before this change are on disk with
      // the prefix baked in; they must not fall into the general section.
      final h = FaccinaHandler(
        Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', ''),
        20,
      );
      expect(h.tagNamespace('artist:someone'), 'artist');
    });

    test('the first namespace to claim a name keeps it', () {
      // Otherwise a tag would jump between sections as later pages load.
      final h = FaccinaHandler(
        Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', ''),
        20,
      );
      h.namespacedTag('original', 'parody');
      h.namespacedTag('original', 'tag');
      expect(h.tagNamespace('original'), 'parody');
    });
  });

  group('search still round-trips', () {
    test('hitomi puts the namespace back, because it indexes them separately', () {
      // hitomi resolves `ahegao` and `female:ahegao` to different indexes, so a
      // chip that displays bare must qualify before it searches.
      final h = HitomiHandler(Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20);
      h.namespacedTag('ahegao', 'female');

      expect(h.qualifyTag('ahegao'), 'female:ahegao');
      expect(HitomiHandler.nozomiTargetFor(h.qualifyTag('ahegao'))?.tag, 'female:ahegao');
    });

    test('an unqualified tag is left alone rather than guessed at', () {
      final h = HitomiHandler(Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20);
      expect(h.qualifyTag('something_unseen'), 'something_unseen');
    });

    test('niyaniya qualifies a whole query, preserving negation', () {
      final h = SchaleHandler(
        Booru('niyaniya', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''),
        20,
      );
      h.namespacedTag('shindol', 'artist');
      h.namespacedTag('busty', 'female');

      expect(h.qualifyQuery('shindol -busty'), 'artist:shindol -female:busty');
      // Already-qualified terms are untouched.
      expect(h.qualifyQuery('parody:blue_archive'), 'parody:blue_archive');
    });
  });

  group('the language badge, which shares this root cause', () {
    test('a language tag is stored under the name the badge looks for', () {
      // The badge maps a tag literally named `english`/`japanese` to EN/JP. It
      // never matched `language:english`, which is why hitomi, hentalk and
      // niyaniya showed no badge at all.
      final h = HitomiHandler(Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20);
      final tag = h.namespacedTag('japanese', 'language');

      expect(tag.fullString, 'japanese');
      expect(h.tagNamespace('japanese'), 'language');
      expect(tag.tagType, TagType.meta);
    });
  });
}
